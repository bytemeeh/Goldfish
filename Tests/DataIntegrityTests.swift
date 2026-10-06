import XCTest
import SwiftData
import SpriteKit
@testable import Goldfish

@MainActor
final class DataIntegrityTests: XCTestCase {
    var manager: GoldfishDataManager!
    var container: ModelContainer!
    override func setUp() async throws { (manager, container) = try makeTestManager() }

    func testPersonSchemaProvidesLegacyMigrationDefault() throws {
        let person = try XCTUnwrap(
            GoldfishModelContainer.schema.entities.first { $0.name == "Person" }
        )
        let isDemo = try XCTUnwrap(person.attributesByName["isDemo"])
        XCTAssertEqual(isDemo.defaultValue as? Bool, false)
    }

    func testRestoringExcludedMembershipKeepsOneActiveGroup() throws {
        try manager.createSystemCircles()
        let person = try manager.createPerson(name: "Person")
        let groups = try manager.fetchAllCircles()
        try manager.addToCircle(person, circle: groups[0])
        try manager.removeFromCircle(person, circle: groups[0])
        try manager.addToCircle(person, circle: groups[1])
        try manager.addToCircle(person, circle: groups[0])
        XCTAssertEqual(Set(person.circleContacts.filter { !$0.manuallyExcluded }.map(\.circle.id)), [groups[0].id])
    }
    func testSelfRelationshipsAndBlankNamesAreRejected() throws {
        let person = try manager.createPerson(name: "Me", isMe: true)
        for type in RelationshipType.allCases {
            XCTAssertThrowsError(try manager.createRelationship(from: person, to: person, type: type))
        }
        XCTAssertTrue(person.allRelationships.isEmpty)
        XCTAssertThrowsError(try manager.createPerson(name: " \n "))
        XCTAssertThrowsError(try manager.createCircle(name: "  "))
    }
    func testAtomicEditRollsBackAllIntermediateWrites() throws {
        enum Failure: Error { case abort }
        XCTAssertThrowsError(try manager.performAtomicEdit {
            try manager.createPerson(name: "Should not persist")
            try manager.createCircle(name: "Should not persist")
            throw Failure.abort
        })
        XCTAssertEqual(try manager.fetchPersonCount(), 0)
        XCTAssertTrue(try manager.fetchAllCircles().isEmpty)
    }
    func testAfterCommitHookCanRegisterAnotherHookAndPersistANewEdit() throws {
        var order: [String] = []
        var createdID: UUID?
        try manager.performAtomicEdit {
            manager.afterCurrentAtomicEditCommits {
                order.append("first-start")
                self.manager.afterCurrentAtomicEditCommits {
                    order.append("second")
                }
                if let created = try? self.manager.createPerson(name: "Created from commit hook") {
                    createdID = created.id
                }
                order.append("first-end")
            }
        }

        XCTAssertEqual(order, ["first-start", "second", "first-end"])
        let created = try XCTUnwrap(createdID)
        XCTAssertTrue(try manager.fetchAllPersons().contains { $0.id == created })
        XCTAssertFalse(manager.context.hasChanges, "The callback's independent edit must be saved")
    }

    func testSystemGroupsAreIdempotentAndRenameDoesNotBreakAssignment() throws {
        try manager.createSystemCircles()
        try manager.createSystemCircles()
        XCTAssertEqual(try manager.fetchAllCircles().count, 3)
        let family = try XCTUnwrap(manager.fetchAllCircles().first { $0.shouldAutoAssign(for: .parent) })
        try manager.updateCircle(family, name: "Home", emoji: "", color: family.color)
        let parent = try manager.createPerson(name: "Parent")
        let child = try manager.createPerson(name: "Me", isMe: true)
        try manager.createRelationship(from: parent, to: child, type: .parent)
        XCTAssertEqual(parent.primaryCircle?.id, family.id)
        XCTAssertNil(child.primaryCircle)
    }
    func testDuplicateRelationshipIsIdempotent() throws {
        let a = try manager.createPerson(name: "A"), b = try manager.createPerson(name: "B")
        let first = try manager.createRelationship(from: a, to: b, type: .friend)
        let second = try manager.createRelationship(from: b, to: a, type: .friend)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(Set(a.allRelationships.map(\.id)).count, 1)
    }

    func testUndoCreatedRelationshipOnlyRemovesTargetedNewEdge() throws {
        let a = try manager.createPerson(name: "A")
        let b = try manager.createPerson(name: "B")
        let c = try manager.createPerson(name: "C")
        let existing = try manager.createRelationship(from: a, to: b, type: .friend)
        let created = try manager.createRelationship(from: a, to: c, type: .friend)

        XCTAssertTrue(try manager.undoCreatedRelationship(id: created.id))
        XCTAssertFalse(try manager.undoCreatedRelationship(id: created.id))
        XCTAssertTrue(a.allRelationships.contains { $0.id == existing.id })
        XCTAssertFalse(a.allRelationships.contains { $0.id == created.id })
    }

    func testUndoNeverTargetsPreexistingRelationshipReturnedByDuplicateCreate() throws {
        let a = try manager.createPerson(name: "A")
        let b = try manager.createPerson(name: "B")
        let existing = try manager.createRelationship(from: a, to: b, type: .friend)
        let idsBefore = Set(a.allRelationships.map(\.id))
        let returned = try manager.createRelationship(from: b, to: a, type: .friend)
        XCTAssertEqual(returned.id, existing.id)
        XCTAssertTrue(idsBefore.contains(returned.id))
        XCTAssertTrue(a.allRelationships.contains { $0.id == existing.id })
    }
    func testSpecificParentRoleRefinesAnExistingGenericInverse() throws {
        let parent = try manager.createPerson(name: "Mother"), child = try manager.createPerson(name: "Child")
        let generic = try manager.createRelationship(from: child, to: parent, type: .child)
        let specific = try manager.createRelationship(from: parent, to: child, type: .mother)
        XCTAssertEqual(generic.id, specific.id)
        XCTAssertEqual(specific.type, .mother)
        XCTAssertEqual(specific.fromContact.id, parent.id)
        XCTAssertEqual(try manager.context.fetch(FetchDescriptor<Relationship>()).count, 1)
    }
    func testCaregiverInverseDoesNotUseFamilyAutoAssignmentOrAncestryDirection() throws {
        let caregiver = try manager.createPerson(name: "Caregiver")
        let recipient = try manager.createPerson(name: "Recipient")
        let relationship = try manager.createRelationship(from: caregiver, to: recipient, type: .caregiver)
        XCTAssertEqual(relationship.type.inverse, .caredFor)
        XCTAssertFalse(relationship.type.isDirectional, "Care relationships must not participate in ancestry-cycle checks")
        XCTAssertNil(caregiver.primaryCircle)
        XCTAssertNil(recipient.primaryCircle)
        XCTAssertEqual(relationship.effectiveType(for: caregiver), .caregiver)
        XCTAssertEqual(relationship.effectiveType(for: recipient), .caredFor)
    }

