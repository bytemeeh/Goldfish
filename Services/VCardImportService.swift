import Foundation
import SwiftData
import os

// MARK: - Import Result
struct ImportResult: Sendable {
    var importedCount: Int = 0
    /// IDs of contacts created by this import, for the post-import organization flow.
    var importedContactIDs: Set<UUID> = []
    var skippedCount: Int = 0
    var errors: [String] = []

    // Names of skipped duplicates for user reporting
    var skippedDuplicates: [String] = []

    // MARK: - Goldfish-Specific Analysis

    /// Whether the imported file was in Goldfish format (manifest detected).
    var isGoldfishFormat: Bool = false

    /// Export version from the manifest (e.g., "1.0").
    var goldfishVersion: String?

    /// Number of connections (relationships) successfully restored.
    var connectionsRestored: Int = 0

    /// Number of connections skipped (duplicate or cycle).
    var connectionsSkipped: Int = 0

    /// Number of new circles (ponds) created during import.
    var circlesCreated: Int = 0

    /// Number of circles that already existed.
    var circlesExisting: Int = 0
}

// MARK: - VCardImportService
/// Background actor for processing large vCard imports without blocking the UI.
@ModelActor
actor VCardImportService {

    private let logger = Logger(subsystem: "com.goldfish.app", category: "VCardImportService")
    private let graphService = GraphService()

    // Circle cache used during a single import session to avoid O(N^2) fetches
    private var circleCache: [UUID: GoldfishCircle] = [:]

    /// Imports contacts from vCard data.
    ///
    /// - Parameters:
    ///   - vcardData: The raw vCard data.
    ///   - progressHandler: Closure called with progress (0.0 to 1.0).
    /// - Returns: Result summary.
    func importContacts(
        _ vcardData: Data,
        progressHandler: @Sendable (Double) -> Void
    ) async throws -> ImportResult {

        // Parse with manifest detection
        let parseResult = VCardParser.parseWithManifest(vcardData)
        let parsedContacts = parseResult.contacts
        let total = parsedContacts.count

        guard total > 0 else {
            return ImportResult(errors: ["No valid contacts found in vCard data."])
        }

        var result = ImportResult()
        var existingPetKindUndo: [UUID: (person: Person, value: String?)] = [:]

        // Goldfish format analysis
        if let manifest = parseResult.manifest {
            result.isGoldfishFormat = true
            result.goldfishVersion = manifest.version
            logger.info("Goldfish export detected: v\(manifest.version), \(manifest.contactCount) contacts, \(manifest.connectionCount) connections")
        }

        // One import commits once; errors and cancellation cannot leave a partial graph.
        modelContext.autosaveEnabled = false
        defer { circleCache.removeAll() }
        do {
            try populateCircleCache()

            // Map vCard UID -> Local Person (New or Existing)
            // Used for resolving relationships across the import batch
            var uidMap: [UUID: Person] = [:]
            var resolvedContacts: [(VCardContact, Person)] = []
            var newRelationships: [Relationship] = []

            // Batch configuration
            let batchSize = 50
            var processed = 0

            // 1. Process Contacts (Insert/Skip)
            for chunk in parsedContacts.chunks(ofCount: batchSize) {
                try Task.checkCancellation()
                for vContact in chunk {
                    // Duplicate check
                    if let existing = try findDuplicate(for: vContact) {
                        // A pet discriminator is explicit transfer metadata. Apply it
                        // to a matched contact when present; a missing discriminator
                        // from an older export must leave the existing value intact.
                        if !existing.isMe, let importedKind = vContact.petKindRaw {
                            if existingPetKindUndo[existing.id] == nil {
                                existingPetKindUndo[existing.id] = (existing, existing.petKindRaw)
                            }
                            existing.petKindRaw = importedKind
                        }
                        // Mark as skipped duplicate
                        result.skippedCount += 1
                        if let name = vContact.name {
                            result.skippedDuplicates.append(name)
                        }

                        // Map the vCard UID to the EXISTING person
                        // This ensures relationships pointing to this person still work
                        if let vUid = vContact.uid {
                            uidMap[vUid] = existing
                        }
                        resolvedContacts.append((vContact, existing))
                        continue
                    }

                    // Create new Person
                    let person = try createPerson(from: vContact)
                    modelContext.insert(person)
                    result.importedCount += 1
                    result.importedContactIDs.insert(person.id)
                    resolvedContacts.append((vContact, person))

                    // Map vCard UID to NEW person
                    if let vUid = vContact.uid {
                        uidMap[vUid] = person
                    }

                }


                processed += chunk.count
                progressHandler(Double(processed) / Double(total) * 0.8) // 80% progress for contact creation
            }

            // Restore every explicit membership before relationship auto-assignment.
            for (vContact, person) in resolvedContacts {
                try Task.checkCancellation()
                let counts = try resolveCircles(for: person, contact: vContact)
                result.circlesCreated += counts.created
                result.circlesExisting += counts.existing
            }
            progressHandler(0.85)
            processed = 0
            for (vContact, person) in resolvedContacts {
                try Task.checkCancellation()
                // B. Relationships
                // vContact.relatedTo contains [(targetUUID, type)]
                for (targetUid, type) in vContact.relatedTo {
                    // Find target person
                    guard let targetPerson = uidMap[targetUid] else {
                        // Target might have been skipped/missing, or wasn't in the import file
                        // Spec says: "UUID references another contact's UID field within the SAME export bundle."
                        // So if not in map, it's a broken link.
                        continue
                    }

                    // Avoid self-relationships (unless specific logic allows, but GraphService blocks directional self-loops)
                    if person.id == targetPerson.id { continue }

                    // Check if relationship already exists (including inverse deduplication)
                    if let existing = person.allRelationships.first(where: { $0.matches(from: person, to: targetPerson, type: type) }) {
                        existing.preserveSpecificRole(from: person, to: targetPerson, type: type)
                        result.connectionsSkipped += 1
                    } else {
                        // Create relationship
                        // Check cycle for directional types
                        if graphService.wouldCreateCycle(from: person, to: targetPerson, type: type, context: modelContext) {
                            logger.error("Skipping relationship \(person.name) -> \(targetPerson.name) (\(type.rawValue)): cycle detected")
                            result.connectionsSkipped += 1
                            continue
                        }

                        let rel = Relationship(from: person, to: targetPerson, type: type)
                        modelContext.insert(rel)
                        if !person.outgoingRelationships.contains(where: { $0.id == rel.id }) { person.outgoingRelationships.append(rel) }
                        if !targetPerson.incomingRelationships.contains(where: { $0.id == rel.id }) { targetPerson.incomingRelationships.append(rel) }
                        result.connectionsRestored += 1

                        newRelationships.append(rel)
                    }
                }

                processed += 1
                if processed % batchSize == 0 {
                    let baseProgress = 0.85
                    let currentPhaseProgress = Double(processed) / Double(total) * 0.15
                    progressHandler(baseProgress + currentPhaseProgress)
                }
            }

            // Resolve context after every relationship exists. Direct and social
            // links establish ponds before household branches inherit them, even
            // when the vCards place children before their parents.
            let assignmentOrder = newRelationships.sorted { first, second in
                func priority(_ relationship: Relationship) -> Int {
                    if relationship.fromContact.isMe || relationship.toContact.isMe { return 0 }
                    return relationship.type.autoCircleName == "Family" ? 2 : 1
                }
                return priority(first) < priority(second)
            }
            for _ in 0..<max(1, resolvedContacts.count) {
                try Task.checkCancellation()
                var assigned = false
                for relationship in assignmentOrder {
                    let fromAssigned = autoAssignCircle(for: relationship.fromContact, relatedTo: relationship.toContact, type: relationship.type)
                    let toAssigned = autoAssignCircle(for: relationship.toContact, relatedTo: relationship.fromContact, type: relationship.type)
                    assigned = assigned || fromAssigned || toAssigned
                }
                if !assigned { break }
            }

            try Task.checkCancellation()
            try modelContext.save()
            progressHandler(1.0)

            return result
        } catch {
            modelContext.rollback()
            for entry in existingPetKindUndo.values { entry.person.petKindRaw = entry.value }
            throw error
        }
    }

    // MARK: - Helpers

    private func findDuplicate(for vContact: VCardContact) throws -> Person? {
        // 1. Exact UID match (strongest signal)
        if let uid = vContact.uid {
            var descriptor = FetchDescriptor<Person>(predicate: #Predicate { $0.id == uid })
            descriptor.fetchLimit = 1
            if let match = try modelContext.fetch(descriptor).first {
                return match
            }
        }

        // 2. Name + (Phone or Email)
        guard let name = vContact.name else { return nil }

        // Note: SwiftData predicates are limited. We can't do complex ORs easily across optionals sometimes.
        // Fetch candidates by name first
        let candidates = try modelContext.fetch(FetchDescriptor<Person>(predicate: #Predicate { $0.name == name }))

        for candidate in candidates {
            // Check Phone
            if let cPhone = candidate.phone, let vPhone = vContact.phone, cPhone == vPhone {
                return candidate
            }
            // Check Email
            if let cEmail = candidate.email, let vEmail = vContact.email, cEmail == vEmail {
                return candidate
            }
        }

        return nil
    }

    private func createPerson(from vContact: VCardContact) throws -> Person {
        // Demote isMe if local isMe exists
        var isMe = vContact.isMe
        if isMe {
            let existingMe = try modelContext.fetch(FetchDescriptor<Person>(predicate: #Predicate { $0.isMe == true })).first
            if existingMe != nil {
                isMe = false // Demote
            }
        }

        let person = Person(
            id: vContact.uid ?? UUID(), // Use imported UID if available, else generate
            name: vContact.name ?? "Unknown",
            phone: vContact.phone,
            email: vContact.email,
            birthday: vContact.birthday,
            notes: vContact.notes,
            isMe: isMe,
            petKindRaw: isMe ? nil : vContact.petKindRaw,
            isFavorite: vContact.isFavorite,
            tags: vContact.tags,
            color: vContact.color,
            photoData: vContact.photoData,
            street: vContact.street,
            city: vContact.city,
            state: vContact.state,
            country: vContact.country,
            postalCode: vContact.postalCode
        )
        return person
    }

    /// Import metadata by stable ID. Older name-only exports use a deterministic fallback.
    /// Existing local memberships and manual exclusions take precedence over imported choices.
    private func resolveCircles(for person: Person, contact: VCardContact) throws -> (created: Int, existing: Int) {
        guard !person.isMe else { return (0, 0) }
        var created = 0, existing = 0
        var targets: [GoldfishCircle] = []
        if !contact.groups.isEmpty {
            for metadata in contact.groups {
                if let exact = circleCache[metadata.id] {
                    targets.append(exact); existing += 1
                } else if let role = metadata.systemRole,
                          let system = orderedCircles.first(where: { $0.isSystem && $0.transferMetadata.systemRole == role }) {
                    targets.append(system); existing += 1
                } else {
                    // Imported system roles map to local defaults above. An unavailable role
                    // becomes an editable custom group, never a new protected system group.
                    let group = GoldfishCircle(id: metadata.id, name: metadata.name, color: metadata.color,
                                               isSystem: false, sortOrder: nextCircleOrder)
                    modelContext.insert(group); circleCache[group.id] = group
                    targets.append(group); created += 1
                }
            }
        } else {
            var seen = Set<String>()
            for rawName in contact.circles {
                let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { continue }
                if let group = orderedCircles.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                    targets.append(group); existing += 1
                } else {
                    let group = GoldfishCircle(name: name, isSystem: false, sortOrder: nextCircleOrder)
                    modelContext.insert(group); circleCache[group.id] = group
                    targets.append(group); created += 1
                }
            }
        }
        if person.primaryCircle == nil,
           let target = targets.first,
           !person.circleContacts.contains(where: { $0.circle.id == target.id }) {
            insertMembership(person, in: target)
        }
        return (created, existing)
    }

    private var orderedCircles: [GoldfishCircle] {
        circleCache.values.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
    private var nextCircleOrder: Int { (circleCache.values.map(\.sortOrder).max() ?? -1) + 1 }

    private func populateCircleCache() throws {
        circleCache.removeAll()
        for circle in try modelContext.fetch(FetchDescriptor<GoldfishCircle>()) { circleCache[circle.id] = circle }
    }

    private func insertMembership(_ person: Person, in circle: GoldfishCircle) {
        let membership = CircleContact(circle: circle, contact: person)
        modelContext.insert(membership)
        if !person.circleContacts.contains(where: { $0.id == membership.id }) { person.circleContacts.append(membership) }
        if !circle.circleContacts.contains(where: { $0.id == membership.id }) { circle.circleContacts.append(membership) }
    }

    private func autoAssignCircle(for person: Person, relatedTo other: Person, type: RelationshipType) -> Bool {
        guard let circle = PondAssignmentPolicy.suggestedCircle(
            for: person, relatedTo: other, type: type,
            systemCircles: orderedCircles.filter(\.isSystem)
        ) else { return false }
        insertMembership(person, in: circle)
        return true
    }
}

// MARK: - Array Chunks Helper
extension Array {
    func chunks(ofCount count: Int) -> [SubSequence] {
        precondition(count > 0, "Chunk size must be positive")
        var chunks: [SubSequence] = []
        var i = startIndex
        while i < endIndex {
            let nextIndex = index(i, offsetBy: count, limitedBy: endIndex) ?? endIndex
            chunks.append(self[i..<nextIndex])
            i = nextIndex
        }
        return chunks
    }
}
