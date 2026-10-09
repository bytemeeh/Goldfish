import XCTest
import SwiftData
@testable import Goldfish

// MARK: - Test Helpers

/// Creates an in-memory ModelContainer for isolated testing.
/// No CloudKit, no disk persistence — tests run fast and don't interfere.
@MainActor
func makeTestContainer() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let schema = Schema([
        Person.self,
        Relationship.self,
        Location.self,
        GoldfishCircle.self,
        CircleContact.self
    ])
    return try ModelContainer(for: schema, configurations: [config])
}

/// Creates a GoldfishDataManager backed by an in-memory store.
/// Also returns the container — callers must retain it for the test's lifetime,
/// because ModelContext does not keep its ModelContainer alive (a deallocated
/// container makes the first insert trap inside SwiftData).
@MainActor
func makeTestManager() throws -> (manager: GoldfishDataManager, container: ModelContainer) {
    let container = try makeTestContainer()
    return (GoldfishDataManager(context: container.mainContext), container)
}

// MARK: - Cycle Detection Tests

@MainActor
final class CycleDetectionTests: XCTestCase {

    var manager: GoldfishDataManager!
    var container: ModelContainer!

    override func setUp() async throws {
        (manager, container) = try makeTestManager()
    }

    /// A is B's mother, B is C's mother.
    /// "A is C's child" makes C an ancestor of A while A is an ancestor of C
    /// (lineage cycle A→B→C→A) → blocked.
    func testDirectionalCycleIsBlocked() throws {
        let a = try manager.createPerson(name: "Alice")
        let b = try manager.createPerson(name: "Bob")
        let c = try manager.createPerson(name: "Charlie")

        // A is B's mother
        try manager.createRelationship(from: a, to: b, type: .mother)
        // B is C's mother
        try manager.createRelationship(from: b, to: c, type: .mother)

        // A is C's child → C becomes A's parent, closing the cycle A→B→C→A
        XCTAssertThrowsError(
            try manager.createRelationship(from: a, to: c, type: .child)
        ) { error in
            XCTAssertEqual(error as? GoldfishError, .wouldCreateCycle)
        }
    }

    /// A is B's father AND B is A's father — the minimal genuine cycle → blocked.
    func testMutualParenthoodIsBlocked() throws {
        let a = try manager.createPerson(name: "Alice")
        let b = try manager.createPerson(name: "Bob")

        try manager.createRelationship(from: a, to: b, type: .father)

        XCTAssertThrowsError(
            try manager.createRelationship(from: b, to: a, type: .father)
        ) { error in
            XCTAssertEqual(error as? GoldfishError, .wouldCreateCycle)
        }
    }

    /// One parent having two children is valid — regression test for the
    /// false positive hit by DemoDataService.seedDemoData. With
    /// dad —father→ me, mom —mother→ me, mom —mother→ tom in place, the old
    /// connectivity-based detector found dad via tom←mom→me←dad and wrongly
    /// flagged dad —father→ tom as a cycle.
    func testParentOfTwoChildrenIsAllowed() throws {
        let me = try manager.createPerson(name: "Me")
        let mom = try manager.createPerson(name: "Mom")
        let dad = try manager.createPerson(name: "Dad")
        let tom = try manager.createPerson(name: "Tom")

        try manager.createRelationship(from: dad, to: me, type: .father)
        try manager.createRelationship(from: mom, to: me, type: .mother)
        try manager.createRelationship(from: mom, to: tom, type: .mother)

        XCTAssertNoThrow(
            try manager.createRelationship(from: dad, to: tom, type: .father)
        )
    }

    /// Both parents linked to both children, plus spouse/sibling edges —
    /// the full DemoDataService family shape must seed without cycle errors.
    func testFullNuclearFamilyIsAllowed() throws {
        let me = try manager.createPerson(name: "Me")
        let mom = try manager.createPerson(name: "Mom")
        let dad = try manager.createPerson(name: "Dad")
        let tom = try manager.createPerson(name: "Tom")

        try manager.createRelationship(from: mom, to: me, type: .mother)
        try manager.createRelationship(from: dad, to: me, type: .father)
        try manager.createRelationship(from: me, to: tom, type: .sibling)
        XCTAssertNoThrow(try manager.createRelationship(from: mom, to: tom, type: .mother))
        XCTAssertNoThrow(try manager.createRelationship(from: dad, to: tom, type: .father))
        XCTAssertNoThrow(try manager.createRelationship(from: mom, to: dad, type: .spouse))
    }

