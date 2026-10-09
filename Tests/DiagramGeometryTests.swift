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
        let basinCenter = basins.reduce(DiagramGeometry.Point.zero) {
            DiagramGeometry.Point(x: $0.x + $1.center.x, y: $0.y + $1.center.y)
        }
        XCTAssertEqual(basinCenter.x / Double(basins.count), 0, accuracy: 0.000001,
                       "The composition should be centered on its ponds rather than reserving the origin for Me")
        XCTAssertEqual(basinCenter.y / Double(basins.count), 0, accuracy: 0.000001,
                       "The composition should be centered on its ponds rather than reserving the origin for Me")
        for (i, a) in basins.enumerated() {
            XCTAssertTrue(a.center.x.isFinite && a.center.y.isFinite)
            for b in basins.dropFirst(i + 1) {
                XCTAssertGreaterThanOrEqual(hypot(a.center.x - b.center.x, a.center.y - b.center.y),
                                             (a.radius + b.radius) * 1.08 + 240,
                                             "Unequal ponds need enough center separation for their actual radii")
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
                XCTAssertGreaterThanOrEqual(hypot(point.x - other.x, point.y - other.y), 299.9)
            }
        }
    }

    func testThreeToFivePondMapsUseBalancedCompactOrbits() {
        for pondCount in 3...5 {
            // The 50-contact fixture's largest three ponds plus an expanded
            // Daycare branch exercise the uneven sizes seen in actual maps.
            let groups = (0..<pondCount).map { index in
                let members = (0..<([7, 4, 39, 4, 3][index])).map { _ in UUID() }
                let names = ["Family", "Friends", "Community Choir", "Expanded-Daycare", "Book Club"]
                return DiagramGeometry.Group(id: names[index], members: members)
            }
            let composition = DiagramGeometry.radial(groups)
            let basins = groups.compactMap { composition.basins[$0.id] }
            let mean = basins.reduce(DiagramGeometry.Point.zero) {
                DiagramGeometry.Point(x: $0.x + $1.center.x, y: $0.y + $1.center.y)
            }
            XCTAssertEqual(mean.x / Double(pondCount), 0, accuracy: 0.000001)
            XCTAssertEqual(mean.y / Double(pondCount), 0, accuracy: 0.000001)

            XCTAssertLessThan(hypot(basins[0].center.x, basins[0].center.y),
                              outerRadiiMean(basins),
                              "A small map should retain a central pond")
            let outerRadii = basins.dropFirst().map { hypot($0.center.x, $0.center.y) }
            XCTAssertGreaterThan(outerRadii.min() ?? 0, hypot(basins[0].center.x, basins[0].center.y))
            for (index, basin) in basins.enumerated() {
                for other in basins.dropFirst(index + 1) {
                    XCTAssertGreaterThanOrEqual(
                        hypot(basin.center.x - other.center.x, basin.center.y - other.center.y),
                        (basin.radius + other.radius) * 1.08 + 240,
                        "Unequal ponds need enough room for their contact labels and titles"
                    )
                }
            }
        }
    }

    private func outerRadiiMean(_ basins: [DiagramGeometry.Basin]) -> Double {
        let radii = basins.dropFirst().map { hypot($0.center.x, $0.center.y) }
        return radii.reduce(0, +) / Double(max(radii.count, 1))
    }

    func testThreePondsFormAnIrregularTriangleInsteadOfAVerticalStack() {
        let groups = (0..<3).map { DiagramGeometry.Group(id: "pond-\($0)", members: [UUID()]) }
        let composition = DiagramGeometry.radial(groups)
        let centers = groups.compactMap { composition.basins[$0.id]?.center }
        XCTAssertEqual(centers.count, 3)
        XCTAssertGreaterThan(abs(centers[1].x - centers[2].x), 200)
        let area = abs((centers[1].x - centers[0].x) * (centers[2].y - centers[0].y) -
                       (centers[2].x - centers[0].x) * (centers[1].y - centers[0].y))
        XCTAssertGreaterThan(area, 1_000)
    }

    func testRelatedPondsOccupyNeighboringOrbitSlots() {
        let groups = (0..<7).map { DiagramGeometry.Group(id: "pond-\($0)", members: [UUID()]) }
        let composition = DiagramGeometry.radial(groups, relatedPonds: [("pond-1", "pond-6")])
        let first = composition.basins["pond-1"]!.center
        let related = composition.basins["pond-6"]!.center
        let unrelated = composition.basins["pond-4"]!.center
        XCTAssertLessThan(hypot(first.x - related.x, first.y - related.y),
                          hypot(first.x - unrelated.x, first.y - unrelated.y))
    }

    func testEquivalentNamedPondsKeepPositionsAcrossFreshIdentifiers() {
        let titles = ["Family", "Friends", "Daycare", "Book Club"]
        func layout() -> [DiagramGeometry.Basin] {
            let groups = titles.map { title in
                DiagramGeometry.Group(id: UUID().uuidString, members: [UUID()], seed: title)
            }
            let composition = DiagramGeometry.radial(groups)
            return groups.compactMap { composition.basins[$0.id] }
        }
        let first = layout(), second = layout()
        XCTAssertEqual(first.count, second.count)
        for (a, b) in zip(first, second) {
            XCTAssertEqual(a.center.x, b.center.x, accuracy: 0.000001)
            XCTAssertEqual(a.center.y, b.center.y, accuracy: 0.000001)
        }
    }

    func testTwentyThreeContactSampleCompositionUsesItsWholePopulation() {
        let sizes = [5, 7, 3, 3, 4, 1] // Family, Friends, Professional, Book Club, Daycare, unassigned
        let groups = sizes.enumerated().map { index, count in
            DiagramGeometry.Group(id: "sample-\(index)", members: (0..<count).map { _ in UUID() })
        }
        let composition = DiagramGeometry.radial(groups)

        XCTAssertEqual(composition.slots.count, 23)
        XCTAssertEqual(composition.basins.count, sizes.count)
        let basins = groups.compactMap { composition.basins[$0.id] }
        let center = basins.reduce(DiagramGeometry.Point.zero) {
            DiagramGeometry.Point(x: $0.x + $1.center.x, y: $0.y + $1.center.y)
        }
        XCTAssertEqual(center.x / Double(basins.count), 0, accuracy: 0.000001)
        XCTAssertEqual(center.y / Double(basins.count), 0, accuracy: 0.000001)
        for (index, basin) in basins.enumerated() {
            for other in basins.dropFirst(index + 1) {
                XCTAssertGreaterThanOrEqual(
                    hypot(basin.center.x - other.center.x, basin.center.y - other.center.y),
                    (basin.radius + other.radius) * 1.08 + 240,
                    "All six sample ponds need a separate title and identity area"
                )
            }
        }
    }
}
