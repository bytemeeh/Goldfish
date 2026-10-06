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
    case invalidName
    case selfRelationship
    case cannotAssignSelf
    /// An Undo token references a contact, pond, or record that no longer exists.
    case undoTargetMissing
    /// Data changed after the reversible operation, so restoring would overwrite it.
    case undoConflict

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
        case .invalidName:
            return "Enter a name before saving."
        case .selfRelationship:
            return "A contact cannot be connected to itself."
        case .cannotAssignSelf:
            return "Me stays at the center and cannot join a group."
        case .undoTargetMissing:
            return "Undo is no longer available because one of its contacts or ponds was removed."
        case .undoConflict:
            return "Undo is no longer available because this connection or pond membership changed."
        }
    }
}

// MARK: - Reversible operation snapshots

/// Immutable state needed to restore one relationship exactly as it was removed.
struct RelationshipRemovalUndoToken: Equatable {
    let relationshipID: UUID
    let fromContactID: UUID
    let toContactID: UUID
    let type: RelationshipType
    let isPrimary: Bool
    let createdAt: Date
}

/// One exact persisted membership row, including retained system-pond exclusions.
struct PondMembershipSnapshot: Equatable {
    let membershipID: UUID
    let circleID: UUID
    let manuallyExcluded: Bool
    let createdAt: Date
}

/// Immutable before/after state for one pond-membership change.
/// The after snapshot acts as a revision check so Undo never overwrites later edits.
struct PondMembershipUndoToken: Equatable {
    let personID: UUID
    let before: [PondMembershipSnapshot]
    let after: [PondMembershipSnapshot]
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
/// Production persistence is local; CloudKit is explicitly disabled.
@MainActor
final class GoldfishDataManager: ObservableObject {

    let context: ModelContext
    private let graphService = GraphService()

    init(context: ModelContext) {
        self.context = context
    }
    private var editDepth = 0
    private var petKindUndo: [UUID: (person: Person, value: String?)] = [:]
    private var afterCommitActions: [() -> Void] = []

    /// Runs work only after the current outer transaction has committed. Nested
    /// repository calls can register follow-up state without marking a rollback
    /// as complete.
    func afterCurrentAtomicEditCommits(_ action: @escaping () -> Void) {
        if editDepth == 0 {
            action()
        } else {
            afterCommitActions.append(action)
        }
    }

