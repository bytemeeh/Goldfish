import XCTest
import CoreGraphics
@testable import Goldfish

@MainActor
final class RippleGraphTests: XCTestCase {
    private func people(_ names: String...) -> [Person] {
        names.enumerated().map { Person(id: UUID(), name: $0.element, isMe: $0.offset == 0) }
    }

    @discardableResult
    private func link(_ from: Person, _ to: Person, _ type: RelationshipType, primary: Bool = false) -> Relationship {
        let relationship = Relationship(from: from, to: to, type: type, isPrimary: primary)
        from.outgoingRelationships.append(relationship)
        to.incomingRelationships.append(relationship)
        return relationship
    }

    func testDirectionalRolesAreReversedFromTheOtherSide() {
        let (me, child, spouse) = tuple(people("Me", "Child", "Spouse"))
        link(me, child, .mother)
        link(me, spouse, .spouse)
        let graph = RippleGraph(people: [me, child, spouse])

        XCTAssertEqual(graph.role(of: child.id, relativeTo: me.id)?.roleLabel, "Child")
        XCTAssertEqual(graph.role(of: me.id, relativeTo: child.id)?.roleLabel, "Mother")
        XCTAssertEqual(graph.role(of: spouse.id, relativeTo: me.id)?.relationshipTypes, [.spouse])
    }

    func testScopeDeduplicationAndStableNeighborOrder() {
        let (me, zed, amy) = tuple(people("Me", "Zed", "Amy"))
        link(me, zed, .friend)
        link(me, amy, .friend)
        link(me, amy, .coworker, primary: true)
        let graph = RippleGraph(people: [amy, me, zed, amy])

        XCTAssertEqual(graph.neighbors(of: me.id).map(\.person.name), ["Amy", "Zed"])
        XCTAssertEqual(graph.role(of: amy.id, relativeTo: me.id)?.roleLabel, "Coworker")
        XCTAssertEqual(Set(graph.role(of: amy.id, relativeTo: me.id)!.relationshipTypes), [.friend, .coworker])
    }

    func testShortestPathAndExplorationValidation() {
        let (me, a, b, c, isolated) = tuple(people("Me", "A", "B", "C", "Isolated"))
        link(me, a, .friend)
        link(a, b, .friend)
        link(b, c, .friend)
        let graph = RippleGraph(people: [me, a, b, c, isolated])

        XCTAssertEqual(graph.shortestPath(from: me.id, to: c.id), [me.id, a.id, b.id, c.id])
        XCTAssertEqual(graph.initialTrail(to: isolated.id), [])
        XCTAssertEqual(graph.validatedTrail([me.id, a.id, b.id, a.id, c.id]), [me.id, a.id, b.id])
        XCTAssertEqual(graph.validatedTrail([me.id, a.id, UUID()]), [me.id, a.id])
    }

    func testDiamondAndHighDegreeGraphsRemainFiniteAndDeduplicated() {
        let root = Person(name: "Me", isMe: true)
        let left = Person(name: "Left")
        let right = Person(name: "Right")
        let shared = Person(name: "Shared")
        link(root, left, .friend); link(root, right, .friend)
        link(left, shared, .friend); link(right, shared, .friend)
        var all = [root, left, right, shared]
        for i in 0..<60 {
            let person = Person(name: "Leaf \(i)")
            link(root, person, .friend)
            all.append(person)
        }
        let graph = RippleGraph(people: all)
        XCTAssertEqual(graph.neighbors(of: root.id).count, 62)
        XCTAssertEqual(graph.shortestPath(from: root.id, to: shared.id), [root.id, left.id, shared.id])
        XCTAssertEqual(graph.neighbors(of: left.id).filter { $0.id == shared.id }.count, 1)
    }

    func testDeepChainDoesNotUseRecursiveTraversalAndCyclesDoNotBreakPaths() {
        let root = Person(name: "Max", isMe: true)
        var all = [root]
        var previous = root
        for index in 0..<55 {
            let next = Person(name: index == 54 ? "Sam" : "Contact \(index)")
            link(previous, next, .friend)
            all.append(next)
            previous = next
        }
        // A symmetric relationship can close a cycle without changing the shortest route.
        link(all[1], root, .friend)
        let graph = RippleGraph(people: all)
        XCTAssertEqual(graph.shortestPath(from: root.id, to: previous.id)?.count, 56)
        XCTAssertEqual(graph.validatedTrail([root.id, all[1].id, root.id]), [root.id, all[1].id])
    }

