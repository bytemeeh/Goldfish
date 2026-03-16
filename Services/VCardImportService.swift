import Foundation
import SwiftData
import os

// MARK: - Import Result
struct ImportResult: Sendable {
    var importedCount: Int = 0
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
    private var circleCache: [String: GoldfishCircle] = [:]
    
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
        
        // Goldfish format analysis
        if let manifest = parseResult.manifest {
            result.isGoldfishFormat = true
            result.goldfishVersion = manifest.version
            logger.info("Goldfish export detected: v\(manifest.version), \(manifest.contactCount) contacts, \(manifest.connectionCount) connections")
        }
        
        // Prepare Circle Cache
        try populateCircleCache()
        
        // Map vCard UID -> Local Person (New or Existing)
        // Used for resolving relationships across the import batch
        var uidMap: [UUID: Person] = [:]
        
        // Batch configuration
        let batchSize = 50
        var processed = 0
        
        // 1. Process Contacts (Insert/Skip)
        for chunk in parsedContacts.chunks(ofCount: batchSize) {
            for vContact in chunk {
                do {
                    // Duplicate check
                    if let existing = try findDuplicate(for: vContact) {
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
                        continue
                    }
                    
                    // Create new Person
                    let person = try createPerson(from: vContact)
                    modelContext.insert(person)
                    result.importedCount += 1
                    
                    // Map vCard UID to NEW person
                    if let vUid = vContact.uid {
                        uidMap[vUid] = person
                    }
                    
                } catch {
                    logger.error("Failed to import contact '\(vContact.name ?? "?")': \(error.localizedDescription)")
                    result.errors.append("Failed to import \(vContact.name ?? "?"): \(error.localizedDescription)")
                }
            }
            
            // Save batch
            try modelContext.save()
            
            processed += chunk.count
            progressHandler(Double(processed) / Double(total) * 0.8) // 80% progress for contact creation
        }
        
        // 2. Resolve Relationships & Circles (Pass 2)
        // Now that all persons are in modelContext (or mapped to existing), we connect them.
        // We iterate the parsed contacts again to establish links.
        
        processed = 0 // Reset for relative progress in this phase
        
        for vContact in parsedContacts {
            // Find the person object we settled on (Created or Existing)
            guard let vUid = vContact.uid, let person = uidMap[vUid] else {
                continue
            }
            
            // A. Circles
            let circleResult = try resolveCircles(for: person, circleNames: vContact.circles)
            result.circlesCreated += circleResult.created
            result.circlesExisting += circleResult.existing
            
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
                if !relationshipExists(from: person, to: targetPerson, type: type) {
                    // Create relationship
                    // Check cycle for directional types
                    if graphService.wouldCreateCycle(from: person, to: targetPerson, type: type, context: modelContext) {
                        logger.error("Skipping relationship \(person.name) -> \(targetPerson.name) (\(type.rawValue)): cycle detected")
                        result.connectionsSkipped += 1
                        continue
                    }
                    
                    let rel = Relationship(from: person, to: targetPerson, type: type)
                    modelContext.insert(rel)
                    result.connectionsRestored += 1
                    
                    // Auto-assign circles based on relationship
                    try autoAssignSystemCircle(for: person, relationshipType: type)
                    try autoAssignSystemCircle(for: targetPerson, relationshipType: type)
                } else {
                    result.connectionsSkipped += 1
                }
            }
            
