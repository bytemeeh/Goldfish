import XCTest
import CoreGraphics
@testable import Goldfish

@MainActor
final class PondDisclosureTests: XCTestCase {
    @discardableResult
    private func link(_ from: Person, _ to: Person, _ type: RelationshipType = .friend) -> Relationship {
        let relationship = Relationship(from: from, to: to, type: type)
        from.outgoingRelationships.append(relationship)
        to.incomingRelationships.append(relationship)
        return relationship
    }

    private func membership(_ person: Person, in pond: GoldfishCircle) {
        let relation = CircleContact(circle: pond, contact: person)
        pond.circleContacts.append(relation)
        person.circleContacts.append(relation)
    }

    func testInitialDisclosureIsMeAndDirectContactsThenDavidRevealsLisaAndChris() {
        let me = Person(name: "Me", isMe: true)
        let david = Person(name: "David")
        let lisa = Person(name: "Lisa")
        let chris = Person(name: "Chris")
        link(me, david); link(david, lisa); link(david, chris)
        var disclosure = PondDisclosure(people: [me, david, lisa, chris])

        XCTAssertEqual(disclosure.snapshot.visibleIDs, Set([me.id, david.id]))
        XCTAssertEqual(disclosure.snapshot.directIDs, Set([david.id]))
        XCTAssertEqual(disclosure.hiddenNeighborCount(for: david.id), 2)

        disclosure.togglePondConnections(id: david.id)
        XCTAssertEqual(disclosure.snapshot.visibleIDs, Set([me.id, david.id, lisa.id, chris.id]))
        XCTAssertTrue(disclosure.isExpanded(david.id))
        XCTAssertEqual(disclosure.snapshot.hiddenNeighborCounts[david.id], 0)
    }

    func testNestedAndSharedBranchesRemainReachableWithoutTreeAssumption() {
        let me = Person(name: "Me", isMe: true)
        let david = Person(name: "David")
        let erin = Person(name: "Erin")
        let lisa = Person(name: "Lisa")
        let jo = Person(name: "Jo")
        link(me, david); link(me, erin); link(david, lisa); link(erin, lisa); link(lisa, jo)
        var disclosure = PondDisclosure(people: [me, david, erin, lisa, jo])

        disclosure.togglePondConnections(id: david.id)
        disclosure.togglePondConnections(id: lisa.id)
        XCTAssertTrue(disclosure.canExpand(erin.id), "A visible shared contact still needs an alternate branch to keep it reachable")
        disclosure.togglePondConnections(id: erin.id)
        XCTAssertTrue(disclosure.snapshot.visibleIDs.contains(jo.id))
        disclosure.togglePondConnections(id: david.id)
        XCTAssertTrue(disclosure.snapshot.visibleIDs.contains(lisa.id))
        XCTAssertTrue(disclosure.snapshot.visibleIDs.contains(jo.id))
        disclosure.togglePondConnections(id: erin.id)
        XCTAssertFalse(disclosure.snapshot.visibleIDs.contains(jo.id))
        XCTAssertFalse(disclosure.snapshot.expandedIDs.contains(lisa.id))
    }

    func testSelectedTrailStaysRootedWhenExpandedNodesLinkBackToEachOther() {
        let me = Person(name: "Me", isMe: true)
        let david = Person(name: "David")
        let lisa = Person(name: "Lisa")
        let chris = Person(name: "Chris")
        link(me, david); link(david, lisa); link(lisa, chris); link(chris, lisa)
        var disclosure = PondDisclosure(people: [me, david, lisa, chris])

        disclosure.togglePondConnections(id: david.id)
        disclosure.togglePondConnections(id: lisa.id)
        disclosure.togglePondConnections(id: chris.id)
        XCTAssertEqual(disclosure.snapshot.trail, [me.id, david.id, lisa.id, chris.id])
        XCTAssertEqual(Set(disclosure.snapshot.trail).count, disclosure.snapshot.trail.count)
        XCTAssertEqual(disclosure.snapshot.trail.first, me.id)
    }

    func testSelectingTrailAncestorPreservesEveryOpenBranch() {
        let me = Person(name: "Me", isMe: true)
        let david = Person(name: "David")
        let lisa = Person(name: "Lisa")
        let chris = Person(name: "Chris")
        let sibling = Person(name: "Sibling")
        link(me, david); link(david, lisa); link(david, sibling); link(lisa, chris)
        var disclosure = PondDisclosure(people: [me, david, lisa, chris, sibling])

        disclosure.togglePondConnections(id: david.id)
        disclosure.togglePondConnections(id: lisa.id)
        XCTAssertEqual(disclosure.snapshot.trail, [me.id, david.id, lisa.id])
        let visible = disclosure.snapshot.visibleIDs
        let openBranches = disclosure.snapshot.expandedIDs

        XCTAssertTrue(disclosure.selectTrailAncestor(id: david.id))
        XCTAssertEqual(disclosure.snapshot.selectedID, david.id)
        XCTAssertEqual(disclosure.snapshot.trail, [me.id, david.id])
        XCTAssertEqual(disclosure.snapshot.visibleIDs, visible)
        XCTAssertEqual(disclosure.snapshot.expandedIDs, openBranches)
        XCTAssertTrue(disclosure.snapshot.visibleIDs.contains(chris.id))
        XCTAssertFalse(disclosure.selectTrailAncestor(id: UUID()))
        XCTAssertEqual(disclosure.snapshot.expandedIDs, openBranches)
    }

    func testTerminalContactSelectionDoesNotCreateMeaninglessExpansion() {
        let me = Person(name: "Me", isMe: true)
        let leaf = Person(name: "Leaf")
        link(me, leaf)
        var disclosure = PondDisclosure(people: [me, leaf])

        disclosure.selectPondContact(id: leaf.id)
        disclosure.togglePondConnections(id: leaf.id)
        XCTAssertEqual(disclosure.snapshot.selectedID, leaf.id)
        XCTAssertEqual(disclosure.snapshot.trail, [me.id, leaf.id])
        XCTAssertFalse(disclosure.snapshot.expandedIDs.contains(leaf.id))
    }

