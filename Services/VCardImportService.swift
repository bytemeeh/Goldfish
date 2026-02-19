import Foundation
import SwiftData
import os

// MARK: - Import Result
struct ImportResult: Sendable {
    var importedCount: Int = 0
    var skippedCount: Int = 0
    var mergedCount: Int = 0 // Future use
    var errors: [String] = []
    
    // Names of skipped duplicates for user reporting
    var skippedDuplicates: [String] = []
}

// MARK: - VCardImportService
/// Background actor for processing large vCard imports without blocking the UI.
@ModelActor
actor VCardImportService {
    
    private let logger = Logger(subsystem: "com.goldfish.app", category: "VCardImportService")
    private let graphService = GraphService()
    
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
        
        let parsedContacts = VCardParser.parse(vcardData)
        let total = parsedContacts.count
        
        guard total > 0 else {
            return ImportResult(errors: ["No valid contacts found in vCard data."])
        }
        
        var result = ImportResult()
        
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
            try resolveCircles(for: person, circleNames: vContact.circles)
            
            // B. Relationships
            // vContact.relatedTo contains [(targetUUID, type)]
            for (targetUid, type) in vContact.relatedTo {
                // Find target person
                guard let targetPerson = uidMap[targetUid] else {
                    // Target might have been skipped/missing, or wasn't in the import file
                    // We can try to look it up by ID in DB if it was a reference to an existing person outside this import?
                    // Spec says: "UUID references another contact's UID field within the SAME export bundle."
                    // So if not in map, it's a broken link.
                    continue
                }
                
                // Avoid self-relationships (unless specific logic allows, but GraphService blocks directional self-loops)
                if person.id == targetPerson.id { continue }
                
                // Check if relationship already exists
                if !relationshipExists(from: person, to: targetPerson, type: type) {
                    // Create relationship
                    // Check cycle for directional types
                    if graphService.wouldCreateCycle(from: person, to: targetPerson, type: type, context: modelContext) {
                        logger.error("Skipping relationship \(person.name) -> \(targetPerson.name) (\(type.rawValue)): cycle detected")
                        continue
                    }
                    
                    let rel = Relationship(from: person, to: targetPerson, type: type)
                    modelContext.insert(rel)
                    
                    // Auto-assign circles based on relationship
                    try autoAssignSystemCircle(for: person, relationshipType: type)
                    try autoAssignSystemCircle(for: targetPerson, relationshipType: type)
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
    
    private func resolveCircles(for person: Person, circleNames: [String]) throws {
        let uniqueNames = Set(circleNames)
        
        for name in uniqueNames {
            // Check if circle exists
            // Since we might be creating circles on the fly in the same transaction,
            // we should fetch carefully.
            
            var circle: GoldfishCircle?
            
            // Fetch by name (case insensitive)
            // SwiftData predicate string comparison is reliable?
            // "Family" vs "family" -> we should normalize.
            // But efficient fetch might require exact match.
            // Let's iterate all circles if we have to, or rely on fetching.
            // Let's assume standard names.
            
            let allCircles = try modelContext.fetch(FetchDescriptor<GoldfishCircle>())
            // In-memory filter for case-insensitivity
            if let existing = allCircles.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
                circle = existing
            } else {
                // Create new custom circle
                let newCircle = GoldfishCircle(name: name, isSystem: false)
                modelContext.insert(newCircle)
                // We must save/re-fetch? No, context knows about inserted object.
                circle = newCircle
            }
            
            guard let targetCircle = circle else { continue }
            
            // Add membership if not exists
            if !person.circleContacts.contains(where: { $0.circle.id == targetCircle.id }) {
                let membership = CircleContact(circle: targetCircle, contact: person)
                modelContext.insert(membership)
            }
        }
    }
    
    private func relationshipExists(from: Person, to: Person, type: RelationshipType) -> Bool {
        // Direct Check
        // We look through outgoing relationships of 'from'
        let direct = from.outgoingRelationships.contains { rel in
            rel.toContact.id == to.id && rel.type == type
        }
        if direct { return true }
        
        // Inverse Check
        // If type has an inverse (e.g., mother -> child), check if that exists FROM the other side.
        // Relationship(from: A, to: B, type: mother) <--> Relationship(from: B, to: A, type: child)
        if let inverse = type.inverse {
             let inverseExists = to.outgoingRelationships.contains { rel in
                rel.toContact.id == from.id && rel.type == inverse
            }
            if inverseExists { return true }
        }
        
        return false
    }
    
    // Auto-assign to system circles logic (mirrors GoldfishDataManager)
    private func autoAssignSystemCircle(for person: Person, relationshipType: RelationshipType) throws {
        guard let circleName = relationshipType.autoCircleName else { return }
        
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