            processed += 1
            if processed % batchSize == 0 {
                try modelContext.save()
                let baseProgress = 0.8
                let currentPhaseProgress = Double(processed) / Double(total) * 0.2
                progressHandler(baseProgress + currentPhaseProgress)
            }
        }
        
        // Cleanup cache
        circleCache.removeAll()
        
        try modelContext.save()
        progressHandler(1.0)
        
        return result
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
    
    /// Returns (created, existing) counts for circle resolution.
    /// Enforces single pond per contact — only the first circle name is assigned.
    private func resolveCircles(for person: Person, circleNames: [String]) throws -> (created: Int, existing: Int) {
        let uniqueNames = Set(circleNames)
        var created = 0
        var existing = 0
        var assigned = false
        
        // Check if person is already in a pond
        let alreadyInPond = person.circleContacts.contains { !$0.manuallyExcluded }
        
        for name in uniqueNames {
            var circle: GoldfishCircle?
            
            // 1. Check local session cache (populated in populateCircleCache or during this session)
            if let cached = circleCache.values.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                circle = cached
                existing += 1
            } else {
                // 2. Create new custom circle
                let newCircle = GoldfishCircle(name: name, isSystem: false)
                modelContext.insert(newCircle)
                circleCache[name.lowercased()] = newCircle
                circle = newCircle
                created += 1
            }
            
            guard let targetCircle = circle else { continue }
            
            // Single pond enforcement: only assign the first circle, skip if already in a pond
            if !assigned && !alreadyInPond {
                if !person.circleContacts.contains(where: { $0.circle.id == targetCircle.id }) {
                    // Remove any existing memberships first
                    for cc in person.circleContacts where !cc.manuallyExcluded {
                        modelContext.delete(cc)
                    }
                    let membership = CircleContact(circle: targetCircle, contact: person)
                    modelContext.insert(membership)
                }
                assigned = true
            }
        }
        
        return (created, existing)
    }
    
    /// Pre-populates the cache with all existing circles to avoid fetching in the loop.
    private func populateCircleCache() throws {
        circleCache.removeAll()
        let allCircles = try modelContext.fetch(FetchDescriptor<GoldfishCircle>())
        for circle in allCircles {
            circleCache[circle.name.lowercased()] = circle
        }
    }
    
    /// Checks if a relationship (or its inverse) already exists between two contacts.
    /// This prevents creating duplicate logical edges (e.g., Mom→Son as `mother`
    /// AND Son→Mom as `child` when they represent the same real-world relationship).
    private func relationshipExists(from: Person, to: Person, type: RelationshipType) -> Bool {
        // Direct Check: from -> to with this type
        let direct = from.outgoingRelationships.contains { rel in
            rel.toContact.id == to.id && rel.type == type
        }
        if direct { return true }
        
        // Symmetric Check: for symmetric types, also check reverse direction
        if type.isSymmetric {
            let reverseSymmetric = to.outgoingRelationships.contains { rel in
                rel.toContact.id == from.id && rel.type == type
            }
            if reverseSymmetric { return true }
        }
        
        // Inverse Check: if type has an inverse, check if the inverse relationship
        // exists from the other direction.
        // e.g., if we're trying to create (Son, Mom, child),
        // check if (Mom, Son, mother) already exists — because mother.inverse == child.
        if let inverse = type.inverse, inverse != type {
            // Check if (to -> from, inverse) exists
            let inverseExists = to.outgoingRelationships.contains { rel in
                rel.toContact.id == from.id && rel.type == inverse
            }
            if inverseExists { return true }
            
            // Also check if (from -> to, inverse) exists (shouldn't normally, but be safe)
            let inverseReverse = from.outgoingRelationships.contains { rel in
                rel.toContact.id == to.id && rel.type == inverse
            }
            if inverseReverse { return true }
        }
        
        return false
    }
    
    // Auto-assign to system circles logic (mirrors GoldfishDataManager)
    // Skips if contact is already in any pond (single pond enforcement).
    private func autoAssignSystemCircle(for person: Person, relationshipType: RelationshipType) throws {
        guard let circleName = relationshipType.autoCircleName else { return }
        
        // Skip if already in any pond (don't move people automatically)
        let activeMemberships = person.circleContacts.filter { !$0.manuallyExcluded }
        if !activeMemberships.isEmpty { return }
        
        // Find existing system circle
        let circles = try modelContext.fetch(FetchDescriptor<GoldfishCircle>(predicate: #Predicate { $0.isSystem == true }))
        guard let circle = circles.first(where: { $0.name == circleName }) else { return }
        
        // Check exclusion and existing membership
        if let existing = person.circleContacts.first(where: { $0.circle.id == circle.id }) {
            if existing.manuallyExcluded { return }
            return // Already member
        }
        
        let membership = CircleContact(circle: circle, contact: person)
        modelContext.insert(membership)
    }
}

// MARK: - Array Chunks Helper
extension Array {
    func chunks(ofCount count: Int) -> [SubSequence] {
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