    func testFirstConnectionIncludesMeAndMissingTargetRollsBackSave() throws {
        let me = try manager.createPerson(name: "Me", isMe: true)
        let form = ContactFormViewModel(dataManager: manager)
        XCTAssertTrue(form.allPersons.contains { $0.id == me.id })
        form.firstName = "New contact"
        form.selectedConnectionID = UUID()
        XCTAssertFalse(form.save())
        XCTAssertEqual(try manager.fetchPersonCount(), 1)
    }
    func testDuplicateGroupNamesAndEmptyGroupRetainSeparateIdentity() throws {
        let me = try manager.createPerson(name: "Me", isMe: true)
        let a = try manager.createCircle(name: "Same", color: "#FF0000")
        let b = try manager.createCircle(name: "Same", color: "#0000FF")
        let p = try manager.createPerson(name: "Member")
        try manager.addToCircle(p, circle: a)
        let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 844))
        scene.didUpdateGroups([a,b])
        _ = scene.debugLayout([GraphLevel(depth: 0, circleGroups: [CircleGroup(circle: nil, contacts: [me,p,p])])])
        XCTAssertEqual(scene.debugGroupIDs, [a.id.uuidString, b.id.uuidString])
        XCTAssertNotEqual(scene.debugGroupColors[a.id.uuidString], scene.debugGroupColors[b.id.uuidString])
    }
    func testContactFormDoesNotRestoreExcludedGroup() throws {
        try manager.createSystemCircles()
        let person = try manager.createPerson(name: "Person")
        let group = try XCTUnwrap(manager.fetchAllCircles().first)
        try manager.addToCircle(person, circle: group)
        try manager.removeFromCircle(person, circle: group)
        let form = ContactFormViewModel(dataManager: manager, person: person)
        XCTAssertFalse(form.selectedCircleIDs.contains(group.id))
    }
    func testSearchIsReevaluatedAfterDeletion() throws {
        let person = try manager.createPerson(name: "Alice")
        let home = HomeViewModel(dataManager: manager)
        home.searchText = "Alice"
        home.loadData()
        XCTAssertEqual(home.filteredContacts.map(\.id), [person.id])
        try manager.deletePerson(person)
        home.loadData()
        XCTAssertTrue(home.filteredContacts.isEmpty)
    }
    func testDemoContactFormKeepsNewPersonVisibleWithoutMixingRealPeople() throws {
        _ = try manager.createPerson(name: "Me", isMe: true)
        let demo = try manager.createPerson(name: "Sample Person", isDemo: true)
        let real = try manager.createPerson(name: "Private Person")
        let form = ContactFormViewModel(dataManager: manager, isDemoMode: true)
        XCTAssertTrue(form.allPersons.contains { $0.id == demo.id })
        XCTAssertFalse(form.allPersons.contains { $0.id == real.id })
        form.firstName = "New Demo Person"
        form.selectedConnectionID = demo.id
        form.selectedRelationshipType = .friend
        XCTAssertTrue(form.save())
        let created = try XCTUnwrap(manager.fetchAllPersons().first { $0.name == "New Demo Person" })
        XCTAssertTrue(created.isDemo)
        let home = HomeViewModel(dataManager: manager)
        home.isDemoMode = true
        home.loadData()
        XCTAssertTrue(home.contacts.contains { $0.id == created.id })
        home.isDemoMode = false
        home.loadData()
        XCTAssertFalse(home.contacts.contains { $0.id == created.id })
        XCTAssertTrue(home.contacts.contains { $0.id == real.id })
    }

    func testContactFormRequiresAnExplicitRelationshipBeforeSavingAConnection() throws {
        let me = try manager.createPerson(name: "Me", isMe: true)
        let form = ContactFormViewModel(dataManager: manager)
        form.firstName = "New Contact"
        form.selectedConnectionID = me.id

        XCTAssertFalse(form.hasSelectedRelationshipType)
        XCTAssertFalse(form.save())
        XCTAssertEqual(try manager.fetchPersonCount(), 1)
        XCTAssertEqual(form.errorMessage, "Choose how these contacts are connected.")

        form.selectedRelationshipType = .other
        XCTAssertTrue(form.hasSelectedRelationshipType)
        XCTAssertTrue(form.save())
    }

    func testFirstConnectionRespectsExplicitUnassignedGroupChoice() throws {
        let me = try manager.createPerson(name: "Me", isMe: true)
        let form = ContactFormViewModel(dataManager: manager, isDemoMode: false)
        form.firstName = "Unassigned Friend"
        form.selectedConnectionID = me.id
        form.selectedRelationshipType = .friend
        form.selectedCircleIDs = []
        XCTAssertTrue(form.save())
        let created = try XCTUnwrap(manager.fetchAllPersons().first { $0.name == "Unassigned Friend" })
        XCTAssertEqual(created.allRelationships.count, 1)
        XCTAssertNil(created.primaryCircle)
    }

    func testFocusedGroupPrefillsNewFormAndSurvivesSaving() throws {
        let group = try manager.createCircle(name: "Empty Group")
        let form = ContactFormViewModel(dataManager: manager, isDemoMode: false, initialCircleID: group.id)
        XCTAssertEqual(form.selectedCircleIDs, [group.id])
        XCTAssertFalse(form.hasUnsavedChanges)
        form.firstName = "First Member"
        XCTAssertTrue(form.save())
        let created = try XCTUnwrap(manager.fetchAllPersons().first { $0.name == "First Member" })
        XCTAssertEqual(created.primaryCircle?.id, group.id)
    }

    func testHomeScopeUsesUUIDAndExplicitUnassignedDestination() throws {
        let group = try manager.createCircle(name: "Family")
        let grouped = try manager.createPerson(name: "Grouped")
        let unassigned = try manager.createPerson(name: "Unassigned")
        try manager.addToCircle(grouped, circle: group)

        let home = HomeViewModel(dataManager: manager)
        home.selectedScopeID = group.id.uuidString
        home.loadData()
        XCTAssertEqual(home.contacts.map(\.id), [grouped.id])

        home.selectedScopeID = "unassigned"
        home.loadData()
        XCTAssertEqual(home.contacts.map(\.id), [unassigned.id])
    }

    func testHomeSearchTrimsQueryAndReportsDetailMatchContext() throws {
        let person = try manager.createPerson(name: "Alice Example", email: "alice@example.com", tags: ["gym"])
        let home = HomeViewModel(dataManager: manager)
        home.searchText = "  alice@example.com  "
        home.loadData()
        XCTAssertEqual(home.normalizedSearchText, "alice@example.com")
        XCTAssertEqual(home.filteredContacts.map(\.id), [person.id])
        XCTAssertEqual(home.matchContext(for: person), "Email match")

        home.searchText = "   "
        home.loadData()
        XCTAssertFalse(home.isSearching)
        XCTAssertTrue(home.filteredContacts.contains { $0.id == person.id })
    }

}