    /// Symmetric types (friend) should never trigger cycle detection.
    /// A ↔ B ↔ C ↔ A is perfectly valid for friendships.
    func testSymmetricCycleIsAllowed() throws {
        let a = try manager.createPerson(name: "Alice")
        let b = try manager.createPerson(name: "Bob")
        let c = try manager.createPerson(name: "Charlie")

        try manager.createRelationship(from: a, to: b, type: .friend)
        try manager.createRelationship(from: b, to: c, type: .friend)

        // This should NOT throw — friend cycles are fine
        XCTAssertNoThrow(
            try manager.createRelationship(from: c, to: a, type: .friend)
        )
    }

    /// A person cannot be their own parent (self-loop on directional type).
    func testSelfRelationshipBlockedForDirectional() throws {
        let a = try manager.createPerson(name: "Alice")

        XCTAssertThrowsError(
            try manager.createRelationship(from: a, to: a, type: .mother)
        ) { error in
            XCTAssertEqual(error as? GoldfishError, .selfRelationship)
        }
        XCTAssertTrue(a.allRelationships.isEmpty)
    }

    /// Simple parent-child relationship (no cycle) should succeed.
    func testValidDirectionalRelationship() throws {
        let parent = try manager.createPerson(name: "Parent")
        let child = try manager.createPerson(name: "Child")

        XCTAssertNoThrow(
            try manager.createRelationship(from: parent, to: child, type: .mother)
        )
    }
}

@MainActor
final class PetIdentityTests: XCTestCase {
    func testPetCreateEditPersistsAndMeStaysHuman() throws {
        let (manager, container) = try makeTestManager()
        let pet = try manager.createPerson(name: "Milo", petKindRaw: ContactKind.dog.rawValue)
        XCTAssertTrue(pet.isPet)
        XCTAssertEqual(pet.petSpeciesLabel, "Dog")

        try manager.updatePerson(pet, petKindRaw: .set(ContactKind.cat.rawValue))
        XCTAssertEqual(pet.contactKind, .cat)
        let me = try manager.createPerson(name: "Me", isMe: true, petKindRaw: ContactKind.dog.rawValue)
        XCTAssertFalse(me.isPet)
        XCTAssertNil(me.petKindRaw)
        XCTAssertNotNil(container)
        try manager.updatePerson(me, petKindRaw: .set(ContactKind.cat.rawValue))
        XCTAssertFalse(me.isPet)
        XCTAssertNil(me.petKindRaw)
    }

    func testPetGuardianInverseDoesNotTriggerAncestryCycle() throws {
        let (manager, container) = try makeTestManager()
        let pet = try manager.createPerson(name: "Milo", petKindRaw: ContactKind.dog.rawValue)
        let guardian = try manager.createPerson(name: "Alex")
        let relationship = try manager.createRelationship(from: pet, to: guardian, type: .pet)
        XCTAssertEqual(relationship.effectiveType(for: pet), .pet)
        XCTAssertEqual(relationship.effectiveType(for: guardian), .guardian)
        XCTAssertNoThrow(try manager.createRelationship(from: guardian, to: pet, type: .guardian))
        XCTAssertNotNil(container)
    }

