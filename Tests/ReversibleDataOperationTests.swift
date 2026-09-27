import XCTest
import SwiftData
import Foundation
@testable import Goldfish

@MainActor
final class ReversibleDataOperationTests: XCTestCase {
    private var manager: GoldfishDataManager!
    private var container: ModelContainer!

    override func setUp() async throws {
        (manager, container) = try makeTestManager()
    }

    func testRemovedRelationshipRestoresExactStoredState() throws {
        let parent = try manager.createPerson(name: "Parent")
        let child = try manager.createPerson(name: "Child")
        let relationship = try manager.createRelationship(
            from: parent,
            to: child,
            type: .mother,
            isPrimary: true,
            skipAutoAssign: true
        )
        let originalID = relationship.id
        let originalCreatedAt = relationship.createdAt

        let token = try manager.removeRelationshipWithUndo(relationship)
        XCTAssertTrue(try manager.context.fetch(FetchDescriptor<Relationship>()).isEmpty)

        let restored = try manager.restoreRemovedRelationship(using: token)

        XCTAssertEqual(restored.id, originalID)
        XCTAssertEqual(restored.fromContact.id, parent.id)
        XCTAssertEqual(restored.toContact.id, child.id)
        XCTAssertEqual(restored.type, .mother)
        XCTAssertTrue(restored.isPrimary)
        XCTAssertEqual(restored.createdAt, originalCreatedAt)
        XCTAssertEqual(try manager.context.fetch(FetchDescriptor<Relationship>()).count, 1)
    }

    func testRelationshipRestoreRejectsConflictingReplacementWithoutDuplicate() throws {
        let first = try manager.createPerson(name: "First")
        let second = try manager.createPerson(name: "Second")
        let removed = try manager.createRelationship(
            from: first,
            to: second,
            type: .friend,
            skipAutoAssign: true
        )
        let token = try manager.removeRelationshipWithUndo(removed)
        let replacement = try manager.createRelationship(
            from: second,
            to: first,
            type: .friend,
            skipAutoAssign: true
        )

        XCTAssertThrowsError(try manager.restoreRemovedRelationship(using: token)) { error in
            XCTAssertEqual(error as? GoldfishError, .undoConflict)
        }
        let stored = try manager.context.fetch(FetchDescriptor<Relationship>())
        XCTAssertEqual(stored.map(\.id), [replacement.id])
    }

    func testRelationshipRestoreRejectsDeletedEndpointWithoutChangingStore() throws {
        let first = try manager.createPerson(name: "First")
        let second = try manager.createPerson(name: "Second")
        let removed = try manager.createRelationship(
            from: first,
            to: second,
            type: .coworker,
            skipAutoAssign: true
        )
        let token = try manager.removeRelationshipWithUndo(removed)
        try manager.deletePerson(second)

        XCTAssertThrowsError(try manager.restoreRemovedRelationship(using: token)) { error in
            XCTAssertEqual(error as? GoldfishError, .undoTargetMissing)
        }
        XCTAssertTrue(try manager.context.fetch(FetchDescriptor<Relationship>()).isEmpty)
    }

    func testRelationshipRestoreRejectsAParentCycleCreatedAfterRemoval() throws {
        let first = try manager.createPerson(name: "First")
        let second = try manager.createPerson(name: "Second")
        let removed = try manager.createRelationship(
            from: first,
            to: second,
            type: .mother,
            skipAutoAssign: true
        )
        let token = try manager.removeRelationshipWithUndo(removed)
        let later = try manager.createRelationship(
            from: second,
            to: first,
            type: .mother,
            skipAutoAssign: true
        )

        XCTAssertThrowsError(try manager.restoreRemovedRelationship(using: token)) { error in
            XCTAssertEqual(error as? GoldfishError, .undoConflict)
        }
        let stored = try manager.context.fetch(FetchDescriptor<Relationship>())
        XCTAssertEqual(stored.map(\.id), [later.id])
    }

    func testPondUndoRestoresMembershipIDsAndSystemExclusionsExactly() throws {
        try manager.createSystemCircles()
        let person = try manager.createPerson(name: "Person")
        let family = try XCTUnwrap(try manager.fetchAllCircles().first { $0.name == "Family" })
        let friends = try XCTUnwrap(try manager.fetchAllCircles().first { $0.name == "Friends" })
        let custom = try manager.createCircle(name: "Choir")

        try manager.addToCircle(person, circle: family)
        try manager.removeFromCircle(person, circle: family)
        try manager.addToCircle(person, circle: custom)

        let before = snapshots(for: person)
        let token = try manager.changePondMembership(of: person, to: friends)
        XCTAssertEqual(person.primaryCircle?.id, friends.id)

        try manager.restorePondMembership(using: token)

        XCTAssertEqual(snapshots(for: person), before)
        XCTAssertEqual(person.primaryCircle?.id, custom.id)
        XCTAssertEqual(
            person.circleContacts.first(where: { $0.circle.id == family.id })?.manuallyExcluded,
            true
        )
        XCTAssertFalse(person.circleContacts.contains { $0.circle.id == friends.id })
    }