extension DataIntegrityTests {
    func testTourActionWaitsForContinueAndIgnoresUnrelatedEvents() {
        let tour = FeatureWalkthroughManager()
        tour.isActive = true
        tour.currentStep = .profile

        tour.report(.openedSearchResult)
        XCTAssertEqual(tour.currentStep, .profile)
        XCTAssertFalse(tour.justCompletedStep)

        tour.report(.openedProfile)
        XCTAssertEqual(tour.currentStep, .profile)
        XCTAssertTrue(tour.justCompletedStep)

        tour.nextStep()
        XCTAssertEqual(tour.currentStep, .link)
        XCTAssertFalse(tour.justCompletedStep)
    }

    func testTourBackNavigationClearsStaleSuccessState() {
        let tour = FeatureWalkthroughManager()
        tour.isActive = true
        tour.currentStep = .profile
        tour.justCompletedStep = true

        tour.previousStep()

        XCTAssertEqual(tour.currentStep, .welcome)
        XCTAssertFalse(tour.justCompletedStep)
    }

    func testDemoFixtureIsRealAndRemovalLeavesSavedContacts() throws {
        _ = try manager.createPerson(name: "Me", isMe: true)
        let saved = try manager.createPerson(name: "Private Person")
        let service = DemoDataService(dataManager: manager)

        XCTAssertTrue(try service.seedDemoData())
        let people = try manager.fetchAllPersons()
        let demoNames = Set(people.filter(\.isDemo).map(\.name))
        XCTAssertEqual(demoNames.count, 23)
        XCTAssertTrue(demoNames.contains("Priya Patel"))
        XCTAssertEqual(try manager.fetchAllCircles().first(where: { $0.name == "Family" })?.activeContacts.count, 5)
        XCTAssertEqual(try manager.fetchAllCircles().first(where: { $0.name == "Friends" })?.activeContacts.count, 7)
        XCTAssertEqual(try manager.fetchAllCircles().first(where: { $0.name == "Book Club" })?.activeContacts.count, 3)
        XCTAssertEqual(try manager.fetchAllCircles().first(where: { $0.name == "Professional" })?.activeContacts.count, 3)

        let demoIDs = Set((try manager.buildGraphLayout(demoMode: true) ?? []).flatMap(\.allContacts).map(\.id))
        XCTAssertFalse(demoIDs.contains(saved.id))

        try service.removeDemoData()
        XCTAssertTrue((try manager.fetchAllPersons()).contains { $0.id == saved.id && !$0.isDemo })
        XCTAssertFalse((try manager.fetchAllPersons()).contains { $0.isDemo })
    }

