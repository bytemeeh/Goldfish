import XCTest
import SwiftData
import Foundation
@testable import Goldfish

@MainActor
final class ContactOrganizationTests: XCTestCase {
    func testAssignFiftyPeopleAndUndoRestoresExactMembershipsAndExclusions() throws {
        let (manager, container) = try makeTestManager()
        try manager.createSystemCircles()
        let ponds = try manager.fetchAllCircles()
        let family = try XCTUnwrap(ponds.first { $0.name == "Family" })
        let friends = try XCTUnwrap(ponds.first { $0.name == "Friends" })
        let selected = try (0..<50).map { index in
            try manager.createPerson(name: "Contact \(index)")
        }
        try manager.addToCircle(selected[0], circle: family)
        try manager.removeFromCircle(selected[0], circle: family)
        try manager.addToCircle(selected[1], circle: family)
        let before = Dictionary(uniqueKeysWithValues: selected.map { ($0.id, snapshots($0)) })

        let service = ContactOrganizationService(container: container)
        let receipt = try service.assignPeople(ids: Set(selected.map(\.id)), to: friends.id)
        XCTAssertEqual(receipt.entries.count, 50)
        let readContext = ModelContext(container)
        let fresh = try readContext.fetch(FetchDescriptor<Person>())
        for person in selected {
            let assigned = try XCTUnwrap(fresh.first { $0.id == person.id })
            XCTAssertEqual(assigned.primaryCircle?.id, friends.id)
        }

        try service.undoAssignment(receipt)
        let afterUndo = try readContext.fetch(FetchDescriptor<Person>())
        for person in selected {
            XCTAssertEqual(snapshots(try XCTUnwrap(afterUndo.first { $0.id == person.id })), before[person.id])
        }
    }

    func testBatchRelationshipsPreserveDirectionDeduplicateInverseAndDoNotAssignPonds() throws {
        let (manager, container) = try makeTestManager()
        try manager.createSystemCircles()
        let me = try manager.createPerson(name: "Parent")
        let child = try manager.createPerson(name: "Child")
        let friendA = try manager.createPerson(name: "A")
        let friendB = try manager.createPerson(name: "B")
        let drafts = [
            RelationshipDraft(sourceID: me.id, targetID: child.id, type: .mother),
            RelationshipDraft(sourceID: friendA.id, targetID: friendB.id, type: .friend),
            RelationshipDraft(sourceID: friendB.id, targetID: friendA.id, type: .friend)
        ]
        let service = ContactOrganizationService(container: container)
        let ids = try service.createRelationships(drafts)
        XCTAssertEqual(ids.count, 2)
        let relationships = try manager.context.fetch(FetchDescriptor<Relationship>())
        let maternal = try XCTUnwrap(relationships.first { $0.type == .mother })
        XCTAssertEqual(maternal.fromContact.id, me.id)
        XCTAssertEqual(maternal.toContact.id, child.id)
        XCTAssertTrue(try manager.fetchAllPersons().allSatisfy { $0.primaryCircle == nil })

        try service.undoRelationships(ids: ids)
        XCTAssertTrue(try manager.context.fetch(FetchDescriptor<Relationship>()).isEmpty)
    }

    func testBatchCycleAndMixedDemoScopeFailWithoutPartialWrites() throws {
        let (manager, container) = try makeTestManager()
        let a = try manager.createPerson(name: "A")
        let b = try manager.createPerson(name: "B")
        let c = try manager.createPerson(name: "C")
        let service = ContactOrganizationService(container: container)
        let cycle = [
            RelationshipDraft(sourceID: a.id, targetID: b.id, type: .parent),
            RelationshipDraft(sourceID: b.id, targetID: c.id, type: .parent),
            RelationshipDraft(sourceID: c.id, targetID: a.id, type: .parent)
        ]
        XCTAssertThrowsError(try service.createRelationships(cycle)) {
            XCTAssertEqual($0 as? ContactOrganizationError, .ancestryCycle)
        }
        XCTAssertTrue(try manager.context.fetch(FetchDescriptor<Relationship>()).isEmpty)

        let sample = try manager.createPerson(name: "Sample", isDemo: true)
        XCTAssertThrowsError(try service.createRelationships([
            RelationshipDraft(sourceID: a.id, targetID: b.id, type: .friend),
            RelationshipDraft(sourceID: b.id, targetID: sample.id, type: .friend)
        ])) {
            XCTAssertEqual($0 as? ContactOrganizationError, .mixedDemoScope)
        }
        XCTAssertTrue(try manager.context.fetch(FetchDescriptor<Relationship>()).isEmpty)
    }