    func testActivatingNestedContactKeepsFocusRootAndRepeatedTapDoesNotCollapse() {
        let me = Person(name: "Me", isMe: true)
        let adriana = Person(name: "Adriana")
        let riley = Person(name: "Riley")
        let parent = Person(name: "Parent")
        link(me, adriana); link(adriana, riley); link(riley, parent)
        var disclosure = PondDisclosure(people: [me, adriana, riley, parent])

        disclosure.activatePondContact(id: adriana.id)
        XCTAssertEqual(disclosure.snapshot.focusRootID, adriana.id)
        XCTAssertTrue(disclosure.snapshot.focusedIDs.contains(riley.id))
        XCTAssertTrue(disclosure.snapshot.expandedIDs.contains(adriana.id))

        disclosure.activatePondContact(id: riley.id)
        XCTAssertEqual(disclosure.snapshot.focusRootID, adriana.id)
        XCTAssertEqual(disclosure.snapshot.selectedID, riley.id)
        XCTAssertTrue(disclosure.snapshot.expandedIDs.contains(adriana.id))
        XCTAssertTrue(disclosure.snapshot.expandedIDs.contains(riley.id))
        XCTAssertTrue(disclosure.snapshot.focusedIDs.contains(parent.id))
        XCTAssertTrue(disclosure.snapshot.focusedEdges.contains(PondDisclosureEdge(from: riley.id, to: parent.id)))

        let branches = disclosure.snapshot.expandedIDs
        disclosure.activatePondContact(id: riley.id)
        XCTAssertEqual(disclosure.snapshot.expandedIDs, branches)
        XCTAssertEqual(disclosure.snapshot.focusRootID, adriana.id)
    }

    func testActivatingUnrelatedContactSwitchesFocusAndClearPreservesBranches() {
        let me = Person(name: "Me", isMe: true)
        let adriana = Person(name: "Adriana")
        let riley = Person(name: "Riley")
        let unrelated = Person(name: "Unrelated")
        let colleague = Person(name: "Colleague")
        link(me, adriana); link(adriana, riley)
        link(me, unrelated); link(unrelated, colleague)
        var disclosure = PondDisclosure(people: [me, adriana, riley, unrelated, colleague])

        disclosure.activatePondContact(id: adriana.id)
        disclosure.activatePondContact(id: unrelated.id)
        XCTAssertEqual(disclosure.snapshot.focusRootID, unrelated.id)
        XCTAssertTrue(disclosure.snapshot.focusedIDs.contains(colleague.id))
        XCTAssertFalse(disclosure.snapshot.focusedIDs.contains(riley.id))

        let branches = disclosure.snapshot.expandedIDs
        disclosure.clearPondFocus()
        XCTAssertNil(disclosure.snapshot.focusRootID)
        XCTAssertNil(disclosure.snapshot.selectedID)
        XCTAssertTrue(disclosure.snapshot.focusedIDs.isEmpty)
        XCTAssertEqual(disclosure.snapshot.expandedIDs, branches)
        XCTAssertTrue(disclosure.snapshot.visibleIDs.contains(riley.id))
    }

    func testFocusTraversalStopsAtMeAndUpstreamAncestorsAndHandlesSharedCycles() {
        let me = Person(name: "Me", isMe: true)
        let upstream = Person(name: "Upstream")
        let root = Person(name: "Root")
        let shared = Person(name: "Shared")
        let side = Person(name: "Side")
        link(me, upstream); link(upstream, root)
        link(root, shared); link(root, side); link(shared, side); link(side, root)
        var disclosure = PondDisclosure(people: [me, upstream, root, shared, side])

        disclosure.activatePondContact(id: upstream.id)
        disclosure.clearPondFocus()
        disclosure.activatePondContact(id: root.id)
        disclosure.activatePondContact(id: shared.id)
        disclosure.activatePondContact(id: side.id)

        XCTAssertEqual(disclosure.snapshot.focusRootID, root.id)
        XCTAssertFalse(disclosure.snapshot.focusedIDs.contains(me.id))
        XCTAssertFalse(disclosure.snapshot.focusedIDs.contains(upstream.id))
        XCTAssertEqual(disclosure.snapshot.focusedIDs.intersection([root.id, shared.id, side.id]), [root.id, shared.id, side.id])
        XCTAssertFalse(disclosure.snapshot.focusedEdges.contains { $0.to == me.id || $0.from == me.id })
        XCTAssertFalse(disclosure.snapshot.focusedEdges.contains { $0.to == upstream.id })
        XCTAssertEqual(Set(disclosure.snapshot.focusedEdges).count, disclosure.snapshot.focusedEdges.count)
    }

    func testConnectionPathIsExplicitAndSelectionClearsItWithoutMovingFocusRoot() {
        let me = Person(name: "Me", isMe: true)
        let adriana = Person(name: "Adriana")
        let riley = Person(name: "Riley")
        let parent = Person(name: "Parent")
        link(me, adriana); link(adriana, riley); link(riley, parent)
        var disclosure = PondDisclosure(people: [me, adriana, riley, parent])

        disclosure.activatePondContact(id: adriana.id)
        disclosure.activatePondContact(id: riley.id)
        disclosure.showConnectionPath()
        XCTAssertEqual(disclosure.snapshot.focusRootID, adriana.id)
        XCTAssertEqual(disclosure.snapshot.pathHighlightIDs.last, riley.id)
        XCTAssertFalse(disclosure.snapshot.pathHighlightIDs.isEmpty)

        disclosure.activatePondContact(id: parent.id)
        XCTAssertEqual(disclosure.snapshot.focusRootID, adriana.id)
        XCTAssertTrue(disclosure.snapshot.pathHighlightIDs.isEmpty)
        disclosure.clearPondFocus()
        XCTAssertTrue(disclosure.snapshot.pathHighlightIDs.isEmpty)
    }