    func testPetAndRelationshipSurviveDiskStoreReopen() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("goldfish-pet-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let configuration = ModelConfiguration(url: url)
        let schema = Schema([Person.self, Relationship.self, Location.self, GoldfishCircle.self, CircleContact.self])
        let firstContainer = try ModelContainer(for: schema, configurations: [configuration])
        let firstManager = GoldfishDataManager(context: firstContainer.mainContext)
        let pet = try firstManager.createPerson(name: "Milo", petKindRaw: ContactKind.dog.rawValue)
        let guardian = try firstManager.createPerson(name: "Alex")
        try firstManager.createRelationship(from: pet, to: guardian, type: .pet)
        try firstManager.context.save()
        let reopened = try ModelContainer(for: schema, configurations: [configuration])
        let manager = GoldfishDataManager(context: reopened.mainContext)
        let contacts = try manager.fetchAllPersons()
        let reopenedPet = try XCTUnwrap(contacts.first { $0.name == "Milo" })
        let reopenedGuardian = try XCTUnwrap(contacts.first { $0.name == "Alex" })
        XCTAssertEqual(reopenedPet.contactKind, .dog)
        let relationship = try XCTUnwrap(reopenedPet.allRelationships.first { $0.otherContact(from: reopenedPet).id == reopenedGuardian.id })
        XCTAssertEqual(relationship.effectiveType(for: reopenedPet), .pet)
    }

    func testAtomicRollbackRestoresPetKind() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("goldfish-rollback-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: url) }
        let schema = Schema([Person.self, Relationship.self, Location.self, GoldfishCircle.self, CircleContact.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(url: url)])
        let manager = GoldfishDataManager(context: container.mainContext)
        let pet = try manager.createPerson(name: "Milo", petKindRaw: ContactKind.dog.rawValue)
        try manager.updatePerson(pet, petKindRaw: .set(ContactKind.cat.rawValue))
        try manager.updatePerson(pet, petKindRaw: .set(ContactKind.dog.rawValue))
        struct TestFailure: Error {}
        XCTAssertThrowsError(try manager.performAtomicEdit {
            try manager.updatePerson(pet, petKindRaw: .set(ContactKind.cat.rawValue))
            try manager.performAtomicEdit {
                try manager.updatePerson(pet, petKindRaw: .set(ContactKind.pet.rawValue))
            }
            throw TestFailure()
        })
        XCTAssertEqual(pet.contactKind, .dog)
        // Also verify the durable atomic rollback result by reopening the store.
        let reopened = try ModelContainer(for: schema, configurations: [ModelConfiguration(url: url)])
        let petID = pet.id
        let restored = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<Person>(predicate: #Predicate { $0.id == petID })).first)
        XCTAssertEqual(restored.contactKind, .dog)
        XCTAssertNotNil(container)
    }
}

// MARK: - Search Tests

@MainActor
final class SearchTests: XCTestCase {

    var manager: GoldfishDataManager!
    var container: ModelContainer!

    override func setUp() async throws {
        (manager, container) = try makeTestManager()
    }

    /// Partial, case-insensitive name match.
    func testSearchByName() throws {
        try manager.createPerson(name: "Mara Morgan")
        try manager.createPerson(name: "Maria Mueller")
        try manager.createPerson(name: "Bob Smith")

        let results = try manager.search(query: "mar")
        XCTAssertEqual(results.count, 2)
        XCTAssertTrue(results.allSatisfy {
            $0.name.lowercased().contains("mar")
        })
    }

    /// Exact name match ranks above contains.
    func testSearchRanking() throws {
        try manager.createPerson(name: "Bob")
        try manager.createPerson(name: "Bobby")
        try manager.createPerson(name: "Mr. Bob Jones")

        let results = try manager.search(query: "bob")
        XCTAssertGreaterThanOrEqual(results.count, 3)
        // "Bob" (exact) should rank first
        XCTAssertEqual(results.first?.name, "Bob")
    }

    /// Search by email field.
    func testSearchByEmail() throws {
        try manager.createPerson(name: "Alice", email: "alice@example.com")
        try manager.createPerson(name: "Bob")

        let results = try manager.search(query: "alice@")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.name, "Alice")
    }

    /// Search finds contacts via their circle name.
    func testSearchByCircleName() throws {
        try manager.createSystemCircles()
        let alice = try manager.createPerson(name: "Alice")
        let circles = try manager.fetchSystemCircles()
        let familyCircle = circles.first { $0.name == "Family" }!
        try manager.addToCircle(alice, circle: familyCircle)

        let results = try manager.search(query: "Family")
        XCTAssertTrue(results.contains { $0.id == alice.id })
    }

