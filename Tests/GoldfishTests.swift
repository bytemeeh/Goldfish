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

    /// The isMe contact must never be added to any circle.
    func testMeCannotBeAddedToCircle() throws {
        let me = try manager.createPerson(name: "Me", isMe: true)
        let familyCircle = try manager.fetchSystemCircles().first { $0.name == "Family" }!

        _ = try manager.addToCircle(me, circle: familyCircle)

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
    let graphService = GraphService()

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

        let levels = graphService.buildGraphLevels(root: me, context: manager.context)
        // ME is excluded from visible levels: depth 0 = Friend, depth 1 = Friend of Friend
        XCTAssertEqual(levels.count, 2)
        XCTAssertEqual(levels[0].depth, 0)
        XCTAssertEqual(levels[0].allContacts.count, 1) // Friend
        XCTAssertEqual(levels[1].allContacts.count, 1) // Friend of Friend
    }

    /// Orphans are excluded from graph layout.
    func testOrphansExcludedFromGraph() throws {
        let me = try manager.createPerson(name: "Me", isMe: true)
        let orphan = try manager.createPerson(name: "Orphan")

        let levels = graphService.buildGraphLevels(root: me, context: manager.context)
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

// MARK: - Demo Data Seeding Tests

@MainActor
final class DemoDataSeedingTests: XCTestCase {

    var manager: GoldfishDataManager!

    override func setUp() async throws {
        manager = try makeTestManager()
        try manager.createSystemCircles()
    }

    /// Every demo contact should have exactly one active circle membership after seeding.
    func testDemoDataHasValidCircleMemberships() throws {
        _ = try manager.createPerson(name: "Me", isMe: true)
        let service = DemoDataService(dataManager: manager)
        try service.seedDemoData()

        let allPersons = try manager.fetchAllPersons()
        let demoPersons = allPersons.filter { $0.isDemo }

        XCTAssertFalse(demoPersons.isEmpty, "Demo persons should have been created")

        for person in demoPersons {
            let active = person.circleContacts.filter { !$0.manuallyExcluded }
            if person.isOrphan {
                XCTAssertEqual(active.count, 0, "\(person.name) is the intentional unlinked demo contact and should have 0 circles, has \(active.count)")
            } else {
                XCTAssertEqual(active.count, 1, "\(person.name) should have exactly 1 circle, has \(active.count)")
            }
        }
    }

    /// Seeding is idempotent — calling it twice should not duplicate contacts.
    func testSeedingIsIdempotent() throws {
        _ = try manager.createPerson(name: "Me", isMe: true)
        let service = DemoDataService(dataManager: manager)

        try service.seedDemoData()
        let countAfterFirst = try manager.fetchAllPersons().filter { $0.isDemo }.count

        try service.seedDemoData()
        let countAfterSecond = try manager.fetchAllPersons().filter { $0.isDemo }.count

        XCTAssertEqual(countAfterFirst, countAfterSecond, "Seeding twice should not create duplicates")
    }
    
    /// Repair restores circle assignments after they've been deleted.
    func testRepairRestoresMissingCircleAssignments() throws {
        _ = try manager.createPerson(name: "Me", isMe: true)
        let service = DemoDataService(dataManager: manager)
        try service.seedDemoData()
        
        // Delete all CircleContact records for demo contacts
        let allPersons = try manager.fetchAllPersons()
        let demoPersons = allPersons.filter { $0.isDemo }
        for person in demoPersons {
            for cc in person.circleContacts {
                manager.context.delete(cc)
            }
            person.circleContacts.removeAll()
        }
        try manager.context.save()
        
        // Verify circles are gone
        for person in demoPersons {
            XCTAssertTrue(person.circleContacts.isEmpty, "\(person.name) should have 0 circles after deletion")
        }
        
        // Re-seed should trigger repair
        try service.seedDemoData()
        
        // Verify all demo contacts have exactly 1 circle again
        let refreshedPersons = try manager.fetchAllPersons().filter { $0.isDemo }
        for person in refreshedPersons {
            let active = person.circleContacts.filter { !$0.manuallyExcluded }
            if person.isOrphan {
                XCTAssertEqual(active.count, 0, "\(person.name) is the intentional unlinked demo contact and repair should leave it pondless, has \(active.count)")
            } else {
                XCTAssertEqual(active.count, 1, "\(person.name) should have 1 circle after repair, has \(active.count)")
            }
        }
    }
    
    /// Re-running repair on already-assigned contacts does not duplicate memberships.
    func testRepairDoesNotDuplicateExistingCircleAssignments() throws {
        _ = try manager.createPerson(name: "Me", isMe: true)
        let service = DemoDataService(dataManager: manager)
        try service.seedDemoData()
        
        // Call repair directly on contacts that already have circles
        let demoPersons = try manager.fetchAllPersons().filter { $0.isDemo }
        try service.repairCircleAssignments(demoPersons: demoPersons)
        
        // Every contact should still have exactly 1 circle (no duplicates)
        for person in demoPersons {
            let active = person.circleContacts.filter { !$0.manuallyExcluded }
            if person.isOrphan {
                XCTAssertEqual(active.count, 0, "\(person.name) is the intentional unlinked demo contact and should stay pondless, has \(active.count)")
            } else {
                XCTAssertEqual(active.count, 1, "\(person.name) should still have 1 circle, has \(active.count)")
            }
        }
    }
}

// MARK: - RelationshipType Edge Coverage Tests

@MainActor
final class RelationshipTypeEdgeCoverageTests: XCTestCase {

    var manager: GoldfishDataManager!

    override func setUp() async throws {
        manager = try makeTestManager()
        try manager.createSystemCircles()
    }

    // MARK: - Symmetry

    /// Spouse is symmetric — one row covers both directions.
    func testSpouseIsSymmetric() throws {
        let a = try manager.createPerson(name: "Alice")
        let b = try manager.createPerson(name: "Bob")
        try manager.createRelationship(from: a, to: b, type: .spouse)

        XCTAssertTrue(RelationshipType.spouse.isSymmetric)
        XCTAssertEqual(a.allRelationships.count, 1)
        XCTAssertEqual(b.allRelationships.count, 1)
    }

    /// Partner is symmetric — one row covers both directions.
    func testPartnerIsSymmetric() throws {
        let a = try manager.createPerson(name: "Alice")
        let b = try manager.createPerson(name: "Bob")
        try manager.createRelationship(from: a, to: b, type: .partner)

        XCTAssertTrue(RelationshipType.partner.isSymmetric)
        let rel = a.outgoingRelationships.first!
        XCTAssertEqual(rel.effectiveType(for: a), .partner)
        XCTAssertEqual(rel.effectiveType(for: b), .partner)
    }

    /// Coworker is symmetric.
    func testCoworkerIsSymmetric() throws {
        let a = try manager.createPerson(name: "Alice")
        let b = try manager.createPerson(name: "Bob")
        try manager.createRelationship(from: a, to: b, type: .coworker)

        XCTAssertTrue(RelationshipType.coworker.isSymmetric)
        let rel = a.outgoingRelationships.first!
        XCTAssertEqual(rel.effectiveType(for: a), .coworker)
        XCTAssertEqual(rel.effectiveType(for: b), .coworker)
    }

    // MARK: - Directional Inverses

    /// Father ↔ child inverse works correctly.
    func testFatherInverse() throws {
        let dad = try manager.createPerson(name: "Dad")
        let kid = try manager.createPerson(name: "Kid")
        try manager.createRelationship(from: dad, to: kid, type: .father)

        let rel = dad.outgoingRelationships.first!
        XCTAssertEqual(rel.effectiveType(for: dad), .father)
        XCTAssertEqual(rel.effectiveType(for: kid), .child)
    }

    /// Parent ↔ child inverse works correctly (gender-neutral parent).
    func testParentChildInverse() throws {
        let parent = try manager.createPerson(name: "Parent")
        let kid = try manager.createPerson(name: "Kid")
        try manager.createRelationship(from: parent, to: kid, type: .parent)

        let rel = parent.outgoingRelationships.first!
        XCTAssertEqual(rel.effectiveType(for: parent), .parent)
        XCTAssertEqual(rel.effectiveType(for: kid), .child)
    }

    /// Child → parent inverse resolves to .parent.
    func testChildInverseIsParent() throws {
        let kid = try manager.createPerson(name: "Kid")
        let guardian = try manager.createPerson(name: "Guardian")
        try manager.createRelationship(from: kid, to: guardian, type: .child)

        let rel = kid.outgoingRelationships.first!
        XCTAssertEqual(rel.effectiveType(for: kid), .child)
        XCTAssertEqual(rel.effectiveType(for: guardian), .parent)
    }

    /// Other has no inverse — effectiveType falls back to .other for both sides.
    func testOtherHasNoInverse() throws {
        XCTAssertNil(RelationshipType.other.inverse)

        let a = try manager.createPerson(name: "Alice")
        let b = try manager.createPerson(name: "Bob")
        try manager.createRelationship(from: a, to: b, type: .other)

        let rel = a.outgoingRelationships.first!
        XCTAssertEqual(rel.effectiveType(for: a), .other)
        // .other has nil inverse → falls back to stored type
        XCTAssertEqual(rel.effectiveType(for: b), .other)
    }

    // MARK: - Cycle Detection for Other Directional Types

    /// Father type also triggers cycle detection.
    func testFatherCycleDetection() throws {
        let a = try manager.createPerson(name: "A")
        let b = try manager.createPerson(name: "B")
        try manager.createRelationship(from: a, to: b, type: .father)

        // B → A (child) would close the cycle
        XCTAssertThrowsError(
            try manager.createRelationship(from: b, to: a, type: .child)
        ) { error in
            XCTAssertEqual(error as? GoldfishError, .wouldCreateCycle)
        }
    }

    /// Parent (gender-neutral) also triggers cycle detection.
    func testParentCycleDetection() throws {
        let a = try manager.createPerson(name: "A")
        let b = try manager.createPerson(name: "B")
        try manager.createRelationship(from: a, to: b, type: .parent)

        // B → A (child) would close the cycle
        XCTAssertThrowsError(
            try manager.createRelationship(from: b, to: a, type: .child)
        ) { error in
            XCTAssertEqual(error as? GoldfishError, .wouldCreateCycle)
        }
    }

    /// Symmetric partner cycle is allowed (not directional).
    func testPartnerCycleAllowed() throws {
        let a = try manager.createPerson(name: "A")
        let b = try manager.createPerson(name: "B")
        let c = try manager.createPerson(name: "C")

        try manager.createRelationship(from: a, to: b, type: .partner)
        try manager.createRelationship(from: b, to: c, type: .partner)
        XCTAssertNoThrow(
            try manager.createRelationship(from: c, to: a, type: .partner)
        )
    }

    // MARK: - Auto-Assignment

    /// Coworker auto-assigns to Professional circle.
    func testCoworkerAutoAssignsProfessional() throws {
        let a = try manager.createPerson(name: "Alice")
        let b = try manager.createPerson(name: "Bob")
        try manager.createRelationship(from: a, to: b, type: .coworker)

        let proCircle = try manager.fetchSystemCircles().first { $0.name == "Professional" }!
        XCTAssertTrue(proCircle.activeContacts.contains { $0.id == a.id })
        XCTAssertTrue(proCircle.activeContacts.contains { $0.id == b.id })
    }

    /// Spouse auto-assigns to Family circle.
    func testSpouseAutoAssignsFamily() throws {
        let a = try manager.createPerson(name: "Alice")
        let b = try manager.createPerson(name: "Bob")
        try manager.createRelationship(from: a, to: b, type: .spouse)

        let familyCircle = try manager.fetchSystemCircles().first { $0.name == "Family" }!
        XCTAssertTrue(familyCircle.activeContacts.contains { $0.id == a.id })
        XCTAssertTrue(familyCircle.activeContacts.contains { $0.id == b.id })
    }

    /// Other type does NOT auto-assign to any circle.
    func testOtherDoesNotAutoAssign() throws {
        let a = try manager.createPerson(name: "Alice")
        let b = try manager.createPerson(name: "Bob")
        try manager.createRelationship(from: a, to: b, type: .other)

        let circles = try manager.fetchSystemCircles()
        for circle in circles {
            XCTAssertFalse(circle.activeContacts.contains { $0.id == a.id },
                          "\(a.name) should not be in \(circle.name) from .other")
            XCTAssertFalse(circle.activeContacts.contains { $0.id == b.id },
                          "\(b.name) should not be in \(circle.name) from .other")
        }
    }

    // MARK: - Descendants with .parent

    /// getDescendants traverses .parent relationships (gender-neutral parent → child).
    func testGetDescendantsViaParentType() throws {
        let guardian = try manager.createPerson(name: "Guardian")
        let kid = try manager.createPerson(name: "Kid")
        try manager.createRelationship(from: guardian, to: kid, type: .parent)

        let descendants = manager.getDescendants(of: guardian)
        XCTAssertEqual(descendants.count, 1)
        XCTAssertEqual(descendants.first?.name, "Kid")
    }

    /// getDescendants follows mixed parent types in a chain.
    func testGetDescendantsMixedParentTypes() throws {
        let grandparent = try manager.createPerson(name: "Grandparent")
        let parentPerson = try manager.createPerson(name: "Parent")
        let child = try manager.createPerson(name: "Child")

        // grandparent → parent via .parent (gender-neutral)
        try manager.createRelationship(from: grandparent, to: parentPerson, type: .parent)
        // parent → child via .mother
        try manager.createRelationship(from: parentPerson, to: child, type: .mother)

        let descendants = manager.getDescendants(of: grandparent)
        XCTAssertEqual(descendants.count, 2)
        XCTAssertTrue(descendants.contains { $0.name == "Parent" })
        XCTAssertTrue(descendants.contains { $0.name == "Child" })
    }
}