    func testStandardDemoRelationshipsAndNotesMatchTheirPondContexts() throws {
        let me = try manager.createPerson(name: "Me", isMe: true)
        let service = DemoDataService(dataManager: manager)
        XCTAssertTrue(try service.seedDemoData())
        let demos = try manager.fetchAllPersons().filter(\.isDemo)
        let people = Dictionary(uniqueKeysWithValues: demos.map { ($0.name, $0) })

        let expectedPonds: [String: Set<String>] = [
            "Family": ["Sarah Chen", "Linda Miller", "Robert Miller", "Tom Miller", "Adriana"],
            "Friends": ["Jake Morrison", "Nicole Morrison", "Liam Morrison", "Ella Morrison", "Noah Morrison", "Sam Taylor", "Alex Jordan"],
            "Book Club": ["Emma Wilson", "Mia Rodriguez", "Ryan O'Brien"],
            "Professional": ["David Park", "Lisa Thompson", "Chris Evans"]
        ]
        for (pond, expected) in expectedPonds {
            let actual = Set(demos.filter { $0.primaryCircle?.name == pond }.map(\.name))
            XCTAssertEqual(actual, expected, "Unexpected members in \(pond)")
        }

        let graph = RippleGraph(people: [me] + demos)
        let allowedFamilyTypes: Set<RelationshipType> = [.mother, .father, .parent, .child, .sibling, .spouse, .partner]
        for name in expectedPonds["Family"] ?? [] {
            let person = try XCTUnwrap(people[name])
            XCTAssertEqual(graph.shortestPath(from: me.id, to: person.id), [me.id, person.id], "\(name) should be directly related to Me")
            let direct = try XCTUnwrap(graph.role(of: person.id, relativeTo: me.id))
            XCTAssertTrue(Set(direct.relationshipTypes).isSubset(of: allowedFamilyTypes))
            XCTAssertTrue(Set(direct.relationshipTypes).isDisjoint(with: [.friend, .coworker]))
        }

        let jake = try XCTUnwrap(people["Jake Morrison"])
        let nicole = try XCTUnwrap(people["Nicole Morrison"])
        let children = try ["Liam Morrison", "Ella Morrison", "Noah Morrison"].map { try XCTUnwrap(people[$0]) }
        XCTAssertTrue(hasRelationship(from: jake, to: nicole, type: .spouse))
        for child in children {
            XCTAssertTrue(hasRelationship(from: jake, to: child, type: .father), "Jake should be \(child.name)'s father")
            XCTAssertTrue(hasRelationship(from: nicole, to: child, type: .mother), "Nicole should be \(child.name)'s mother")
            XCTAssertEqual(child.primaryCircle?.name, "Friends")
        }

        let emma = try XCTUnwrap(people["Emma Wilson"])
        let mia = try XCTUnwrap(people["Mia Rodriguez"])
        let ryan = try XCTUnwrap(people["Ryan O'Brien"])
        let david = try XCTUnwrap(people["David Park"])
        let lisa = try XCTUnwrap(people["Lisa Thompson"])
        let chris = try XCTUnwrap(people["Chris Evans"])
        XCTAssertTrue(hasRelationship(between: me, and: emma, type: .friend))
        XCTAssertTrue(hasRelationship(between: emma, and: mia, type: .friend))
        XCTAssertTrue(hasRelationship(between: emma, and: ryan, type: .friend))
        XCTAssertTrue(hasRelationship(between: me, and: david, type: .coworker))
        XCTAssertTrue(hasRelationship(between: david, and: lisa, type: .coworker))
        XCTAssertTrue(hasRelationship(between: david, and: chris, type: .coworker))

        XCTAssertTrue(note(for: people["Sarah Chen"], mentionsAny: ["spouse", "partner", "married"]))
        XCTAssertTrue(note(for: people["Linda Miller"], mentionsAny: ["mom", "mother"]))
        XCTAssertTrue(note(for: people["Robert Miller"], mentionsAny: ["dad", "father"]))
        XCTAssertTrue(note(for: people["Tom Miller"], mentionsAny: ["brother", "sibling"]))
        XCTAssertTrue(note(for: people["Jake Morrison"], mentionsAny: ["friend", "roommate"]))
        XCTAssertTrue(note(for: people["Nicole Morrison"], mentionsAny: ["wife", "spouse"]))
        for child in children {
            XCTAssertTrue(note(for: child, mentionsAny: ["child", "oldest", "middle", "youngest"]))
        }
        XCTAssertTrue(note(for: people["Emma Wilson"], mentionsAny: ["book club", "book-club"]))
        XCTAssertTrue(note(for: people["Mia Rodriguez"], mentionsAny: ["Emma", "organizes"]))
        XCTAssertTrue(note(for: people["Ryan O'Brien"], mentionsAny: ["Emma", "book-club"]))
        XCTAssertTrue(note(for: people["David Park"], mentionsAny: ["work", "team", "mentor"]))
        XCTAssertTrue(note(for: people["Lisa Thompson"], mentionsAny: ["David", "colleague"]))
        XCTAssertTrue(note(for: people["Chris Evans"], mentionsAny: ["David", "colleague"]))
        XCTAssertTrue(note(for: people["Sam Taylor"], mentionsAny: ["friend", "Jake"]))
        XCTAssertTrue(note(for: people["Alex Jordan"], mentionsAny: ["Sam", "partner"]))

        let priya = try XCTUnwrap(people["Priya Patel"])
        XCTAssertTrue(priya.isOrphan)
        XCTAssertNil(priya.primaryCircle)
        XCTAssertTrue(note(for: priya, mentionsAny: ["design", "conference"]))
        let adriana = try XCTUnwrap(people["Adriana"])
        let riley = try XCTUnwrap(people["Riley"])
        let zach = try XCTUnwrap(people["Zach"])
        let aaron = try XCTUnwrap(people["Aaron"])
        let selma = try XCTUnwrap(people["Selma"])
        let daycare = try XCTUnwrap(manager.fetchAllCircles().first { $0.name == "Daycare" })
        XCTAssertTrue(adriana.isDemo && riley.isDemo && zach.isDemo && aaron.isDemo && selma.isDemo)
        XCTAssertTrue([adriana, riley, zach, aaron, selma].allSatisfy { ($0.notes ?? "").isEmpty })
        XCTAssertTrue(hasRelationship(from: adriana, to: me, type: .child))
        XCTAssertTrue(hasRelationship(between: adriana, and: riley, type: .friend))
        XCTAssertTrue(hasRelationship(from: zach, to: riley, type: .parent))
        XCTAssertTrue(hasRelationship(from: aaron, to: riley, type: .parent))
        XCTAssertTrue(hasRelationship(from: selma, to: adriana, type: .caregiver))
        XCTAssertEqual(adriana.primaryCircle?.name, "Family")
        for person in [riley, zach, aaron, selma] { XCTAssertEqual(person.primaryCircle?.id, daycare.id) }
        XCTAssertFalse(hasRelationship(between: adriana, and: zach, type: .parent))
        XCTAssertFalse(hasRelationship(between: adriana, and: aaron, type: .parent))
        XCTAssertFalse(hasRelationship(between: zach, and: aaron, type: .spouse))
        let idsBeforeReplay = Set(try manager.fetchAllPersons().map(\.id))
        XCTAssertTrue(try service.seedDemoData())
        XCTAssertEqual(Set(try manager.fetchAllPersons().map(\.id)), idsBeforeReplay)

        let customPond = try manager.createCircle(name: "Riley's Pond")
        try manager.updatePerson(riley, name: "Riley Edited", notes: .set("A note I added."))
        try manager.addToCircle(riley, circle: customPond)
        try manager.deletePerson(selma)
        XCTAssertTrue(try service.seedDemoData())
        let replayedPeople = try manager.fetchAllPersons()
        XCTAssertEqual(replayedPeople.first { $0.id == riley.id }?.name, "Riley Edited")
        XCTAssertEqual(replayedPeople.first { $0.id == riley.id }?.notes, "A note I added.")
        XCTAssertEqual(replayedPeople.first { $0.id == riley.id }?.primaryCircle?.id, customPond.id)
        XCTAssertFalse(replayedPeople.contains { $0.id == selma.id })

        let siblingResponse = try XCTUnwrap(manager.relationshipSearch(query: "my sibling", demoMode: true))
        XCTAssertTrue(siblingResponse.paths.contains { $0.person.name == "Tom Miller" })
    }

