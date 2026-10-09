import XCTest
import SwiftData
@testable import Goldfish

@MainActor
final class ConnectionSessionTests: XCTestCase {
    func testOnlyPersistedEdgesConnectedToAnchorCount() throws {
        let (manager, container) = try makeTestManager()
        let anchor = try manager.createPerson(name: "Anchor")
        let connected = try manager.createPerson(name: "Connected")
        let unrelated = try manager.createPerson(name: "Unrelated")
        let saved = try manager.createRelationship(from: connected, to: anchor, type: .friend)
        let wrongAnchor = try manager.createRelationship(from: connected, to: unrelated, type: .coworker)
        let session = ConnectionSession()
        session.start(isDemoMode: false)

        session.record(relationshipIDs: [saved.id, wrongAnchor.id, UUID()], anchorID: anchor.id, container: container)

        XCTAssertEqual(session.count, 1)
        XCTAssertEqual(session.peopleByRelationship, [saved.id: connected.id])
    }

    func testProgressCountsDistinctPeopleAndUndoReopensCompletion() throws {
        let (manager, container) = try makeTestManager()
        let anchor = try manager.createPerson(name: "Anchor", isMe: true)
        let others = try (0..<5).map { try manager.createPerson(name: "Person \($0)") }
        var relationships: [Relationship] = []
        for person in others {
            relationships.append(try manager.createRelationship(from: person, to: anchor, type: .friend))
        }
        // A second persisted edge to the same person must not add progress.
        let duplicatePersonEdge = try manager.createRelationship(from: others[0], to: anchor, type: .coworker)
        let session = ConnectionSession()
        session.start(isDemoMode: false)
        session.record(relationshipIDs: (relationships + [duplicatePersonEdge]).map(\.id), anchorID: anchor.id, container: container)
        XCTAssertEqual(session.count, 5)
        XCTAssertTrue(session.isComplete)

        session.undo(relationshipIDs: [relationships[4].id])

        XCTAssertEqual(session.count, 4)
        XCTAssertFalse(session.isComplete)
    }

    func testCrossScopeEdgesAreIgnoredButSharedMeIsAllowed() throws {
        let (manager, container) = try makeTestManager()
        let me = try manager.createPerson(name: "Me", isMe: true)
        let personal = try manager.createPerson(name: "Personal")
        let sample = try manager.createPerson(name: "Sample", isDemo: true)
        let personalEdge = try manager.createRelationship(from: personal, to: me, type: .friend)
        let sampleEdge = try manager.createRelationship(from: sample, to: me, type: .coworker)
        let session = ConnectionSession()
        session.start(isDemoMode: false)
        session.record(relationshipIDs: [personalEdge.id, sampleEdge.id], anchorID: me.id, container: container)
        XCTAssertEqual(session.count, 1)
        XCTAssertEqual(session.peopleByRelationship, [personalEdge.id: personal.id])

        session.start(isDemoMode: true)
        session.record(relationshipIDs: [personalEdge.id, sampleEdge.id], anchorID: me.id, container: container)
        XCTAssertEqual(session.count, 1)
        XCTAssertEqual(session.peopleByRelationship, [sampleEdge.id: sample.id])
    }

    func testSessionIsOptionalAndFinishResetsProgress() throws {
        let (manager, container) = try makeTestManager()
        let anchor = try manager.createPerson(name: "Anchor", isMe: true)
        let other = try manager.createPerson(name: "Other")
        let edge = try manager.createRelationship(from: other, to: anchor, type: .friend)
        let session = ConnectionSession()

        session.record(relationshipIDs: [edge.id], anchorID: anchor.id, container: container)
        XCTAssertFalse(session.isActive)
        XCTAssertEqual(session.count, 0)
        XCTAssertNil(session.anchorID)

        session.start(isDemoMode: false)
        session.record(relationshipIDs: [edge.id], anchorID: anchor.id, container: container)
        XCTAssertEqual(session.count, 1)
        session.finish()

        XCTAssertFalse(session.isActive)
        XCTAssertEqual(session.count, 0)
        XCTAssertNil(session.anchorID)
        XCTAssertTrue(session.peopleByRelationship.isEmpty)
    }

    func testReconcilePrunesDeletedEdgesWithoutEndingSession() throws {
        let (manager, container) = try makeTestManager()
        let anchor = try manager.createPerson(name: "Anchor", isMe: true)
        let other = try manager.createPerson(name: "Other")
        let edge = try manager.createRelationship(from: other, to: anchor, type: .friend)
        let session = ConnectionSession()
        session.start(isDemoMode: false)
        session.record(relationshipIDs: [edge.id], anchorID: anchor.id, container: container)
        XCTAssertEqual(session.count, 1)

        try manager.deleteRelationship(edge)
        session.reconcile(container: container)

        XCTAssertEqual(session.count, 0)
        XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.anchorID, anchor.id)
    }

    func testReconcilePrunesEdgesWhosePeopleNowViolateSessionScope() throws {
        let (manager, container) = try makeTestManager()
        let sampleAnchor = try manager.createPerson(name: "Sample anchor", isDemo: true)
        let sampleOther = try manager.createPerson(name: "Sample person", isDemo: true)
        let edge = try manager.createRelationship(from: sampleOther, to: sampleAnchor, type: .friend)
        let session = ConnectionSession()
        session.start(isDemoMode: true)
        session.record(relationshipIDs: [edge.id], anchorID: sampleAnchor.id, container: container)
        XCTAssertEqual(session.count, 1)

        sampleOther.isDemo = false
        try manager.context.save()
        session.reconcile(container: container)

        XCTAssertEqual(session.count, 0)
        XCTAssertTrue(session.isActive)
        XCTAssertEqual(session.anchorID, sampleAnchor.id)
    }

    func testReconcileClearsMissingAnchorAndItsMappings() throws {
        let (manager, container) = try makeTestManager()
        let anchor = try manager.createPerson(name: "Anchor")
        let other = try manager.createPerson(name: "Other")
        let edge = try manager.createRelationship(from: other, to: anchor, type: .friend)
        let session = ConnectionSession()
        session.start(isDemoMode: false)
        session.record(relationshipIDs: [edge.id], anchorID: anchor.id, container: container)

        try manager.deletePerson(anchor)
        session.reconcile(container: container)

        XCTAssertEqual(session.count, 0)
        XCTAssertNil(session.anchorID)
        XCTAssertTrue(session.isActive)
    }
}
