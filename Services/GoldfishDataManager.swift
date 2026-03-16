import Foundation
import SwiftData
import UIKit

// MARK: - OptionalUpdate Helper

/// An explicit opt-in for updating optional fields. It distinguishes between
/// "retain the current value" (`.ignore`) and "set a new value, including nil" (`.set`).
public enum OptionalUpdate<T> {
    case ignore
    case set(T?)
}

// MARK: - DataManager Errors

/// Errors thrown by `GoldfishDataManager` for business rule violations.
enum GoldfishError: LocalizedError, Equatable {
    /// Attempted to delete the `isMe` contact.
    case cannotDeleteSelf
    /// Attempted to set `isMe` on a contact when one already exists.
    case isMeAlreadyExists
    /// Attempted to reassign `isMe` to a different contact.
    case cannotReassignIsMe
    /// Creating this relationship would form an ancestry cycle.
    case wouldCreateCycle
    /// Cannot delete a system circle.
    case cannotDeleteSystemCircle
    /// The referenced contact was not found.
    case contactNotFound
    /// The referenced circle was not found.
    case circleNotFound

    var errorDescription: String? {
        switch self {
        case .cannotDeleteSelf:
            return "The 'Me' contact cannot be deleted."
        case .isMeAlreadyExists:
            return "A 'Me' contact already exists. Only one is allowed."
        case .cannotReassignIsMe:
            return "The 'Me' designation cannot be reassigned after initial creation."
        case .wouldCreateCycle:
            return "This relationship would create a circular ancestry chain."
        case .cannotDeleteSystemCircle:
            return "System circles (Family, Friends, Professional) cannot be deleted."
        case .contactNotFound:
            return "The specified contact was not found."
        case .circleNotFound:
            return "The specified circle was not found."
        }
    }
}

// MARK: - GoldfishDataManager

/// Central repository for all CRUD operations and business logic.
///
/// Enforces invariants:
/// - Exactly one `isMe` contact exists at all times
/// - `isMe` cannot be deleted or reassigned
/// - Directional relationships cannot create ancestry cycles
/// - System circles cannot be deleted
/// - Auto-assignment respects manual exclusion flags
///
/// **Threading:** This class operates on a `ModelContext` and should be used
/// on the same actor/thread as its context. For `@MainActor` SwiftUI views,
/// pass a main-actor context.
///
/// **CloudKit:** All models sync automatically via `ModelConfiguration`
/// with a `cloudKitContainerIdentifier`. No custom sync logic needed.
/// Merge conflicts use "latest wins" (CloudKit default).
@MainActor
final class GoldfishDataManager: ObservableObject {

    let context: ModelContext
    private let graphService = GraphService()

    init(context: ModelContext) {
        self.context = context
    }
    // MARK: - Preview Init (see Extensions.swift)

    // MARK: ───────────────────────────────────────────────
    // MARK: Person CRUD
    // MARK: ───────────────────────────────────────────────

    /// Creates a new contact and inserts it into the store.
    ///
    /// If `isMe` is true, this enforces the isMe invariant:
    /// - Only one isMe contact may exist
    /// - isMe can only be set during initial creation (onboarding)
    ///
    /// Photo data is automatically compressed before storage.
    ///
    /// - Returns: The newly created `Person`.
    @discardableResult
    func createPerson(
        name: String,
        phone: String? = nil,
        email: String? = nil,
        birthday: Date? = nil,
        notes: String? = nil,
        isMe: Bool = false,
        isDemo: Bool = false,
        isFavorite: Bool = false,
        tags: [String] = [],
        color: String? = nil,
        photoData: Data? = nil,
        street: String? = nil,
        city: String? = nil,
        state: String? = nil,
        country: String? = nil,
        postalCode: String? = nil
    ) throws -> Person {
        // Enforce isMe invariant
        if isMe {
            let existing = try fetchMePerson()
            if existing != nil {
                throw GoldfishError.isMeAlreadyExists
            }
        }

        // Compress photo if provided
        let compressed: Data? = photoData.flatMap { compressPhoto($0) }

        let person = Person(
            name: name,
            phone: phone,
            email: email,
            birthday: birthday,
            notes: notes,
            isMe: isMe,
            isDemo: isDemo,
            isFavorite: isFavorite,
            tags: tags,
            color: color,
            photoData: compressed,
            street: street,
            city: city,
            state: state,
            country: country,
            postalCode: postalCode
        )

        context.insert(person)
        try context.save()
        return person
    }