    func testExistingStandardDemoUpgradeRunsFromContextRepairAndKeepsPersonalContacts() throws {
        let me = try manager.createPerson(name: "Me", isMe: true)
        let personal = try manager.createPerson(name: "Personal Contact", notes: "Keep this.")
        let service = DemoDataService(dataManager: manager)
        XCTAssertTrue(try service.seedDemoData())
        let sample = try manager.fetchAllPersons().filter(\.isDemo)
        for person in sample where ["Adriana", "Riley", "Zach", "Aaron", "Selma"].contains(person.name) {
            try manager.deletePerson(person)
        }
        let daycare = try XCTUnwrap(manager.fetchAllCircles().first { $0.name == "Daycare" })
        try manager.deleteCircle(daycare)
        UserDefaults.standard.removeObject(forKey: "demo.daycare-cluster.v1.\(me.id.uuidString)")

        try service.updateExistingDemoContexts()

        let upgraded = try manager.fetchAllPersons()
        XCTAssertTrue(["Adriana", "Riley", "Zach", "Aaron", "Selma"].allSatisfy { name in
            upgraded.contains { $0.name == name && $0.isDemo }
        })
        XCTAssertTrue(upgraded.contains { $0.id == personal.id && !$0.isDemo && $0.notes == "Keep this." })
    }

    func testCompletedSampleClusterTombstonePreventsReaddingDeletedPeopleOrPond() throws {
        let me = try manager.createPerson(name: "Me", isMe: true)
        let service = DemoDataService(dataManager: manager)
        XCTAssertTrue(try service.seedDemoData())
        let sample = try manager.fetchAllPersons().filter(\.isDemo)
        for person in sample where ["Adriana", "Riley", "Zach", "Aaron", "Selma"].contains(person.name) {
            try manager.deletePerson(person)
        }
        let daycare = try XCTUnwrap(manager.fetchAllCircles().first { $0.name == "Daycare" })
        try manager.deleteCircle(daycare)

        XCTAssertTrue(try service.seedDemoData())

        let remaining = try manager.fetchAllPersons()
        XCTAssertFalse(remaining.contains { ["Adriana", "Riley", "Zach", "Aaron", "Selma"].contains($0.name) })
        XCTAssertFalse(try manager.fetchAllCircles().contains { $0.name == "Daycare" })
        XCTAssertTrue(remaining.contains { $0.id == me.id && $0.isMe })
    }

