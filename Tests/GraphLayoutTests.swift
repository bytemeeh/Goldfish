import XCTest
import SpriteKit
import SwiftData
@testable import Goldfish

@MainActor
final class PondDragBoundaryTests: XCTestCase {
    private var basins: [String: CGPath] {
        ["family": CGPath(rect: CGRect(x: 0, y: 0, width: 100, height: 100), transform: nil),
         "friends": CGPath(rect: CGRect(x: 200, y: 0, width: 100, height: 100), transform: nil)]
    }

    func testMovementWithinCurrentPondDoesNotSuggestMembershipChange() {
        XCTAssertNil(PondDragBoundary.target(from: CGPoint(x: 30, y: 50), to: CGPoint(x: 70, y: 50),
                                            sourcePondID: "family", basins: basins, zoom: 1))
    }

    func testCrossingIntoDifferentPondSuggestsThatPond() {
        XCTAssertEqual(PondDragBoundary.target(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 250, y: 50),
                                              sourcePondID: "family", basins: basins, zoom: 1), "friends")
    }

    func testReturningToOriginalPondOrLeavingAllPondsClearsCandidate() {
        let start = CGPoint(x: 50, y: 50)
        XCTAssertEqual(PondDragBoundary.target(from: start, to: CGPoint(x: 250, y: 50),
                                              sourcePondID: "family", basins: basins, zoom: 1), "friends")
        XCTAssertNil(PondDragBoundary.target(from: start, to: CGPoint(x: 70, y: 50),
                                            sourcePondID: "family", basins: basins, zoom: 1))
        XCTAssertNil(PondDragBoundary.target(from: start, to: CGPoint(x: 150, y: 50),
                                            sourcePondID: "family", basins: basins, zoom: 1))
    }

    func testBorderJitterIsSuppressedAtDifferentZoomLevels() {
        for zoom: CGFloat in [0.25, 1, 2] {
            XCTAssertNil(PondDragBoundary.target(from: CGPoint(x: 50, y: 50),
                                                to: CGPoint(x: 200 + 4 / zoom, y: 50),
                                                sourcePondID: "family", basins: basins, zoom: zoom))
            XCTAssertEqual(PondDragBoundary.target(from: CGPoint(x: 50, y: 50),
                                                  to: CGPoint(x: 200 + 12 / zoom, y: 50),
                                                  sourcePondID: "family", basins: basins, zoom: zoom), "friends")
        }
    }

    func testStartingInsideDestinationDoesNotCountAsCrossingItsBorder() {
        XCTAssertNil(PondDragBoundary.target(from: CGPoint(x: 240, y: 50), to: CGPoint(x: 260, y: 50),
                                            sourcePondID: "family", basins: basins, zoom: 1))
    }

    func testStartingNearSourceBorderStillAllowsAClearCrossing() {
        XCTAssertEqual(PondDragBoundary.target(from: CGPoint(x: 99, y: 50), to: CGPoint(x: 250, y: 50),
                                              sourcePondID: "family", basins: basins, zoom: 1), "friends")
    }

    func testPondOutlineIsUsedInsteadOfItsBoundingRectangle() {
        let roundPond = CGPath(ellipseIn: CGRect(x: 200, y: 0, width: 100, height: 100), transform: nil)
        XCTAssertNil(PondDragBoundary.target(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 208, y: 8),
                                            sourcePondID: "family", basins: ["friends": roundPond], zoom: 1))
    }

    func testUnassignedBoundarySupportsMovesBothWaysWithoutNoOp() {
        let paths = ["family": basins["family"]!, "unassigned": basins["friends"]!]
        XCTAssertEqual(PondDragBoundary.target(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 250, y: 50),
                                              sourcePondID: "family", basins: paths, zoom: 1), "unassigned")
        XCTAssertEqual(PondDragBoundary.target(from: CGPoint(x: 250, y: 50), to: CGPoint(x: 50, y: 50),
                                              sourcePondID: "unassigned", basins: paths, zoom: 1), "family")
        XCTAssertNil(PondDragBoundary.target(from: CGPoint(x: 250, y: 50), to: CGPoint(x: 275, y: 50),
                                            sourcePondID: "unassigned", basins: paths, zoom: 1))
    }

    func testInvalidCoordinatesOrZoomCannotProposeAMove() {
        for zoom: CGFloat in [0, -1, .nan, .infinity] {
            XCTAssertNil(PondDragBoundary.target(from: CGPoint(x: 50, y: 50), to: CGPoint(x: 250, y: 50),
                                                sourcePondID: "family", basins: basins, zoom: zoom))
        }
        XCTAssertNil(PondDragBoundary.target(from: CGPoint(x: CGFloat.nan, y: 50), to: CGPoint(x: 250, y: 50),
                                            sourcePondID: "family", basins: basins, zoom: 1))
    }

    func testViewModelRejectsNoOpAndInvalidMembershipSuggestions() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let person = try manager.createPerson(name: "Alex")
        let unassigned = try manager.createPerson(name: "Jo")
        let demo = try manager.createPerson(name: "Sample person", isDemo: true)
        let family = try manager.createCircle(name: "Family")
        try manager.addToCircle(person, circle: family)
        let model = GraphViewModel(dataManager: manager)
        model.loadGraph()
        for (id, target) in [(person.id, family.id.uuidString), (unassigned.id, "unassigned"),
                             (person.id, "missing"), (me.id, family.id.uuidString),
                             (demo.id, family.id.uuidString), (UUID(), family.id.uuidString)] {
            model.requestPondMove(for: id, to: target)
            XCTAssertNil(model.pendingPondMovePerson)
            XCTAssertNil(model.pendingPondMoveTarget)
        }
    }

    func testValidSuggestionDoesNotChangeMembershipBeforeConfirmation() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        _ = try manager.createPerson(name: "Me", isMe: true)
        let person = try manager.createPerson(name: "Alex")
        let family = try manager.createCircle(name: "Family")
        let friends = try manager.createCircle(name: "Friends")
        try manager.addToCircle(person, circle: family)
        let model = GraphViewModel(dataManager: manager)
        model.loadGraph()
        model.requestPondMove(for: person.id, to: friends.id.uuidString)
        XCTAssertEqual(model.pendingPondMovePerson, person.id)
        XCTAssertEqual(model.pendingPondMoveTarget, friends.id.uuidString)
        XCTAssertEqual(person.primaryCircle?.id, family.id)
        model.pendingPondMovePerson = nil
        model.pendingPondMoveTarget = nil
        model.requestPondMove(for: person.id, to: "unassigned")
        XCTAssertEqual(model.pendingPondMoveTarget, "unassigned")
        XCTAssertEqual(person.primaryCircle?.id, family.id)
    }
}

@MainActor
final class GraphSceneLayoutTests: XCTestCase {
    private func assertPondHeadingsStayAttached(
        _ scene: GoldfishGraphScene, file: StaticString = #filePath, line: UInt = #line
    ) {
        for (pondID, heading) in scene.debugPondLabelBounds {
            guard let bank = scene.debugPondBasinBounds[pondID] else {
                XCTFail("A pond heading needs a visible bank", file: file, line: line)
                continue
            }
            XCTAssertLessThan(abs(heading.midX - bank.midX) * scene.debugCameraZoom, 2,
                              "A heading must stay attached to its own pond", file: file, line: line)
            XCTAssertTrue(bank.contains(heading), "The title band must contain its heading", file: file, line: line)
            for (personID, identity) in scene.debugVisibleIdentityBounds {
                XCTAssertFalse(heading.intersects(identity),
                               "\(scene.debugLabelTexts[pondID] ?? pondID) title overlaps \(scene.debugDisclosureIdentityLabels[personID] ?? personID.uuidString)",
                               file: file, line: line)
            }
        }
        assertPresentedPondsDoNotOverlap(scene, file: file, line: line)
    }

    private func assertPresentedPondsDoNotOverlap(
        _ scene: GoldfishGraphScene, file: StaticString = #filePath, line: UInt = #line
    ) {
        let banks = scene.debugPresentedPondPaths.sorted { $0.key < $1.key }
        for (index, bank) in banks.enumerated() {
            for other in banks.dropFirst(index + 1) {
                let sharedBounds = bank.value.boundingBoxOfPath.intersection(other.value.boundingBoxOfPath)
                guard !sharedBounds.isNull, !sharedBounds.isEmpty else { continue }
                // Oval bounding rectangles can overlap at empty corners.
                // Check the actual painted water at one-screen-point spacing.
                let step = 1 / max(scene.debugCameraZoom, 0.001)
                var sharesWater = false
                for x in stride(from: sharedBounds.minX, through: sharedBounds.maxX, by: step) {
                    for y in stride(from: sharedBounds.minY, through: sharedBounds.maxY, by: step) {
                        let point = CGPoint(x: x, y: y)
                        if bank.value.contains(point) && other.value.contains(point) { sharesWater = true }
                    }
                }
                XCTAssertFalse(sharesWater,
                               "\(scene.debugLabelTexts[bank.key] ?? bank.key) and \(scene.debugLabelTexts[other.key] ?? other.key) need separate pond space",
                               file: file, line: line)
            }
        }
    }

    private func assertMeAbsentFromOrdinaryOverview(
        _ me: Person, in scene: GoldfishGraphScene, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertFalse(scene.debugMeIsVisible, "Me should be omitted from ordinary pond overview", file: file, line: line)
        XCTAssertFalse(scene.debugRenderedVisibleIDs.contains(me.id), "Me should not be rendered in ordinary overview", file: file, line: line)
        XCTAssertFalse(scene.debugRevealedNodeIDs.contains(me.id), "Me should not have a visible scene node in ordinary overview", file: file, line: line)
        if let point = scene.debugNodePositions[me.id] {
            XCTAssertFalse(scene.debugContactCandidateIDs(at: point).contains(me.id),
                           "Me should not be a contact hit target in ordinary overview", file: file, line: line)
        } else {
            XCTFail("The graph should retain Me's canonical position for explicit routes", file: file, line: line)
        }
    }

    private func assertVisibleNamesAvoidOtherCoins(
        in scene: GoldfishGraphScene, file: StaticString = #filePath, line: UInt = #line
    ) {
        let labels = scene.debugVisibleNameLabelBounds
        let coins = scene.debugVisibleCoinBounds
        for (personID, label) in labels {
            for (otherID, coin) in coins where personID != otherID {
                XCTAssertFalse(label.intersects(coin),
                               "Visible name label \(scene.debugDisclosureIdentityLabels[personID] ?? personID.uuidString) overlaps another visible coin \(otherID)",
                               file: file, line: line)
            }
        }
    }