    func testPondUndoRejectsLaterMembershipEditWithoutOverwritingIt() throws {
        let person = try manager.createPerson(name: "Person")
        let first = try manager.createCircle(name: "First")
        let second = try manager.createCircle(name: "Second")
        let latest = try manager.createCircle(name: "Latest")
        try manager.addToCircle(person, circle: first)

        let token = try manager.changePondMembership(of: person, to: second)
        _ = try manager.changePondMembership(of: person, to: latest)
        let stateBeforeFailedUndo = snapshots(for: person)

        XCTAssertThrowsError(try manager.restorePondMembership(using: token)) { error in
            XCTAssertEqual(error as? GoldfishError, .undoConflict)
        }
        XCTAssertEqual(snapshots(for: person), stateBeforeFailedUndo)
        XCTAssertEqual(person.primaryCircle?.id, latest.id)
    }

    func testPondUndoRejectsDeletedOriginalPondWithoutPartialRestore() throws {
        let person = try manager.createPerson(name: "Person")
        let original = try manager.createCircle(name: "Original")
        let destination = try manager.createCircle(name: "Destination")
        try manager.addToCircle(person, circle: original)

        let token = try manager.changePondMembership(of: person, to: destination)
        try manager.deleteCircle(original)
        let stateBeforeFailedUndo = snapshots(for: person)

        XCTAssertThrowsError(try manager.restorePondMembership(using: token)) { error in
            XCTAssertEqual(error as? GoldfishError, .undoTargetMissing)
        }
        XCTAssertEqual(snapshots(for: person), stateBeforeFailedUndo)
        XCTAssertEqual(person.primaryCircle?.id, destination.id)
    }

    private func snapshots(for person: Person) -> [PondMembershipSnapshot] {
        person.circleContacts
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
}

@MainActor
final class FirstRunModeRegressionTests: XCTestCase {
    func testStartingPersonalPondDoesNotSeedSampleContactsLater() throws {
        let defaults = UserDefaults.standard
        let previousSeen = defaults.object(forKey: "hasSeenWalkthrough")
        defer { restore(previousSeen, forKey: "hasSeenWalkthrough", in: defaults) }
        defaults.removeObject(forKey: "hasSeenWalkthrough")

        let (manager, container) = try makeTestManager()
        _ = container
        try manager.performOnboarding(name: "Me")
        let walkthrough = FeatureWalkthroughManager()

        walkthrough.completeOnboardingWithoutWalkthrough()
        walkthrough.startWalkthroughIfNeeded(dataManager: manager)

        XCTAssertFalse(walkthrough.isActive)
        XCTAssertFalse(try manager.fetchAllPersons().contains { $0.isDemo })
    }

    func testLeavingSampleModeRetainsBothSamplesAndPersonalContactsInTheirScopes() throws {
        let defaults = UserDefaults.standard
        let previousMode = defaults.object(forKey: "isDemoModeActive")
        defer { restore(previousMode, forKey: "isDemoModeActive", in: defaults) }
        defaults.removeObject(forKey: "isDemoModeActive")

        let (manager, container) = try makeTestManager()
        _ = container
        _ = try manager.performOnboarding(name: "Me")
        let personal = try manager.createPerson(name: "Personal")
        let demoMode = DemoModeManager()

        XCTAssertTrue(demoMode.activateDemoMode(dataManager: manager))
        demoMode.deactivateDemoMode()

        let stored = try manager.fetchAllPersons()
        XCTAssertTrue(stored.contains { $0.isDemo })
        XCTAssertTrue(stored.contains { $0.id == personal.id })

        let home = HomeViewModel(dataManager: manager)
        home.isDemoMode = false
        home.loadData()
        XCTAssertTrue(home.contacts.contains { $0.id == personal.id })
        XCTAssertFalse(home.contacts.contains { $0.isDemo })
    }

    func testFailedSampleRemovalKeepsSampleModeAndExposesAnError() {
        enum RemovalFailure: Error { case failed }
        let defaults = UserDefaults.standard
        let previousMode = defaults.object(forKey: "isDemoModeActive")
        defer { restore(previousMode, forKey: "isDemoModeActive", in: defaults) }

        let demoMode = DemoModeManager()
        demoMode.isDemoModeActive = true

        XCTAssertFalse(demoMode.removeDemoData(operation: { throw RemovalFailure.failed }))
        XCTAssertTrue(demoMode.isDemoModeActive)
        XCTAssertEqual(demoMode.demoErrorMessage, "Couldn’t remove sample contacts. Try again.")
    }

    private func restore(_ value: Any?, forKey key: String, in defaults: UserDefaults) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
