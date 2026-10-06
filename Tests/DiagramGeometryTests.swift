import XCTest
@testable import Goldfish

final class DiagramGeometryTests: XCTestCase {
    func testEveryTrackSegmentIsOctilinear() {
        for x in stride(from: -450, through: 450, by: 37) {
            for y in stride(from: -500, through: 500, by: 43) {
                let end = DiagramGeometry.Point(x: Double(x), y: Double(y))
                let path = DiagramGeometry.octilinear(from: .zero, to: end)
                XCTAssertEqual(path.first, .zero)
                XCTAssertEqual(path.last, end)
                for (a, b) in zip(path, path.dropFirst()) {
                    let dx = abs(b.x - a.x), dy = abs(b.y - a.y)
                    XCTAssertTrue(dx < 0.000001 || dy < 0.000001 || abs(dx - dy) < 0.000001)
                }
            }
        }
    }
    func testRejectsNonfiniteTrackInput() {
        XCTAssertTrue(DiagramGeometry.octilinear(from: .init(x: .nan, y: 0), to: .zero).isEmpty)
        XCTAssertTrue(DiagramGeometry.octilinear(from: .zero, to: .init(x: 1, y: .infinity)).isEmpty)
    }
    func testDenseUnequalPondsAreDisjointAndContainTheirPeople() {
        let groups = [0, 1, 7, 8, 37, 80, 140, 250].enumerated().map { i, count in
            DiagramGeometry.Group(id: "group-\(i)", members: (0..<count).map { _ in UUID() })
        }
        let composition = DiagramGeometry.radial(groups)
        XCTAssertEqual(composition.slots.count, groups.reduce(0) { $0 + $1.members.count })
        let basins = Array(composition.basins.values)
        for (i, a) in basins.enumerated() {
            XCTAssertTrue(a.center.x.isFinite && a.center.y.isFinite)
            XCTAssertGreaterThan(hypot(a.center.x, a.center.y), a.radius + 80)
            for b in basins.dropFirst(i + 1) {
                XCTAssertGreaterThan(hypot(a.center.x - b.center.x, a.center.y - b.center.y), (a.radius + b.radius) * 1.04)
            }
        }
        for group in groups {
            let basin = composition.basins[group.id]!
            for id in group.members {
                let point = composition.slots[id]!
                // The tighter basins still reserve room for the 44-unit
                // contact medallion and its attached identity near the bank.
                XCTAssertLessThan(hypot(point.x - basin.center.x, point.y - basin.center.y), basin.radius - 80)
            }
        }
        let slots = Array(composition.slots.values)
        for (i, point) in slots.enumerated() {
            for other in slots.dropFirst(i + 1) { XCTAssertGreaterThan(hypot(point.x - other.x, point.y - other.y), 100) }
        }
    }
    func testRepeatedLayoutAndDuplicateContacts() {
        let ids = (0..<40).map { _ in UUID() }
        let a = DiagramGeometry.radial([.init(id: "a", members: ids)])
        let b = DiagramGeometry.radial([.init(id: "a", members: Array(ids.reversed()))])
        XCTAssertEqual(a.slots, b.slots)
        let shared = DiagramGeometry.radial([.init(id: "a", members: ids), .init(id: "b", members: ids)])
        XCTAssertEqual(shared.slots.count, ids.count)
        XCTAssertTrue(DiagramGeometry.radial([]).slots.isEmpty)
    }

    func testFiveContactRingLeavesRoomForPhoneWidthIdentityLabels() {
        let ids = (0..<5).map { _ in UUID() }
        let composition = DiagramGeometry.radial([.init(id: "family", members: ids)])
        let points = ids.compactMap { composition.slots[$0] }
        for (index, point) in points.enumerated() {
            for other in points.dropFirst(index + 1) {
                XCTAssertGreaterThanOrEqual(hypot(point.x - other.x, point.y - other.y), 219.9)
            }
        }
    }
}