    func testLateInitialDisclosureDoesNotResetExplicitCameraControls() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "You", isMe: true)
        let friend = try manager.createPerson(name: "Alex")
        try manager.createRelationship(from: me, to: friend, type: .friend)
        let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 500))
        _ = scene.debugLayout([GraphLevel(depth: 0, circleGroups: [CircleGroup(circle: nil, contacts: [me, friend])])])
        scene.didUpdateCameraPosition(CGPoint(x: 72, y: -41))
        scene.didUpdateZoom(0.74)
        scene.didUpdateDisclosure(PondDisclosure(people: [me, friend]).snapshot)
        XCTAssertEqual(scene.debugCameraPosition, CGPoint(x: 72, y: -41))
        XCTAssertEqual(scene.debugCameraZoom, 0.74)
    }

    func testOverviewHidesMeUntilTheRelationshipPathIsExplicit() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "You", isMe: true)
        let alice = try manager.createPerson(name: "Alice")
        let bob = try manager.createPerson(name: "Bob")
        let family = try manager.createCircle(name: "Family")
        try manager.addToCircle(alice, circle: family)
        try manager.createRelationship(from: me, to: alice, type: .friend)
        try manager.createRelationship(from: me, to: bob, type: .friend)
        try manager.createRelationship(from: alice, to: bob, type: .friend)
        let people = [me, alice, bob]
        var disclosure = PondDisclosure(people: people)
        let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 500))
        scene.didUpdateGroups([family])
        _ = scene.debugLayout([GraphLevel(depth: 0, circleGroups: [CircleGroup(circle: nil, contacts: people)])])
        scene.didUpdateDisclosure(disclosure.snapshot)
        XCTAssertEqual(scene.debugVisibleEdgeCount, 0)
        XCTAssertEqual(scene.debugOverviewConnectorCount, 0)
        assertMeAbsentFromOrdinaryOverview(me, in: scene)
        disclosure.selectPondContact(id: alice.id)
        scene.didUpdateDisclosure(disclosure.snapshot)
        let meAliceEdge = [me.id.uuidString, alice.id.uuidString].sorted().joined(separator: "_")
        XCTAssertFalse(scene.debugVisibleEdgeKeys.contains(meAliceEdge),
                       "Selecting a contact should not implicitly reveal its relationship to Me")
        assertMeAbsentFromOrdinaryOverview(me, in: scene)
        disclosure.showConnectionPath()
        scene.didUpdateDisclosure(disclosure.snapshot)
        XCTAssertTrue(scene.debugMeIsVisible, "An explicit route should show Me as its actual endpoint")
        XCTAssertTrue(scene.debugRevealedNodeIDs.contains(me.id),
                      "An explicit route should present Me as its actual endpoint")
        XCTAssertTrue(scene.debugRenderedVisibleIDs.contains(me.id))
        let mePoint = try XCTUnwrap(scene.debugPresentedMePosition)
        let renderedMePoint = try XCTUnwrap(scene.debugNodePositions[me.id])
        XCTAssertEqual(renderedMePoint.x, mePoint.x, accuracy: 0.0001,
                       "The rendered Me marker and explicit relationship endpoint must share an x position")
        XCTAssertEqual(renderedMePoint.y, mePoint.y, accuracy: 0.0001,
                       "The rendered Me marker and explicit relationship endpoint must share a y position")
        let alicePoint = try XCTUnwrap(scene.debugNodePositions[alice.id])
        let directEdge = meAliceEdge
        XCTAssertTrue(scene.debugVisibleEdgeKeys.contains(directEdge))
        let pathBounds = try XCTUnwrap(scene.debugEdgePaths[directEdge]?.boundingBoxOfPath)
        XCTAssertTrue(pathBounds.insetBy(dx: -0.001, dy: -0.001).contains(mePoint),
                      "The explicit relationship path should reach its Me endpoint")
        XCTAssertTrue(pathBounds.insetBy(dx: -0.001, dy: -0.001).contains(alicePoint),
                      "The explicit relationship path should reach the selected contact endpoint")
        let meFootprint = CGRect(x: mePoint.x - 38, y: mePoint.y - 48, width: 76, height: 96)
        XCTAssertFalse(scene.debugVisibleIdentityBounds.filter { $0.key != me.id }.values
            .contains(where: { meFootprint.intersects($0) }),
                       "The path endpoint must not overlap a visible contact identity")
        XCTAssertTrue(scene.debugPresentedPondPaths.values.allSatisfy { !$0.contains(mePoint) },
                      "The path endpoint must sit outside painted pond water")

        scene.didUpdateZoom(0.74)
        let pondBounds = try XCTUnwrap(scene.debugPondBasinBounds[family.id.uuidString])
        XCTAssertTrue(scene.debugBeginPondDrag(pondID: family.id.uuidString, at: CGPoint(x: pondBounds.midX, y: pondBounds.midY)))
        scene.debugUpdatePondDrag(to: CGPoint(x: pondBounds.midX + 29, y: pondBounds.midY - 16))
        scene.debugEndPondDrag()
        let movedMePoint = try XCTUnwrap(scene.debugPresentedMePosition)
        let movedRenderedMePoint = try XCTUnwrap(scene.debugNodePositions[me.id])
        XCTAssertEqual(movedRenderedMePoint.x, movedMePoint.x, accuracy: 0.0001,
                       "Moving a pond must keep the rendered endpoint aligned horizontally with its route")
        XCTAssertEqual(movedRenderedMePoint.y, movedMePoint.y, accuracy: 0.0001,
                       "Moving a pond must keep the rendered endpoint aligned vertically with its route")
        let movedPathBounds = try XCTUnwrap(scene.debugEdgePaths[directEdge]?.boundingBoxOfPath)
        XCTAssertTrue(movedPathBounds.insetBy(dx: -0.001, dy: -0.001).contains(movedMePoint))
        let movedMeFootprint = CGRect(x: movedMePoint.x - 38, y: movedMePoint.y - 48, width: 76, height: 96)
        XCTAssertFalse(scene.debugVisibleIdentityBounds.filter { $0.key != me.id }.values
            .contains(where: { movedMeFootprint.intersects($0) }))
        XCTAssertTrue(scene.debugPresentedPondPaths.values.allSatisfy { !$0.contains(movedMePoint) })
        disclosure.collapseAllPondConnections()
        scene.didUpdateDisclosure(disclosure.snapshot)
        XCTAssertEqual(scene.debugVisibleEdgeCount, 0)
        assertMeAbsentFromOrdinaryOverview(me, in: scene)
    }

    func testSampleOverviewSeparatesVisibleIdentitiesAtPhoneWidth() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        try manager.performOnboarding(name: "You")
        XCTAssertTrue(try DemoDataService(dataManager: manager).seedDemoData())
        let people = try manager.fetchAllPersons()
        let groups = try manager.fetchAllCircles()
        let tom = try XCTUnwrap(people.first { $0.name == "Tom Miller" })
        let levels = [GraphLevel(depth: 0, circleGroups: [CircleGroup(circle: nil, contacts: people)])]

        for height: CGFloat in [430, 540] {
            let scene = GoldfishGraphScene(size: CGSize(width: 390, height: height))
            var disclosure = PondDisclosure(people: people)
            scene.didUpdateDisclosure(disclosure.snapshot)
            scene.didUpdateGroups(groups)
            _ = scene.debugLayout(levels)
            scene.didUpdateDisclosure(disclosure.snapshot)
            scene.fitAllNodesWithLabels(animated: false)
            XCTAssertEqual(scene.debugOverviewConnectorCount, 0,
                           "Pond overview should not use Me as an organization hub")
            assertMeAbsentFromOrdinaryOverview(try XCTUnwrap(people.first { $0.isMe }), in: scene)

            func assertReadableIdentities(_ state: String, file: StaticString = #filePath, line: UInt = #line) {
                let expected = disclosure.snapshot.visibleIDs
                let expectedOnMap = expected.subtracting(people.filter(\.isMe).map(\.id))
                XCTAssertEqual(scene.debugFullIdentityIDs, expectedOnMap, "Every visible contact needs an identity in \(state)", file: file, line: line)
                let bounds = scene.debugVisibleIdentityBounds
                for (id, rect) in bounds {
                    for (otherID, otherRect) in bounds where id.uuidString < otherID.uuidString {
                        XCTAssertFalse(rect.intersects(otherRect),
                                       "\(people.first { $0.id == id }!.name) overlaps \(people.first { $0.id == otherID }!.name) in \(state), height \(height)",
                                       file: file, line: line)
                    }
                }
                assertPondHeadingsStayAttached(scene, file: file, line: line)
            }
            assertReadableIdentities("initial overview")
            let originalPositions = scene.debugNodePositions
            let originalCamera = (scene.debugCameraPosition, scene.debugCameraZoom)
            disclosure.selectPondContact(id: tom.id)
            scene.didUpdateDisclosure(disclosure.snapshot)
            assertReadableIdentities("selected Tom")
            XCTAssertEqual(scene.debugNodePositions, originalPositions)
            XCTAssertEqual(scene.debugCameraPosition, originalCamera.0)
            XCTAssertEqual(scene.debugCameraZoom, originalCamera.1)
        }
    }

    func testExpandedDaycareStaysClearOfFamilyAfterReturningHome() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        try manager.performOnboarding(name: "You")
        XCTAssertTrue(try DemoDataService(dataManager: manager).seedDemoData())

        let people = try manager.fetchAllPersons()
        let circles = try manager.fetchAllCircles()
        let adriana = try XCTUnwrap(people.first { $0.name == "Adriana" })
        let riley = try XCTUnwrap(people.first { $0.name == "Riley" })
        let selma = try XCTUnwrap(people.first { $0.name == "Selma" })
        let sarah = try XCTUnwrap(people.first { $0.name == "Sarah Chen" })
        let family = try XCTUnwrap(circles.first { $0.name == "Family" })
        let daycare = try XCTUnwrap(circles.first { $0.name == "Daycare" })
        XCTAssertEqual(sarah.primaryCircle?.id, family.id)
        XCTAssertEqual(selma.primaryCircle?.id, daycare.id)

        let model = GraphViewModel(dataManager: manager)
        model.isDemoMode = true
        let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 700))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        view.presentScene(scene)
        defer { view.presentScene(nil) }
        scene.graphDelegate = model
        model.sceneDelegate = scene
        model.loadGraph()

        XCTAssertTrue(scene.debugPondOffsets.isEmpty, "The collision check must use automatic pond placement")
        scene.debugActivatePondContact(adriana.id)
        scene.debugActivatePondContact(riley.id)
        XCTAssertTrue(model.disclosureSnapshot.expandedIDs.contains(adriana.id))
        XCTAssertTrue(model.disclosureSnapshot.expandedIDs.contains(riley.id))
        XCTAssertTrue(model.disclosureSnapshot.visibleIDs.contains(selma.id))

        let positionsBeforeHome = scene.debugNodePositions
        model.showMyPonds()
        XCTAssertTrue(model.disclosureSnapshot.expandedIDs.contains(adriana.id),
                      "Returning home must preserve Adriana's expanded branch")
        XCTAssertTrue(model.disclosureSnapshot.expandedIDs.contains(riley.id),
                      "Returning home must preserve Riley's expanded branch")
        XCTAssertNil(model.disclosureSnapshot.focusRootID)
        XCTAssertTrue(scene.debugPondOffsets.isEmpty, "Showing home must not create personal pond offsets")
        for person in [selma, sarah] {
            let before = try XCTUnwrap(positionsBeforeHome[person.id])
            let after = try XCTUnwrap(scene.debugNodePositions[person.id])
            XCTAssertEqual(after.x, before.x, accuracy: 0.0001,
                           "Home framing must not move saved identity slot for \(person.name)")
            XCTAssertEqual(after.y, before.y, accuracy: 0.0001,
                           "Home framing must not move saved identity slot for \(person.name)")
        }

        // Fit and counter-scale repeatedly to exercise name placement after the
        // camera changes. A second pass can reveal labels suppressed earlier.
        for pass in 0..<3 {
            scene.fitToGraph()
            let zoomFactor: CGFloat = pass.isMultiple(of: 2) ? 0.92 : 1.08
            scene.didUpdateZoom(scene.debugCameraZoom * zoomFactor)
            scene.didUpdateZoom(scene.debugCameraZoom / zoomFactor)
            assertVisibleNamesAvoidOtherCoins(in: scene)
        }

        let familyIDs = Set(people.filter { $0.primaryCircle?.id == family.id }.map(\.id))
        let daycareIDs = Set(people.filter { $0.primaryCircle?.id == daycare.id }.map(\.id))
        let coinBounds = scene.debugVisibleCoinBounds
        let nameBounds = scene.debugVisibleNameLabelBounds
        let zoom = scene.debugCameraZoom
        XCTAssertTrue(zoom.isFinite && zoom > 0, "Screen-space comparison needs a valid camera scale")
        func scaledToScreen(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX * zoom, y: rect.minY * zoom,
                   width: rect.width * zoom, height: rect.height * zoom)
        }
        let namesByID = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0.name) })
        let selmaCoin = try XCTUnwrap(coinBounds[selma.id], "Expanded Daycare coin must be presented")
        let sarahCoin = try XCTUnwrap(coinBounds[sarah.id], "Family coin must remain presented")
        XCTAssertFalse(scaledToScreen(selmaCoin).intersects(scaledToScreen(sarahCoin)),
                       "Daycare coin Selma \(selmaCoin) must not overlap Family coin Sarah \(sarahCoin)")
        for daycareID in daycareIDs {
            guard let daycareCoin = coinBounds[daycareID] else { continue }
            for familyID in familyIDs {
                guard let familyCoin = coinBounds[familyID] else { continue }
                let daycareName = namesByID[daycareID] ?? daycareID.uuidString
                let familyName = namesByID[familyID] ?? familyID.uuidString
                XCTAssertFalse(scaledToScreen(daycareCoin).intersects(scaledToScreen(familyCoin)),
                               "Daycare coin \(daycareName) overlaps Family coin \(familyName): \(daycareCoin) / \(familyCoin)")
                if let label = nameBounds[daycareID] {
                    XCTAssertFalse(scaledToScreen(label).intersects(scaledToScreen(familyCoin)),
                                   "Daycare label \(daycareName) overlaps Family coin \(familyName): \(label) / \(familyCoin)")
                }
                if let label = nameBounds[familyID] {
                    XCTAssertFalse(scaledToScreen(daycareCoin).intersects(scaledToScreen(label)),
                                   "Daycare coin \(daycareName) overlaps Family label \(familyName): \(daycareCoin) / \(label)")
                }
                if let daycareLabel = nameBounds[daycareID], let familyLabel = nameBounds[familyID] {
                    XCTAssertFalse(scaledToScreen(daycareLabel).intersects(scaledToScreen(familyLabel)),
                                   "Daycare label \(daycareName) overlaps Family label \(familyName): \(daycareLabel) / \(familyLabel)")
                }
            }
        }
    }

    func testOverviewFitTracksSavedPondOffsetsInsteadOfMeOrigin() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let alice = try manager.createPerson(name: "Alice")
        let bob = try manager.createPerson(name: "Bob")
        let family = try manager.createCircle(name: "Family")
        let friends = try manager.createCircle(name: "Friends")
        try manager.addToCircle(alice, circle: family)
        try manager.addToCircle(bob, circle: friends)
        try manager.createRelationship(from: me, to: alice, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: me, to: bob, type: .friend, skipAutoAssign: true)
        let people = [me, alice, bob]
        let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 500))
        scene.didUpdateGroups([family, friends])
        _ = scene.debugLayout([GraphLevel(depth: 0, circleGroups: [CircleGroup(circle: nil, contacts: people)])])
        scene.didUpdateDisclosure(PondDisclosure(people: people).snapshot)
        scene.setPondLayoutOffsets([
            family.id.uuidString: CGPoint(x: 820, y: 360),
            friends.id.uuidString: CGPoint(x: 820, y: 360)
        ])
        scene.fitToGraph()

        XCTAssertGreaterThan(scene.debugCameraPosition.x, 500,
                             "Fitting the overview should follow the saved ponds instead of centering on Me's canonical origin")
        XCTAssertGreaterThan(scene.debugCameraPosition.y, 100)
        assertMeAbsentFromOrdinaryOverview(me, in: scene)
    }

    func testGuidedTourVisibilityToggleUpdatesMeNodeAndHitTesting() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let direct = try manager.createPerson(name: "Direct")
        try manager.createRelationship(from: me, to: direct, type: .friend, skipAutoAssign: true)
        let people = [me, direct]
        let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 500))
        scene.didUpdateGroups([])
        _ = scene.debugLayout([GraphLevel(depth: 0, circleGroups: [CircleGroup(circle: nil, contacts: people)])])
        scene.didUpdateDisclosure(PondDisclosure(people: people).snapshot)
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 390, height: 500))
        view.presentScene(scene)

        assertMeAbsentFromOrdinaryOverview(me, in: scene)
        scene.showsMeDuringGuidedTour = true
        XCTAssertTrue(scene.debugMeIsVisible)
        XCTAssertTrue(scene.debugRevealedNodeIDs.contains(me.id))
        guard let mePoint = scene.debugNodePositions[me.id] else {
            XCTFail("A guided tour must place Me at a hittable graph position")
            view.presentScene(nil)
            return
        }
        XCTAssertTrue(scene.debugContactCandidateIDs(at: mePoint).contains(me.id),
                      "Me should be a contact hit target during the guided lesson")

        scene.showsMeDuringGuidedTour = false
        assertMeAbsentFromOrdinaryOverview(me, in: scene)
        view.presentScene(nil)
    }

    func testUnassignedPondAppearsOnlyWhenItsHiddenMemberIsRevealed() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        try manager.performOnboarding(name: "You")
        XCTAssertTrue(try DemoDataService(dataManager: manager).seedDemoData())
        let people = try manager.fetchAllPersons()
        let unassigned = try XCTUnwrap(people.first { !$0.isMe && $0.primaryCircle == nil })
        var disclosure = PondDisclosure(people: people)
        let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 500))
        scene.didUpdateDisclosure(disclosure.snapshot)
        scene.didUpdateGroups(try manager.fetchAllCircles())
        _ = scene.debugLayout([GraphLevel(depth: 0, circleGroups: [CircleGroup(circle: nil, contacts: people)])])
        scene.didUpdateDisclosure(disclosure.snapshot)
        scene.fitAllNodesWithLabels(animated: false)
        let positions = scene.debugNodePositions
        let camera = (scene.debugCameraPosition, scene.debugCameraZoom)

        XCTAssertNil(scene.debugPondBasinBounds["unassigned"])
        XCTAssertNil(scene.debugPondLabelBounds["unassigned"])
        disclosure.revealHiddenPeople(in: "unassigned")
        scene.didUpdateDisclosure(disclosure.snapshot)
        XCTAssertTrue(scene.debugRenderedVisibleIDs.contains(unassigned.id))
        XCTAssertNotNil(scene.debugPondBasinBounds["unassigned"])
        XCTAssertNotNil(scene.debugPondLabelBounds["unassigned"])
        XCTAssertEqual(scene.debugNodePositions, positions)
        XCTAssertEqual(scene.debugCameraPosition, camera.0)
        XCTAssertEqual(scene.debugCameraZoom, camera.1)
    }

    func testFiftyPersonOverviewKeepsDirectContactsReadable() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        try manager.performOnboarding(name: "You")
        try DemoDataService(dataManager: manager).seedQualityReviewNetwork()
        let people = try manager.fetchAllPersons()
        var disclosure = PondDisclosure(people: people)
        let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 500))
        scene.didUpdateGroups(try manager.fetchAllCircles())
        _ = scene.debugLayout([GraphLevel(depth: 0, circleGroups: [CircleGroup(circle: nil, contacts: people)])])
        scene.didUpdateDisclosure(disclosure.snapshot)
        scene.fitAllNodesWithLabels(animated: false)
        let positions = scene.debugNodePositions
        let camera = (scene.debugCameraPosition, scene.debugCameraZoom)
        let tom = try XCTUnwrap(people.first { $0.name == "Tom Miller" })

        for selectedID in [nil, tom.id] {
            if let selectedID { disclosure.selectPondContact(id: selectedID) }
            scene.didUpdateDisclosure(disclosure.snapshot)
            let expectedVisibleIDs = disclosure.snapshot.visibleIDs.subtracting(people.filter(\.isMe).map(\.id))
            XCTAssertEqual(scene.debugFullIdentityIDs, expectedVisibleIDs)
            let bounds = scene.debugVisibleIdentityBounds
            for (id, rect) in bounds {
                for (otherID, otherRect) in bounds where id.uuidString < otherID.uuidString {
                    XCTAssertFalse(rect.intersects(otherRect),
                                   "\(people.first { $0.id == id }!.name) overlaps \(people.first { $0.id == otherID }!.name) with 50 saved contacts")
                }
            }
            assertPondHeadingsStayAttached(scene)
        }
        XCTAssertEqual(scene.debugNodePositions, positions)
        XCTAssertEqual(scene.debugCameraPosition, camera.0)
        XCTAssertEqual(scene.debugCameraZoom, camera.1)
    }

    func testHiddenPopulationDoesNotCompressTheInitialDirectLayout() throws {
        func directPositions(largeNetwork: Bool) throws -> [String: CGPoint] {
            let (manager, container) = try makeTestManager()
            defer { withExtendedLifetime(container) {} }
            try manager.performOnboarding(name: "You")
            if largeNetwork {
                try DemoDataService(dataManager: manager).seedQualityReviewNetwork()
            } else {
                XCTAssertTrue(try DemoDataService(dataManager: manager).seedDemoData())
            }
            let people = try manager.fetchAllPersons()
            let disclosure = PondDisclosure(people: people)
            let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 500))
            scene.didUpdateGroups(try manager.fetchAllCircles())
            _ = scene.debugLayout([GraphLevel(depth: 0, circleGroups: [CircleGroup(circle: nil, contacts: people)])])
            scene.didUpdateDisclosure(disclosure.snapshot)
            return Dictionary(uniqueKeysWithValues: people.compactMap { person in
                guard disclosure.snapshot.visibleIDs.contains(person.id),
                      let position = scene.debugNodePositions[person.id] else { return nil }
                return (person.name, position)
            })
        }
        let small = try directPositions(largeNetwork: false)
        let large = try directPositions(largeNetwork: true)
        XCTAssertEqual(Set(small.keys), Set(large.keys), "Both graphs should expose the same direct contacts")
        for name in small.keys {
            let first = try XCTUnwrap(small[name])
            let second = try XCTUnwrap(large[name])
            XCTAssertEqual(first.x, second.x, accuracy: 0.000001,
                           "Adding only indirect contacts must not move \(name) horizontally")
            XCTAssertEqual(first.y, second.y, accuracy: 0.000001,
                           "Adding only indirect contacts must not move \(name) vertically")
        }
    }

    func testLargePondKeepsDistinctHiddenSlotsAfterCompaction() throws {
        for linked in [true, false] {
            let (manager, container) = try makeTestManager()
            defer { withExtendedLifetime(container) {} }
            let me = try manager.createPerson(name: "You", isMe: true)
            let parent = try manager.createPerson(name: "David")
            let pond = try manager.createCircle(name: "Professional")
            try manager.addToCircle(parent, circle: pond)
            try manager.createRelationship(from: me, to: parent, type: .coworker, skipAutoAssign: true)
            var people = [me, parent]
            for index in 0..<13 {
                let colleague = try manager.createPerson(name: "Colleague \(index)")
                try manager.addToCircle(colleague, circle: pond)
                if linked {
                    try manager.createRelationship(from: parent, to: colleague, type: .coworker, skipAutoAssign: true)
                }
                people.append(colleague)
            }
            var disclosure = PondDisclosure(people: people)
            let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 500))
            scene.didUpdateGroups([pond])
            _ = scene.debugLayout([GraphLevel(depth: 0, circleGroups: [CircleGroup(circle: nil, contacts: people)])])
            scene.didUpdateDisclosure(disclosure.snapshot)
            let positions = scene.debugNodePositions
            let parentPoint = try XCTUnwrap(positions[parent.id])
            for colleague in people where !colleague.isMe && colleague.id != parent.id {
                let point = try XCTUnwrap(positions[colleague.id])
                XCTAssertGreaterThan(hypot(point.x - parentPoint.x, point.y - parentPoint.y), 100,
                                     "Hidden contact \(colleague.name) must not share its parent's reserved slot")
            }
            if linked {
                disclosure.togglePondConnections(id: parent.id)
            } else {
                disclosure.revealHiddenPeople(in: pond.id.uuidString)
            }
            scene.didUpdateDisclosure(disclosure.snapshot)
            XCTAssertEqual(scene.debugNodePositions, positions)
        }
    }

    func testPondOutlineGrowsAroundRevealedPeopleWithoutMovingThem() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "You", isMe: true)
        let david = try manager.createPerson(name: "David")
        let lisa = try manager.createPerson(name: "Lisa")
        let chris = try manager.createPerson(name: "Chris")
        let pond = try manager.createCircle(name: "Professional")
        for person in [david, lisa, chris] { try manager.addToCircle(person, circle: pond) }
        try manager.createRelationship(from: me, to: david, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: david, to: lisa, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: david, to: chris, type: .friend, skipAutoAssign: true)
        let people = [me, david, lisa, chris]
        var disclosure = PondDisclosure(people: people)
        let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 500))
        scene.didUpdateGroups([pond])
        _ = scene.debugLayout([GraphLevel(depth: 0, circleGroups: [CircleGroup(circle: nil, contacts: people)])])
        scene.didUpdateDisclosure(disclosure.snapshot)
        let positions = scene.debugNodePositions
        let camera = (scene.debugCameraPosition, scene.debugCameraZoom)
        let initialBounds = try XCTUnwrap(scene.debugPondBasinBounds[pond.id.uuidString])
        let initialDragBounds = try XCTUnwrap(scene.debugVisibleDragBasinBounds[pond.id.uuidString])
        let reservedBounds = try XCTUnwrap(scene.debugPondGeometryBounds[pond.id.uuidString])
        XCTAssertTrue(initialBounds.contains(initialDragBounds))
        XCTAssertLessThan(initialDragBounds.width, reservedBounds.width,
                          "A hidden future station must not leave an invisible drag destination")
        disclosure.togglePondConnections(id: david.id)
        scene.didUpdateDisclosure(disclosure.snapshot)
        let expandedBounds = try XCTUnwrap(scene.debugPondBasinBounds[pond.id.uuidString])
        let expandedDragBounds = try XCTUnwrap(scene.debugVisibleDragBasinBounds[pond.id.uuidString])
        XCTAssertTrue(expandedBounds.contains(expandedDragBounds))
        XCTAssertGreaterThan(expandedDragBounds.width * expandedDragBounds.height,
                             initialDragBounds.width * initialDragBounds.height)
        XCTAssertGreaterThan(expandedBounds.width * expandedBounds.height, initialBounds.width * initialBounds.height)
        for person in [david, lisa, chris] {
            XCTAssertTrue(expandedBounds.contains(try XCTUnwrap(positions[person.id])))
        }
        XCTAssertEqual(scene.debugNodePositions, positions)
        XCTAssertEqual(scene.debugCameraPosition, camera.0)
        XCTAssertEqual(scene.debugCameraZoom, camera.1)
    }

    func testLastUnassignedMemberMovingClearsObsoleteFocus() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        _ = try manager.createPerson(name: "Me", isMe: true)
        let person = try manager.createPerson(name: "Unassigned person")
        let group = try manager.createCircle(name: "Team", color: "#334455")
        let model = GraphViewModel(dataManager: manager)
        model.loadGraph()
        model.selectedPondFilter = "unassigned"
        try manager.addToCircle(person, circle: group)
        model.refreshGraph()
        XCTAssertNil(model.selectedPondFilter)
        XCTAssertEqual(person.primaryCircle?.id, group.id)
        XCTAssertFalse(model.hasNoData)
    }

    func testLayoutIsDeterministicAndDisclosureHidesEdgesThenSearchReveals() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        try manager.createSystemCircles()
        let me = try manager.createPerson(name: "Me", isMe: true)
        let root = try manager.createPerson(name: "Root")
        let child = try manager.createPerson(name: "Child")
        try manager.createRelationship(from: me, to: root, type: .friend)
        try manager.createRelationship(from: root, to: child, type: .friend)
        let contacts = [me, root, child]
        let levels = [GraphLevel(depth: 0, circleGroups: [CircleGroup(circle: nil, contacts: contacts)])]
        let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 844))
        let first = scene.debugLayout(levels)
        XCTAssertEqual(first.count, 3)
        XCTAssertEqual(first[me.id], CGPoint.zero)
        XCTAssertEqual(scene.debugParents[child.id], root.id)
        let reversed = [GraphLevel(depth: 0, circleGroups: [CircleGroup(circle: nil, contacts: Array(contacts.reversed()))])]
        XCTAssertEqual(first, scene.debugLayout(reversed))
        scene.didUpdateDisclosure(PondDisclosureSnapshot(
            visibleIDs: [me.id, root.id], directIDs: [root.id], expandedIDs: [], selectedID: nil,
            trail: [], hiddenNeighborCounts: [root.id: 1], hiddenByPond: [:], unlinkedIDs: [],
            revealedEdges: [PondDisclosureEdge(from: me.id, to: root.id)], parents: [root.id: me.id]
        ))
        XCTAssertFalse(scene.debugRenderedVisibleIDs.contains(child.id))
        XCTAssertEqual(scene.debugVisibleEdgeCount, 0)
        XCTAssertEqual(scene.debugOverviewConnectorCount, 0)
        assertMeAbsentFromOrdinaryOverview(me, in: scene)
        scene.didUpdateZoom(scene.debugCameraZoom * 0.8)
        assertMeAbsentFromOrdinaryOverview(me, in: scene)
        scene.didUpdateSearchMatches([child.id, me.id])
        XCTAssertTrue(scene.debugRenderedVisibleIDs.contains(child.id))
        assertMeAbsentFromOrdinaryOverview(me, in: scene)
        XCTAssertEqual(scene.debugVisibleEdgeCount, 1)
        let directEdge = [me.id.uuidString, root.id.uuidString].sorted().joined(separator: "_")
        XCTAssertFalse(scene.debugVisibleEdgeKeys.contains(directEdge))
        scene.didUpdateSearchMatches(nil)
        scene.didUpdateDisclosure(PondDisclosureSnapshot(
            visibleIDs: [me.id, root.id], directIDs: [root.id], expandedIDs: [], selectedID: root.id,
            trail: [me.id, root.id], hiddenNeighborCounts: [root.id: 1], hiddenByPond: [:], unlinkedIDs: [],
            revealedEdges: [PondDisclosureEdge(from: me.id, to: root.id)], parents: [root.id: me.id],
            pathHighlightIDs: [me.id, root.id]
        ))
        XCTAssertTrue(scene.debugVisibleEdgeKeys.contains(directEdge), "An explicit path remains visible without relationship focus")
    }

    func testFocusedClusterFramesNestedExpansionAndRestoresOverviewCamera() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let adriana = try manager.createPerson(name: "Adriana")
        let riley = try manager.createPerson(name: "Riley")
        let casey = try manager.createPerson(name: "Casey")
        try manager.createRelationship(from: me, to: adriana, type: .friend)
        try manager.createRelationship(from: adriana, to: riley, type: .friend)
        try manager.createRelationship(from: riley, to: casey, type: .friend)
        let people = [me, adriana, riley, casey]
        let levels = [GraphLevel(depth: 0, circleGroups: [CircleGroup(circle: nil, contacts: people)])]
        let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 700))
        _ = scene.debugLayout(levels)
        var disclosure = PondDisclosure(people: people)
        let overview = disclosure.snapshot
        scene.didUpdateDisclosure(overview)
        let overviewCamera = (scene.debugCameraPosition, scene.debugCameraZoom)

        disclosure.activatePondContact(id: adriana.id)
        scene.didUpdateDisclosure(disclosure.snapshot)
        XCTAssertEqual(disclosure.snapshot.focusRootID, adriana.id)
        XCTAssertTrue(disclosure.snapshot.focusedIDs.contains(riley.id))
        let directEdge = [me.id.uuidString, adriana.id.uuidString].sorted().joined(separator: "_")
        XCTAssertFalse(scene.debugVisibleEdgeKeys.contains(directEdge))
        disclosure.showConnectionPath()
        scene.didUpdateDisclosure(disclosure.snapshot)
        XCTAssertTrue(scene.debugVisibleEdgeKeys.contains(directEdge), "The explicit route may show the direct relationship line")
        disclosure.clearConnectionPath()
        scene.didUpdateDisclosure(disclosure.snapshot)
        XCTAssertFalse(scene.debugVisibleEdgeKeys.contains(directEdge))
        let firstFocusCamera = (scene.debugCameraPosition, scene.debugCameraZoom)
        XCTAssertTrue(firstFocusCamera.0 != overviewCamera.0 || firstFocusCamera.1 != overviewCamera.1)

        disclosure.activatePondContact(id: riley.id)
        scene.didUpdateDisclosure(disclosure.snapshot)
        XCTAssertEqual(disclosure.snapshot.focusRootID, adriana.id)
        XCTAssertTrue(disclosure.snapshot.focusedIDs.contains(casey.id))
        XCTAssertTrue(scene.debugCameraPosition != firstFocusCamera.0 || scene.debugCameraZoom != firstFocusCamera.1)

        disclosure.clearPondFocus()
        scene.didUpdateDisclosure(disclosure.snapshot)
        XCTAssertEqual(scene.debugCameraPosition, overviewCamera.0)
        XCTAssertEqual(scene.debugCameraZoom, overviewCamera.1, accuracy: 0.000001)
        XCTAssertTrue(disclosure.snapshot.visibleIDs.contains(casey.id), "Returning to overview keeps expanded branches open")
    }

    func testDeletingAPondRetiresItsOverviewBank() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "You", isMe: true)
        let person = try manager.createPerson(name: "Alex")
        let pond = try manager.createCircle(name: "Team")
        let removedPondID = pond.id.uuidString
        try manager.createRelationship(from: me, to: person, type: .friend, skipAutoAssign: true)
        try manager.addToCircle(person, circle: pond)
        let people = [me, person]
        let levels = [GraphLevel(depth: 0, circleGroups: [CircleGroup(circle: nil, contacts: people)])]
        let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 500))
        scene.didUpdateGroups(try manager.fetchAllCircles())
        _ = scene.debugLayout(levels)
        scene.didUpdateDisclosure(PondDisclosure(people: people).snapshot)
        XCTAssertTrue(scene.debugPondBasinBounds[removedPondID] != nil)

        try manager.deleteCircle(pond)
        scene.didUpdateGroups(try manager.fetchAllCircles())
        _ = scene.debugLayout(levels)
        scene.didUpdateDisclosure(PondDisclosure(people: people).snapshot)

        XCTAssertFalse(scene.debugPondBasinBounds.keys.contains(removedPondID))
        XCTAssertNotNil(scene.debugPondBasinBounds["unassigned"])
        XCTAssertEqual(scene.debugOverviewConnectorCount, 0)
    }

    func testDenseLayoutHasFiniteDistinctSlots() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        try manager.createSystemCircles()
        let me = try manager.createPerson(name: "Me", isMe: true)
        var contacts = [me]
        for index in 0..<80 {
            let person = try manager.createPerson(name: "Person \(index)")
            try manager.createRelationship(from: me, to: person, type: .friend)
            contacts.append(person)
        }
        let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 844))
        let slots = scene.debugLayout([GraphLevel(depth: 0, circleGroups: [CircleGroup(circle: nil, contacts: contacts)])])
        XCTAssertEqual(slots.count, contacts.count)
        XCTAssertEqual(slots[me.id], .zero, "Me retains a canonical slot for explicit paths and the walkthrough")
        let values = contacts.filter { !$0.isMe }.compactMap { slots[$0.id] }
        for (i, point) in values.enumerated() {
            XCTAssertTrue(point.x.isFinite && point.y.isFinite)
            for other in values.dropFirst(i + 1) {
                XCTAssertGreaterThan(hypot(point.x - other.x, point.y - other.y), 50)
            }
        }
    }
    func testDisclosurePreservesExplicitPondMembershipAcrossCrossPondExpansion() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let a = try manager.createCircle(name: "Same", color: "#B44A36")
        let b = try manager.createCircle(name: "Same", color: "#336699")
        let root = try manager.createPerson(name: "Root")
        let samePond = try manager.createPerson(name: "Same pond")
        let otherPond = try manager.createPerson(name: "Other pond")
        try manager.addToCircle(root, circle: a)
        try manager.addToCircle(samePond, circle: a)
        try manager.addToCircle(otherPond, circle: b)
        try manager.createRelationship(from: me, to: root, type: .friend)
        try manager.createRelationship(from: root, to: samePond, type: .friend)
        try manager.createRelationship(from: root, to: otherPond, type: .friend)
        let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 844))
        scene.didUpdateGroups([a, b])
        _ = scene.debugLayout([GraphLevel(depth: 0, circleGroups: [CircleGroup(circle: nil, contacts: [me, root, samePond, otherPond])])])
        XCTAssertEqual(scene.debugGroupMembers[a.id.uuidString], [root.id, samePond.id])
        XCTAssertEqual(scene.debugGroupMembers[b.id.uuidString], [otherPond.id])
        XCTAssertEqual(scene.debugLabelTexts[a.id.uuidString], "Same")
        XCTAssertEqual(scene.debugLabelTexts[b.id.uuidString], "Same")
        var disclosure = PondDisclosure(people: [me, root, samePond, otherPond])
        let initial = disclosure.snapshot
        XCTAssertTrue(initial.visibleIDs.contains(me.id))
        XCTAssertTrue(initial.visibleIDs.contains(root.id))
        XCTAssertFalse(initial.visibleIDs.contains(samePond.id))
        XCTAssertFalse(initial.visibleIDs.contains(otherPond.id))
        scene.didUpdateDisclosure(initial)
        XCTAssertFalse(scene.debugRenderedVisibleIDs.contains(samePond.id))
        disclosure.togglePondConnections(id: root.id)
        scene.didUpdateDisclosure(disclosure.snapshot)
        XCTAssertTrue(scene.debugRenderedVisibleIDs.contains(samePond.id))
        XCTAssertTrue(scene.debugRenderedVisibleIDs.contains(otherPond.id))
        XCTAssertEqual(otherPond.primaryCircle?.id, b.id)
    }

    func testPondSlotsPlaceDirectContactBeforeDeeperMembersDeterministically() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let david = try manager.createPerson(name: "David")
        let lisa = try manager.createPerson(name: "Lisa")
        let chris = try manager.createPerson(name: "Chris")
        let pond = try manager.createCircle(name: "Professional")
        for person in [david, lisa, chris] { try manager.addToCircle(person, circle: pond) }
        try manager.createRelationship(from: me, to: david, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: david, to: lisa, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: david, to: chris, type: .friend, skipAutoAssign: true)
        let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 700))
        scene.didUpdateGroups([pond])
        let contacts = [me, david, lisa, chris]
        let levels = [GraphLevel(depth: 0, circleGroups: [CircleGroup(circle: nil, contacts: contacts)])]
        let first = scene.debugLayout(levels)
        func distance(_ id: UUID) -> CGFloat {
            let point = first[id]!
            return hypot(point.x, point.y)
        }
        XCTAssertLessThan(distance(david.id), distance(lisa.id))
        XCTAssertLessThan(distance(david.id), distance(chris.id))
        let reversed = scene.debugLayout([GraphLevel(depth: 0,
            circleGroups: [CircleGroup(circle: nil, contacts: Array(contacts.reversed()))])])
        XCTAssertEqual(first, reversed)
    }

    func testWalkthroughKeepsPondSignageAndMeReadableAtPhoneWidth() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        var contacts = [me]
        var groups: [GoldfishCircle] = []
        for i in 0..<5 {
            let group = try manager.createCircle(name: "Pond \(i)")
            groups.append(group)
            for j in 0..<8 {
                let person = try manager.createPerson(name: "Person \(i) \(j)")
                try manager.addToCircle(person, circle: group)
                contacts.append(person)
            }
        }
        let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 700))
        scene.showsMeDuringGuidedTour = true
        scene.didUpdateGroups(groups)
        _ = scene.debugLayout([GraphLevel(depth: 0, circleGroups: [CircleGroup(circle: nil, contacts: contacts)])])
        scene.fitToGraph()
        XCTAssertEqual(scene.debugPondLabelPointSizes.count, groups.count)
        XCTAssertTrue(scene.debugPondLabelPointSizes.allSatisfy { $0 >= 13.5 })
        XCTAssertTrue(scene.debugMeIsVisible)
        XCTAssertTrue(scene.debugMeShowsIdentity)
        let camera = scene.debugCameraPosition
        let zoom = max(scene.debugCameraZoom, 0.001)
        let visible = CGRect(
            x: camera.x - scene.size.width / (2 * zoom),
            y: camera.y - scene.size.height / (2 * zoom),
            width: scene.size.width / zoom,
            height: scene.size.height / zoom
        ).insetBy(dx: 42 / zoom, dy: 42 / zoom)
        for (name, bounds) in scene.debugPondLabelBounds {
            XCTAssertTrue(visible.contains(bounds), "\(name) heading must remain inside the fitted overview")
        }
    }

    func testNormalViewportFitRecoversAfterLargeTextCounterScale() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        var contacts = [me]
        var groups: [GoldfishCircle] = []
        for groupIndex in 0..<3 {
            let group = try manager.createCircle(name: "Pond \(groupIndex)")
            groups.append(group)
            for personIndex in 0..<17 {
                let person = try manager.createPerson(name: "Person \(groupIndex)-\(personIndex)")
                try manager.addToCircle(person, circle: group)
                contacts.append(person)
            }
        }
        let levels = [GraphLevel(depth: 0, circleGroups: [CircleGroup(circle: nil, contacts: contacts)])]

        let roundTrip = GoldfishGraphScene(size: CGSize(width: 390, height: 430))
        roundTrip.didUpdateGroups(groups)
        _ = roundTrip.debugLayout(levels)
        // Simulate the counter-scaled labels left behind by the large-text
        // viewport before the map returns to its normal height.
        roundTrip.didUpdateZoom(0.04)
        roundTrip.size = CGSize(width: 390, height: 430)
        roundTrip.fitToGraph()

        let fresh = GoldfishGraphScene(size: CGSize(width: 390, height: 430))
        fresh.didUpdateGroups(groups)
        _ = fresh.debugLayout(levels)
        fresh.fitToGraph()

        XCTAssertEqual(roundTrip.debugCameraZoom, fresh.debugCameraZoom, accuracy: 0.001)
        XCTAssertEqual(roundTrip.debugCameraPosition.x, fresh.debugCameraPosition.x, accuracy: 0.5)
        XCTAssertEqual(roundTrip.debugCameraPosition.y, fresh.debugCameraPosition.y, accuracy: 0.5)
    }

    func testPondFocusCapturesOverviewCameraAndRestoresItAfterFocus() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let first = try manager.createCircle(name: "Family")
        let second = try manager.createCircle(name: "Friends")
        let a = try manager.createPerson(name: "Alice")
        let b = try manager.createPerson(name: "Bob")
        try manager.addToCircle(a, circle: first)
        try manager.addToCircle(b, circle: second)
        let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 700))
        scene.didUpdateGroups([first, second])
        _ = scene.debugLayout([GraphLevel(depth: 0, circleGroups: [CircleGroup(circle: nil, contacts: [me, a, b])])])
        scene.didUpdateCameraPosition(CGPoint(x: 72, y: -41))
        scene.didUpdateZoom(0.74)
        let overview = (scene.debugCameraPosition, scene.debugCameraZoom)

        scene.didUpdatePondFilter(first.id.uuidString)
        XCTAssertEqual(scene.debugFocusedPondName, first.id.uuidString)
        XCTAssertEqual(scene.debugCameraBeforePondFocus?.position, overview.0)
        XCTAssertEqual(scene.debugCameraBeforePondFocus?.zoom, overview.1)
        XCTAssertTrue(scene.debugFullIdentityIDs.contains(a.id))
        XCTAssertTrue(scene.debugDimmedIDs.contains(b.id))

        scene.centerOnContact(b.id)
        XCTAssertEqual(scene.debugFocusedPondName, first.id.uuidString,
                       "Centering is a camera operation and must preserve the pond filter")
        XCTAssertEqual(scene.debugCameraBeforePondFocus?.position, overview.0)
        XCTAssertTrue(scene.debugDimmedIDs.contains(b.id))

        scene.didUpdatePondFilter(second.id.uuidString)
        XCTAssertEqual(scene.debugFocusedPondName, second.id.uuidString)
        XCTAssertTrue(scene.debugFullIdentityIDs.contains(b.id))
        XCTAssertTrue(scene.debugDimmedIDs.contains(a.id))

        scene.didUpdatePondFilter(nil)
        XCTAssertNil(scene.debugFocusedPondName)
        XCTAssertEqual(scene.debugCameraPosition, overview.0)
        XCTAssertEqual(scene.debugCameraZoom, overview.1)
        XCTAssertNil(scene.debugCameraBeforePondFocus)
    }

    func testDisclosureStartsWithMeAndDirectContactsOnly() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let david = try manager.createPerson(name: "David")
        let lisa = try manager.createPerson(name: "Lisa")
        let chris = try manager.createPerson(name: "Chris")
        try manager.createRelationship(from: me, to: david, type: .friend)
        try manager.createRelationship(from: david, to: lisa, type: .friend)
        try manager.createRelationship(from: david, to: chris, type: .friend)
        let contacts = [me, david, lisa, chris]
        let levels = [GraphLevel(depth: 0, circleGroups: [CircleGroup(circle: nil, contacts: contacts)])]
        let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 700))
        _ = scene.debugLayout(levels)
        scene.didUpdateDisclosure(PondDisclosureSnapshot(
            visibleIDs: [me.id, david.id], directIDs: [david.id], expandedIDs: [], selectedID: nil,
            trail: [], hiddenNeighborCounts: [david.id: 2], hiddenByPond: [:], unlinkedIDs: [],
            revealedEdges: [PondDisclosureEdge(from: me.id, to: david.id)], parents: [david.id: me.id]
        ))
        XCTAssertEqual(scene.debugDisclosureVisibleIDs, [me.id, david.id])
        XCTAssertEqual(scene.debugRenderedVisibleIDs, [david.id])
        XCTAssertFalse(scene.debugDisclosureVisibleIDs.contains(lisa.id))
        XCTAssertFalse(scene.debugDisclosureVisibleIDs.contains(chris.id))
        XCTAssertEqual(scene.debugDisclosureHiddenCounts[david.id], 2)
    }

    func testDisclosureExpansionKeepsDavidAnchoredAndCollapseRestoresVisibility() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let david = try manager.createPerson(name: "David")
        let lisa = try manager.createPerson(name: "Lisa")
        let chris = try manager.createPerson(name: "Chris")
        let family = try manager.createCircle(name: "Family")
        let friends = try manager.createCircle(name: "Friends")
        try manager.addToCircle(david, circle: family)
        try manager.addToCircle(lisa, circle: family)
        try manager.addToCircle(chris, circle: friends)
        try manager.createRelationship(from: me, to: david, type: .friend)
        try manager.createRelationship(from: david, to: lisa, type: .friend)
        try manager.createRelationship(from: david, to: chris, type: .friend)
        let contacts = [me, david, lisa, chris]
        let levels = [GraphLevel(depth: 0, circleGroups: [CircleGroup(circle: nil, contacts: contacts)])]
        let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 700))
        scene.didUpdateGroups([family, friends])
        _ = scene.debugLayout(levels)
        let initial = PondDisclosureSnapshot(visibleIDs: [me.id, david.id], directIDs: [david.id], expandedIDs: [], selectedID: nil,
            trail: [], hiddenNeighborCounts: [david.id: 2], hiddenByPond: [:], unlinkedIDs: [],
            revealedEdges: [PondDisclosureEdge(from: me.id, to: david.id)], parents: [david.id: me.id])
        scene.didUpdateDisclosure(initial)
        // Capture the actual direct-first overview after its initial fit.
        // Subsequent branch interactions must preserve both geometry and camera.
        let davidPosition = scene.debugNodePositions[david.id]
        let overviewPositions = scene.debugNodePositions
        let overviewCamera = (scene.debugCameraPosition, scene.debugCameraZoom)
        let overviewPonds = scene.debugGroupMembers
        let overviewBasins = scene.debugPondGeometryBounds
        scene.didUpdateDisclosure(PondDisclosureSnapshot(visibleIDs: [me.id, david.id, lisa.id, chris.id], directIDs: [david.id], expandedIDs: [david.id], selectedID: david.id,
            trail: [me.id, david.id], hiddenNeighborCounts: [:], hiddenByPond: [:], unlinkedIDs: [],
            revealedEdges: [PondDisclosureEdge(from: me.id, to: david.id), PondDisclosureEdge(from: david.id, to: lisa.id), PondDisclosureEdge(from: david.id, to: chris.id)], parents: [david.id: me.id, lisa.id: david.id, chris.id: david.id]))
        XCTAssertEqual(scene.debugNodePositions[david.id], davidPosition)
        XCTAssertEqual(scene.debugNodePositions, overviewPositions)
        XCTAssertEqual(scene.debugCameraPosition, overviewCamera.0)
        XCTAssertEqual(scene.debugCameraZoom, overviewCamera.1, accuracy: 0.000001)
        XCTAssertEqual(scene.debugGroupMembers, overviewPonds)
        XCTAssertEqual(scene.debugPondGeometryBounds, overviewBasins)
        XCTAssertEqual(scene.debugDisclosureVisibleIDs, [me.id, david.id, lisa.id, chris.id])
        scene.didUpdateDisclosure(initial)
        XCTAssertEqual(scene.debugNodePositions[david.id], davidPosition)
        XCTAssertEqual(scene.debugNodePositions, overviewPositions)
        XCTAssertEqual(scene.debugCameraPosition, overviewCamera.0)
        XCTAssertEqual(scene.debugCameraZoom, overviewCamera.1, accuracy: 0.000001)
        XCTAssertEqual(scene.debugGroupMembers, overviewPonds)
        XCTAssertEqual(scene.debugPondGeometryBounds, overviewBasins)
        XCTAssertFalse(scene.debugDisclosureVisibleIDs.contains(lisa.id))
        XCTAssertFalse(scene.debugDisclosureVisibleIDs.contains(chris.id))
    }

    func testDisclosureSnapshotBeforeSceneMountIsAppliedAfterGraphMount() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let david = try manager.createPerson(name: "David")
        let lisa = try manager.createPerson(name: "Lisa")
        try manager.createRelationship(from: me, to: david, type: .friend)
        try manager.createRelationship(from: david, to: lisa, type: .friend)
        let contacts = [me, david, lisa]
        let levels = [GraphLevel(depth: 0, circleGroups: [CircleGroup(circle: nil, contacts: contacts)])]
        let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 440))
        scene.didUpdateDisclosure(PondDisclosureSnapshot(visibleIDs: [me.id, david.id, lisa.id], directIDs: [david.id], expandedIDs: [david.id], selectedID: david.id,
            trail: [me.id, david.id], hiddenNeighborCounts: [:], hiddenByPond: [:], unlinkedIDs: [], revealedEdges: [], parents: [:]))
        scene.didUpdateGraphLevels(levels)
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 390, height: 440))
        view.presentScene(scene)
        XCTAssertEqual(scene.debugDisclosureVisibleIDs, [me.id, david.id, lisa.id])
        XCTAssertTrue(scene.debugDisclosureExpandedIDs.contains(david.id))
        XCTAssertEqual(scene.debugRenderedVisibleIDs, [david.id, lisa.id])
    }

    func testDisclosureContextUsesReciprocalRoleAndAge() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let david = try manager.createPerson(name: "David")
        let birthday = Calendar.current.date(byAdding: .year, value: -9, to: Date())!
        let lisa = try manager.createPerson(name: "Lisa", birthday: birthday)
        try manager.createRelationship(from: me, to: david, type: .friend)
        try manager.createRelationship(from: david, to: lisa, type: .parent)
        let levels = [GraphLevel(depth: 0, circleGroups: [CircleGroup(circle: nil, contacts: [me, david, lisa])])]
        let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 700))
        _ = scene.debugLayout(levels)
        let disclosure = PondDisclosure(people: [me, david, lisa])
        // The initial state is direct-only; this snapshot models David's
        // branch after the scene tap has asked the service to expand it.
        var expanded = disclosure
        expanded.togglePondConnections(id: david.id)
        expanded.selectPondContact(id: david.id)
        scene.didUpdateDisclosure(expanded.snapshot)
        XCTAssertNil(scene.debugDisclosureRoleLabels[me.id])
        XCTAssertEqual(scene.debugDisclosureRoleLabels[lisa.id], "Child · Age 9")
        XCTAssertEqual(scene.debugDisclosureIdentityLabels[lisa.id], "Lisa")
    }

    func testFocusedSmallDisclosureKeepsBranchNamesWhenGlobalGraphIsDense() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let david = try manager.createPerson(name: "David")
        let lisa = try manager.createPerson(name: "Lisa Longsurname")
        let chris = try manager.createPerson(name: "Chris Longsurname")
        let professional = try manager.createCircle(name: "Professional")
        let friends = try manager.createCircle(name: "Friends")
        for person in [david, lisa, chris] { try manager.addToCircle(person, circle: professional) }
        var others: [Person] = []
        for index in 0..<6 {
            let person = try manager.createPerson(name: "Friend \(index)")
            try manager.addToCircle(person, circle: friends)
            others.append(person)
        }
        try manager.createRelationship(from: me, to: david, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: david, to: lisa, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: david, to: chris, type: .friend, skipAutoAssign: true)
        let contacts = [me, david, lisa, chris] + others
        let levels = [GraphLevel(depth: 0, circleGroups: [CircleGroup(circle: nil, contacts: contacts)])]
        let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 360))
        scene.didUpdateGroups([professional, friends])
        _ = scene.debugLayout(levels)
        scene.didUpdateDisclosure(PondDisclosureSnapshot(
            visibleIDs: Set(contacts.map(\.id)), directIDs: [david.id], expandedIDs: [david.id], selectedID: david.id,
            trail: [me.id, david.id], hiddenNeighborCounts: [:], hiddenByPond: [:], unlinkedIDs: Set(others.map(\.id)),
            revealedEdges: [PondDisclosureEdge(from: me.id, to: david.id), PondDisclosureEdge(from: david.id, to: lisa.id), PondDisclosureEdge(from: david.id, to: chris.id)],
            parents: [david.id: me.id, lisa.id: david.id, chris.id: david.id]
        ))
        scene.didUpdatePondFilter(professional.id.uuidString)
        XCTAssertEqual(scene.debugDisclosureIdentityLabels[lisa.id], "Lisa")
        XCTAssertEqual(scene.debugDisclosureIdentityLabels[chris.id], "Chris")
        XCTAssertNil(scene.debugDisclosureRoleLabels[me.id])
    }

    func testPointerActivationUsesViewModelDisclosureAndKeepsCanvasAnchored() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let david = try manager.createPerson(name: "David")
        let lisa = try manager.createPerson(name: "Lisa")
        let chris = try manager.createPerson(name: "Chris")
        let family = try manager.createCircle(name: "Family")
        let friends = try manager.createCircle(name: "Friends")
        try manager.addToCircle(david, circle: family)
        try manager.addToCircle(lisa, circle: family)
        try manager.addToCircle(chris, circle: friends)
        try manager.createRelationship(from: me, to: david, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: david, to: lisa, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: david, to: chris, type: .friend, skipAutoAssign: true)

        let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 700))
        scene.opensRipplesOnTap = true
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        view.presentScene(scene)
        let model = GraphViewModel(dataManager: manager)
        scene.graphDelegate = model
        model.sceneDelegate = scene
        model.loadGraph()

        // The test host SKView has no window, so inspect the actual node
        // visibility flags before their reveal fades have advanced.
        let initialPositions = scene.debugNodePositions
        let initialCamera = (scene.debugCameraPosition, scene.debugCameraZoom)
        XCTAssertEqual(model.pondDisclosureSnapshot.directIDs, [david.id])
        XCTAssertEqual(scene.debugRevealedNodeIDs, [david.id])
        XCTAssertNil(model.selectedContactID)

        // A normal model refresh must not re-fit the same canvas around the
        // user. This also guards the profile-dismissal refresh path.
        scene.didUpdateGraphLevels(model.graphLevels ?? [])
        XCTAssertEqual(scene.debugNodePositions, initialPositions)
        XCTAssertEqual(scene.debugCameraPosition, initialCamera.0)
        XCTAssertEqual(scene.debugCameraZoom, initialCamera.1)

        // This calls the same scene activation used by touchesEnded: it opens
        // the branch, selects David, and moves the camera to his cluster.
        scene.debugActivatePondContact(david.id)
        XCTAssertEqual(scene.debugRevealedNodeIDs, [david.id, lisa.id, chris.id])
        XCTAssertNil(model.selectedContactID)
        XCTAssertEqual(model.pondDisclosureSnapshot.focusRootID, david.id)
        let focusedCamera = (scene.debugCameraPosition, scene.debugCameraZoom)
        XCTAssertTrue(focusedCamera.0 != initialCamera.0 || focusedCamera.1 != initialCamera.1)
        XCTAssertEqual(scene.debugNodePositions, initialPositions)
        XCTAssertEqual(model.pondDisclosureSnapshot.parents[lisa.id], david.id)
        XCTAssertEqual(model.pondDisclosureSnapshot.parents[chris.id], david.id)

        // A leaf has no further branch, so the same path selects it for the
        // inline inspector while keeping the canvas and profile selection free.
        scene.debugActivatePondContact(lisa.id)
        XCTAssertEqual(model.selectedPondContactID, lisa.id)
        XCTAssertNil(model.selectedContactID)
        XCTAssertEqual(scene.debugRevealedNodeIDs, [david.id, lisa.id, chris.id])
        XCTAssertEqual(model.pondDisclosureSnapshot.focusRootID, david.id)

        // Re-activating an open contact is idempotent; it does not collapse the
        // branch or move the already framed camera.
        scene.debugActivatePondContact(david.id)
        XCTAssertTrue(scene.debugRevealedNodeIDs.contains(lisa.id))
        XCTAssertTrue(scene.debugRevealedNodeIDs.contains(chris.id))
        XCTAssertEqual(model.pondDisclosureSnapshot.directIDs, [david.id])
        XCTAssertEqual(model.pondDisclosureSnapshot.parents[david.id], me.id)
        XCTAssertNil(model.selectedContactID)
        XCTAssertEqual(scene.debugCameraPosition, focusedCamera.0)
        XCTAssertEqual(scene.debugCameraZoom, focusedCamera.1)
        view.presentScene(nil)
    }

    func testOverlappingContactTargetsOfferDeterministicChoiceWithoutChangingRoute() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let alex = try manager.createPerson(name: "Alex")
        let blair = try manager.createPerson(name: "Blair")
        try manager.createRelationship(from: me, to: alex, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: me, to: blair, type: .friend, skipAutoAssign: true)
        let model = GraphViewModel(dataManager: manager)
        let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 700))
        scene.graphDelegate = model
        model.sceneDelegate = scene
        model.loadGraph()
        _ = scene.debugLayout(model.graphLevels ?? [])
        scene.didUpdateDisclosure(model.disclosureSnapshot)
        let overlap = CGPoint(x: 140, y: 120)
        scene.debugSetContactPosition(overlap, for: alex.id)
        scene.debugSetContactPosition(overlap, for: blair.id)
        let route = model.disclosureTrail

        let candidates = scene.debugContactCandidateIDs(at: overlap)
        XCTAssertEqual(Set(candidates), [alex.id, blair.id])
        XCTAssertTrue(scene.debugPresentContactChoice(at: overlap))
        XCTAssertEqual(model.pendingContactChoiceIDs, candidates)
        XCTAssertEqual(model.disclosureTrail, route)
        XCTAssertNil(model.selectedPondContactID)

        model.choosePendingContact(alex.id)
        XCTAssertEqual(model.selectedPondContactID, alex.id)
        XCTAssertTrue(model.pendingContactChoiceIDs.isEmpty)
    }

    func testOffscreenRevealQueryDoesNotMoveCameraUntilLocateIsRequested() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let person = try manager.createPerson(name: "Distant")
        try manager.createRelationship(from: me, to: person, type: .friend, skipAutoAssign: true)
        let levels = [GraphLevel(depth: 0, circleGroups: [CircleGroup(circle: nil, contacts: [me, person])])]
        let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 700))
        _ = scene.debugLayout(levels)
        let disclosure = PondDisclosure(people: [me, person])
        scene.didUpdateDisclosure(disclosure.snapshot)
        scene.debugSetContactPosition(CGPoint(x: 2_000, y: 1_500), for: person.id)
        let camera = (scene.debugCameraPosition, scene.debugCameraZoom)

        XCTAssertEqual(scene.offscreenContactIDs([person.id]), [person.id])
        XCTAssertEqual(scene.debugCameraPosition, camera.0)
        XCTAssertEqual(scene.debugCameraZoom, camera.1)

        scene.locateContacts([person.id])
        XCTAssertNotEqual(scene.debugCameraPosition, camera.0)
        XCTAssertFalse(scene.offscreenContactIDs([person.id]).contains(person.id))
    }

    func testOffscreenRevealQueryUsesRenderedScaleDuringZoomAnimation() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let person = try manager.createPerson(name: "Edge")
        try manager.createRelationship(from: me, to: person, type: .friend, skipAutoAssign: true)
        let levels = [GraphLevel(depth: 0, circleGroups: [CircleGroup(circle: nil, contacts: [me, person])])]
        let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 700))
        let view = SKView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        view.presentScene(scene)
        _ = scene.debugLayout(levels)
        scene.didUpdateDisclosure(PondDisclosure(people: [me, person]).snapshot)
        let camera = scene.debugCameraPosition
        let renderedZoom = scene.debugCameraZoom
        let renderedHalfWidth = scene.size.width / (2 * renderedZoom)
        scene.debugSetContactPosition(
            CGPoint(x: camera.x + renderedHalfWidth + 60, y: camera.y),
            for: person.id
        )

        // With no host window the SpriteKit action has not advanced: the map is
        // still rendered at its fitted zoom even though currentZoom is already
        // the wider destination.
        let targetZoom = renderedZoom / 2
        scene.didUpdateZoom(targetZoom)
        XCTAssertEqual(scene.debugCameraZoom, targetZoom)
        XCTAssertEqual(scene.offscreenContactIDs([person.id]), [person.id])
        view.presentScene(nil)
    }

    func testNilPondFilterKeepsOverviewModeAndDoesNotCaptureFocusState() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let person = try manager.createPerson(name: "Person")
        let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 700))
        _ = scene.debugLayout([GraphLevel(depth: 0, circleGroups: [CircleGroup(circle: nil, contacts: [me, person])])])
        scene.didUpdatePondFilter(nil)
        XCTAssertNil(scene.debugFocusedPondName)
        XCTAssertNil(scene.debugCameraBeforePondFocus)
    }

    func testFarZoomKeepsCompactIdentityTokensVisible() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let person = try manager.createPerson(name: "Alex Jordan")
        let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 700))
        _ = scene.debugLayout([GraphLevel(depth: 0, circleGroups: [CircleGroup(circle: nil, contacts: [me, person])])])
        scene.didUpdateZoom(0.05)
        XCTAssertTrue(scene.debugCompactIdentityIDs.contains(person.id))
    }

    func testSelectedPersonUsesFullMeasuredLabelAndClears() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let person = try manager.createPerson(name: "Alexandra Jordan")
        let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 700))
        _ = scene.debugLayout([GraphLevel(depth: 0, circleGroups: [CircleGroup(circle: nil, contacts: [me, person])])])
        scene.didSelectContact(person.id)
        XCTAssertEqual(scene.debugSelectedLabelText, "Alexandra Jordan")
        scene.didSelectContact(nil)
        XCTAssertNil(scene.debugSelectedLabelText)
    }

    func testCompactOverviewUsesTokensAndSeparatesPondSignage() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let previousTrait = GraphInk.traitForResolution
        defer { GraphInk.traitForResolution = previousTrait }
        GraphInk.traitForResolution = UITraitCollection(mutations: { traits in
            traits.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
            traits.userInterfaceStyle = .dark
        })

        let me = try manager.createPerson(name: "Me", isMe: true)
        var contacts = [me]
        var groups: [GoldfishCircle] = []
        let groupSpecs = [("Family", 8), ("Friends", 3), ("Professional", 3), ("Book Club", 3)]
        for (name, count) in groupSpecs {
            let group = try manager.createCircle(name: name)
            groups.append(group)
            for index in 0..<count {
                let person = try manager.createPerson(name: "\(name) person \(index)")
                try manager.addToCircle(person, circle: group)
                contacts.append(person)
            }
        }
        contacts.append(try manager.createPerson(name: "Priya"))

        let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 320))
        scene.didUpdateGroups(groups)
        _ = scene.debugLayout([GraphLevel(depth: 0, circleGroups: [CircleGroup(circle: nil, contacts: contacts)])])
        scene.fitToGraph()

        XCTAssertTrue(scene.debugCompactOverviewIdentity)
        XCTAssertEqual(scene.debugCompactIdentityIDs, Set(contacts.dropFirst().map(\.id)))
        XCTAssertEqual(scene.debugPondLabelBounds.count, 5)
        let headingBounds = Array(scene.debugPondLabelBounds.values)
        let identityBounds = Array(scene.debugVisibleIdentityBounds.values)
        for (index, first) in headingBounds.enumerated() {
            for second in headingBounds.dropFirst(index + 1) {
                XCTAssertFalse(first.intersects(second), "Pond headings must not collide in compact overview")
            }
        }
        for heading in headingBounds {
            for identity in identityBounds {
                XCTAssertFalse(heading.intersects(identity), "Pond heading must not occlude an identity token")
            }
        }
        assertPresentedPondsDoNotOverlap(scene)

        scene.didSelectContact(contacts[1].id)
        XCTAssertEqual(scene.debugSelectedLabelText, contacts[1].name)
    }

}