    func testReloadClearsDeletedFocusAndSelectionWithoutRevealingStaleBranch() {
        let me = Person(name: "Me", isMe: true)
        let root = Person(name: "Root")
        let child = Person(name: "Child")
        link(me, root); link(root, child)
        var disclosure = PondDisclosure(people: [me, root, child])
        disclosure.activatePondContact(id: root.id)
        disclosure.activatePondContact(id: child.id)
        XCTAssertEqual(disclosure.snapshot.focusRootID, root.id)

        disclosure.reload(people: [me, child])
        XCTAssertNil(disclosure.snapshot.focusRootID)
        XCTAssertNil(disclosure.snapshot.selectedID)
        XCTAssertFalse(disclosure.snapshot.visibleIDs.contains(root.id))
    }

    func testShowInPondRevealsOnlyTheSavedRouteUntilConnectionsAreExplicitlyOpened() {
        let me = Person(name: "Me", isMe: true)
        let direct = Person(name: "Direct")
        let target = Person(name: "Target")
        let further = Person(name: "Further")
        link(me, direct)
        link(direct, target)
        link(target, further)
        var disclosure = PondDisclosure(people: [me, direct, target, further])

        disclosure.revealRoute([me.id, direct.id, target.id], selecting: target.id)

        XCTAssertEqual(disclosure.snapshot.visibleIDs, Set([me.id, direct.id, target.id]))
        XCTAssertEqual(disclosure.snapshot.trail, [me.id, direct.id, target.id])
        XCTAssertEqual(disclosure.snapshot.selectedID, target.id)
        XCTAssertTrue(disclosure.snapshot.expandedIDs.isEmpty)
        XCTAssertFalse(disclosure.snapshot.visibleIDs.contains(further.id))
        XCTAssertTrue(disclosure.canExpand(target.id))

        disclosure.togglePondConnections(id: target.id)

        XCTAssertTrue(disclosure.snapshot.expandedIDs.contains(target.id))
        XCTAssertTrue(disclosure.snapshot.visibleIDs.contains(further.id))
    }

    func testShowInPondDoesNotGiveATerminalLeafAMeaninglessHideState() {
        let me = Person(name: "Me", isMe: true)
        let leaf = Person(name: "Leaf")
        link(me, leaf)
        var disclosure = PondDisclosure(people: [me, leaf])

        disclosure.revealRoute([me.id, leaf.id], selecting: leaf.id)

        XCTAssertEqual(disclosure.snapshot.visibleIDs, Set([me.id, leaf.id]))
        XCTAssertEqual(disclosure.snapshot.selectedID, leaf.id)
        XCTAssertFalse(disclosure.snapshot.expandedIDs.contains(leaf.id))
        XCTAssertFalse(disclosure.canExpand(leaf.id))
    }

    func testAlreadyVisibleFamilyConnectionsDoNotOfferANoOpExpansion() {
        let me = Person(name: "Me", isMe: true)
        let tom = Person(name: "Tom")
        let mother = Person(name: "Mother")
        let father = Person(name: "Father")
        link(me, tom, .sibling)
        link(mother, me, .mother)
        link(father, me, .father)
        link(mother, tom, .mother)
        link(father, tom, .father)
        var disclosure = PondDisclosure(people: [me, tom, mother, father])
        disclosure.revealRoute([me.id, tom.id], selecting: tom.id)
        let visibleBeforeTap = disclosure.snapshot.visibleIDs

        XCTAssertEqual(visibleBeforeTap, Set([me.id, tom.id, mother.id, father.id]))
        XCTAssertEqual(disclosure.hiddenNeighborCount(for: tom.id), 0)
        XCTAssertFalse(disclosure.canExpand(tom.id))

        disclosure.togglePondConnections(id: tom.id)

        XCTAssertEqual(disclosure.snapshot.visibleIDs, visibleBeforeTap)
        XCTAssertEqual(disclosure.snapshot.selectedID, tom.id)
        XCTAssertFalse(disclosure.snapshot.expandedIDs.contains(tom.id))
    }

    func testSharedContactKeepsTheRouteUsedToReachIt() {
        let me = Person(name: "Me", isMe: true)
        let alex = Person(name: "Alex")
        let max = Person(name: "Max")
        let nora = Person(name: "Nora")
        link(me, alex); link(me, nora); link(alex, max); link(max, nora, .spouse)
        var disclosure = PondDisclosure(people: [me, alex, max, nora])
        disclosure.togglePondConnections(id: alex.id)
        disclosure.togglePondConnections(id: max.id)
        disclosure.togglePondConnections(id: nora.id)
        XCTAssertEqual(disclosure.snapshot.trail, [me.id, alex.id, max.id, nora.id])
        XCTAssertTrue(disclosure.snapshot.directIDs.contains(nora.id))
        disclosure.selectPondContact(id: nil)
        XCTAssertNil(disclosure.snapshot.selectedID)
        XCTAssertTrue(disclosure.snapshot.trail.isEmpty)
    }

    func testCyclesCannotKeepDetachedBranchVisible() {
        let me = Person(name: "Me", isMe: true)
        let david = Person(name: "David")
        let a = Person(name: "A")
        let b = Person(name: "B")
        link(me, david); link(david, a); link(a, b); link(b, a)
        var disclosure = PondDisclosure(people: [me, david, a, b])

        disclosure.togglePondConnections(id: david.id)
        XCTAssertTrue(disclosure.snapshot.visibleIDs.contains(a.id))
        disclosure.togglePondConnections(id: a.id)
        disclosure.togglePondConnections(id: b.id)
        XCTAssertTrue(disclosure.snapshot.visibleIDs.contains(b.id))
        disclosure.togglePondConnections(id: david.id)
        XCTAssertFalse(disclosure.snapshot.visibleIDs.contains(a.id))
        XCTAssertFalse(disclosure.snapshot.visibleIDs.contains(b.id))
        XCTAssertFalse(disclosure.snapshot.expandedIDs.contains(b.id))
    }