    /// Empty query returns no results.
    func testEmptyQueryReturnsNothing() throws {
        try manager.createPerson(name: "Alice")

        let results = try manager.search(query: "")
        XCTAssertTrue(results.isEmpty)
    }

    /// Search by tags.
    func testSearchByTag() throws {
        try manager.createPerson(name: "Alice", tags: ["gym", "yoga"])
        try manager.createPerson(name: "Bob", tags: ["work"])

        let results = try manager.search(query: "gym")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.name, "Alice")
    }
}

// MARK: - IsMe Invariant Tests

@MainActor
final class IsMeInvariantTests: XCTestCase {

    var manager: GoldfishDataManager!
    var container: ModelContainer!

    override func setUp() async throws {
        (manager, container) = try makeTestManager()
    }

    /// The isMe contact cannot be deleted.
    func testIsMeCannotBeDeleted() throws {
        let me = try manager.createPerson(name: "Me", isMe: true)

        XCTAssertThrowsError(try manager.deletePerson(me)) { error in
            XCTAssertEqual(error as? GoldfishError, .cannotDeleteSelf)
        }
    }

    /// Only one isMe contact can exist.
    func testOnlyOneIsMeAllowed() throws {
        try manager.createPerson(name: "Me", isMe: true)

        XCTAssertThrowsError(
            try manager.createPerson(name: "Also Me", isMe: true)
        ) { error in
            XCTAssertEqual(error as? GoldfishError, .isMeAlreadyExists)
        }
    }

    /// Non-isMe contacts can be deleted normally.
    func testRegularContactCanBeDeleted() throws {
        let bob = try manager.createPerson(name: "Bob")

        XCTAssertNoThrow(try manager.deletePerson(bob))
    }
}

// MARK: - Circle Auto-Assignment Tests

@MainActor
final class CircleAutoAssignmentTests: XCTestCase {

    var manager: GoldfishDataManager!
    var container: ModelContainer!

    override func setUp() async throws {
        (manager, container) = try makeTestManager()
        try manager.createSystemCircles()
    }

    /// A direct parent belongs in your Family; Me remains outside every pond.
    func testMotherRelationshipAutoAssignsToFamily() throws {
        let mom = try manager.createPerson(name: "Mom")
        let child = try manager.createPerson(name: "Me", isMe: true)

        try manager.createRelationship(from: mom, to: child, type: .mother)

        let familyCircle = try manager.fetchSystemCircles().first { $0.name == "Family" }!
        let members = familyCircle.activeContacts
        XCTAssertTrue(members.contains { $0.id == mom.id })
        XCTAssertFalse(members.contains { $0.id == child.id })
    }

    func testFriendsHouseholdKeepsItsContextWhileDirectFamilyStaysFamily() throws {
        let me = try manager.createPerson(name: "Me", isMe: true)
        let jake = try manager.createPerson(name: "Jake")
        let nicole = try manager.createPerson(name: "Nicole")
        let child = try manager.createPerson(name: "Child")
        let dog = try manager.createPerson(name: "Biscuit", petKindRaw: "dog")
        let parent = try manager.createPerson(name: "Parent")
        try manager.createRelationship(from: me, to: jake, type: .friend)
        try manager.createRelationship(from: nicole, to: jake, type: .spouse)
        try manager.createRelationship(from: jake, to: child, type: .parent)
        try manager.createRelationship(from: dog, to: nicole, type: .pet)
        try manager.createRelationship(from: parent, to: me, type: .parent)
        XCTAssertTrue([jake, nicole, child, dog].allSatisfy { $0.primaryCircle?.name == "Friends" })
        XCTAssertEqual(parent.primaryCircle?.name, "Family")
        XCTAssertNil(me.primaryCircle)
    }

