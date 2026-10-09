import Foundation
import SwiftData

/// Portable, versioned transfer of a selected part of a Goldfish relationship graph.
enum GoldfishContactBundle {
    private static let currentVersion = 1
    private static let maximumBundleSize = 50 * 1_024 * 1_024
    private static let maximumPeople = 1_000

    struct GoldfishSharePreview {
        let people: [String]
        let relationshipsCount: Int
        let ponds: [String]
        let includesNotes: Bool
    }

    struct GoldfishShareImportResult {
        let addedPeople: Int
        let addedContactIDs: Set<UUID>
        let reusedPeople: Int
        let connectionsAdded: Int
        let pondsAdded: Int
        let organizationConflicts: Int
    }

    enum BundleError: LocalizedError {
        case tooLarge, unsupportedVersion(Int), invalidData(String)
        var errorDescription: String? {
            switch self {
            case .tooLarge: return "This Goldfish contact bundle is too large."
            case .unsupportedVersion(let value): return "This Goldfish contact bundle version (\(value)) is not supported."
            case .invalidData(let reason): return "This Goldfish contact bundle is invalid: \(reason)"
            }
        }
    }

    private struct Bundle: Codable {
        var format: String
        var version: Int
        var includesNotes: Bool
        var people: [PersonDTO]
        var relationships: [RelationshipDTO]
        var ponds: [PondDTO]
    }
    private struct PersonDTO: Codable {
        var id: UUID; var name: String; var phone: String?; var email: String?
        var birthday: Date?; var notes: String?; var isMe: Bool; var petKindRaw: String?
        var isFavorite: Bool; var tags: [String]; var color: String?; var photoData: Data?
        var street: String?; var city: String?; var state: String?; var country: String?; var postalCode: String?
        var isDemo: Bool; var createdAt: Date; var updatedAt: Date; var locations: [LocationDTO]
    }
    private struct LocationDTO: Codable {
        var id: UUID; var type: String; var name: String?; var address: String?
        var latitude: Double?; var longitude: Double?; var isPrimary: Bool; var createdAt: Date
    }
    private struct RelationshipDTO: Codable {
        var id: UUID; var fromID: UUID; var toID: UUID; var type: String; var isPrimary: Bool; var createdAt: Date
    }
    private struct PondDTO: Codable {
        var id: UUID; var name: String; var color: String; var emoji: String
        var desc: String?; var sortOrder: Int; var createdAt: Date; var memberships: [MembershipDTO]
    }
    private struct MembershipDTO: Codable {
        var id: UUID; var personID: UUID; var manuallyExcluded: Bool; var createdAt: Date
    }

    static func preview(data: Data) throws -> GoldfishSharePreview {
        let bundle = try decodeAndValidate(data)
        return GoldfishSharePreview(people: bundle.people.map(\.name),
                                    relationshipsCount: bundle.relationships.count,
                                    ponds: bundle.ponds.map(\.name), includesNotes: bundle.includesNotes)
    }