    /// Updates an existing person's fields.
    /// The `isMe` flag cannot be changed after creation.
    func updatePerson(
        _ person: Person,
        name: String? = nil,
        phone: OptionalUpdate<String> = .ignore,
        email: OptionalUpdate<String> = .ignore,
        birthday: OptionalUpdate<Date> = .ignore,
        notes: OptionalUpdate<String> = .ignore,
        isFavorite: Bool? = nil,
        tags: [String]? = nil,
        color: String? = nil,
        photoData: OptionalUpdate<Data> = .ignore,
        street: OptionalUpdate<String> = .ignore,
        city: OptionalUpdate<String> = .ignore,
        state: OptionalUpdate<String> = .ignore,
        country: OptionalUpdate<String> = .ignore,
        postalCode: OptionalUpdate<String> = .ignore
    ) throws {
        if let name { person.name = name }
        if case .set(let v) = phone { person.phone = v }
        if case .set(let v) = email { person.email = v }
        if case .set(let v) = birthday { person.birthday = v }
        if case .set(let v) = notes { person.notes = v }
        if let isFavorite { person.isFavorite = isFavorite }
        if let tags { person.tags = tags }
        if let color { person.color = color }
        if case .set(let v) = photoData { person.photoData = v.flatMap { compressPhoto($0) } }
        if case .set(let v) = street { person.street = v }
        if case .set(let v) = city { person.city = v }
        if case .set(let v) = state { person.state = v }
        if case .set(let v) = country { person.country = v }
        if case .set(let v) = postalCode { person.postalCode = v }

        person.updatedAt = Date()
        try context.save()
    }

    /// Deletes a contact. Throws if the contact has `isMe == true`.
    /// Cascade delete rules handle removing associated relationships,
    /// locations, and circle memberships.
    func deletePerson(_ person: Person) throws {
        guard !person.isMe else {
            throw GoldfishError.cannotDeleteSelf
        }
        context.delete(person)
        try context.save()
    }

    /// Fetches all contacts, optionally filtered and sorted.
    func fetchAllPersons(
        sortBy: SortDescriptor<Person> = SortDescriptor(\Person.name)
    ) throws -> [Person] {
        let descriptor: FetchDescriptor<Person> = FetchDescriptor<Person>(sortBy: [sortBy])
        return try context.fetch(descriptor)
    }