    func testSampleClusterMarkerIsWrittenOnlyAfterTheOuterTransactionCommits() throws {
        enum Failure: Error { case abort }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let service = DemoDataService(dataManager: manager)
        let marker = "demo.daycare-cluster.v1.\(me.id.uuidString)"

        XCTAssertThrowsError(try manager.performAtomicEdit {
            XCTAssertTrue(try service.seedDemoData())
            throw Failure.abort
        })

        XCTAssertFalse(UserDefaults.standard.bool(forKey: marker))
        XCTAssertTrue(try manager.fetchAllPersons().filter(\.isDemo).isEmpty)
        XCTAssertTrue(try service.seedDemoData())
        XCTAssertEqual(try manager.fetchAllPersons().filter(\.isDemo).count, 23)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: marker))
    }

    func testEditedCustomDemoSetDoesNotReceiveStandardSampleCluster() throws {
        let me = try manager.createPerson(name: "Me", isMe: true)
        let service = DemoDataService(dataManager: manager)
        XCTAssertTrue(try service.seedDemoData())
        let sample = try manager.fetchAllPersons().filter(\.isDemo)
        for person in sample where ["Adriana", "Riley", "Zach", "Aaron", "Selma"].contains(person.name) {
            try manager.deletePerson(person)
        }
        let daycare = try XCTUnwrap(manager.fetchAllCircles().first { $0.name == "Daycare" })
        try manager.deleteCircle(daycare)
        let sarah = try XCTUnwrap(sample.first { $0.name == "Sarah Chen" })
        try manager.updatePerson(sarah, name: "Sarah's New Name")
        UserDefaults.standard.removeObject(forKey: "demo.daycare-cluster.v1.\(me.id.uuidString)")

        try service.updateExistingDemoContexts()

        let people = try manager.fetchAllPersons()
        XCTAssertEqual(people.filter(\.isDemo).count, 18)
        XCTAssertFalse(people.contains { ["Adriana", "Riley", "Zach", "Aaron", "Selma"].contains($0.name) })
        XCTAssertFalse(try manager.fetchAllCircles().contains { $0.name == "Daycare" })
        XCTAssertEqual(people.first { $0.id == sarah.id }?.name, "Sarah's New Name")
    }

    func testLegacyDemoContextRepairPreservesIdentityThenRespectsLaterUserEdits() throws {
        let me = try manager.createPerson(name: "Me", isMe: true)
        let personal = try manager.createPerson(name: "Personal Contact", notes: "Never sample data")
        let service = DemoDataService(dataManager: manager)
        XCTAssertTrue(try service.seedDemoData())

        let custom = try manager.createCircle(name: "Our Neighbors", color: "#123456", emoji: "")
        let circles = try manager.fetchAllCircles()
        let family = try XCTUnwrap(circles.first { $0.shouldAutoAssign(for: .parent) })
        let friends = try XCTUnwrap(circles.first { $0.shouldAutoAssign(for: .friend) })
        try manager.updateCircle(family, name: "Home", emoji: family.emoji, color: family.color)

        let demos = try manager.fetchAllPersons().filter(\.isDemo)
        let people = Dictionary(uniqueKeysWithValues: demos.map { ($0.name, $0) })
        let legacyNotes: [String: String] = [
            "Sarah Chen": "Loves hiking and photography. Met at college.",
            "Linda Miller": "Mom. Calls every Sunday.",
            "Robert Miller": "Dad. Loves woodworking and jazz.",
            "Jake Morrison": "College roommate. Married to Nicole, 3 kids. Always up for weekend trips and BBQs.",
            "Nicole Morrison": "Jake's wife. Graphic designer, loves pasta making and Saturday farmers markets.",
            "Liam Morrison": "Jake & Nicole's oldest. Obsessed with dinosaurs and Lego. Plays little league.",
            "Ella Morrison": "Middle child. Taking ballet classes. Loves drawing rainbows.",
            "Noah Morrison": "The baby! Born Dec 2025. Already has his dad's smile.",
            "Emma Wilson": "Book club friend. Recommends great reads.",
            "David Park": "Team lead at work. Great mentor.",
            "Lisa Thompson": "Coworker. Works on the design team.",
            "Tom Miller": "Younger brother. Studying engineering.",
            "Mia Rodriguez": "Book club organizer. Loves mystery novels.",
            "Ryan O'Brien": "Book club member. Sci-fi enthusiast.",
            "Chris Evans": "David's manager.",
            "Sam Taylor": "Jake's teammate.",
            "Alex Jordan": "Sam's partner.",
            "Priya Patel": "Met at a design conference. A sample contact for practicing connections."
        ]
        for (name, note) in legacyNotes {
            let person = try XCTUnwrap(people[name])
            try manager.updatePerson(person, notes: .set(note))
        }
        let householdNames = ["Nicole Morrison", "Liam Morrison", "Ella Morrison", "Noah Morrison"]
        for name in householdNames {
            let person = try XCTUnwrap(people[name])
            try manager.addToCircle(person, circle: family)
        }
        let emma = try XCTUnwrap(people["Emma Wilson"])
        let priya = try XCTUnwrap(people["Priya Patel"])
        if let legacyMissingLink = me.allRelationships.first(where: {
            $0.type == .friend && $0.otherContact(from: me).id == emma.id
        }) {
            try manager.deleteRelationship(legacyMissingLink)
        }
        let idsBeforeRepair = Dictionary(uniqueKeysWithValues: people.map { ($0.key, $0.value.id) })

        try service.updateExistingDemoContexts()

        let repaired = try manager.fetchAllPersons().filter(\.isDemo)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: repaired.map { ($0.name, $0.id) }), idsBeforeRepair)
        for name in householdNames {
            XCTAssertEqual(repaired.first { $0.name == name }?.primaryCircle?.id, friends.id)
        }
        for (name, oldNote) in legacyNotes {
            XCTAssertNotEqual(repaired.first { $0.name == name }?.notes, oldNote, "Legacy context was not updated for \(name)")
        }
        XCTAssertTrue(hasRelationship(between: me, and: emma, type: .friend))
        XCTAssertEqual(repaired.first { $0.id == priya.id }?.notes, "Met at a design conference. Interested in accessible design.")
        XCTAssertTrue(repaired.first { $0.id == priya.id }?.isOrphan == true)
        XCTAssertNil(repaired.first { $0.id == priya.id }?.primaryCircle)
        XCTAssertEqual(try manager.fetchAllCircles().filter(\.isSystem).count, 3)
        XCTAssertTrue((try manager.fetchAllPersons()).contains { $0.id == personal.id && !$0.isDemo })

        // Once a legacy fingerprint has been updated, later edits belong to the
        // user. Replaying either repair entry point must not move or rewrite it.
        let liam = try XCTUnwrap(repaired.first { $0.name == "Liam Morrison" })
        try manager.updatePerson(liam, notes: .set("Our family keeps this note."))
        try manager.addToCircle(liam, circle: family)
        let ella = try XCTUnwrap(repaired.first { $0.name == "Ella Morrison" })
        let repairedEllaNote = ella.notes
        try manager.addToCircle(ella, circle: family)
        let sam = try XCTUnwrap(repaired.first { $0.name == "Sam Taylor" })
        try manager.updatePerson(sam, notes: .set("Met through our neighborhood garden."))
        try manager.addToCircle(sam, circle: custom)
        let relationshipIDs = Set(try manager.context.fetch(FetchDescriptor<Relationship>()).map(\.id))

        try service.updateExistingDemoContexts()
        XCTAssertTrue(try service.seedDemoData())
        try service.updateExistingDemoContexts()

        let finalPeople = try manager.fetchAllPersons()
        XCTAssertEqual(finalPeople.first { $0.id == liam.id }?.primaryCircle?.id, family.id)
        XCTAssertEqual(finalPeople.first { $0.id == liam.id }?.notes, "Our family keeps this note.")
        XCTAssertEqual(finalPeople.first { $0.id == ella.id }?.primaryCircle?.id, family.id)
        XCTAssertEqual(finalPeople.first { $0.id == ella.id }?.notes, repairedEllaNote)
        XCTAssertEqual(finalPeople.first { $0.id == sam.id }?.primaryCircle?.id, custom.id)
        XCTAssertEqual(finalPeople.first { $0.id == sam.id }?.notes, "Met through our neighborhood garden.")
        XCTAssertEqual(Set(finalPeople.filter(\.isDemo).map(\.id)), Set(idsBeforeRepair.values))
        let finalRelationships = try manager.context.fetch(FetchDescriptor<Relationship>())
        XCTAssertEqual(Set(finalRelationships.map(\.id)), relationshipIDs)
        XCTAssertEqual(Set(finalRelationships.map(\.id)).count, finalRelationships.count)
    }

    func testExistingDemoContextRepairDoesNotCompleteAPartialFixture() throws {
        _ = try manager.createPerson(name: "Me", isMe: true)
        let sarah = try manager.createPerson(
            name: "Sarah Chen",
            notes: "Loves hiking and photography. Met at college.",
            isDemo: true
        )
        let personal = try manager.createPerson(name: "Personal Contact")
        let idsBefore = Set((try manager.fetchAllPersons()).map(\.id))

        let service = DemoDataService(dataManager: manager)
        try service.updateExistingDemoContexts()

        XCTAssertEqual(Set((try manager.fetchAllPersons()).map(\.id)), idsBefore)
        XCTAssertEqual((try manager.fetchAllPersons()).first { $0.id == sarah.id }?.id, sarah.id)
        XCTAssertTrue((try manager.fetchAllPersons()).contains { $0.id == personal.id && !$0.isDemo })
        XCTAssertFalse(try service.seedDemoData())
    }

    func testDemoCleanupPreservesAnEmptyUserBookClub() throws {
        _ = try manager.createPerson(name: "Me", isMe: true)
        let userCircle = try manager.createCircle(name: "Book Club", color: "#123456", emoji: "📖")
        let service = DemoDataService(dataManager: manager)

        XCTAssertTrue(try service.seedDemoData())
        try service.removeDemoData()

        let retained = try XCTUnwrap(manager.fetchAllCircles().first { $0.id == userCircle.id })
        XCTAssertEqual(retained.color, "#123456")
        XCTAssertTrue(retained.activeContacts.isEmpty)
    }

    func testRemovingSampleClearsMarkerAndAllowsReseedingItsRetainedDaycarePond() throws {
        let me = try manager.createPerson(name: "Me", isMe: true)
        let service = DemoDataService(dataManager: manager)
        let marker = "demo.daycare-cluster.v1.\(me.id.uuidString)"
        XCTAssertTrue(try service.seedDemoData())
        let originalPond = try XCTUnwrap(manager.fetchAllCircles().first { $0.name == "Daycare" })

        try service.removeDemoData()

        XCTAssertFalse(UserDefaults.standard.bool(forKey: marker))
        XCTAssertEqual(try manager.fetchAllCircles().first { $0.id == originalPond.id }?.activeContacts.count, 0)
        XCTAssertTrue(try service.seedDemoData())

        let reseededPeople = try manager.fetchAllPersons().filter(\.isDemo)
        let adriana = try XCTUnwrap(reseededPeople.first { $0.name == "Adriana" })
        let daycare = try XCTUnwrap(manager.fetchAllCircles().first { $0.name == "Daycare" })
        XCTAssertEqual(reseededPeople.count, 23)
        XCTAssertEqual(daycare.id, originalPond.id)
        XCTAssertEqual(adriana.primaryCircle?.name, "Family")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: marker))
    }

    func testDemoSeedFindsRenamedSystemCirclesByRole() throws {
        _ = try manager.createPerson(name: "Me", isMe: true)
        try manager.createSystemCircles()
        let family = try XCTUnwrap(manager.fetchAllCircles().first { $0.shouldAutoAssign(for: .parent) })
        let friends = try XCTUnwrap(manager.fetchAllCircles().first { $0.shouldAutoAssign(for: .friend) })
        let professional = try XCTUnwrap(manager.fetchAllCircles().first { $0.shouldAutoAssign(for: .coworker) })
        try manager.updateCircle(family, name: "Home", emoji: family.emoji, color: family.color)
        try manager.updateCircle(friends, name: "People", emoji: friends.emoji, color: friends.color)
        try manager.updateCircle(professional, name: "Work", emoji: professional.emoji, color: professional.color)

        XCTAssertTrue(try DemoDataService(dataManager: manager).seedDemoData())
        XCTAssertEqual(try manager.fetchAllCircles().first { $0.id == family.id }?.activeContacts.count, 5)
        XCTAssertEqual(try manager.fetchAllCircles().first { $0.id == friends.id }?.activeContacts.count, 7)
        XCTAssertEqual(try manager.fetchAllCircles().first { $0.id == professional.id }?.activeContacts.count, 3)
        XCTAssertEqual(try manager.fetchAllCircles().filter(\.isSystem).count, 3)
    }

    func testPartialDemoFixtureIsNotReportedAsSeeded() throws {
        _ = try manager.createPerson(name: "Me", isMe: true)
        _ = try manager.createPerson(name: "Sarah Chen", isDemo: true)

        XCTAssertFalse(try DemoDataService(dataManager: manager).seedDemoData())
        XCTAssertEqual(try manager.fetchAllPersons().filter(\.isDemo).count, 1)
    }

    func testWalkthroughChoosesAnActualUnlinkedExample() throws {
        _ = try manager.createPerson(name: "Me", isMe: true)
        let tour = FeatureWalkthroughManager()

        XCTAssertTrue(tour.seedDemoDataIfNeeded(dataManager: manager))
        XCTAssertNotNil(tour.examplePersonID)
        XCTAssertEqual(tour.examplePersonName, "Priya Patel")
        XCTAssertEqual(tour.suggestedConnectionName, "Me")
        XCTAssertTrue(tour.currentActionPrompt == nil)
        tour.currentStep = .link
        XCTAssertTrue(tour.currentActionPrompt?.contains("Priya Patel") == true)

        let me = try XCTUnwrap(try manager.fetchMePerson())
        let priya = try XCTUnwrap((try manager.fetchAllPersons()).first { $0.name == "Priya Patel" })
        try manager.createRelationship(from: priya, to: me, type: .friend)
        tour.reset()
        XCTAssertTrue(tour.seedDemoDataIfNeeded(dataManager: manager))
        XCTAssertNotEqual(tour.examplePersonID, priya.id)
        if let chosenID = tour.examplePersonID {
            XCTAssertFalse(me.connectedContacts.contains { $0.id == chosenID })
        }
        XCTAssertTrue(tour.currentActionPrompt == nil)
    }

    func testReplayChoosesPairWithoutExistingMeConnectionWhenNamesAreEdited() throws {
        let me = try manager.createPerson(name: "Me", isMe: true)
        let tour = FeatureWalkthroughManager()
        XCTAssertTrue(tour.seedDemoDataIfNeeded(dataManager: manager))
        let alex = try XCTUnwrap((try manager.fetchAllPersons()).first { $0.name == "Alex Jordan" })
        try manager.updatePerson(alex, name: "Alex Renamed")

        // Connecting every sample to Me still leaves demo-demo pairs available.
        // Replay should choose one of those real, unlinked pairs.
        for person in try manager.fetchAllPersons().filter(\.isDemo) {
            try manager.createRelationship(from: person, to: me, type: .friend)
        }
        tour.reset()
        tour.replayWalkthrough(dataManager: manager)
        XCTAssertFalse(tour.exampleConnectionIsExisting)
        let people = try manager.fetchAllPersons()
        let target = try XCTUnwrap(tour.examplePersonID.flatMap { id in people.first { $0.id == id } })
        let partner = try XCTUnwrap(people.first { $0.isDemo && $0.name == tour.suggestedConnectionName })
        XCTAssertNotEqual(target.id, partner.id)
        XCTAssertFalse(target.allRelationships.contains { relationship in
            (relationship.fromContact.id == target.id && relationship.toContact.id == partner.id)
                || (relationship.fromContact.id == partner.id && relationship.toContact.id == target.id)
        })
        tour.currentStep = .link
        XCTAssertTrue(tour.currentActionPrompt?.contains(target.name) == true)
        XCTAssertTrue(tour.currentActionPrompt?.contains(partner.name) == true)
        try manager.createRelationship(from: target, to: partner, type: .friend)
        tour.report(.createdLink)
        XCTAssertTrue(tour.justCompletedStep)
    }

    func testReplayFullSampleCliqueUsesExistingConnectionLesson() throws {
        let me = try manager.createPerson(name: "Me", isMe: true)
        let tour = FeatureWalkthroughManager()
        XCTAssertTrue(tour.seedDemoDataIfNeeded(dataManager: manager))
        let demos = try manager.fetchAllPersons().filter(\.isDemo)
        for person in demos {
            try manager.createRelationship(from: person, to: me, type: .friend)
        }
        for firstIndex in demos.indices {
            for secondIndex in demos.indices where secondIndex > firstIndex {
                try manager.createRelationship(from: demos[firstIndex], to: demos[secondIndex], type: .friend)
            }
        }

        tour.reset()
        tour.replayWalkthrough(dataManager: manager)
        XCTAssertTrue(tour.exampleConnectionIsExisting)
        tour.currentStep = .link
        XCTAssertNotNil(tour.currentActionPrompt)

        tour.report(.openedProfile)
        XCTAssertTrue(tour.justCompletedStep)
    }

    func testReplayWithoutMeExplainsWhyTourCannotStart() throws {
        let tour = FeatureWalkthroughManager()
        tour.replayWalkthrough(dataManager: manager)
        XCTAssertFalse(tour.isActive)
        XCTAssertEqual(tour.demoErrorMessage, "Create your profile before replaying the sample tour.")
    }

    func testTourInsetsFollowMeasuredCardPlacementBelowHomeControls() {
        let tour = FeatureWalkthroughManager()
        tour.isActive = true
        tour.graphViewportFrame = CGRect(x: 0, y: 84, width: 375, height: 583)
        tour.graphFooterHeight = 80
        tour.currentStep = .ponds
        tour.overlayFrame = CGRect(x: 20, y: 32, width: 335, height: 340)
        XCTAssertEqual(tour.graphObscuredInsets.top, 288)
        XCTAssertEqual(tour.graphObscuredInsets.bottom, 80)

        tour.currentStep = .profile
        tour.overlayFrame = CGRect(x: 20, y: 287, width: 335, height: 350)
        XCTAssertEqual(tour.graphObscuredInsets.top, 0)
        XCTAssertEqual(tour.graphObscuredInsets.bottom, 380)

        // Searching or opening a sheet removes the card's obstruction, while
        // the graph's own group controls still reserve their measured height.
        tour.overlayFrame = .zero
        XCTAssertEqual(tour.graphObscuredInsets.top, 0)
        XCTAssertEqual(tour.graphObscuredInsets.bottom, 80)
    }

    func testTourCardRetainsGraphSpaceOnCompactAndLargeTextLayouts() {
        let layouts: [(width: CGFloat, height: CGFloat, controls: CGFloat, footer: CGFloat)] = [
            (375, 647, 64, 80),
            (667, 355, 108, 104),
            (375, 647, 120, 112)
        ]
        for layout in layouts {
            let tour = FeatureWalkthroughManager()
            tour.isActive = true
            let home = CGRect(x: 0, y: 20, width: layout.width, height: layout.height)
            tour.graphViewportFrame = CGRect(x: 0, y: 20 + layout.controls,
                width: layout.width, height: layout.height - layout.controls)
            tour.graphFooterHeight = layout.footer
            for step in [WalkthroughStep.profile, .ponds] {
                tour.currentStep = step
                let height = tour.maximumOverlayHeight(in: home)
                let y = step.hintPlacement == .top ? home.minY + 12 : home.maxY - 30 - height
                tour.overlayFrame = CGRect(x: 20, y: y, width: layout.width - 40, height: height)
                let insets = tour.graphObscuredInsets
                let visibleHeight = tour.graphViewportFrame.height - insets.top - insets.bottom
                XCTAssertLessThanOrEqual(height, home.height * 0.55)
                XCTAssertGreaterThanOrEqual(visibleHeight + 0.001,
                    min(160, tour.graphViewportFrame.height * 0.35))
            }
        }
    }

    private func hasRelationship(from: Person, to: Person, type: RelationshipType) -> Bool {
        from.allRelationships.contains {
            !$0.isDeleted && $0.fromContact.id == from.id && $0.toContact.id == to.id && $0.type == type
        }
    }

    private func hasRelationship(between first: Person, and second: Person, type: RelationshipType) -> Bool {
        first.allRelationships.contains {
            !$0.isDeleted && $0.type == type &&
                Set([$0.fromContact.id, $0.toContact.id]) == Set([first.id, second.id])
        }
    }

    private func note(for person: Person?, mentionsAny terms: [String]) -> Bool {
        guard let note = person?.notes else { return false }
        func normalized(_ value: String) -> String {
            value.lowercased()
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "‑", with: " ")
        }
        let context = normalized(note)
        return terms.contains { context.contains(normalized($0)) }
    }
}
