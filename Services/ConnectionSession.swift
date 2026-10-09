import SwiftUI
import SwiftData

/// Optional, device-local session. Progress reflects saved distinct people, not taps.
@MainActor
final class ConnectionSession: ObservableObject {
    static let shared = ConnectionSession()
    @Published private(set) var isActive = false
    @Published private(set) var isDemoMode = false
    @Published private(set) var peopleByRelationship: [UUID: UUID] = [:]
    @Published private(set) var anchorID: UUID?
    @Published private(set) var feedbackID = UUID()
    private var anchorByRelationship: [UUID: UUID] = [:]
    let goal = 5
    var count: Int { Set(peopleByRelationship.values).count }
    var isComplete: Bool { count >= goal }

    func start(isDemoMode: Bool) {
        self.isDemoMode = isDemoMode
        peopleByRelationship = [:]
        anchorByRelationship = [:]
        anchorID = nil
        isActive = true
    }

    func finish() {
        isActive = false
        peopleByRelationship = [:]
        anchorByRelationship = [:]
        anchorID = nil
    }

    func record(relationshipIDs: [UUID], anchorID: UUID, container: ModelContainer) {
        guard isActive, !relationshipIDs.isEmpty else { return }
        let context = ModelContext(container)
        guard let relations = try? context.fetch(FetchDescriptor<Relationship>()) else { return }
        let requested = Set(relationshipIDs)
        for relation in relations where requested.contains(relation.id) {
            let endpoints = [relation.fromContact, relation.toContact]
            guard endpoints.contains(where: { $0.id == anchorID }),
                  endpoints.filter({ !$0.isMe }).allSatisfy({ $0.isDemo == isDemoMode }) else { continue }
            let other = relation.otherContact(from: endpoints.first { $0.id == anchorID }!)
            peopleByRelationship[relation.id] = other.id
            anchorByRelationship[relation.id] = anchorID
        }
        self.anchorID = anchorID
        feedbackID = UUID()
    }

    func undo(relationshipIDs: [UUID]) {
        for id in relationshipIDs {
            peopleByRelationship.removeValue(forKey: id)
            anchorByRelationship.removeValue(forKey: id)
        }
        feedbackID = UUID()
    }

    /// Drops progress entries whose persisted edge, endpoints, anchor, or
    /// contact scope no longer matches the state recorded for this session.
    /// An active session remains active when all its edges disappear so the
    /// user can continue from zero.
    func reconcile(container: ModelContainer) {
        let context = ModelContext(container)
        guard let people = try? context.fetch(FetchDescriptor<Person>()),
              let relationships = try? context.fetch(FetchDescriptor<Relationship>()) else { return }

        let peopleByID = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })
        let relationshipsByID = Dictionary(uniqueKeysWithValues: relationships.map { ($0.id, $0) })
        var changed = false

        if let anchorID, peopleByID[anchorID] == nil {
            self.anchorID = nil
            changed = true
        }

        var invalidRelationshipIDs: [UUID] = []
        for (relationshipID, otherID) in peopleByRelationship {
            guard let recordedAnchorID = anchorByRelationship[relationshipID],
                  let anchor = peopleByID[recordedAnchorID],
                  let other = peopleByID[otherID],
                  let relationship = relationshipsByID[relationshipID] else {
                invalidRelationshipIDs.append(relationshipID)
                continue
            }

            let connectsRecordedPeople =
                (relationship.fromContact.id == anchor.id && relationship.toContact.id == other.id) ||
                (relationship.toContact.id == anchor.id && relationship.fromContact.id == other.id)
            let endpointsMatchScope = [anchor, other]
                .filter { !$0.isMe }
                .allSatisfy { $0.isDemo == isDemoMode }
            if !connectsRecordedPeople || !endpointsMatchScope {
                invalidRelationshipIDs.append(relationshipID)
            }
        }

        for id in invalidRelationshipIDs {
            peopleByRelationship.removeValue(forKey: id)
            anchorByRelationship.removeValue(forKey: id)
            changed = true
        }
        if changed { feedbackID = UUID() }
    }
}