    /// Fetches the unique `isMe` contact, or nil if not yet created (pre-onboarding).
    func fetchMePerson() throws -> Person? {
        let predicate = #Predicate<Person> { $0.isMe == true }
        var descriptor = FetchDescriptor<Person>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Fetches all favorited contacts.
    func fetchFavorites() throws -> [Person] {
        let predicate = #Predicate<Person> { $0.isFavorite == true }
        let descriptor = FetchDescriptor<Person>(
            predicate: predicate,
            sortBy: [SortDescriptor(\Person.name)]
        )
        return try context.fetch(descriptor)
    }

    /// Returns the total number of stored contacts.
    ///
    /// Uses SwiftData's efficient `fetchCount()` — no objects are materialized.
    /// Useful for capacity checks (e.g., approaching the app's ~1000 contact limit)
    /// without the overhead of loading every `Person` into memory.
    func fetchPersonCount() throws -> Int {
        let descriptor = FetchDescriptor<Person>()
        return try context.fetchCount(descriptor)
    }

    /// Returns the number of manually created contacts (non-demo, non-self).
    func fetchManualContactsCount() throws -> Int {
        let predicate = #Predicate<Person> { !$0.isDemo && !$0.isMe }
        let descriptor = FetchDescriptor<Person>(predicate: predicate)
        return try context.fetchCount(descriptor)
    }

    /// Fetches all orphan contacts (no relationships).
    ///
    /// **Why in-memory filtering?**
    /// SwiftData's `#Predicate` cannot express "empty relationship array" checks
    /// (e.g., `outgoingRelationships.isEmpty && incomingRelationships.isEmpty`),
    /// so we load all contacts and check the computed `isOrphan` property.
    /// This is acceptable for Goldfish's stated limit of <1000 contacts.
    /// For capacity-only checks, prefer `fetchPersonCount()` which avoids
    /// materializing objects entirely.
    func fetchOrphans() throws -> [Person] {
        try fetchAllPersons().filter { $0.isOrphan }
    }

    // MARK: ───────────────────────────────────────────────
    // MARK: Relationship CRUD
    // MARK: ───────────────────────────────────────────────

    /// Creates a new relationship between two contacts.
    ///
    /// **Cycle detection:** For directional types (mother, father, child),
    /// BFS checks that the new edge won't make anyone their own ancestor.
    ///
    /// **Circle auto-assignment:** After creating the relationship, both contacts
    /// are automatically added to the matching system circle (Family, Friends,
    /// Professional) unless they were manually excluded.
    ///
    /// - Parameters:
    ///   - from: The subject (this person IS the `type`).
    ///   - to: The object (relative to this person).
    ///   - type: The relationship type.
    ///   - isPrimary: Whether this is the primary relationship between these two contacts.
    /// - Returns: The newly created `Relationship`.
    @discardableResult
    func createRelationship(
        from: Person,
        to: Person,
        type: RelationshipType,
        isPrimary: Bool = false,
        skipAutoAssign: Bool = false
    ) throws -> Relationship {
        // Cycle detection for directional types
        if graphService.wouldCreateCycle(from: from, to: to, type: type, context: context) {
            throw GoldfishError.wouldCreateCycle
        }

        let relationship = Relationship(from: from, to: to, type: type, isPrimary: isPrimary)
        context.insert(relationship)
        
        // Explicitly maintain in-memory arrays to workaround SwiftData caching
        from.outgoingRelationships.append(relationship)
        to.incomingRelationships.append(relationship)

        // Auto-assign circles (skip when caller handles assignment explicitly, e.g. demo data)
        if !skipAutoAssign {
            try autoAssignCircle(for: from, relationshipType: type)
            try autoAssignCircle(for: to, relationshipType: type)
        }

        try context.save()
        return relationship
    }

    /// Deletes a relationship.
    func deleteRelationship(_ relationship: Relationship) throws {
        // Explicitly maintain in-memory arrays
        relationship.fromContact.outgoingRelationships.removeAll { $0.id == relationship.id }
        relationship.toContact.incomingRelationships.removeAll { $0.id == relationship.id }
        
        context.delete(relationship)
        try context.save()
    }

    /// Fetches all relationships for a given contact (both directions).
    func fetchRelationships(for person: Person) -> [Relationship] {
        person.allRelationships
    }

    // MARK: ───────────────────────────────────────────────
    // MARK: Location CRUD
    // MARK: ───────────────────────────────────────────────

    /// Adds a location to a contact. The first location is automatically primary.
    @discardableResult
    func addLocation(
        to person: Person,
        type: LocationType = .home,
        name: String? = nil,
        address: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) throws -> Location {
        let isPrimary = person.locations.isEmpty
        let location = Location(
            contact: person,
            type: type,
            name: name,
            address: address,
            latitude: latitude,
            longitude: longitude,
            isPrimary: isPrimary
        )
        context.insert(location)
        try context.save()
        return location
    }

    /// Sets a location as the primary for its contact (un-primaries others).
    func setPrimaryLocation(_ location: Location) throws {
        for loc in location.contact.locations {
            loc.isPrimary = (loc.id == location.id)
        }
        try context.save()
    }

    /// Deletes a location.
    func deleteLocation(_ location: Location) throws {
        let wasPrimary = location.isPrimary
        let contact = location.contact
        context.delete(location)

        // If the deleted location was primary, promote the first remaining one
        if wasPrimary, let first = contact.locations.first {
            first.isPrimary = true
        }
        try context.save()
    }

    // MARK: ───────────────────────────────────────────────
    // MARK: Circle CRUD
    // MARK: ───────────────────────────────────────────────

    /// Creates the three default system circles. Should be called once during onboarding.
    func createSystemCircles() throws {
        let circles = GoldfishCircle.createSystemCircles()
        for circle in circles {
            context.insert(circle)
        }
        try context.save()
    }

    /// Creates a custom (non-system) circle.
    @discardableResult
    func createCircle(
        name: String,
        color: String = "#808080",
        emoji: String = "⭐",
        desc: String? = nil
    ) throws -> GoldfishCircle {
        let maxSort = try fetchAllCircles().map(\.sortOrder).max() ?? -1
        let circle = GoldfishCircle(
            name: name,
            color: color,
            emoji: emoji,
            desc: desc,
            isSystem: false,
            sortOrder: maxSort + 1
        )
        context.insert(circle)
        try context.save()
        return circle
    }

    /// Deletes a circle. Throws if the circle is a system circle.
    func deleteCircle(_ circle: GoldfishCircle) throws {
        guard !circle.isSystem else {
            throw GoldfishError.cannotDeleteSystemCircle
        }
        context.delete(circle)
        try context.save()
    }

    /// Updates a circle's display properties.
    /// System and custom circles can both be updated.
    func updateCircle(
        _ circle: GoldfishCircle,
        name: String,
        emoji: String,
        color: String
    ) throws {
        circle.name = name
        circle.emoji = emoji
        circle.color = color
        try context.save()
    }

    /// Fetches all circles, ordered by sortOrder.
    func fetchAllCircles() throws -> [GoldfishCircle] {
        let descriptor = FetchDescriptor<GoldfishCircle>(
            sortBy: [SortDescriptor(\GoldfishCircle.sortOrder)]
        )
        return try context.fetch(descriptor)
    }

    /// Fetches only system circles.
    func fetchSystemCircles() throws -> [GoldfishCircle] {
        let predicate = #Predicate<GoldfishCircle> { $0.isSystem == true }
        let descriptor = FetchDescriptor<GoldfishCircle>(
            predicate: predicate,
            sortBy: [SortDescriptor(\GoldfishCircle.sortOrder)]
        )
        return try context.fetch(descriptor)
    }

    // MARK: ───────────────────────────────────────────────
    // MARK: Circle Membership
    // MARK: ───────────────────────────────────────────────

    /// Adds a contact to a circle, enforcing the **single pond per contact** invariant.
    /// Any existing memberships are removed before the new one is added.
    /// The `isMe` contact is never added to any circle — it serves as the graph anchor only.
    @discardableResult
    func addToCircle(
        _ person: Person,
        circle: GoldfishCircle
    ) throws -> CircleContact {
        // The "Me" contact must never belong to a pond
        guard !person.isMe else {
            // Return a dummy membership that won't be persisted — caller doesn't need to know
            return CircleContact(circle: circle, contact: person)
        }

        // Check if already a member of THIS circle
        if let existing = findCircleContact(person: person, circle: circle) {
            if existing.manuallyExcluded {
                // Re-adding after manual exclusion: clear the flag
                existing.manuallyExcluded = false
                try context.save()
            }
            return existing
        }

        // Remove all existing pond memberships (single pond enforcement)
        for cc in person.circleContacts where !cc.manuallyExcluded {
            context.delete(cc)
        }

        let membership = CircleContact(circle: circle, contact: person)
        context.insert(membership)
        try context.save()
        return membership
    }

    /// Removes a contact from a circle.
    /// For system circles: sets `manuallyExcluded = true` to prevent auto-re-addition.
    /// For custom circles: deletes the `CircleContact` row.
    func removeFromCircle(_ person: Person, circle: GoldfishCircle) throws {
        guard let membership = findCircleContact(person: person, circle: circle) else {
            return // Not a member, nothing to do
        }

        if circle.isSystem {
            // Mark as manually excluded instead of deleting
            membership.manuallyExcluded = true
        } else {
            context.delete(membership)
        }
        try context.save()
    }

    /// Finds the CircleContact junction record for a person + circle pair.
    private func findCircleContact(person: Person, circle: GoldfishCircle) -> CircleContact? {
        circle.circleContacts.first { $0.contact.id == person.id }
    }

    // MARK: ───────────────────────────────────────────────
    // MARK: Auto-Assignment
    // MARK: ───────────────────────────────────────────────

    /// Auto-assigns a contact to the matching system circle based on relationship type.
    /// Skips if the contact was manually excluded from that circle,
    /// or if the contact is **already in any pond** (single pond enforcement).
    private func autoAssignCircle(for person: Person, relationshipType: RelationshipType) throws {
        // Never auto-assign the "Me" contact to any circle
        guard !person.isMe else { return }
        guard let circleName = relationshipType.autoCircleName else { return }

        // Skip if already in any pond (don't move people automatically)
        let activeMemberships = person.circleContacts.filter { !$0.manuallyExcluded }
        if !activeMemberships.isEmpty { return }

        let predicate = #Predicate<GoldfishCircle> { $0.name == circleName && $0.isSystem == true }
        var descriptor = FetchDescriptor<GoldfishCircle>(predicate: predicate)
        descriptor.fetchLimit = 1

        guard let circle = try context.fetch(descriptor).first else { return }

        // Check if manually excluded from this specific circle
        if let existing = findCircleContact(person: person, circle: circle) {
            if existing.manuallyExcluded {
                return // Respect manual exclusion
            }
            return // Already a member
        }

        // Auto-add (also sync in-memory arrays to avoid stale reads)
        let membership = CircleContact(circle: circle, contact: person)
        context.insert(membership)
        person.circleContacts.append(membership)
        circle.circleContacts.append(membership)
    }

    // MARK: ───────────────────────────────────────────────
    // MARK: Graph Operations (Delegates to GraphService)
    // MARK: ───────────────────────────────────────────────

    /// Builds the BFS graph layout from the `isMe` root.
    /// Returns nil if no `isMe` contact exists yet.
    func buildGraphLayout() throws -> [GraphLevel]? {
        guard let me = try fetchMePerson() else { return nil }
        return graphService.buildGraphLevels(root: me, context: context)
    }
    
    /// Builds the BFS graph layout filtered by demo mode.
    /// When `demoMode` is true, only demo contacts are included.
    /// When `demoMode` is false, only real contacts are included.
    func buildGraphLayout(demoMode: Bool) throws -> [GraphLevel]? {
        guard let me = try fetchMePerson() else { return nil }
        return graphService.buildGraphLevels(root: me, context: context, demoMode: demoMode)
    }

    /// Returns all contacts reachable from the given contact through
    /// directional (parent → child) relationships.
    func getDescendants(of contact: Person) -> [Person] {
        graphService.getDescendants(of: contact)
    }

    /// Searches contacts with ranked results.
    func search(query: String, demoMode: Bool = false) throws -> [Person] {
        try graphService.search(query: query, context: context, demoMode: demoMode)
    }

    // MARK: ───────────────────────────────────────────────
    // MARK: Photo Compression
    // MARK: ───────────────────────────────────────────────

    /// Compresses image data to JPEG at ≤800×800px and ≤500KB.
    /// Returns nil if the data cannot be decoded as an image.
    private func compressPhoto(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }

        // Resize to max 800×800 maintaining aspect ratio
        let maxDimension: CGFloat = 800
        let size = image.size
        var targetSize = size

        if size.width > maxDimension || size.height > maxDimension {
            let scale = min(maxDimension / size.width, maxDimension / size.height)
            targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        }

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resizedImage = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        // Compress to JPEG, iteratively reducing quality to stay under 500KB
        let maxBytes = 500 * 1024 // 500KB
        var quality: CGFloat = 0.8

        while quality > 0.1 {
            if let compressed = resizedImage.jpegData(compressionQuality: quality),
               compressed.count <= maxBytes {
                return compressed
            }
            quality -= 0.1
        }

        // Last resort: lowest quality
        return resizedImage.jpegData(compressionQuality: 0.1)
    }

