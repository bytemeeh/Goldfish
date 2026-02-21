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
@MainActor
func makeTestManager() throws -> GoldfishDataManager {
    let container = try makeTestContainer()
    return GoldfishDataManager(context: container.mainContext)
}

// MARK: - Cycle Detection Tests

@MainActor
final class CycleDetectionTests: XCTestCase {

    var manager: GoldfishDataManager!

    override func setUp() async throws {
        manager = try makeTestManager()
    }

    /// A → B (mother), B → C (mother).
    /// Adding C → A (child) would make A their own ancestor → blocked.
    func testDirectionalCycleIsBlocked() throws {
        let a = try manager.createPerson(name: "Alice")
        let b = try manager.createPerson(name: "Bob")
        let c = try manager.createPerson(name: "Charlie")

        // A is B's mother
        try manager.createRelationship(from: a, to: b, type: .mother)
        // B is C's mother
        try manager.createRelationship(from: b, to: c, type: .mother)

        // C → A (child) would close the cycle: A→B→C→A
        XCTAssertThrowsError(
            try manager.createRelationship(from: c, to: a, type: .child)
        ) { error in
            XCTAssertEqual(error as? GoldfishError, .wouldCreateCycle)
        }
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
            XCTAssertEqual(error as? GoldfishError, .wouldCreateCycle)
        }
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

// MARK: - Search Tests

@MainActor
final class SearchTests: XCTestCase {

    var manager: GoldfishDataManager!

    override func setUp() async throws {
        manager = try makeTestManager()
    }

    /// Partial, case-insensitive name match.
    func testSearchByName() throws {
        try manager.createPerson(name: "Marcel Meeh")
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

    override func setUp() async throws {
        manager = try makeTestManager()
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

    override func setUp() async throws {
        manager = try makeTestManager()
        try manager.createSystemCircles()
    }

    /// Creating a mother relationship auto-assigns both contacts to Family.
    func testMotherRelationshipAutoAssignsToFamily() throws {
        let mom = try manager.createPerson(name: "Mom")
        let child = try manager.createPerson(name: "Child")

        try manager.createRelationship(from: mom, to: child, type: .mother)

        let familyCircle = try manager.fetchSystemCircles().first { $0.name == "Family" }!
        let members = familyCircle.activeContacts
        XCTAssertTrue(members.contains { $0.id == mom.id })
        XCTAssertTrue(members.contains { $0.id == child.id })
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
}

// MARK: - Graph Layout Tests

@MainActor
final class GraphLayoutTests: XCTestCase {

    var manager: GoldfishDataManager!

    override func setUp() async throws {
        manager = try makeTestManager()
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
        XCTAssertEqual(levels.count, 3)
        XCTAssertEqual(levels[0].depth, 0)
        XCTAssertEqual(levels[0].allContacts.count, 1) // Me
        XCTAssertEqual(levels[1].allContacts.count, 1) // Friend
        XCTAssertEqual(levels[2].allContacts.count, 1) // Friend of Friend
    }

    /// Orphans are excluded from graph layout.
    func testOrphansExcludedFromGraph() throws {
        let me = try manager.createPerson(name: "Me", isMe: true)
        let orphan = try manager.createPerson(name: "Orphan")

        let levels = try manager.buildGraphLayout()!
        let allInGraph = levels.flatMap(\.allContacts)
        XCTAssertFalse(allInGraph.contains { $0.id == orphan.id })
    }
}

// MARK: - Descendants Tests

@MainActor
final class DescendantsTests: XCTestCase {

    var manager: GoldfishDataManager!

    override func setUp() async throws {
        manager = try makeTestManager()
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