    func testCrossPondAndOrphanRevealsKeepTruthfulPondBuckets() {
        let me = Person(name: "Me", isMe: true)
        let family = GoldfishCircle(name: "Family")
        let friends = GoldfishCircle(name: "Friends")
        let familyOnly = Person(name: "Family only")
        let friendOnly = Person(name: "Friend only")
        let orphan = Person(name: "Orphan")
        membership(familyOnly, in: family); membership(friendOnly, in: friends); membership(orphan, in: friends)
        link(familyOnly, friendOnly)
        var disclosure = PondDisclosure(people: [me, familyOnly, friendOnly, orphan])

        XCTAssertEqual(Set(disclosure.snapshot.hiddenByPond[family.id.uuidString] ?? []), Set([familyOnly.id]))
        XCTAssertEqual(Set(disclosure.snapshot.hiddenByPond[friends.id.uuidString] ?? []), Set([friendOnly.id, orphan.id]))
        XCTAssertTrue(disclosure.snapshot.unlinkedIDs.contains(familyOnly.id))
        disclosure.revealHiddenPeople(in: friends.id.uuidString)
        XCTAssertEqual(disclosure.snapshot.visibleIDs.intersection(Set([friendOnly.id, orphan.id])).count, 2)
        XCTAssertTrue(disclosure.snapshot.visibleIDs.contains(friendOnly.id))
        XCTAssertTrue(disclosure.snapshot.visibleIDs.contains(orphan.id))
    }

    func testFiftyContactsAreAddedCumulativelyInFourContactBatches() {
        let me = Person(name: "Me", isMe: true)
        let david = Person(name: "David")
        var contacts = [me, david]
        link(me, david)
        for index in 0..<50 {
            let contact = Person(name: "Contact \(index)")
            link(david, contact)
            contacts.append(contact)
        }
        var disclosure = PondDisclosure(people: contacts)

        disclosure.togglePondConnections(id: david.id)
        XCTAssertEqual(disclosure.snapshot.visibleIDs.count, 2 + 4)
        disclosure.showMorePondConnections(id: david.id)
        XCTAssertEqual(disclosure.snapshot.visibleIDs.count, 2 + 8)
        disclosure.showMorePondConnections(id: david.id)
        XCTAssertEqual(disclosure.snapshot.visibleIDs.count, 2 + 12)
        XCTAssertEqual(disclosure.snapshot.hiddenNeighborCounts[david.id], 38)
    }

    func testCollapseAllReturnsToDirectOnlyAndClearsManualRoots() {
        let me = Person(name: "Me", isMe: true)
        let david = Person(name: "David")
        let lisa = Person(name: "Lisa")
        let pond = GoldfishCircle(name: "Pond")
        let orphan = Person(name: "Orphan")
        membership(orphan, in: pond); membership(lisa, in: pond)
        link(me, david); link(david, lisa)
        var disclosure = PondDisclosure(people: [me, david, lisa, orphan])
        disclosure.togglePondConnections(id: david.id)
        disclosure.revealHiddenPeople(in: pond.id.uuidString)
        XCTAssertTrue(disclosure.snapshot.visibleIDs.contains(orphan.id))
        XCTAssertTrue(disclosure.snapshot.visibleIDs.contains(lisa.id))
        disclosure.collapseAllPondConnections()
        XCTAssertEqual(disclosure.snapshot.visibleIDs, Set([me.id, david.id]))
        XCTAssertTrue(disclosure.snapshot.hiddenByPond[pond.id.uuidString]?.contains(orphan.id) == true)
        XCTAssertTrue(disclosure.snapshot.hiddenByPond[pond.id.uuidString]?.contains(lisa.id) == true)
        XCTAssertTrue(disclosure.snapshot.expandedIDs.isEmpty)
    }

    func testReloadRemovesDeletedEdgesAndSearchRouteStopsAtFirstInvalidLink() {
        let me = Person(name: "Me", isMe: true)
        let david = Person(name: "David")
        let lisa = Person(name: "Lisa")
        let oldLink = link(david, lisa)
        link(me, david)
        var disclosure = PondDisclosure(people: [me, david, lisa])
        disclosure.revealRoute([me.id, david.id, lisa.id], selecting: lisa.id)
        XCTAssertEqual(disclosure.snapshot.trail, [me.id, david.id, lisa.id])

        david.outgoingRelationships.removeAll { $0.id == oldLink.id }
        lisa.incomingRelationships.removeAll { $0.id == oldLink.id }
        disclosure.reload(people: [me, david, lisa])
        XCTAssertEqual(disclosure.snapshot.trail, [me.id, david.id])
        XCTAssertFalse(disclosure.snapshot.revealedEdges.contains { $0.to == lisa.id })
    }

    func testSelectingDisclosureContactDoesNotRecenterThePond() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        _ = try manager.createPerson(name: "Me", isMe: true)
        let contact = try manager.createPerson(name: "Contact")
        try manager.createRelationship(from: try XCTUnwrap(manager.fetchMePerson()), to: contact, type: .friend, skipAutoAssign: true)

        let viewModel = GraphViewModel(dataManager: manager)
        let spy = DisclosureSceneSpy()
        viewModel.sceneDelegate = spy
        viewModel.loadGraph()
        viewModel.selectPondContact(id: contact.id)
        viewModel.selectContact(contact.id)

