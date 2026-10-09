import Foundation
import SwiftData

/// A directional relationship draft. `sourceID` is the person who IS the
/// requested role relative to `targetID` (for example, the mother of).
struct RelationshipDraft: Equatable {
    let sourceID: UUID
    let targetID: UUID
    let type: RelationshipType

    init(sourceID: UUID, targetID: UUID, type: RelationshipType) {
        self.sourceID = sourceID
        self.targetID = targetID
        self.type = type
    }
}

struct PondAssignmentUndoReceipt: Equatable {
    let entries: [Entry]

    struct Entry: Equatable {
        let personID: UUID
        let before: [PondMembershipSnapshot]
        let after: [PondMembershipSnapshot]
    }
}

enum ContactOrganizationError: LocalizedError, Equatable {
    case emptyBatch
    case missingPerson
    case missingPond
    case mixedDemoScope
    case cannotAssignSelf
    case selfRelationship
    case ancestryCycle
    case undoConflict
    case undoTargetMissing

    var errorDescription: String? {
        switch self {
        case .emptyBatch: return "Select at least one contact."
        case .missingPerson: return "A selected contact could not be found."
        case .missingPond: return "The selected pond could not be found."
        case .mixedDemoScope: return "Sample and personal contacts cannot be changed together."
        case .cannotAssignSelf: return "Me cannot be assigned to a pond."
        case .selfRelationship: return "A contact cannot be connected to itself."
        case .ancestryCycle: return "This relationship would create an ancestry cycle."
        case .undoConflict: return "Undo is unavailable because this data changed afterward."
        case .undoTargetMissing: return "Undo is unavailable because a contact, pond, or connection was removed."
        }
    }
}

/// Atomic bulk contact organization. It uses its own context so each operation
/// has one save/rollback boundary and relationship creation never guesses pond
/// membership from a role.
@MainActor
final class ContactOrganizationService {
    private let container: ModelContainer
    private(set) var context: ModelContext
    private var relationshipUndoSnapshots: [UUID: RelationshipState] = [:]

    private struct RelationshipState: Equatable {
        let sourceID: UUID
        let targetID: UUID
        let typeRawValue: String
        let isPrimary: Bool
        let createdAt: Date

        init(_ relationship: Relationship) {
            sourceID = relationship.fromContact.id
            targetID = relationship.toContact.id
            typeRawValue = relationship.typeRawValue
            isPrimary = relationship.isPrimary
            createdAt = relationship.createdAt
        }
    }