    func testDifferentScopesProduceIndependentBoundedGraphs() {
        let (me, inside, outside) = tuple(people("Me", "Inside", "Outside"))
        link(me, inside, .friend)
        link(inside, outside, .friend)
        let graph = RippleGraph(people: [me, inside])
        XCTAssertEqual(graph.peopleByID.count, 2)
        XCTAssertEqual(graph.neighbors(of: inside.id).map(\.id), [me.id])
        XCTAssertNil(graph.shortestPath(from: me.id, to: outside.id))
        XCTAssertEqual(graph.initialTrail(to: outside.id), [])
    }

    func testStoredGuardianResolvesPetRoleForTheOtherEndpoint() {
        let (owner, pet, _) = tuple(people("Owner", "Pet", "Unused"))
        pet.petKindRaw = ContactKind.cat.rawValue
        link(owner, pet, .guardian)
        let graph = RippleGraph(people: [owner, pet])

        XCTAssertEqual(graph.role(of: pet.id, relativeTo: owner.id)?.roleLabel, "Cat")
        XCTAssertEqual(graph.role(of: owner.id, relativeTo: pet.id)?.roleLabel, "Guardian")
    }

    func testRelationshipTypesUseReciprocalRolesAcrossDirections() {
        let (parent, child, _) = tuple(people("Parent", "Child", "Unused"))
        link(parent, child, .mother, primary: true)
        link(child, parent, .friend)
        let graph = RippleGraph(people: [parent, child])

        XCTAssertEqual(graph.role(of: child.id, relativeTo: parent.id)?.roleLabel, "Child")
        XCTAssertEqual(graph.role(of: child.id, relativeTo: parent.id)?.relationshipTypes, [.friend, .child])
        XCTAssertEqual(graph.role(of: parent.id, relativeTo: child.id)?.relationshipTypes, [.mother, .friend])
    }

    func testValidatedTrailPreservesExplorationRouteAndTruncatesDeletedEdge() {
        let (me, a, b, c, _) = tuple(people("Me", "A", "B", "C", "Unused"))
        link(me, a, .friend)
        link(me, b, .friend)
        let bToC = link(b, c, .friend)
        link(a, c, .friend)
        let graph = RippleGraph(people: [me, a, b, c])

        XCTAssertEqual(graph.shortestPath(from: me.id, to: c.id), [me.id, a.id, c.id])
        XCTAssertEqual(graph.validatedTrail([me.id, b.id, c.id]), [me.id, b.id, c.id])

        b.outgoingRelationships.removeAll { $0.id == bToC.id }
        c.incomingRelationships.removeAll { $0.id == bToC.id }
        let afterDeletion = RippleGraph(people: [me, a, b, c])
        XCTAssertEqual(afterDeletion.validatedTrail([me.id, b.id, c.id]), [me.id, b.id])
    }

    func testPondRippleFocusEntryAndReturnPreserveCameraAndFilter() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let contact = try manager.createPerson(name: "Friend")
        let pond = try manager.createCircle(name: "Friends")
        try manager.addToCircle(contact, circle: pond)
        try manager.createRelationship(from: me, to: contact, type: .friend, skipAutoAssign: true)

        let viewModel = GraphViewModel(dataManager: manager)
        viewModel.cameraPosition = CGPoint(x: 48, y: -19)
        viewModel.zoomLevel = 1.7
        viewModel.selectedPondFilter = pond.id.uuidString
        viewModel.loadGraph()

        let camera = viewModel.cameraPosition
        let zoom = viewModel.zoomLevel
        let filter = viewModel.selectedPondFilter
        viewModel.openRipple(contact.id)