        XCTAssertEqual(viewModel.selectedPondContactID, contact.id)
        XCTAssertEqual(spy.centeredIDs, [])
    }

    func testPondAndSearchScopeChangesClearFocusButKeepOpenedBranches() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let root = try manager.createPerson(name: "Root")
        let child = try manager.createPerson(name: "Child")
        try manager.createRelationship(from: me, to: root, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: root, to: child, type: .friend, skipAutoAssign: true)

        let viewModel = GraphViewModel(dataManager: manager)
        let spy = DisclosureSceneSpy()
        viewModel.sceneDelegate = spy
        viewModel.loadGraph()
        viewModel.activatePondContact(id: root.id)
        XCTAssertEqual(viewModel.disclosureSnapshot.focusRootID, root.id)
        XCTAssertTrue(viewModel.disclosureSnapshot.expandedIDs.contains(root.id))

        viewModel.selectedPondFilter = "unassigned"
        XCTAssertNil(viewModel.disclosureSnapshot.focusRootID)
        XCTAssertNil(viewModel.disclosureSnapshot.selectedID)
        XCTAssertTrue(viewModel.disclosureSnapshot.expandedIDs.contains(root.id))
        XCTAssertNil(spy.focusRootAtPondFilterCallback, "Disclosure focus must clear before the pond filter callback")

        viewModel.activatePondContact(id: root.id)
        viewModel.selectedPondFilter = nil
        XCTAssertNil(viewModel.disclosureSnapshot.focusRootID,
                     "Clearing a pond filter must also end branch focus")
        XCTAssertNil(viewModel.disclosureSnapshot.selectedID)
        XCTAssertTrue(viewModel.disclosureSnapshot.expandedIDs.contains(root.id))
        XCTAssertNil(spy.focusRootAtPondFilterCallback,
                     "Disclosure focus must clear before the filter callback when returning to All ponds")

        viewModel.activatePondContact(id: root.id)
        viewModel.searchMatchedIDs = [child.id]
        XCTAssertNil(viewModel.disclosureSnapshot.focusRootID)
        XCTAssertNil(viewModel.disclosureSnapshot.selectedID)
        XCTAssertTrue(viewModel.disclosureSnapshot.expandedIDs.contains(root.id))
        XCTAssertNil(spy.focusRootAtSearchCallback, "Disclosure focus must clear before the search callback")
    }

    func testLeavingPondViewClearsCompatibilityRouteAndFocusButKeepsBranches() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let root = try manager.createPerson(name: "Root")
        let child = try manager.createPerson(name: "Child")
        try manager.createRelationship(from: me, to: root, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: root, to: child, type: .friend, skipAutoAssign: true)

        let viewModel = GraphViewModel(dataManager: manager)
        viewModel.loadGraph()
        viewModel.openRipple(child.id, initialTrail: [me.id, root.id, child.id])
        viewModel.activatePondContact(id: root.id)
        XCTAssertTrue(viewModel.disclosureSnapshot.expandedIDs.contains(root.id))

        viewModel.leavePondView()

        XCTAssertNil(viewModel.rippleFocus)
        XCTAssertNil(viewModel.disclosureSnapshot.focusRootID)
        XCTAssertNil(viewModel.disclosureSnapshot.selectedID)
        XCTAssertTrue(viewModel.disclosureSnapshot.trail.isEmpty)
        XCTAssertTrue(viewModel.disclosureSnapshot.expandedIDs.contains(root.id))
        XCTAssertTrue(viewModel.disclosureSnapshot.visibleIDs.contains(child.id))
    }

    func testGraphViewModelPublishesDisclosureSnapshotAfterCompatibilityRoute() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let david = try manager.createPerson(name: "David")
        let lisa = try manager.createPerson(name: "Lisa")
        try manager.createRelationship(from: me, to: david, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: david, to: lisa, type: .friend, skipAutoAssign: true)

        let viewModel = GraphViewModel(dataManager: manager)
        let spy = DisclosureSceneSpy()
        viewModel.sceneDelegate = spy
        viewModel.loadGraph()
        viewModel.openRipple(lisa.id, initialTrail: [me.id, david.id, lisa.id], summary: "Me → David → Lisa")

        XCTAssertEqual(viewModel.disclosureSnapshot.trail, [me.id, david.id, lisa.id])
        XCTAssertTrue(viewModel.disclosureSnapshot.visibleIDs.contains(lisa.id))
        XCTAssertEqual(spy.lastSnapshot?.trail, viewModel.disclosureSnapshot.trail)
        XCTAssertEqual(spy.lastSnapshot?.visibleIDs, viewModel.disclosureSnapshot.visibleIDs)
    }

    func testPondFocusPreservesOpenBranchesAndTheRouteBeingExplored() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let direct = try manager.createPerson(name: "Direct")
        let target = try manager.createPerson(name: "Target")
        let further = try manager.createPerson(name: "Further")
        try manager.createRelationship(from: me, to: direct, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: direct, to: target, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: target, to: further, type: .friend, skipAutoAssign: true)

        let viewModel = GraphViewModel(dataManager: manager)
        let spy = DisclosureSceneSpy()
        viewModel.sceneDelegate = spy
        viewModel.loadGraph()
        viewModel.openRipple(target.id, initialTrail: [me.id, direct.id, target.id], summary: "saved route")
        viewModel.togglePondConnections(target.id)
        let disclosureBeforeFocus = viewModel.disclosureSnapshot
        let rippleBeforeFocus = viewModel.rippleFocus

        viewModel.selectedPondFilter = "friends-pond"

        XCTAssertEqual(viewModel.disclosureSnapshot, disclosureBeforeFocus)
        XCTAssertEqual(viewModel.rippleFocus, rippleBeforeFocus)
        XCTAssertEqual(spy.lastPondFilter, "friends-pond")
        XCTAssertTrue(viewModel.disclosureSnapshot.visibleIDs.contains(further.id))
    }

    func testResetCameraPreservesDisclosureRouteBranchesAndPondFilter() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let direct = try manager.createPerson(name: "Direct")
        let target = try manager.createPerson(name: "Target")
        let further = try manager.createPerson(name: "Further")
        try manager.createRelationship(from: me, to: direct, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: direct, to: target, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: target, to: further, type: .friend, skipAutoAssign: true)
        let viewModel = GraphViewModel(dataManager: manager)
        let spy = DisclosureSceneSpy()
        viewModel.sceneDelegate = spy
        viewModel.loadGraph()
        viewModel.openRipple(target.id, initialTrail: [me.id, direct.id, target.id])
        viewModel.togglePondConnections(target.id)
        viewModel.selectedPondFilter = "friends-pond"
        XCTAssertTrue(viewModel.selectDisclosureTrailAncestor(direct.id))
        XCTAssertEqual(viewModel.rippleFocus?.contactID, direct.id)
        XCTAssertTrue(viewModel.disclosureSnapshot.expandedIDs.contains(target.id))
        XCTAssertTrue(viewModel.disclosureSnapshot.visibleIDs.contains(further.id))
        let disclosure = viewModel.disclosureSnapshot
        let focus = viewModel.rippleFocus

        viewModel.resetCamera()

        XCTAssertEqual(spy.fitToGraphCount, 1)
        XCTAssertEqual(viewModel.disclosureSnapshot, disclosure)
        XCTAssertEqual(viewModel.rippleFocus, focus)
        XCTAssertEqual(viewModel.selectedPondFilter, "friends-pond")
    }

    func testMyPondsHomeClearsTransientScopeButKeepsBranchesAndSavedLayout() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let root = try manager.createPerson(name: "Root")
        let child = try manager.createPerson(name: "Child")
        let grandchild = try manager.createPerson(name: "Grandchild")
        let pond = try manager.createCircle(name: "Family")
        try manager.addToCircle(root, circle: pond)
        try manager.createRelationship(from: me, to: root, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: root, to: child, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: child, to: grandchild, type: .friend, skipAutoAssign: true)

        let suiteName = "GoldfishMyPondsHomeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PondLayoutStore(defaults: defaults)
        let viewModel = GraphViewModel(dataManager: manager, pondLayoutStore: store)
        let spy = DisclosureSceneSpy()
        viewModel.sceneDelegate = spy
        viewModel.loadGraph()
        let offset = CGPoint(x: 36, y: -24)
        viewModel.savePondLayoutOffset(offset, for: pond.id.uuidString, meID: me.id)

        viewModel.selectedPondFilter = pond.id.uuidString
        viewModel.searchMatchedIDs = [root.id, child.id]
        viewModel.selectedContactID = root.id
        viewModel.activatePondContact(id: root.id)
        viewModel.activatePondContact(id: child.id)
        viewModel.showConnectionPath()
        let expanded = viewModel.disclosureSnapshot.expandedIDs
        XCTAssertEqual(viewModel.disclosureSnapshot.focusRootID, root.id)
        XCTAssertFalse(viewModel.disclosureSnapshot.pathHighlightIDs.isEmpty)
        XCTAssertTrue(expanded.contains(root.id))
        XCTAssertTrue(expanded.contains(child.id))

        viewModel.showMyPonds()

        XCTAssertNil(viewModel.disclosureSnapshot.focusRootID)
        XCTAssertNil(viewModel.disclosureSnapshot.selectedID)
        XCTAssertTrue(viewModel.disclosureSnapshot.pathHighlightIDs.isEmpty)
        XCTAssertTrue(viewModel.disclosureSnapshot.trail.isEmpty)
        XCTAssertEqual(viewModel.disclosureSnapshot.expandedIDs, expanded)
        XCTAssertTrue(viewModel.disclosureSnapshot.visibleIDs.contains(grandchild.id))
        XCTAssertNil(viewModel.selectedContactID)
        XCTAssertNil(viewModel.searchMatchedIDs)
        XCTAssertNil(viewModel.selectedPondFilter)
        XCTAssertEqual(viewModel.pondLayoutOffsets(forMeID: me.id)[pond.id.uuidString], offset)
        XCTAssertEqual(spy.fitToGraphCount, 1)
    }

    func testOpeningMeProfileReturnsHomeWhileOrdinaryProfileOpensRipple() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let root = try manager.createPerson(name: "Root")
        let child = try manager.createPerson(name: "Child")
        let grandchild = try manager.createPerson(name: "Grandchild")
        let family = try manager.createCircle(name: "Family")
        try manager.addToCircle(root, circle: family)
        try manager.createRelationship(from: me, to: root, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: root, to: child, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: child, to: grandchild, type: .friend, skipAutoAssign: true)

        let viewModel = GraphViewModel(dataManager: manager)
        let spy = DisclosureSceneSpy()
        viewModel.sceneDelegate = spy
        viewModel.loadGraph()
        viewModel.selectedPondFilter = family.id.uuidString
        viewModel.searchMatchedIDs = [child.id]
        viewModel.activatePondContact(id: root.id)
        viewModel.activatePondContact(id: child.id)
        viewModel.showConnectionPath()
        viewModel.selectedContactID = root.id

        XCTAssertNotNil(viewModel.disclosureSnapshot.focusRootID)
        XCTAssertFalse(viewModel.disclosureSnapshot.pathHighlightIDs.isEmpty)
        XCTAssertTrue(viewModel.disclosureSnapshot.expandedIDs.contains(root.id))
        XCTAssertTrue(viewModel.disclosureSnapshot.expandedIDs.contains(child.id))

        viewModel.openRipple(me.id)

        XCTAssertNil(viewModel.rippleFocus, "Opening Me's profile should not create a route rooted on the hidden node")
        XCTAssertNil(viewModel.disclosureSnapshot.focusRootID)
        XCTAssertNil(viewModel.disclosureSnapshot.selectedID)
        XCTAssertTrue(viewModel.disclosureSnapshot.pathHighlightIDs.isEmpty)
        XCTAssertTrue(viewModel.disclosureSnapshot.trail.isEmpty)
        XCTAssertTrue(viewModel.disclosureSnapshot.expandedIDs.contains(root.id))
        XCTAssertTrue(viewModel.disclosureSnapshot.expandedIDs.contains(child.id))
        XCTAssertNil(viewModel.selectedContactID)
        XCTAssertNil(viewModel.searchMatchedIDs)
        XCTAssertNil(viewModel.selectedPondFilter)
        XCTAssertEqual(spy.fitToGraphCount, 1)

        viewModel.openRipple(child.id)
        XCTAssertEqual(viewModel.rippleFocus?.contactID, child.id,
                       "Opening an ordinary contact profile should keep the ripple route behavior")
        XCTAssertTrue(viewModel.disclosureSnapshot.trail.contains(child.id))
        XCTAssertEqual(spy.fitToGraphCount, 1,
                       "An ordinary contact route should not invoke the My ponds framing action")
    }

    func testRevealFeedbackReportsOffscreenIDsAndOnlyLocatesOnRequest() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let direct = try manager.createPerson(name: "Direct")
        let first = try manager.createPerson(name: "First")
        let second = try manager.createPerson(name: "Second")
        try manager.createRelationship(from: me, to: direct, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: direct, to: first, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: direct, to: second, type: .friend, skipAutoAssign: true)
        let viewModel = GraphViewModel(dataManager: manager)
        let spy = DisclosureSceneSpy()
        spy.offscreenIDs = [second.id]
        viewModel.sceneDelegate = spy
        viewModel.loadGraph()

        viewModel.togglePondConnections(direct.id)

        let feedback = try XCTUnwrap(viewModel.latestPondReveal)
        XCTAssertEqual(feedback.revealedIDs, [first.id, second.id])
        XCTAssertEqual(feedback.offscreenIDs, [second.id])
        XCTAssertEqual(feedback.count, 2)
        XCTAssertEqual(spy.locatedIDs, [])

        viewModel.togglePondConnections(direct.id)
        XCTAssertNil(viewModel.latestPondReveal,
                     "Hiding the just-revealed branch must remove stale feedback")
        XCTAssertFalse(viewModel.disclosureSnapshot.visibleIDs.contains(first.id))

        viewModel.togglePondConnections(direct.id)
        XCTAssertNotNil(viewModel.latestPondReveal)
        viewModel.locateLatestPondReveal()
        XCTAssertEqual(spy.locatedIDs, [first.id, second.id])
        XCTAssertNil(viewModel.latestPondReveal)
        XCTAssertTrue(viewModel.disclosureSnapshot.visibleIDs.contains(first.id))
    }

    func testPendingAmbiguousChoiceLeavesRouteUntouchedUntilResolution() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let direct = try manager.createPerson(name: "Direct")
        let target = try manager.createPerson(name: "Target")
        try manager.createRelationship(from: me, to: direct, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: direct, to: target, type: .friend, skipAutoAssign: true)
        let viewModel = GraphViewModel(dataManager: manager)
        let spy = DisclosureSceneSpy()
        viewModel.sceneDelegate = spy
        viewModel.loadGraph()
        viewModel.togglePondConnections(direct.id)
        let route = viewModel.disclosureTrail

        viewModel.presentContactChoices([target.id, direct.id, target.id])

        XCTAssertEqual(viewModel.pendingContactChoiceIDs, [target.id, direct.id])
        XCTAssertEqual(Set(viewModel.pendingContactChoiceIDs), [direct.id, target.id])
        XCTAssertEqual(viewModel.disclosureTrail, route)
        XCTAssertTrue(spy.activatedChoiceIDs.isEmpty)
        viewModel.choosePendingContact(target.id)
        XCTAssertEqual(spy.activatedChoiceIDs, [target.id])
        XCTAssertTrue(viewModel.pendingContactChoiceIDs.isEmpty)
    }

    func testGraphViewModelDisclosureStaysWithinPersonalAndDemoScopesAfterReveals() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let personal = try manager.createPerson(name: "Personal")
        let personalChild = try manager.createPerson(name: "Personal child")
        let personalOrphan = try manager.createPerson(name: "Personal orphan")
        let sample = try manager.createPerson(name: "Sample", isDemo: true)
        let sampleChild = try manager.createPerson(name: "Sample child", isDemo: true)
        try manager.createRelationship(from: me, to: personal, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: personal, to: personalChild, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: me, to: sample, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: sample, to: sampleChild, type: .friend, skipAutoAssign: true)

        let viewModel = GraphViewModel(dataManager: manager)
        viewModel.loadGraph()
        viewModel.togglePondConnections(personal.id)
        viewModel.revealHiddenPeople(in: "unassigned")
        XCTAssertTrue(viewModel.disclosureSnapshot.visibleIDs.contains(personalChild.id))
        XCTAssertTrue(viewModel.disclosureSnapshot.visibleIDs.contains(personalOrphan.id))

        viewModel.isDemoMode = true
        viewModel.loadGraph()

        XCTAssertEqual(viewModel.disclosureSnapshot.visibleIDs, Set([me.id, sample.id]))
        XCTAssertFalse(viewModel.disclosureSnapshot.visibleIDs.contains(personal.id))
        XCTAssertFalse(viewModel.disclosureSnapshot.visibleIDs.contains(personalChild.id))
        XCTAssertFalse(viewModel.disclosureSnapshot.visibleIDs.contains(personalOrphan.id))
        viewModel.togglePondConnections(sample.id)
        XCTAssertTrue(viewModel.disclosureSnapshot.visibleIDs.contains(sampleChild.id))
        XCTAssertFalse(viewModel.disclosureSnapshot.visibleIDs.contains(personalChild.id))
    }

    func testReloadRemovesSelectedContactAndDetachedExpansion() {
        let me = Person(name: "Me", isMe: true)
        let david = Person(name: "David")
        let lisa = Person(name: "Lisa")
        link(me, david)
        link(david, lisa)
        var disclosure = PondDisclosure(people: [me, david, lisa])

        disclosure.togglePondConnections(id: david.id)
        disclosure.selectPondContact(id: lisa.id)
        XCTAssertEqual(disclosure.snapshot.selectedID, lisa.id)
        XCTAssertTrue(disclosure.snapshot.visibleIDs.contains(lisa.id))

        disclosure.reload(people: [me, lisa])

        XCTAssertNil(disclosure.snapshot.selectedID)
        XCTAssertFalse(disclosure.snapshot.visibleIDs.contains(lisa.id))
        XCTAssertTrue(disclosure.snapshot.expandedIDs.isEmpty)
        XCTAssertFalse(disclosure.snapshot.trail.contains(david.id))
    }

    func testSharedNeighborAfterFourNewContactsIsRecordedAndSurvivesOtherBranchCollapse() {
        let me = Person(name: "Me", isMe: true)
        let david = Person(name: "David")
        let erin = Person(name: "Erin")
        let branch = Person(name: "Branch")
        let shared = Person(name: "Shared")
        let hidden = (1...5).map { Person(name: "Hidden \($0)") }
        link(me, david)
        link(me, erin)
        link(david, branch)
        link(erin, shared)
        link(branch, shared)
        for person in hidden { link(branch, person) }
        var disclosure = PondDisclosure(people: [me, david, erin, branch, shared] + hidden)

        disclosure.togglePondConnections(id: david.id)
        disclosure.togglePondConnections(id: erin.id)
        XCTAssertTrue(disclosure.snapshot.visibleIDs.contains(shared.id))
        disclosure.togglePondConnections(id: branch.id)

        XCTAssertTrue(disclosure.snapshot.revealedEdges.contains {
            $0.from == branch.id && $0.to == shared.id
        })
        XCTAssertEqual(disclosure.snapshot.visibleIDs.intersection(Set(hidden.map(\.id))).count, 4)
        disclosure.togglePondConnections(id: erin.id)
        XCTAssertTrue(disclosure.snapshot.visibleIDs.contains(shared.id))
        XCTAssertTrue(disclosure.snapshot.revealedEdges.contains {
            $0.from == branch.id && $0.to == shared.id
        })
    }

    func testLongSearchRouteUsesActualPredecessorAndCollapseAllClearsCompatibilityFocus() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let short = try manager.createPerson(name: "Short")
        let long = try manager.createPerson(name: "Long")
        let target = try manager.createPerson(name: "Target")
        try manager.createRelationship(from: me, to: short, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: short, to: target, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: me, to: long, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: long, to: target, type: .sibling, skipAutoAssign: true)

        let viewModel = GraphViewModel(dataManager: manager)
        viewModel.loadGraph()
        viewModel.openRipple(target.id, initialTrail: [me.id, long.id, target.id], summary: "long route")

        XCTAssertEqual(viewModel.disclosureTrail, [me.id, long.id, target.id])
        XCTAssertEqual(viewModel.disclosureRole(for: target.id)?.relationshipTypes, [.sibling])
        XCTAssertNotNil(viewModel.rippleFocus)

        viewModel.collapseAllPondConnections()

        XCTAssertNil(viewModel.rippleFocus)
        XCTAssertTrue(viewModel.disclosureSnapshot.trail.isEmpty)
        XCTAssertEqual(viewModel.disclosureSnapshot.visibleIDs, Set([me.id, short.id, long.id]))
    }
}