@MainActor
final class PondRepositionTests: XCTestCase {
    private func isolatedLayoutStore() -> (PondLayoutStore, UserDefaults, String) {
        let suiteName = "GoldfishPondRepositionTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (PondLayoutStore(defaults: defaults), defaults, suiteName)
    }

    func testPondOffsetsPersistAcrossModelRestartAndRemainScopedByMode() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let (store, defaults, suiteName) = isolatedLayoutStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstModel = GraphViewModel(dataManager: manager, pondLayoutStore: store)
        let personalOffset = CGPoint(x: 81.5, y: -42.25)
        firstModel.savePondLayoutOffset(personalOffset, for: "family", meID: me.id)
        XCTAssertEqual(firstModel.pondLayoutOffsets(forMeID: me.id)["family"], personalOffset)

        let relaunchedModel = GraphViewModel(dataManager: manager, pondLayoutStore: store)
        XCTAssertEqual(relaunchedModel.pondLayoutOffsets(forMeID: me.id)["family"], personalOffset)
        XCTAssertNil(relaunchedModel.pondLayoutOffsets(forMeID: UUID())["family"],
                     "Another Me identity must have an independent layout")
        relaunchedModel.isDemoMode = true
        XCTAssertNil(relaunchedModel.pondLayoutOffsets(forMeID: me.id)["family"],
                     "Demo mode must not load a personal pond translation")
        let demoOffset = CGPoint(x: -17, y: 66)
        relaunchedModel.savePondLayoutOffset(demoOffset, for: "family", meID: me.id)
        XCTAssertEqual(relaunchedModel.pondLayoutOffsets(forMeID: me.id)["family"], demoOffset)
        relaunchedModel.isDemoMode = false
        XCTAssertEqual(relaunchedModel.pondLayoutOffsets(forMeID: me.id)["family"], personalOffset,
                       "Returning to personal mode must retain its own pond translation")
    }

    private func makeMovablePondGraph() throws -> (
        ModelContainer, GoldfishDataManager, GraphViewModel, GoldfishGraphScene,
        Person, GoldfishCircle, GoldfishCircle, Person, Person, Person, Person,
        PondLayoutStore, UserDefaults, String
    ) {
        let container = try makeTestContainer()
        let manager = GoldfishDataManager(context: container.mainContext)
        let me = try manager.createPerson(name: "Me", isMe: true)
        let family = try manager.createCircle(name: "Family")
        let friends = try manager.createCircle(name: "Friends")
        let alice = try manager.createPerson(name: "Alice")
        let bob = try manager.createPerson(name: "Bob")
        let hidden = try manager.createPerson(name: "Hidden family member")
        let outsider = try manager.createPerson(name: "Friend")
        for person in [alice, bob, hidden] { try manager.addToCircle(person, circle: family) }
        try manager.addToCircle(outsider, circle: friends)
        try manager.createRelationship(from: me, to: alice, type: .friend)
        try manager.createRelationship(from: me, to: bob, type: .friend)
        try manager.createRelationship(from: me, to: outsider, type: .friend)
        try manager.createRelationship(from: alice, to: bob, type: .friend)
        try manager.createRelationship(from: bob, to: hidden, type: .friend)

        let (store, defaults, suiteName) = isolatedLayoutStore()
        // The returned defaults object is retained by the store. A unique suite
        // prevents test state from touching the user's standard preferences.
        let model = GraphViewModel(dataManager: manager, pondLayoutStore: store)
        let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 700))
        scene.graphDelegate = model
        model.sceneDelegate = scene
        model.loadGraph()
        _ = scene.debugLayout(model.graphLevels ?? [])
        scene.setPondLayoutOffsets(model.pondLayoutOffsets(forMeID: me.id))
        model.activatePondContact(id: alice.id)
        return (container, manager, model, scene, me, family, friends, alice, bob, hidden, outsider,
                store, defaults, suiteName)
    }

    func testLatentDaycareSlotsStayCanonicalWhenSavedOffsetSurvivesGraphReload() throws {
        let container = try makeTestContainer()
        defer { withExtendedLifetime(container) {} }
        let manager = GoldfishDataManager(context: container.mainContext)
        let me = try manager.createPerson(name: "Me", isMe: true)
        let direct = try manager.createPerson(name: "Adriana")
        let daycareMember = try manager.createPerson(name: "Riley")
        let family = try manager.createCircle(name: "Family")
        let daycare = try manager.createCircle(name: "Daycare")
        try manager.addToCircle(direct, circle: family)
        try manager.addToCircle(daycareMember, circle: daycare)
        try manager.createRelationship(from: me, to: direct, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: direct, to: daycareMember, type: .friend, skipAutoAssign: true)
        XCTAssertFalse(me.allRelationships.contains { $0.toContact.id == daycareMember.id || $0.fromContact.id == daycareMember.id },
                       "The Daycare member must not be a direct Me neighbor")

        let suiteName = "GoldfishLatentPondLayoutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PondLayoutStore(defaults: defaults)
        let model = GraphViewModel(dataManager: manager, pondLayoutStore: store)
        let scene = GoldfishGraphScene(size: CGSize(width: 390, height: 700))
        scene.graphDelegate = model
        model.sceneDelegate = scene
        model.loadGraph()
        let levels = try XCTUnwrap(model.graphLevels)
        XCTAssertTrue(model.disclosureSnapshot.directIDs.contains(direct.id))
        XCTAssertFalse(model.disclosureSnapshot.directIDs.contains(daycareMember.id))

        let canonicalBefore = scene.debugLayout(levels)
        let canonicalDaycareSlot = try XCTUnwrap(canonicalBefore[daycareMember.id])
        let offset = CGPoint(x: 72, y: -41)
        model.savePondLayoutOffset(offset, for: daycare.id.uuidString, meID: me.id)
        scene.setPondLayoutOffsets(model.pondLayoutOffsets(forMeID: me.id))
        XCTAssertEqual(scene.debugPondOffsets[daycare.id.uuidString], offset)
        let movedDaycarePosition = try XCTUnwrap(scene.debugNodePositions[daycareMember.id])
        XCTAssertEqual(movedDaycarePosition.x, canonicalDaycareSlot.x + offset.x, accuracy: 0.0001)
        XCTAssertEqual(movedDaycarePosition.y, canonicalDaycareSlot.y + offset.y, accuracy: 0.0001)

        let canonicalWithOffset = scene.debugLayout(levels)
        XCTAssertEqual(canonicalWithOffset.count, canonicalBefore.count)
        for id in canonicalBefore.keys {
            let before = try XCTUnwrap(canonicalBefore[id])
            let after = try XCTUnwrap(canonicalWithOffset[id])
            XCTAssertEqual(after.x, before.x, accuracy: 0.0001,
                           "Saved pond translations must not alter canonical x slots")
            XCTAssertEqual(after.y, before.y, accuracy: 0.0001,
                           "Saved pond translations must not alter canonical y slots")
        }

        let actualBeforeReload = scene.debugNodePositions
        scene.debugReloadGraph(levels)
        XCTAssertEqual(scene.debugPondOffsets[daycare.id.uuidString], offset)
        for id in actualBeforeReload.keys {
            let before = try XCTUnwrap(actualBeforeReload[id])
            let after = try XCTUnwrap(scene.debugNodePositions[id])
            XCTAssertEqual(after.x, before.x, accuracy: 0.0001,
                           "Graph reload must reapply the saved offset exactly once")
            XCTAssertEqual(after.y, before.y, accuracy: 0.0001,
                           "Graph reload must preserve actual position for every node")
        }
    }

    func testPondDragMovesHiddenMembersAndKeepsLabelsOutlinesAndRelationshipsAttached() throws {
        let (container, manager, model, scene, me, family, friends, alice, bob, hidden, outsider,
             store, defaults, suiteName) = try makeMovablePondGraph()
        defer { withExtendedLifetime(container) {} }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let familyID = family.id.uuidString
        let friendsID = friends.id.uuidString
        XCTAssertFalse(scene.debugDisclosureVisibleIDs.contains(hidden.id), "Fixture must include a hidden pond member")
        XCTAssertTrue(scene.debugVisibleEdgeCount > 0, "Fixture must render a relationship inside the moved pond")

        let beforePositions = scene.debugNodePositions
        let beforeLabel = try XCTUnwrap(scene.debugPondLabelBounds[familyID])
        let beforeBasin = try XCTUnwrap(scene.debugPondBasinBounds[familyID])
        let beforeOtherLabel = try XCTUnwrap(scene.debugPondLabelBounds[friendsID])
        let beforeOtherBasin = try XCTUnwrap(scene.debugPondBasinBounds[friendsID])
        let edgeID = [alice.id.uuidString, bob.id.uuidString].sorted().joined(separator: "_")
        let beforeEdge = try XCTUnwrap(scene.debugEdgePaths[edgeID]?.boundingBoxOfPath)
        let delta = CGPoint(x: 53, y: -29)
        XCTAssertTrue(scene.debugBeginPondDrag(pondID: familyID, at: .zero))
        scene.debugUpdatePondDrag(to: delta)
        XCTAssertEqual(scene.debugPondOffsets[familyID], delta)

        for id in [alice.id, bob.id, hidden.id] {
            let before = try XCTUnwrap(beforePositions[id])
            let after = try XCTUnwrap(scene.debugNodePositions[id])
            XCTAssertEqual(after.x - before.x, delta.x, accuracy: 0.001)
            XCTAssertEqual(after.y - before.y, delta.y, accuracy: 0.001)
        }
        for id in [me.id, outsider.id] {
            XCTAssertEqual(scene.debugNodePositions[id], beforePositions[id], "Contacts outside the moved pond stay fixed")
        }
        let movedLabel = try XCTUnwrap(scene.debugPondLabelBounds[familyID])
        let movedBasin = try XCTUnwrap(scene.debugPondBasinBounds[familyID])
        XCTAssertEqual(movedLabel.midX - beforeLabel.midX, delta.x, accuracy: 0.5)
        XCTAssertEqual(movedLabel.midY - beforeLabel.midY, delta.y, accuracy: 0.5)
        XCTAssertEqual(movedBasin.midX - beforeBasin.midX, delta.x, accuracy: 0.5)
        XCTAssertEqual(movedBasin.midY - beforeBasin.midY, delta.y, accuracy: 0.5)
        XCTAssertEqual(scene.debugPondLabelBounds[friendsID], beforeOtherLabel)
        XCTAssertEqual(scene.debugPondBasinBounds[friendsID], beforeOtherBasin)
        let movedEdge = try XCTUnwrap(scene.debugEdgePaths[edgeID]?.boundingBoxOfPath)
        XCTAssertEqual(movedEdge.midX - beforeEdge.midX, delta.x, accuracy: 0.5,
                       "Relationship paths must follow their translated pond members")
        XCTAssertEqual(movedEdge.midY - beforeEdge.midY, delta.y, accuracy: 0.5)

        let movedPositions = scene.debugNodePositions
        scene.didUpdateDisclosure(model.disclosureSnapshot)
        XCTAssertEqual(scene.debugNodePositions, movedPositions,
                       "A disclosure redraw reapplies the same offset without accumulating it")
        scene.debugEndPondDrag()
        XCTAssertEqual(model.pondLayoutOffsets(forMeID: me.id)[familyID], delta)
        XCTAssertEqual(alice.primaryCircle?.id, family.id)
        XCTAssertEqual(bob.primaryCircle?.id, family.id)
        XCTAssertNil(model.pendingPondMovePerson)
        XCTAssertNil(model.pendingPondMoveTarget)

        let relaunchedModel = GraphViewModel(dataManager: manager, pondLayoutStore: store)
        let relaunchedScene = GoldfishGraphScene(size: CGSize(width: 390, height: 700))
        relaunchedScene.graphDelegate = relaunchedModel
        relaunchedModel.sceneDelegate = relaunchedScene
        relaunchedModel.loadGraph()
        relaunchedScene.debugReloadGraph(relaunchedModel.graphLevels ?? [])
        relaunchedModel.activatePondContact(id: alice.id)
        XCTAssertEqual(relaunchedModel.pondLayoutOffsets(forMeID: me.id)[familyID], delta)
        for id in [alice.id, bob.id, hidden.id] {
            let before = try XCTUnwrap(movedPositions[id])
            let after = try XCTUnwrap(relaunchedScene.debugNodePositions[id])
            XCTAssertEqual(after.x, before.x, accuracy: 0.001)
            XCTAssertEqual(after.y, before.y, accuracy: 0.001,
                           "Reloading the graph applies the saved offset exactly once")
        }
    }

    func testCancelledPondDragRollsBackWithoutSavingAndResetRestoresAutomaticLayout() throws {
        let (container, _, model, scene, me, family, _, alice, bob, hidden, _, _, defaults, suiteName) = try makeMovablePondGraph()
        defer { withExtendedLifetime(container) {} }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let familyID = family.id.uuidString
        let automaticPositions = scene.debugNodePositions
        let firstOffset = CGPoint(x: 15, y: -8)
        XCTAssertTrue(scene.debugBeginPondDrag(pondID: familyID, at: .zero))
        scene.debugUpdatePondDrag(to: firstOffset)
        scene.debugEndPondDrag()
        XCTAssertEqual(model.pondLayoutOffsets(forMeID: me.id)[familyID], firstOffset)
        let savedPositions = scene.debugNodePositions

        let delta = CGPoint(x: -34, y: 47)
        XCTAssertTrue(scene.debugBeginPondDrag(pondID: familyID, at: .zero))
        scene.debugUpdatePondDrag(to: CGPoint(x: CGFloat.nan, y: 0))
        scene.debugUpdatePondDrag(to: CGPoint(x: CGFloat.infinity, y: 0))
        XCTAssertEqual(scene.debugNodePositions, savedPositions,
                       "Non-finite drag updates must leave the saved position intact")
        scene.debugUpdatePondDrag(to: delta)
        scene.debugCancelPondDrag()
        XCTAssertEqual(scene.debugNodePositions, savedPositions)
        XCTAssertEqual(scene.debugPondOffsets[familyID], firstOffset)
        XCTAssertEqual(model.pondLayoutOffsets(forMeID: me.id)[familyID], firstOffset,
                       "A cancelled second drag must preserve the earlier saved translation")

        XCTAssertTrue(scene.debugBeginPondDrag(pondID: familyID, at: .zero))
        scene.debugUpdatePondDrag(to: delta)
        scene.debugEndPondDrag()
        XCTAssertNotEqual(scene.debugNodePositions, automaticPositions)
        model.restoreAutomaticPondLayout()
        XCTAssertEqual(model.pondLayoutOffsets(forMeID: me.id), [:])
        for id in [alice.id, bob.id, hidden.id] {
            XCTAssertEqual(scene.debugNodePositions[id], automaticPositions[id], "Reset returns every pond member to its automatic slot")
        }
    }
}