    func testSharedMeCanConnectPersonalAndSampleContacts() throws {
        let (manager, container) = try makeTestManager()
        let me = try manager.createPerson(name: "Me", isMe: true)
        let sample = try manager.createPerson(name: "Sample", isDemo: true)
        let service = ContactOrganizationService(container: container)
        let ids = try service.createRelationships([
            RelationshipDraft(sourceID: sample.id, targetID: me.id, type: .friend)
        ])
        XCTAssertEqual(ids.count, 1)

        let personal = try manager.createPerson(name: "Personal")
        XCTAssertThrowsError(try service.createRelationships([
            RelationshipDraft(sourceID: sample.id, targetID: me.id, type: .sibling),
            RelationshipDraft(sourceID: personal.id, targetID: me.id, type: .friend)
        ])) {
            XCTAssertEqual($0 as? ContactOrganizationError, .mixedDemoScope)
        }
    }

    func testInvalidIDsAndSelfAssignmentAreRejectedBeforeSaving() throws {
        let (manager, container) = try makeTestManager()
        let me = try manager.createPerson(name: "Me", isMe: true)
        let person = try manager.createPerson(name: "Person")
        let pond = try manager.createCircle(name: "Pond")
        let service = ContactOrganizationService(container: container)

        XCTAssertThrowsError(try service.assignPeople(ids: [UUID()], to: pond.id)) {
            XCTAssertEqual($0 as? ContactOrganizationError, .missingPerson)
        }
        XCTAssertThrowsError(try service.assignPeople(ids: [me.id], to: pond.id)) {
            XCTAssertEqual($0 as? ContactOrganizationError, .cannotAssignSelf)
        }
        XCTAssertThrowsError(try service.createRelationships([
            RelationshipDraft(sourceID: person.id, targetID: UUID(), type: .friend)
        ])) {
            XCTAssertEqual($0 as? ContactOrganizationError, .missingPerson)
        }
        XCTAssertTrue(try manager.context.fetch(FetchDescriptor<Relationship>()).isEmpty)
        XCTAssertTrue(person.circleContacts.isEmpty)
    }

    func testAssignmentUndoDetectsMembershipChangedInAnotherContext() throws {
        let (manager, container) = try makeTestManager()
        let person = try manager.createPerson(name: "Person")
        let first = try manager.createCircle(name: "First")
        let assigned = try manager.createCircle(name: "Assigned")
        let later = try manager.createCircle(name: "Later")
        try manager.addToCircle(person, circle: first)

        let service = ContactOrganizationService(container: container)
        let receipt = try service.assignPeople(ids: [person.id], to: assigned.id)
        try manager.changePondMembership(of: person, to: later)
        let stateBeforeUndo = snapshots(person)

        XCTAssertThrowsError(try service.undoAssignment(receipt)) {
            XCTAssertEqual($0 as? ContactOrganizationError, .undoConflict)
        }
        XCTAssertEqual(snapshots(person), stateBeforeUndo)
        XCTAssertEqual(person.primaryCircle?.id, later.id)
    }

    func testRelationshipUndoRejectsLaterRelationshipEdits() throws {
        let (manager, container) = try makeTestManager()
        let source = try manager.createPerson(name: "Source")
        let target = try manager.createPerson(name: "Target")
        let service = ContactOrganizationService(container: container)
        let ids = try service.createRelationships([
            RelationshipDraft(sourceID: source.id, targetID: target.id, type: .friend)
        ])
        let relation = try XCTUnwrap(manager.context.fetch(FetchDescriptor<Relationship>()).first)
        relation.isPrimary = true
        try manager.context.save()

        XCTAssertThrowsError(try service.undoRelationships(ids: ids)) {
            XCTAssertEqual($0 as? ContactOrganizationError, .undoConflict)
        }
        XCTAssertTrue(relation.isPrimary)
    }

    private func snapshots(_ person: Person) -> [PondMembershipSnapshot] {
        person.circleContacts.map {
            PondMembershipSnapshot(membershipID: $0.id, circleID: $0.circle.id,
                                   manuallyExcluded: $0.manuallyExcluded, createdAt: $0.createdAt)
        }.sorted { $0.membershipID.uuidString < $1.membershipID.uuidString }
    }
}