@MainActor
private final class DisclosureSceneSpy: GraphSceneDelegate {
    var centeredIDs: [UUID] = []
    var lastSnapshot: PondDisclosureSnapshot?
    var lastPondFilter: String?
    var focusRootAtPondFilterCallback: UUID?
    var focusRootAtSearchCallback: UUID?
    var centerOnMeCount = 0
    var fitToGraphCount = 0
    var offscreenIDs: Set<UUID> = []
    var locatedIDs: Set<UUID> = []
    var activatedChoiceIDs: [UUID] = []

    func didUpdateGroups(_ groups: [GoldfishCircle]) {}
    func didUpdateGraphLevels(_ levels: [GraphLevel]) {}
    func didSelectContact(_ id: UUID?) {}
    func didUpdateZoom(_ zoom: CGFloat) {}
    func didUpdateCameraPosition(_ position: CGPoint) {}
    func centerOnContact(_ id: UUID) { centeredIDs.append(id) }
    func centerOnMe() { centerOnMeCount += 1 }
    func centerOnPond(name: String) {}
    func didUpdatePondFilter(_ name: String?) {
        lastPondFilter = name
        focusRootAtPondFilterCallback = lastSnapshot?.focusRootID
    }
    func requestConnection(from: UUID, to: UUID) {}
    func didUpdateSearchMatches(_ ids: Set<UUID>?) {
        focusRootAtSearchCallback = lastSnapshot?.focusRootID
    }
    func animateNewConnection(from: UUID, to: UUID) {}
    func didLongPressContact(_ id: UUID) {}
    func fitToGraph() { fitToGraphCount += 1 }
    func didUpdateDisclosure(_ snapshot: PondDisclosureSnapshot) { lastSnapshot = snapshot }
    func offscreenContactIDs(_ ids: Set<UUID>) -> Set<UUID> { ids.intersection(offscreenIDs) }
    func locateContacts(_ ids: Set<UUID>) { locatedIDs = ids }
    func activateContactChoice(_ id: UUID) { activatedChoiceIDs.append(id) }
}