    func performAtomicEdit<T>(_ operation: () throws -> T) throws -> T {
        let entryDepth = editDepth
        let outermost = entryDepth == 0
        editDepth = entryDepth + 1
        defer { editDepth = entryDepth }
        do {
            let value = try operation()
            if outermost {
                try context.save()
                petKindUndo.removeAll()
                // The transaction is committed now. Hooks and synchronous
                // notification observers may start independent edits.
                editDepth = entryDepth
                let actions = afterCommitActions
                afterCommitActions.removeAll()
                actions.forEach { $0() }
                NotificationCenter.default.post(name: .goldfishDataDidChange, object: nil)
            }
            return value
        } catch {
            if outermost {
                context.rollback()
                restorePetKinds()
                afterCommitActions.removeAll()
            }
            throw error
        }
    }
    private func persist() throws {
        guard editDepth == 0 else { return }
        do { try context.save() }
        catch {
            context.rollback()
            restorePetKinds()
            throw error
        }
        petKindUndo.removeAll()
        NotificationCenter.default.post(name: .goldfishDataDidChange, object: nil)
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
        petKindRaw: String? = nil,
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
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw GoldfishError.invalidName }
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
            name: cleanName,
            phone: phone,
            email: email,
            birthday: birthday,
            notes: notes,
            isMe: isMe,
            petKindRaw: petKindRaw,
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
        try persist()
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
        petKindRaw: OptionalUpdate<String> = .ignore,
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
        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw GoldfishError.invalidName }
            person.name = trimmed
        }
        if case .set(let v) = phone { person.phone = v }
        if case .set(let v) = email { person.email = v }
        if case .set(let v) = birthday { person.birthday = v }
        if case .set(let v) = notes { person.notes = v }
        if case .set(let v) = petKindRaw {
            if petKindUndo[person.id] == nil { petKindUndo[person.id] = (person, person.petKindRaw) }
            person.petKindRaw = person.isMe ? nil : v
        }
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
        try persist()
    }

    private func restorePetKinds() {
        for entry in petKindUndo.values { entry.person.petKindRaw = entry.value }
        petKindUndo.removeAll()
    }

    /// Deletes a contact. Throws if the contact has `isMe == true`.
    /// Cascade delete rules handle removing associated relationships,
    /// locations, and circle memberships.
    func deletePerson(_ person: Person) throws {
        guard !person.isMe else {
            throw GoldfishError.cannotDeleteSelf
        }
        context.delete(person)
        try persist()
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
    /// **Circle auto-assignment:** Direct relationships to Me use system ponds.
    /// Other people's household relationships inherit their existing pond context.
    /// Existing memberships and manual exclusions are preserved.
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
        try performAtomicEdit {
        guard from.id != to.id else { throw GoldfishError.selfRelationship }
        if let existing = from.allRelationships.first(where: { $0.matches(from: from, to: to, type: type) }) {
            existing.preserveSpecificRole(from: from, to: to, type: type)
            return existing
        }
        // Cycle detection for directional types
        if graphService.wouldCreateCycle(from: from, to: to, type: type, context: context) {
            throw GoldfishError.wouldCreateCycle
        }

        let relationship = Relationship(from: from, to: to, type: type, isPrimary: isPrimary)
        context.insert(relationship)
        
        // Explicitly maintain in-memory arrays to workaround SwiftData caching
        if !from.outgoingRelationships.contains(where: { $0.id == relationship.id }) { from.outgoingRelationships.append(relationship) }
        if !to.incomingRelationships.contains(where: { $0.id == relationship.id }) { to.incomingRelationships.append(relationship) }

        // Auto-assign circles (skip when caller handles assignment explicitly, e.g. demo data)
        if !skipAutoAssign {
            try autoAssignCircle(for: from, relatedTo: to, relationshipType: type)
            try autoAssignCircle(for: to, relatedTo: from, relationshipType: type)
        }

        try persist()
        return relationship
        }
    }

    /// Deletes a relationship without creating an Undo token.
    func deleteRelationship(_ relationship: Relationship) throws {
        try performAtomicEdit {
            guard let stored = try fetchRelationship(id: relationship.id) else {
                throw GoldfishError.undoTargetMissing
            }
            unlinkAndDelete(stored)
        }
    }

    /// Removes one existing relationship and returns the exact immutable state
    /// required to restore it. Callers can safely retain this value for a toast.
    @discardableResult
    func removeRelationshipWithUndo(_ relationship: Relationship) throws -> RelationshipRemovalUndoToken {
        try performAtomicEdit {
            guard let stored = try fetchRelationship(id: relationship.id) else {
                throw GoldfishError.undoTargetMissing
            }
            let token = RelationshipRemovalUndoToken(
                relationshipID: stored.id,
                fromContactID: stored.fromContact.id,
                toContactID: stored.toContact.id,
                type: stored.type,
                isPrimary: stored.isPrimary,
                createdAt: stored.createdAt
            )
            unlinkAndDelete(stored)
            return token
        }
    }

    /// Restores a relationship only when both endpoints still exist and no
    /// later relationship conflicts with the captured logical edge.
    @discardableResult
    func restoreRemovedRelationship(using token: RelationshipRemovalUndoToken) throws -> Relationship {
        try performAtomicEdit {
            let people = try fetchAllPersons()
            guard let from = people.first(where: { $0.id == token.fromContactID }),
                  let to = people.first(where: { $0.id == token.toContactID }) else {
                throw GoldfishError.undoTargetMissing
            }

            let relationships = try context.fetch(FetchDescriptor<Relationship>())
            guard !relationships.contains(where: { $0.id == token.relationshipID }),
                  !relationships.contains(where: { $0.matches(from: from, to: to, type: token.type) }) else {
                throw GoldfishError.undoConflict
            }
            guard !graphService.wouldCreateCycle(
                from: from,
                to: to,
                type: token.type,
                context: context
            ) else {
                throw GoldfishError.undoConflict
            }

            let restored = Relationship(
                id: token.relationshipID,
                from: from,
                to: to,
                type: token.type,
                isPrimary: token.isPrimary
            )
            restored.createdAt = token.createdAt
            context.insert(restored)
            if !from.outgoingRelationships.contains(where: { $0.id == restored.id }) {
                from.outgoingRelationships.append(restored)
            }
            if !to.incomingRelationships.contains(where: { $0.id == restored.id }) {
                to.incomingRelationships.append(restored)
            }
            return restored
        }
    }

    private func fetchRelationship(id: UUID) throws -> Relationship? {
        try context.fetch(FetchDescriptor<Relationship>()).first { $0.id == id }
    }

    private func unlinkAndDelete(_ relationship: Relationship) {
        relationship.fromContact.outgoingRelationships.removeAll { $0.id == relationship.id }
        relationship.toContact.incomingRelationships.removeAll { $0.id == relationship.id }
        context.delete(relationship)
    }

    /// Removes exactly the relationship identified by `id`, when it still exists.
    /// Used by the short lived Undo affordance after creating a connection; later
    /// edits and unrelated relationships are never touched.
    @discardableResult
    func undoCreatedRelationship(id: UUID) throws -> Bool {
        let relationships = try context.fetch(FetchDescriptor<Relationship>())
        guard let relationship = relationships.first(where: { $0.id == id }) else { return false }
        try deleteRelationship(relationship)
        return true
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
        try persist()
        return location
    }

    /// Sets a location as the primary for its contact (un-primaries others).
    func setPrimaryLocation(_ location: Location) throws {
        for loc in location.contact.locations {
            loc.isPrimary = (loc.id == location.id)
        }
        try persist()
    }

    /// Deletes a location.
    func deleteLocation(_ location: Location) throws {
        let wasPrimary = location.isPrimary
        let contact = location.contact
        contact.locations.removeAll { $0.id == location.id }
        context.delete(location)

        // If the deleted location was primary, promote the first remaining one
        if wasPrimary, let first = contact.locations.first {
            first.isPrimary = true
        }
        try persist()
    }

    // MARK: ───────────────────────────────────────────────
    // MARK: Circle CRUD
    // MARK: ───────────────────────────────────────────────

    /// Creates the three default system circles. Should be called once during onboarding.
    func createSystemCircles() throws {
        try performAtomicEdit {
            let existing = try fetchSystemCircles()
            for circle in GoldfishCircle.createSystemCircles() {
                if let match = existing.first(where: { !Set($0.autoRelationshipTypes).isDisjoint(with: circle.autoRelationshipTypes) }) {
                    // Extend existing system rules without changing its identity or user label.
                    match.autoRelationshipTypes = Array(Set(match.autoRelationshipTypes + circle.autoRelationshipTypes)).sorted()
                } else { context.insert(circle) }
            }
        }
    }

    /// Creates a custom (non-system) circle.
    @discardableResult
    func createCircle(
        name: String,
        color: String = "#808080",
        emoji: String = "⭐",
        desc: String? = nil
    ) throws -> GoldfishCircle {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw GoldfishError.invalidName }
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
        try persist()
        return circle
    }

    /// Deletes a circle. Throws if the circle is a system circle.
    func deleteCircle(_ circle: GoldfishCircle) throws {
        guard !circle.isSystem else {
            throw GoldfishError.cannotDeleteSystemCircle
        }
        context.delete(circle)
        try persist()
    }

    /// Updates a circle's display properties.
    /// System and custom circles can both be updated.
    func updateCircle(
        _ circle: GoldfishCircle,
        name: String,
        emoji: String,
        color: String
    ) throws {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw GoldfishError.invalidName }
        circle.name = name
        circle.emoji = emoji
        circle.color = color
        try persist()
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
        guard !person.isMe else { throw GoldfishError.cannotAssignSelf }
        return try performAtomicEdit {
            // Remove every other active membership even when restoring an exclusion.
            for membership in person.circleContacts where membership.circle.id != circle.id && !membership.manuallyExcluded {
                try removeFromCircle(person, circle: membership.circle)
            }
            if let existing = findCircleContact(person: person, circle: circle) {
                existing.manuallyExcluded = false
                return existing
            }
            let membership = CircleContact(circle: circle, contact: person)
            context.insert(membership)
            if !person.circleContacts.contains(where: { $0.id == membership.id }) { person.circleContacts.append(membership) }
            if !circle.circleContacts.contains(where: { $0.id == membership.id }) { circle.circleContacts.append(membership) }
            return membership
        }
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
            person.circleContacts.removeAll { $0.id == membership.id }
            circle.circleContacts.removeAll { $0.id == membership.id }
            context.delete(membership)
        }
        try persist()
    }

    /// Changes a contact's active pond and returns an exact before/after token.
    /// Passing `nil` makes the contact unassigned while retaining system-pond
    /// exclusion rows that prevent unwanted automatic reassignment.
    @discardableResult
    func changePondMembership(
        of person: Person,
        to circle: GoldfishCircle?
    ) throws -> PondMembershipUndoToken {
        try performAtomicEdit {
            guard let storedPerson = try fetchAllPersons().first(where: { $0.id == person.id }) else {
                throw GoldfishError.contactNotFound
            }
            let storedCircle: GoldfishCircle?
            if let circle {
                guard let match = try fetchAllCircles().first(where: { $0.id == circle.id }) else {
                    throw GoldfishError.circleNotFound
                }
                storedCircle = match
            } else {
                storedCircle = nil
            }

            let before = try membershipSnapshots(for: storedPerson.id)
            if let storedCircle {
                try addToCircle(storedPerson, circle: storedCircle)
            } else {
                let activeMemberships = storedPerson.circleContacts.filter { !$0.manuallyExcluded }
                for membership in activeMemberships {
                    try removeFromCircle(storedPerson, circle: membership.circle)
                }
            }
            let after = try membershipSnapshots(for: storedPerson.id)
            return PondMembershipUndoToken(personID: storedPerson.id, before: before, after: after)
        }
    }

    /// Restores exact membership rows only if no pond edit happened after the
    /// token was created. Missing contacts or ponds and stale state fail safely.
    func restorePondMembership(using token: PondMembershipUndoToken) throws {
        try performAtomicEdit {
            guard let person = try fetchAllPersons().first(where: { $0.id == token.personID }) else {
                throw GoldfishError.undoTargetMissing
            }

            let circles = try fetchAllCircles()
            let circlesByID = Dictionary(uniqueKeysWithValues: circles.map { ($0.id, $0) })
            let requiredCircleIDs = Set((token.before + token.after).map(\.circleID))
            guard requiredCircleIDs.allSatisfy({ circlesByID[$0] != nil }) else {
                throw GoldfishError.undoTargetMissing
            }

            let allMemberships = try context.fetch(FetchDescriptor<CircleContact>())
            let current = snapshots(from: allMemberships.filter { $0.contact.id == token.personID })
            guard current == token.after else { throw GoldfishError.undoConflict }

            let beforeIDs = Set(token.before.map(\.membershipID))
            guard !allMemberships.contains(where: {
                beforeIDs.contains($0.id) && $0.contact.id != token.personID
            }) else {
                throw GoldfishError.undoConflict
            }

            var currentByID = Dictionary(
                uniqueKeysWithValues: allMemberships
                    .filter { $0.contact.id == token.personID }
                    .map { ($0.id, $0) }
            )

            for membership in Array(currentByID.values) where !beforeIDs.contains(membership.id) {
                membership.contact.circleContacts.removeAll { $0.id == membership.id }
                membership.circle.circleContacts.removeAll { $0.id == membership.id }
                context.delete(membership)
                currentByID.removeValue(forKey: membership.id)
            }

            for snapshot in token.before {
                guard let circle = circlesByID[snapshot.circleID] else {
                    throw GoldfishError.undoTargetMissing
                }
                let membership: CircleContact
                if let existing = currentByID[snapshot.membershipID] {
                    if existing.circle.id != circle.id {
                        existing.circle.circleContacts.removeAll { $0.id == existing.id }
                        existing.circle = circle
                    }
                    membership = existing
                } else {
                    membership = CircleContact(
                        id: snapshot.membershipID,
                        circle: circle,
                        contact: person,
                        manuallyExcluded: snapshot.manuallyExcluded
                    )
                    context.insert(membership)
                }
                membership.manuallyExcluded = snapshot.manuallyExcluded
                membership.createdAt = snapshot.createdAt
                if !person.circleContacts.contains(where: { $0.id == membership.id }) {
                    person.circleContacts.append(membership)
                }
                if !circle.circleContacts.contains(where: { $0.id == membership.id }) {
                    circle.circleContacts.append(membership)
                }
            }
        }
    }

    private func membershipSnapshots(for personID: UUID) throws -> [PondMembershipSnapshot] {
        let memberships = try context.fetch(FetchDescriptor<CircleContact>())
            .filter { $0.contact.id == personID }
        return snapshots(from: memberships)
    }

    private func snapshots(from memberships: [CircleContact]) -> [PondMembershipSnapshot] {
        memberships
            .map {
                PondMembershipSnapshot(
                    membershipID: $0.id,
                    circleID: $0.circle.id,
                    manuallyExcluded: $0.manuallyExcluded,
                    createdAt: $0.createdAt
                )
            }
            .sorted { $0.membershipID.uuidString < $1.membershipID.uuidString }
    }

    /// Finds the CircleContact junction record for a person + circle pair.
    private func findCircleContact(person: Person, circle: GoldfishCircle) -> CircleContact? {
        circle.circleContacts.first { $0.contact.id == person.id }
    }

    // MARK: ───────────────────────────────────────────────
    // MARK: Auto-Assignment
    // MARK: ───────────────────────────────────────────────

    private func autoAssignCircle(for person: Person, relatedTo other: Person, relationshipType: RelationshipType) throws {
        guard let circle = PondAssignmentPolicy.suggestedCircle(
            for: person, relatedTo: other, type: relationshipType,
            systemCircles: try fetchSystemCircles()
        ) else { return }

        // Auto-add (also sync in-memory arrays to avoid stale reads)
        let membership = CircleContact(circle: circle, contact: person)
        context.insert(membership)
        if !person.circleContacts.contains(where: { $0.id == membership.id }) { person.circleContacts.append(membership) }
        if !circle.circleContacts.contains(where: { $0.id == membership.id }) { circle.circleContacts.append(membership) }
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
        if let response = try relationshipSearch(query: query, demoMode: demoMode) {
            var seen = Set<UUID>()
            return response.paths.map(\.person).filter { seen.insert($0.id).inserted }
        }
        return try graphService.search(query: query, context: context, demoMode: demoMode)
    }

    /// Nil means an ordinary text search. Recognized questions always produce
    /// an explicit response, including unsupported syntax and missing links.
    func relationshipSearch(query: String, demoMode: Bool = false) throws -> RelationshipSearchResponse? {
        switch RelationshipQueryParser.parse(query) {
        case .plainText:
            return nil
        case .unsupported(let message):
            return RelationshipSearchResponse(query: nil, paths: [], anchorMatches: [], message: message, isTruncated: false)
        case .query(let parsed):
            let people = try fetchAllPersons().filter { !$0.isDeleted && ($0.isMe || $0.isDemo == demoMode) }
            return RelationshipSearchService().search(parsed, people: people)
        }
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
        try performAtomicEdit {
            try createSystemCircles()
            return try createPerson(name: name, isMe: true, color: color)
        }
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
        try performAtomicEdit {
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
        
            try persist()
        }
    }
}