    init(container: ModelContainer) {
        self.container = container
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    init(context: ModelContext) {
        self.container = context.container
        self.context = ModelContext(context.container)
        self.context.autosaveEnabled = false
    }

    private func beginOperation() {
        // A new context sees edits committed by other parts of the app before
        // validating an undo receipt.
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    /// Assigns all selected contacts to one pond as a single transaction.
    /// System pond exclusion rows are retained; undo restores exact row IDs,
    /// exclusion values, and timestamps.
    func assignPeople(ids: Set<UUID>, to pondID: UUID) throws -> PondAssignmentUndoReceipt {
        guard !ids.isEmpty else { throw ContactOrganizationError.emptyBatch }
        beginOperation()
        do {
            let people = try context.fetch(FetchDescriptor<Person>())
            let byID = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })
            guard ids.allSatisfy({ byID[$0] != nil }) else { throw ContactOrganizationError.missingPerson }
            let selected = ids.compactMap { byID[$0] }
            guard Set(selected.filter { !$0.isMe }.map(\.isDemo)).count <= 1 else {
                throw ContactOrganizationError.mixedDemoScope
            }
            guard !selected.contains(where: \.isMe) else { throw ContactOrganizationError.cannotAssignSelf }
            guard let pond = try context.fetch(FetchDescriptor<GoldfishCircle>()).first(where: { $0.id == pondID }) else {
                throw ContactOrganizationError.missingPond
            }

            var entries: [PondAssignmentUndoReceipt.Entry] = []
            for person in selected.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
                let before = try membershipSnapshots(for: person.id)
                // Deactivate active rows while preserving exclusion rows exactly.
                for membership in person.circleContacts where !membership.manuallyExcluded {
                    if membership.circle.isSystem {
                        membership.manuallyExcluded = true
                    } else {
                        detach(membership)
                    }
                }
                if let existing = person.circleContacts.first(where: { $0.circle.id == pond.id }) {
                    existing.manuallyExcluded = false
                } else {
                    let membership = CircleContact(circle: pond, contact: person)
                    context.insert(membership)
                    person.circleContacts.append(membership)
                    pond.circleContacts.append(membership)
                }
                entries.append(.init(personID: person.id, before: before, after: try membershipSnapshots(for: person.id)))
            }
            try commit()
            return PondAssignmentUndoReceipt(entries: entries)
        } catch {
            context.rollback()
            throw error
        }
    }

    func undoAssignment(_ receipt: PondAssignmentUndoReceipt) throws {
        beginOperation()
        do {
            let people = try context.fetch(FetchDescriptor<Person>())
            let peopleByID = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })
            let circles = try context.fetch(FetchDescriptor<GoldfishCircle>())
            let circlesByID = Dictionary(uniqueKeysWithValues: circles.map { ($0.id, $0) })
            for entry in receipt.entries {
                guard peopleByID[entry.personID] != nil,
                      (entry.before + entry.after).allSatisfy({ circlesByID[$0.circleID] != nil }) else {
                    throw ContactOrganizationError.undoTargetMissing
                }
                guard try membershipSnapshots(for: entry.personID) == entry.after else {
                    throw ContactOrganizationError.undoConflict
                }
            }
            // The junction model has a unique ID, so a captured row cannot be
            // reassigned to another person without changing the current state
            // checked above.
            for entry in receipt.entries {
                guard let person = peopleByID[entry.personID] else { throw ContactOrganizationError.undoTargetMissing }
                let priorIDs = Set(entry.before.map(\.membershipID))
                for row in Array(person.circleContacts) where !priorIDs.contains(row.id) { detach(row) }
                var rowsByID = Dictionary(uniqueKeysWithValues: person.circleContacts.map { ($0.id, $0) })
                for snapshot in entry.before {
                    guard let circle = circlesByID[snapshot.circleID] else { throw ContactOrganizationError.undoTargetMissing }
                    let row: CircleContact
                    if let existing = rowsByID[snapshot.membershipID] {
                        if existing.circle.id != circle.id {
                            existing.circle.circleContacts.removeAll { $0.id == existing.id }
                            existing.circle = circle
                        }
                        row = existing
                    } else {
                        row = CircleContact(id: snapshot.membershipID, circle: circle, contact: person,
                                            manuallyExcluded: snapshot.manuallyExcluded)
                        context.insert(row)
                        person.circleContacts.append(row)
                    }
                    row.manuallyExcluded = snapshot.manuallyExcluded
                    row.createdAt = snapshot.createdAt
                    if !circle.circleContacts.contains(where: { $0.id == row.id }) { circle.circleContacts.append(row) }
                    rowsByID[row.id] = row
                }
            }
            try commit()
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Validates the complete batch before insertion, then commits all new
    /// edges together. Existing logical edges (including inverse duplicates)
    /// are left untouched and omitted from the returned undo IDs.
    func createRelationships(_ drafts: [RelationshipDraft]) throws -> [UUID] {
        guard !drafts.isEmpty else { throw ContactOrganizationError.emptyBatch }
        beginOperation()
        do {
            let people = try context.fetch(FetchDescriptor<Person>())
            let byID = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })
            guard drafts.allSatisfy({ byID[$0.sourceID] != nil && byID[$0.targetID] != nil }) else {
                throw ContactOrganizationError.missingPerson
            }
            let endpoints = drafts.flatMap { [byID[$0.sourceID]!, byID[$0.targetID]!] }
            guard Set(endpoints.filter { !$0.isMe }.map(\.isDemo)).count <= 1 else {
                throw ContactOrganizationError.mixedDemoScope
            }
            for draft in drafts where draft.sourceID == draft.targetID { throw ContactOrganizationError.selfRelationship }

            // Build and validate the entire ancestry graph before inserting any
            // rows. This catches cycles formed only by edges in this batch.
            var childrenByParent: [UUID: Set<UUID>] = [:]
            let existing = try context.fetch(FetchDescriptor<Relationship>())
            for relation in existing where isAncestryType(relation.type) {
                let edge = ancestryEdge(from: relation.fromContact.id, to: relation.toContact.id, type: relation.type)
                childrenByParent[edge.parent, default: []].insert(edge.child)
            }
            for draft in drafts where isAncestryType(draft.type) {
                let edge = ancestryEdge(from: draft.sourceID, to: draft.targetID, type: draft.type)
                if hasPath(from: edge.child, to: edge.parent, in: childrenByParent) {
                    throw ContactOrganizationError.ancestryCycle
                }
                childrenByParent[edge.parent, default: []].insert(edge.child)
            }

            var created: [Relationship] = []
            for draft in drafts {
                guard let source = byID[draft.sourceID], let target = byID[draft.targetID] else {
                    throw ContactOrganizationError.missingPerson
                }
                if source.allRelationships.contains(where: { $0.matches(from: source, to: target, type: draft.type) }) {
                    continue
                }
                let relation = Relationship(from: source, to: target, type: draft.type)
                context.insert(relation)
                source.outgoingRelationships.append(relation)
                target.incomingRelationships.append(relation)
                created.append(relation)
            }
            try commit()
            for relationship in created {
                relationshipUndoSnapshots[relationship.id] = RelationshipState(relationship)
            }
            return created.map(\.id)
        } catch {
            context.rollback()
            throw error
        }
    }

    func undoRelationships(ids: [UUID]) throws {
        guard !ids.isEmpty else { return }
        beginOperation()
        do {
            let relationships = try context.fetch(FetchDescriptor<Relationship>())
            let byID = Dictionary(uniqueKeysWithValues: relationships.map { ($0.id, $0) })
            guard ids.allSatisfy({ byID[$0] != nil }) else { throw ContactOrganizationError.undoTargetMissing }
            guard ids.allSatisfy({ id in
                guard let relationship = byID[id], let captured = relationshipUndoSnapshots[id] else { return false }
                return RelationshipState(relationship) == captured
            }) else { throw ContactOrganizationError.undoConflict }
            for id in Set(ids) {
                guard let relationship = byID[id] else { continue }
                relationship.fromContact.outgoingRelationships.removeAll { $0.id == id }
                relationship.toContact.incomingRelationships.removeAll { $0.id == id }
                context.delete(relationship)
            }
            try commit()
            for id in Set(ids) { relationshipUndoSnapshots.removeValue(forKey: id) }
        } catch {
            context.rollback()
            throw error
        }
    }

    private func membershipSnapshots(for personID: UUID) throws -> [PondMembershipSnapshot] {
        try context.fetch(FetchDescriptor<CircleContact>()).filter { $0.contact.id == personID }.map {
            PondMembershipSnapshot(membershipID: $0.id, circleID: $0.circle.id,
                                   manuallyExcluded: $0.manuallyExcluded, createdAt: $0.createdAt)
        }.sorted { $0.membershipID.uuidString < $1.membershipID.uuidString }
    }

    private func detach(_ row: CircleContact) {
        row.contact.circleContacts.removeAll { $0.id == row.id }
        row.circle.circleContacts.removeAll { $0.id == row.id }
        context.delete(row)
    }

    private func ancestryEdge(from source: UUID, to target: UUID, type: RelationshipType) -> (parent: UUID, child: UUID) {
        type == .child ? (target, source) : (source, target)
    }

    private func isAncestryType(_ type: RelationshipType) -> Bool {
        type == .mother || type == .father || type == .parent || type == .child
    }

    private func hasPath(from start: UUID, to goal: UUID, in childrenByParent: [UUID: Set<UUID>]) -> Bool {
        var pending = [start]
        var visited: Set<UUID> = []
        while let current = pending.popLast() {
            if current == goal { return true }
            guard visited.insert(current).inserted else { continue }
            pending.append(contentsOf: childrenByParent[current] ?? [])
        }
        return false
    }

    private func commit() throws {
        try context.save()
        NotificationCenter.default.post(name: .goldfishDataDidChange, object: nil)
    }
}