    // MARK: ───────────────────────────────────────────────
    // MARK: Onboarding
    // MARK: ───────────────────────────────────────────────

    /// Full onboarding setup: creates the `isMe` contact and system circles.
    /// Should be called once at first launch.
    ///
    /// - Parameter name: The user's name for the `isMe` contact.
    /// - Returns: The created `isMe` person.
    @discardableResult
    func performOnboarding(name: String, color: String? = nil) throws -> Person {
        // Only create system circles if they don't already exist
        // (seedDemoData may have already created them)
        let existingCircles = try fetchAllCircles()
        if !existingCircles.contains(where: { $0.isSystem }) {
            try createSystemCircles()
        }
        let me = try createPerson(name: name, isMe: true, color: color)
        return me
    }

    /// Whether onboarding has been completed (isMe contact exists).
    func isOnboardingComplete() throws -> Bool {
        try fetchMePerson() != nil
    }
    
    // MARK: ───────────────────────────────────────────────
    // MARK: Reset
    // MARK: ───────────────────────────────────────────────

    /// Clears all data from the database.
    func resetAllData() throws {
        // Fetch and delete all models manually to ensure reliable deletion
        // order matters to avoid constraint issues during bulk operations
        let circleContacts = try context.fetch(FetchDescriptor<CircleContact>())
        for cc in circleContacts { context.delete(cc) }
        
        let relationships = try context.fetch(FetchDescriptor<Relationship>())
        for rel in relationships { context.delete(rel) }
        
        let locations = try context.fetch(FetchDescriptor<Location>())
        for loc in locations { context.delete(loc) }
        
        let circles = try context.fetch(FetchDescriptor<GoldfishCircle>())
        for circle in circles { context.delete(circle) }
        
        let persons = try context.fetch(FetchDescriptor<Person>())
        for person in persons { context.delete(person) }
        
        try context.save()
    }
}