        XCTAssertEqual(viewModel.rippleFocus?.contactID, contact.id)
        viewModel.closeRipple()
        XCTAssertEqual(viewModel.cameraPosition, camera)
        XCTAssertEqual(viewModel.zoomLevel, zoom)
        XCTAssertEqual(viewModel.selectedPondFilter, filter)
    }

    func testPondRippleFocusRetainsChainSummaryAndTrail() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let first = try manager.createPerson(name: "First")
        let target = try manager.createPerson(name: "Target")
        try manager.createRelationship(from: me, to: first, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: first, to: target, type: .friend, skipAutoAssign: true)

        let viewModel = GraphViewModel(dataManager: manager)
        viewModel.loadGraph()
        let trail = [me.id, first.id, target.id]
        viewModel.openRipple(target.id, initialTrail: trail, searchRouteSummary: "Me → First → Target")

        XCTAssertEqual(viewModel.rippleFocus?.initialTrail, trail)
        XCTAssertEqual(viewModel.rippleFocus?.searchRouteSummary, "Me → First → Target")
    }

    func testPondRippleFocusClosesWhenScopeChanges() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let personal = try manager.createPerson(name: "Personal")
        let sample = try manager.createPerson(name: "Sample", isDemo: true)
        try manager.createRelationship(from: me, to: personal, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: me, to: sample, type: .friend, skipAutoAssign: true)

        let viewModel = GraphViewModel(dataManager: manager)
        viewModel.loadGraph()
        viewModel.openRipple(personal.id)
        XCTAssertNotNil(viewModel.rippleFocus)

        viewModel.isDemoMode = true
        XCTAssertNil(viewModel.rippleFocus)
        viewModel.loadGraph()
        viewModel.openRipple(sample.id)
        XCTAssertNotNil(viewModel.rippleFocus)
        viewModel.isDemoMode = false
        XCTAssertNil(viewModel.rippleFocus)
    }

    func testPondRippleFocusClosesWhenContactIsDeletedOnReload() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let contact = try manager.createPerson(name: "Soon Gone")
        try manager.createRelationship(from: me, to: contact, type: .friend, skipAutoAssign: true)

        let viewModel = GraphViewModel(dataManager: manager)
        viewModel.loadGraph()
        viewModel.openRipple(contact.id)
        XCTAssertNotNil(viewModel.rippleFocus)

        try manager.deletePerson(contact)
        viewModel.refreshGraph()
        XCTAssertNil(viewModel.rippleFocus)
    }

    func testPondRippleFocusRejectsInvalidAndOutOfScopeIDs() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let personal = try manager.createPerson(name: "Personal")
        let sample = try manager.createPerson(name: "Sample", isDemo: true)
        try manager.createRelationship(from: me, to: personal, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: me, to: sample, type: .friend, skipAutoAssign: true)

        let viewModel = GraphViewModel(dataManager: manager)
        viewModel.openRipple(UUID()) // Also exercises the lazy graph load path.
        XCTAssertNil(viewModel.rippleFocus)
        viewModel.openRipple(sample.id)
        XCTAssertNil(viewModel.rippleFocus)
        viewModel.openRipple(personal.id)
        XCTAssertNotNil(viewModel.rippleFocus)
    }

    func testPondRippleFocusGetsFreshIdentityForANewSearchRoute() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let contact = try manager.createPerson(name: "Contact")
        try manager.createRelationship(from: me, to: contact, type: .friend, skipAutoAssign: true)

        let viewModel = GraphViewModel(dataManager: manager)
        viewModel.loadGraph()
        viewModel.openRipple(contact.id, searchRouteSummary: "first route")
        let firstID = viewModel.rippleFocus?.id
        viewModel.openRipple(contact.id, searchRouteSummary: "second route")

        XCTAssertNotEqual(viewModel.rippleFocus?.id, firstID)
        XCTAssertEqual(viewModel.rippleFocus?.searchRouteSummary, "second route")
    }

    func testPondRipplePreservesExplicitNestedRouteAndReturnsToAncestor() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let first = try manager.createPerson(name: "First")
        let alternate = try manager.createPerson(name: "Route")
        let target = try manager.createPerson(name: "Target")
        try manager.createRelationship(from: me, to: first, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: first, to: target, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: me, to: alternate, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: alternate, to: target, type: .friend, skipAutoAssign: true)

        let viewModel = GraphViewModel(dataManager: manager)
        viewModel.loadGraph()
        viewModel.openRipple(target.id, initialTrail: [me.id, alternate.id, target.id], summary: "search route")

        XCTAssertEqual(viewModel.rippleTrail, [me.id, alternate.id, target.id])
        XCTAssertEqual(viewModel.rippleFocus?.initialTrail, [me.id, alternate.id, target.id])
        let graph = RippleGraph(people: (viewModel.graphLevels ?? []).flatMap(\.allContacts))
        XCTAssertEqual(graph.shortestPath(from: me.id, to: target.id), [me.id, first.id, target.id])

        viewModel.openRipple(alternate.id)
        XCTAssertEqual(viewModel.rippleTrail, [me.id, alternate.id])
        XCTAssertEqual(viewModel.rippleCurrentPerson?.id, alternate.id)
    }

    func testPondRipplePagesReachEveryNeighborWithoutDuplicates() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        _ = try manager.createPerson(name: "Me", isMe: true)
        let root = try manager.createPerson(name: "Root")
        var contacts: [Person] = []
        for index in 0..<38 {
            let contact = try manager.createPerson(name: String(format: "Contact %02d", index))
            try manager.createRelationship(from: root, to: contact, type: .friend, skipAutoAssign: true)
            contacts.append(contact)
        }

        let viewModel = GraphViewModel(dataManager: manager)
        viewModel.loadGraph()
        viewModel.openRipple(root.id)

        XCTAssertEqual(viewModel.ripplePageCount, 10)
        XCTAssertEqual(viewModel.visibleRippleNeighbors.count, 4)
        var seen = Set<UUID>()
        for page in 0..<viewModel.ripplePageCount {
            while viewModel.ripplePage < page { viewModel.nextRipplePage() }
            XCTAssertLessThanOrEqual(viewModel.visibleRippleNeighbors.count, 4)
            for neighbor in viewModel.visibleRippleNeighbors {
                XCTAssertTrue(seen.insert(neighbor.id).inserted)
            }
        }
        XCTAssertEqual(seen, Set(contacts.map(\.id)))
        viewModel.previousRipplePage()
        XCTAssertEqual(viewModel.ripplePage, 8)

        for contact in contacts.dropFirst(4) {
            try manager.deletePerson(contact)
        }
        viewModel.refreshGraph()
        XCTAssertEqual(viewModel.ripplePageCount, 1)
        XCTAssertEqual(viewModel.ripplePage, 0)
        XCTAssertEqual(Set(viewModel.visibleRippleNeighbors.map(\.id)), Set(contacts.prefix(4).map(\.id)))
    }

    func testPondRippleNormalizesInvalidTrailAndClosesDeletedFocus() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let first = try manager.createPerson(name: "First")
        let target = try manager.createPerson(name: "Target")
        try manager.createRelationship(from: me, to: first, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: first, to: target, type: .friend, skipAutoAssign: true)

        let viewModel = GraphViewModel(dataManager: manager)
        viewModel.loadGraph()
        viewModel.openRipple(target.id, initialTrail: [me.id, first.id, UUID(), target.id])
        XCTAssertEqual(viewModel.rippleTrail, [me.id, first.id, target.id])

        try manager.deletePerson(first)
        viewModel.refreshGraph()
        XCTAssertEqual(viewModel.rippleCurrentPerson?.id, target.id)
        XCTAssertFalse(viewModel.rippleTrail.contains(first.id))

        try manager.deletePerson(target)
        viewModel.refreshGraph()
        XCTAssertNil(viewModel.rippleFocus)
        XCTAssertTrue(viewModel.rippleNeighbors.isEmpty)
    }

    func testPondRipplePublishesVisibleSnapshotToScene() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        _ = try manager.createPerson(name: "Me", isMe: true)
        let root = try manager.createPerson(name: "Root")
        for index in 0..<6 {
            let contact = try manager.createPerson(name: "Contact \(index)")
            try manager.createRelationship(from: root, to: contact, type: .friend, skipAutoAssign: true)
        }

        let viewModel = GraphViewModel(dataManager: manager)
        let spy = RippleSceneSpy()
        viewModel.sceneDelegate = spy
        viewModel.loadGraph()
        viewModel.openRipple(root.id)
        XCTAssertEqual(spy.lastFocus?.contactID, root.id)
        XCTAssertEqual(spy.lastNeighbors.count, 4)

        viewModel.nextRipplePage()
        XCTAssertEqual(spy.lastNeighbors.count, 2)
        viewModel.closeRipple()
        XCTAssertNil(spy.lastFocus)
        XCTAssertTrue(spy.lastNeighbors.isEmpty)
    }

    private func tuple(_ values: [Person]) -> (Person, Person, Person) {
        (values[0], values[1], values[2])
    }

    private func tuple(_ values: [Person]) -> (Person, Person, Person, Person, Person) {
        (values[0], values[1], values[2], values[3], values[4])
    }
}

@MainActor
private final class RippleSceneSpy: GraphSceneDelegate {
    var lastFocus: PondRippleFocus?
    var lastNeighbors: [RippleNeighbor] = []

    func didUpdateGroups(_ groups: [GoldfishCircle]) {}
    func didUpdateGraphLevels(_ levels: [GraphLevel]) {}
    func didSelectContact(_ id: UUID?) {}
    func didUpdateZoom(_ zoom: CGFloat) {}
    func didUpdateCameraPosition(_ position: CGPoint) {}
    func centerOnContact(_ id: UUID) {}
    func centerOnMe() {}
    func centerOnPond(name: String) {}
    func didUpdatePondFilter(_ name: String?) {}
    func requestConnection(from: UUID, to: UUID) {}
    func didUpdateSearchMatches(_ ids: Set<UUID>?) {}
    func animateNewConnection(from: UUID, to: UUID) {}
    func didLongPressContact(_ id: UUID) {}
    func fitToGraph() {}
    func didUpdateRipple(focus: PondRippleFocus?, neighbors: [RippleNeighbor]) {
        lastFocus = focus
        lastNeighbors = neighbors
    }
}