    func testUnplacedHouseholdIsNotAssumedToBeYourFamily() throws {
        let parent = try manager.createPerson(name: "Someone's parent")
        let child = try manager.createPerson(name: "Their child")
        try manager.createRelationship(from: parent, to: child, type: .parent)
        XCTAssertNil(parent.primaryCircle)
        XCTAssertNil(child.primaryCircle)

        let me = try manager.createPerson(name: "Me", isMe: true)
        let sibling = try manager.createPerson(name: "My sibling")
        let friend = try manager.createPerson(name: "Sibling's friend")
        try manager.createRelationship(from: me, to: sibling, type: .sibling)
        try manager.createRelationship(from: sibling, to: friend, type: .friend)
        XCTAssertEqual(sibling.primaryCircle?.name, "Family")
        XCTAssertEqual(friend.primaryCircle?.name, "Friends")
    }

    func testContextualAssignmentRespectsCustomPondsAndExclusions() throws {
        let club = try manager.createCircle(name: "Book Club")
        let emma = try manager.createPerson(name: "Emma")
        let mia = try manager.createPerson(name: "Mia")
        try manager.addToCircle(emma, circle: club)
        try manager.createRelationship(from: emma, to: mia, type: .friend)
        XCTAssertEqual(mia.primaryCircle?.id, club.id)

        let friends = try XCTUnwrap(manager.fetchSystemCircles().first { $0.name == "Friends" })
        let professional = try XCTUnwrap(manager.fetchSystemCircles().first { $0.name == "Professional" })
        let jake = try manager.createPerson(name: "Jake")
        let excluded = try manager.createPerson(name: "Excluded")
        let assigned = try manager.createPerson(name: "Already assigned")
        try manager.addToCircle(jake, circle: friends)
        try manager.addToCircle(excluded, circle: friends)
        try manager.removeFromCircle(excluded, circle: friends)
        try manager.addToCircle(assigned, circle: professional)
        try manager.createRelationship(from: jake, to: excluded, type: .spouse)
        try manager.createRelationship(from: jake, to: assigned, type: .sibling)
        XCTAssertNil(excluded.primaryCircle)
        XCTAssertEqual(assigned.primaryCircle?.id, professional.id)
        XCTAssertEqual(jake.primaryCircle?.id, friends.id)
    }

    /// Manual exclusion prevents auto-re-addition.
    func testManualExclusionGuard() throws {
        let alice = try manager.createPerson(name: "Alice")
        let bob = try manager.createPerson(name: "Bob")

        // Create friend relationship → auto-assigns to Friends circle
        try manager.createRelationship(from: alice, to: bob, type: .friend)
        let friendsCircle = try manager.fetchSystemCircles().first { $0.name == "Friends" }!

        // Manually remove Alice from Friends
        try manager.removeFromCircle(alice, circle: friendsCircle)

        // Create another friend relationship for Alice
        let charlie = try manager.createPerson(name: "Charlie")
        try manager.createRelationship(from: alice, to: charlie, type: .friend)

        // Alice should NOT be re-added to Friends (manuallyExcluded = true)
        let members = friendsCircle.activeContacts
        XCTAssertFalse(members.contains { $0.id == alice.id })
    }

    /// System circles cannot be deleted.
    func testSystemCircleCannotBeDeleted() throws {
        let familyCircle = try manager.fetchSystemCircles().first { $0.name == "Family" }!

        XCTAssertThrowsError(try manager.deleteCircle(familyCircle)) { error in
            XCTAssertEqual(error as? GoldfishError, .cannotDeleteSystemCircle)
        }
    }

    /// The isMe contact must never be added to any circle.
    func testMeCannotBeAddedToCircle() throws {
        let me = try manager.createPerson(name: "Me", isMe: true)
        let familyCircle = try manager.fetchSystemCircles().first { $0.name == "Family" }!

        XCTAssertThrowsError(try manager.addToCircle(me, circle: familyCircle))

        // No CircleContact should have been persisted for the Me contact
        let members = familyCircle.activeContacts
        XCTAssertFalse(members.contains { $0.id == me.id })
    }