    @MainActor
    static func export(contacts: [Person], includeNotes: Bool = true) throws -> Data {
        let selected = Dictionary(contacts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ids = Set(selected.keys)
        let people = selected.values.sorted { $0.id.uuidString < $1.id.uuidString }.map { person in
            PersonDTO(id: person.id, name: person.name, phone: person.phone, email: person.email,
                      birthday: person.birthday, notes: includeNotes ? person.notes : nil,
                      isMe: person.isMe, petKindRaw: person.petKindRaw, isFavorite: person.isFavorite,
                      tags: person.tags, color: person.color, photoData: person.photoData,
                      street: person.street, city: person.city, state: person.state, country: person.country,
                      postalCode: person.postalCode, isDemo: person.isDemo, createdAt: person.createdAt,
                      updatedAt: person.updatedAt,
                      locations: person.locations.map { LocationDTO(id: $0.id, type: $0.typeRawValue,
                          name: $0.name, address: $0.address, latitude: $0.latitude,
                          longitude: $0.longitude, isPrimary: $0.isPrimary, createdAt: $0.createdAt) })
        }
        var rels: [RelationshipDTO] = []
        var seenRel = Set<UUID>()
        for person in selected.values {
            for rel in person.allRelationships where ids.contains(rel.fromContact.id) && ids.contains(rel.toContact.id) {
                if seenRel.insert(rel.id).inserted {
                    rels.append(RelationshipDTO(id: rel.id, fromID: rel.fromContact.id, toID: rel.toContact.id,
                                                type: rel.typeRawValue, isPrimary: rel.isPrimary, createdAt: rel.createdAt))
                }
            }
        }
        let pondsByID = Dictionary(contacts.flatMap(\.circleContacts).map { ($0.circle.id, $0.circle) },
                                   uniquingKeysWith: { first, _ in first })
        let ponds = pondsByID.values.sorted { $0.id.uuidString < $1.id.uuidString }.map { pond in
            PondDTO(id: pond.id, name: pond.name, color: pond.color, emoji: pond.emoji, desc: pond.desc,
                    sortOrder: pond.sortOrder, createdAt: pond.createdAt,
                    memberships: pond.circleContacts.filter { ids.contains($0.contact.id) }.map {
                        MembershipDTO(id: $0.id, personID: $0.contact.id, manuallyExcluded: $0.manuallyExcluded, createdAt: $0.createdAt)
                    })
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Bundle(format: "goldfish-contact-bundle", version: currentVersion, includesNotes: includeNotes,
                                             people: people, relationships: rels, ponds: ponds))
        guard data.count <= maximumBundleSize else { throw BundleError.tooLarge }
        _ = try decodeAndValidate(data)
        return data
    }

    @MainActor
    static func importData(_ data: Data, into context: ModelContext) throws -> GoldfishShareImportResult {
        let bundle = try decodeAndValidate(data)
        let previousAutosave = context.autosaveEnabled
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = previousAutosave }
        do {
            let existingPeople = try context.fetch(FetchDescriptor<Person>())
            let existingRels = try context.fetch(FetchDescriptor<Relationship>())
            let existingPonds = try context.fetch(FetchDescriptor<GoldfishCircle>())
            let existingLocations = try context.fetch(FetchDescriptor<Location>())
            let existingMemberships = try context.fetch(FetchDescriptor<CircleContact>())
            let existingMembershipsByID = Dictionary(existingMemberships.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let existingLocationsByID = Dictionary(existingLocations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let existingRelsByID = Dictionary(existingRels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let resolvedIDs = Dictionary(uniqueKeysWithValues: bundle.people.map { ($0.id, $0.id) })
            let importedPondIDs = Dictionary(uniqueKeysWithValues: bundle.ponds.map { ($0.id, $0.id) })
            for dto in bundle.people {
                for location in dto.locations {
                    if let old = existingLocationsByID[location.id], old.contact.id != resolvedIDs[dto.id] {
                        throw BundleError.invalidData("a location identifier belongs to another contact")
                    }
                }
            }
            for dto in bundle.relationships {
                if let old = existingRelsByID[dto.id], old.fromContact.id != resolvedIDs[dto.fromID] || old.toContact.id != resolvedIDs[dto.toID] || old.typeRawValue != dto.type {
                    throw BundleError.invalidData("a relationship identifier belongs to a different connection")
                }
            }
            for pond in bundle.ponds {
                for member in pond.memberships {
                    if let old = existingMembershipsByID[member.id],
                       old.contact.id != resolvedIDs[member.personID] || old.circle.id != importedPondIDs[pond.id] {
                        throw BundleError.invalidData("a membership identifier belongs to a different pond or contact")
                    }
                }
            }
            var peopleByID = Dictionary(existingPeople.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var added = 0, reused = 0, connections = 0, pondsAdded = 0, organizationConflicts = 0
            var addedContactIDs = Set<UUID>()

            for dto in bundle.people {
                let person: Person
                let resolvedID = resolvedIDs[dto.id]!
                if let old = peopleByID[resolvedID] {
                    person = old; reused += 1
                    if !old.isMe {
                        // Accepting a share makes a sample match part of the user's
                        // real contacts; it must survive sample cleanup and be visible.
                        person.isDemo = false
                        fillMissing(&person.name, from: dto.name)
                        fillMissing(&person.phone, from: dto.phone); fillMissing(&person.email, from: dto.email)
                        if person.birthday == nil { person.birthday = dto.birthday }
                        if person.notes?.isEmpty != false { person.notes = dto.notes }
                        if person.petKindRaw == nil { person.petKindRaw = dto.petKindRaw }
                        if person.color?.isEmpty != false { person.color = dto.color }
                        if person.photoData == nil { person.photoData = dto.photoData }
                        fillMissing(&person.street, from: dto.street); fillMissing(&person.city, from: dto.city)
                        fillMissing(&person.state, from: dto.state); fillMissing(&person.country, from: dto.country)
                        fillMissing(&person.postalCode, from: dto.postalCode)
                        person.isFavorite = person.isFavorite || dto.isFavorite
                        person.tags = Array(Set(person.tags + dto.tags)).sorted()
                        person.updatedAt = max(person.updatedAt, dto.updatedAt)
                    }
                } else {
                    person = Person(id: resolvedID, name: dto.name, phone: dto.phone, email: dto.email,
                                    birthday: dto.birthday, notes: dto.notes, isMe: false,
                                    petKindRaw: dto.petKindRaw, isDemo: false, isFavorite: dto.isFavorite,
                                    tags: dto.tags, color: dto.color, photoData: dto.photoData,
                                    street: dto.street, city: dto.city, state: dto.state, country: dto.country,
                                    postalCode: dto.postalCode)
                    person.createdAt = dto.createdAt; person.updatedAt = dto.updatedAt
                    context.insert(person); peopleByID[resolvedID] = person; added += 1
                    addedContactIDs.insert(person.id)
                }
                peopleByID[dto.id] = person
                for location in dto.locations where !person.isMe && !person.locations.contains(where: { $0.id == location.id }) {
                    let item = Location(id: location.id, contact: person, type: LocationType(rawValue: location.type)!,
                                        name: location.name, address: location.address, latitude: location.latitude,
                                        longitude: location.longitude, isPrimary: location.isPrimary)
                    item.createdAt = location.createdAt
                    context.insert(item); person.locations.append(item)
                }
            }

            var currentRelationships = existingRels
            for dto in bundle.relationships {
                guard let from = peopleByID[dto.fromID], let to = peopleByID[dto.toID] else {
                    throw BundleError.invalidData("a relationship references a missing contact")
                }
                if existingRelsByID[dto.id] != nil { continue }
                let type = RelationshipType(rawValue: dto.type)!
                if let existing = currentRelationships.first(where: { $0.matches(from: from, to: to, type: type) }) {
                    // A shared mother/father role carries more information than an
                    // existing generic parent/child edge. Preserve that detail when
                    // merging instead of silently treating the edge as a duplicate.
                    existing.preserveSpecificRole(from: from, to: to, type: type)
                    continue
                }
                guard !GraphService().wouldCreateCycle(from: from, to: to, type: type, context: context) else {
                    throw BundleError.invalidData("these connections would create an ancestry loop")
                }
                let rel = Relationship(id: dto.id, from: from, to: to,
                                       type: type, isPrimary: dto.isPrimary)
                rel.createdAt = dto.createdAt
                context.insert(rel)
                if !from.outgoingRelationships.contains(where: { $0.id == rel.id }) { from.outgoingRelationships.append(rel) }
                if !to.incomingRelationships.contains(where: { $0.id == rel.id }) { to.incomingRelationships.append(rel) }
                connections += 1
                currentRelationships.append(rel)
            }

            var pondsByID = Dictionary(existingPonds.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for dto in bundle.ponds {
                let pond: GoldfishCircle
                if let old = pondsByID[dto.id] { pond = old }
                else {
                    let id = importedPondIDs[dto.id]!
                    if let already = pondsByID[id], !already.isSystem { pond = already }
                    else {
                        pond = GoldfishCircle(id: id, name: dto.name, color: dto.color, emoji: dto.emoji,
                                              desc: dto.desc, isSystem: false, autoRelationshipTypes: [], sortOrder: dto.sortOrder)
                        pond.createdAt = dto.createdAt
                        context.insert(pond); pondsByID[id] = pond; pondsAdded += 1
                    }
                }
                let desired = dto.memberships
                for membership in desired where membership.manuallyExcluded {
                    guard let person = peopleByID[membership.personID], !person.isMe else { continue }
                    if existingMembershipsByID[membership.id] != nil { continue }
                    guard !pond.circleContacts.contains(where: { $0.id == membership.id }) else { continue }
                    let row = CircleContact(id: membership.id, circle: pond, contact: person,
                                            manuallyExcluded: membership.manuallyExcluded)
                    row.createdAt = membership.createdAt
                    context.insert(row); person.circleContacts.append(row); pond.circleContacts.append(row)
                }
                for membership in desired where !membership.manuallyExcluded {
                    guard let person = peopleByID[membership.personID] else { continue }
                    if person.isMe { organizationConflicts += 1; continue }
                    if let active = person.circleContacts.first(where: { !$0.manuallyExcluded }) {
                        if active.circle.id != pond.id { organizationConflicts += 1 }
                    } else if !person.circleContacts.contains(where: { $0.id == membership.id }),
                              existingMembershipsByID[membership.id] == nil {
                        let row = CircleContact(id: membership.id, circle: pond, contact: person, manuallyExcluded: false)
                        row.createdAt = membership.createdAt
                        context.insert(row); person.circleContacts.append(row); pond.circleContacts.append(row)
                    }
                }
            }
            try context.save()
            return GoldfishShareImportResult(addedPeople: added, addedContactIDs: addedContactIDs, reusedPeople: reused,
                                             connectionsAdded: connections, pondsAdded: pondsAdded,
                                             organizationConflicts: organizationConflicts)
        } catch {
            context.rollback()
            throw error
        }
    }

    private static func decodeAndValidate(_ data: Data) throws -> Bundle {
        guard data.count <= maximumBundleSize else { throw BundleError.tooLarge }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let bundle: Bundle
        do { bundle = try decoder.decode(Bundle.self, from: data) }
        catch { throw BundleError.invalidData(error.localizedDescription) }
        guard bundle.format == "goldfish-contact-bundle" else { throw BundleError.invalidData("unknown bundle format") }
        guard bundle.version == currentVersion else { throw BundleError.unsupportedVersion(bundle.version) }
        guard bundle.people.count <= maximumPeople else { throw BundleError.invalidData("too many contacts") }
        guard bundle.relationships.count <= 50_000, bundle.ponds.count <= 500 else {
            throw BundleError.invalidData("too many graph records")
        }
        func unique(_ ids: [UUID], _ label: String) throws {
            guard Set(ids).count == ids.count else { throw BundleError.invalidData("duplicate \(label) identifiers") }
        }
        let personIDs = bundle.people.map(\.id)
        try unique(personIDs, "contact")
        let people = Set(personIDs)
        try unique(bundle.relationships.map(\.id), "relationship")
        try unique(bundle.ponds.map(\.id), "pond")
        var allLocationIDs = Set<UUID>()
        for p in bundle.people {
            guard !p.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BundleError.invalidData("contact names cannot be empty") }
            if !bundle.includesNotes, p.notes != nil { throw BundleError.invalidData("notes are present although notes were not included") }
            guard ContactKind(rawValue: p.petKindRaw ?? "human") != nil else { throw BundleError.invalidData("unknown contact kind") }
            try unique(p.locations.map(\.id), "location")
            guard p.locations.allSatisfy({ allLocationIDs.insert($0.id).inserted }) else { throw BundleError.invalidData("duplicate location identifiers") }
            guard p.locations.allSatisfy({ LocationType(rawValue: $0.type) != nil }) else { throw BundleError.invalidData("unknown location type") }
            guard p.locations.allSatisfy({ location in
                switch (location.latitude, location.longitude) {
                case (nil, nil): return true
                case let (lat?, lon?): return lat.isFinite && lon.isFinite && (-90...90).contains(lat) && (-180...180).contains(lon)
                default: return false
                }
            }) else { throw BundleError.invalidData("invalid location coordinates") }
        }
        for r in bundle.relationships {
            guard people.contains(r.fromID), people.contains(r.toID), r.fromID != r.toID,
                  RelationshipType(rawValue: r.type) != nil else { throw BundleError.invalidData("invalid relationship reference or type") }
        }
        var allMembershipIDs = Set<UUID>()
        var totalMemberships = 0
        var activeMembershipCounts: [UUID: Int] = [:]
        for pond in bundle.ponds {
            guard !pond.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw BundleError.invalidData("pond names cannot be empty") }
            try unique(pond.memberships.map(\.id), "membership")
            totalMemberships += pond.memberships.count
            guard pond.memberships.allSatisfy({ people.contains($0.personID) }) else { throw BundleError.invalidData("invalid pond membership reference") }
            for membership in pond.memberships {
                guard allMembershipIDs.insert(membership.id).inserted else { throw BundleError.invalidData("duplicate membership identifiers") }
                if !membership.manuallyExcluded { activeMembershipCounts[membership.personID, default: 0] += 1 }
            }
        }
        guard totalMemberships <= 50_000 else { throw BundleError.invalidData("too many pond memberships") }
        guard activeMembershipCounts.values.allSatisfy({ $0 <= 1 }) else { throw BundleError.invalidData("a contact has multiple active ponds") }
        return bundle
    }

    private static func fillMissing(_ target: inout String?, from source: String?) {
        if target?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false { target = source }
    }
    private static func fillMissing(_ target: inout String, from source: String) {
        if target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { target = source }
    }
}

typealias GoldfishSharePreview = GoldfishContactBundle.GoldfishSharePreview
typealias GoldfishShareImportResult = GoldfishContactBundle.GoldfishShareImportResult