    /// Auto-assignment via relationship creation must skip the isMe contact.
    func testAutoAssignSkipsMeContact() throws {
        let me = try manager.createPerson(name: "Me", isMe: true)
        let bob = try manager.createPerson(name: "Bob")

        try manager.createRelationship(from: me, to: bob, type: .friend)

        let friendsCircle = try manager.fetchSystemCircles().first { $0.name == "Friends" }!
        let members = friendsCircle.activeContacts

        // Bob should be in Friends, Me should NOT
        XCTAssertTrue(members.contains { $0.id == bob.id })
        XCTAssertFalse(members.contains { $0.id == me.id })
    }

    /// Adding a contact to a new pond removes them from the old one (single pond enforcement).
    func testSinglePondEnforcement() throws {
        let alice = try manager.createPerson(name: "Alice")
        let familyCircle = try manager.fetchSystemCircles().first { $0.name == "Family" }!
        let friendsCircle = try manager.fetchSystemCircles().first { $0.name == "Friends" }!

        // Add Alice to Family
        try manager.addToCircle(alice, circle: familyCircle)
        XCTAssertTrue(familyCircle.activeContacts.contains { $0.id == alice.id })

        // Now add Alice to Friends — should move her out of Family
        try manager.addToCircle(alice, circle: friendsCircle)
        XCTAssertTrue(friendsCircle.activeContacts.contains { $0.id == alice.id })

        // Alice should no longer be in Family active contacts
        let familyMembers = familyCircle.circleContacts.filter { !$0.manuallyExcluded && $0.contact.id == alice.id }
        XCTAssertTrue(familyMembers.isEmpty, "Alice should have been removed from Family when added to Friends")
    }

    /// Auto-assignment should NOT move a contact that is already in a pond.
    func testAutoAssignSkipsWhenAlreadyInPond() throws {
        let alice = try manager.createPerson(name: "Alice")
        let familyCircle = try manager.fetchSystemCircles().first { $0.name == "Family" }!

        // Manually put Alice in Family
        try manager.addToCircle(alice, circle: familyCircle)

        // Now create a friend relationship for Alice — auto-assign would normally put her in Friends
        let bob = try manager.createPerson(name: "Bob")
        try manager.createRelationship(from: alice, to: bob, type: .friend)

        // Alice should still be in Family, NOT moved to Friends
        XCTAssertTrue(familyCircle.activeContacts.contains { $0.id == alice.id })
        let friendsCircle = try manager.fetchSystemCircles().first { $0.name == "Friends" }!
        let aliceInFriends = friendsCircle.circleContacts.filter { !$0.manuallyExcluded && $0.contact.id == alice.id }
        XCTAssertTrue(aliceInFriends.isEmpty, "Alice should NOT have been auto-moved to Friends")
    }
}

// MARK: - Graph Layout Tests

@MainActor
final class GraphLayoutTests: XCTestCase {

    var manager: GoldfishDataManager!
    var container: ModelContainer!

    override func setUp() async throws {
        (manager, container) = try makeTestManager()
        try manager.createSystemCircles()
    }

    /// BFS layout from isMe produces correct levels.
    func testGraphLevelsFromRoot() throws {
        let me = try manager.createPerson(name: "Me", isMe: true)
        let friend = try manager.createPerson(name: "Friend")
        let friendOfFriend = try manager.createPerson(name: "Friend of Friend")

        try manager.createRelationship(from: me, to: friend, type: .friend)
        try manager.createRelationship(from: friend, to: friendOfFriend, type: .friend)

        let levels = try manager.buildGraphLayout()!
        // Me anchors depth 0; each relationship hop advances one level.
        XCTAssertEqual(levels.map(\.depth), [0, 1, 2])
        XCTAssertEqual(levels.map { $0.allContacts.map(\.id) },
                       [[me.id], [friend.id], [friendOfFriend.id]])
    }

    /// Unlinked contacts remain discoverable without fabricating relationships.
    func testOrphansIncludedInGraph() throws {
        let me = try manager.createPerson(name: "Me", isMe: true)
        let orphan = try manager.createPerson(name: "Orphan")

        let levels = try manager.buildGraphLayout()!
        let allInGraph = levels.flatMap(\.allContacts)
        XCTAssertEqual(Set(allInGraph.map(\.id)), [me.id, orphan.id])
        XCTAssertEqual(allInGraph.count, 2)
        XCTAssertTrue(orphan.allRelationships.isEmpty)
    }
}

// MARK: - Descendants Tests

@MainActor
final class DescendantsTests: XCTestCase {

    var manager: GoldfishDataManager!
    var container: ModelContainer!

    override func setUp() async throws {
        (manager, container) = try makeTestManager()
    }

    /// Descendants traverses through parent→child chain.
    func testGetDescendants() throws {
        let grandparent = try manager.createPerson(name: "Grandparent")
        let parent = try manager.createPerson(name: "Parent")
        let child = try manager.createPerson(name: "Child")

        try manager.createRelationship(from: grandparent, to: parent, type: .mother)
        try manager.createRelationship(from: parent, to: child, type: .mother)

        let descendants = manager.getDescendants(of: grandparent)
        XCTAssertEqual(descendants.count, 2)
        XCTAssertTrue(descendants.contains { $0.name == "Parent" })
        XCTAssertTrue(descendants.contains { $0.name == "Child" })
    }

    /// Contact with no children returns empty array.
    func testNoDescendants() throws {
        let leaf = try manager.createPerson(name: "Leaf")
        let descendants = manager.getDescendants(of: leaf)
        XCTAssertTrue(descendants.isEmpty)
    }
}

// MARK: - Contact Detail Demo Isolation

@MainActor
final class ContactDetailDemoScopeTests: XCTestCase {
    func testSharedMeShowsOnlyConnectionsFromVisibleMode() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let saved = try manager.createPerson(name: "Saved person")
        let sample = try manager.createPerson(name: "Sample person", isDemo: true)
        try manager.createRelationship(from: saved, to: me, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: sample, to: me, type: .friend, skipAutoAssign: true)
        let model = ContactDetailViewModel(person: me, dataManager: manager)
        func visibleIDs() -> Set<UUID> {
            Set(model.groupedRelationships.values.flatMap { $0 }.map { $0.otherContact(from: me).id })
        }
        XCTAssertEqual(visibleIDs(), [saved.id])
        model.isDemoMode = true
        XCTAssertEqual(visibleIDs(), [sample.id])
        model.isDemoMode = false
        XCTAssertEqual(visibleIDs(), [saved.id])
        XCTAssertEqual(me.allRelationships.count, 2, "Changing visible mode must not delete relationships.")
    }
}

// MARK: - Editorial Profile Story

@MainActor
final class ContactDetailStoryTests: XCTestCase {
    func testProfileStoryUsesTheContactPerspective() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let sister = try manager.createPerson(name: "Anna")
        let friend = try manager.createPerson(name: "Ben")
        try manager.createRelationship(from: sister, to: me, type: .sibling, skipAutoAssign: true)
        try manager.createRelationship(from: sister, to: friend, type: .friend, skipAutoAssign: true)

        let model = ContactDetailViewModel(person: sister, dataManager: manager)
        XCTAssertEqual(model.relationshipToMe, "Sibling")
        XCTAssertEqual(model.connectedPeopleCount, 2)
    }
}

@MainActor
final class FeatureWalkthroughSequenceTests: XCTestCase {
    func testShortTourTraversesThreeActionsAndBacktracks() {
        let manager = FeatureWalkthroughManager()
        manager.startWalkthrough()
        XCTAssertEqual(manager.currentStep, .welcome)

        manager.nextStep()
        XCTAssertEqual(manager.currentStep, .profile)
        manager.report(.openedProfile)
        XCTAssertFalse(manager.justCompletedStep)
        manager.report(.expandedConnections)
        XCTAssertTrue(manager.justCompletedStep)
        manager.nextStep()
        XCTAssertEqual(manager.currentStep, .link)
        manager.report(.createdLink)
        manager.nextStep()
        XCTAssertEqual(manager.currentStep, .ponds)
        manager.report(.focusedPond)
        manager.nextStep()
        XCTAssertEqual(manager.currentStep, .complete)

        manager.previousStep()
        XCTAssertEqual(manager.currentStep, .ponds)
    }
}
