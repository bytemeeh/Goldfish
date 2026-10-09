import Foundation

/// Platform-independent geometry, used directly by SpriteKit and executable on Linux.
enum DiagramGeometry {
    struct Point: Hashable {
        var x: Double
        var y: Double
        static let zero = Point(x: 0, y: 0)
    }
    struct Group {
        let id: String
        let members: [UUID]
    }
    struct Basin {
        let center: Point
        let radius: Double
    }
    struct Composition {
        var slots: [UUID: Point] = [:]
        var basins: [String: Basin] = [:]
    }

    static func octilinear(from start: Point, to end: Point) -> [Point] {
        let dx = end.x - start.x, dy = end.y - start.y
        guard [dx, dy, start.x, start.y].allSatisfy(\.isFinite) else { return [] }
        let diagonal = min(abs(dx), abs(dy))
        if diagonal == 0 || abs(abs(dx) - abs(dy)) < 0.000001 { return [start, end] }
        return [start, Point(x: start.x + diagonal * (dx < 0 ? -1 : 1),
                             y: start.y + diagonal * (dy < 0 ? -1 : 1)), end]
    }

    static func radial(_ groups: [Group], minimumBasinRadius: Double = 0) -> Composition {
        guard !groups.isEmpty else { return Composition() }
        var local: [String: [UUID: Point]] = [:]
        var radii: [String: Double] = [:]
        var assigned: Set<UUID> = []
        for group in groups {
            var slots: [UUID: Point] = [:]
            let members = group.members.sorted { $0.uuidString < $1.uuidString }.filter { assigned.insert($0).inserted }
            // Leave room beneath every station for its counter-scaled name.
            // The wider rows stay legible when a portrait overview fits several
            // ponds into the same phone viewport.
            switch members.count {
            case 0:
                break
            case 1:
                slots[members[0]] = .zero
            case 2:
                slots[members[0]] = Point(x: -190, y: 0)
                slots[members[1]] = Point(x: 190, y: 0)
            case 3:
                slots[members[0]] = Point(x: 0, y: 190)
                slots[members[1]] = Point(x: -170, y: -150)
                slots[members[2]] = Point(x: 170, y: -150)
            case 4:
                slots[members[0]] = Point(x: -170, y: 205)
                slots[members[1]] = Point(x: 170, y: 205)
                slots[members[2]] = Point(x: -170, y: -205)
                slots[members[3]] = Point(x: 170, y: -205)
            case 5:
                // Stagger two rows with a full label-and-coin clearance between
                // them. Wider same-row spacing keeps centered first names apart
                // when the complete map is framed on a phone.
                slots[members[0]] = Point(x: -360, y: 250)
                slots[members[1]] = Point(x: 0, y: 250)
                slots[members[2]] = Point(x: 360, y: 250)
                slots[members[3]] = Point(x: -180, y: -250)
                slots[members[4]] = Point(x: 180, y: -250)
            case 6...12:
                let count = members.count
                let radius = 300 / (2 * sin(.pi / Double(count)))
                for (index, id) in members.enumerated() {
                    let angle = .pi / 2 + Double(index) * 2 * .pi / Double(count)
                    slots[id] = Point(x: cos(angle) * radius, y: sin(angle) * radius)
                }
            default:
                break
            }
            var index = slots.count, ring = 0
            while index < members.count {
                let capacity = ring == 0 ? 1 : ring * 6
                let used = min(capacity, members.count - index)
                for item in 0..<used {
                    let angle = Double(item) * 2 * .pi / Double(used) + Double(ring % 2) * 0.2
                    slots[members[index]] = Point(x: cos(angle) * Double(ring) * 300,
                                                 y: sin(angle) * Double(ring) * 300)
                    index += 1
                }
                ring += 1
            }
            local[group.id] = slots
            // Measure actual slots, including the outer partial ring; never estimate by count.
            radii[group.id] = max(minimumBasinRadius,
                                  (slots.values.map { hypot($0.x, $0.y) }.max() ?? 0) + 90)
        }
        // Keep a pond in the middle for small maps so the layout does not leave
        // an empty bay. The remaining ponds share a balanced outer orbit. Larger
        // maps continue outward on measured concentric rings.
        var centers: [String: Point] = [:]
        if groups.count <= 5 {
            if groups.count == 2 {
                let clearance = ((radii[groups[0].id] ?? 125) + (radii[groups[1].id] ?? 125)) * 1.08 + 240
                centers[groups[0].id] = Point(x: -clearance / 2, y: 0)
                centers[groups[1].id] = Point(x: clearance / 2, y: 0)
            } else {
                centers[groups[0].id] = .zero
            }
            if groups.count > 2 {
                let ringGroups = Array(groups.dropFirst())
                let count = ringGroups.count
                let centerRadius = radii[groups[0].id] ?? 125
                let ringRadius = ringGroups.map { radii[$0.id] ?? 125 }.max() ?? 125
                let radialClearance = (centerRadius + ringRadius) * 1.08 + 240
                let chordClearance = 2 * ringRadius * 1.08 + 240
                let orbit = count > 1
                    ? max(radialClearance, chordClearance / max(2 * sin(.pi / Double(count)), 0.001))
                    : radialClearance
                for (index, group) in ringGroups.enumerated() {
                    let angle = Double(index) * 2 * .pi / Double(count) + .pi / Double(count)
                    centers[group.id] = Point(x: cos(angle) * orbit, y: sin(angle) * orbit)
                }
            }
        } else {
            // Pack larger maps on measured concentric rings. The first pond
            // occupies the center; later rings balance the complete map around it.
            let centerRadius = radii[groups[0].id] ?? 125
            centers[groups[0].id] = .zero
            var nextIndex = 1
            var ring = 1
            var previousOrbit = 0.0
            var previousRingRadius = centerRadius
            while nextIndex < groups.count {
                let count = min(ring * 6, groups.count - nextIndex)
                let ringGroups = Array(groups[nextIndex..<(nextIndex + count)])
                let ringRadius = ringGroups.map { radii[$0.id] ?? 125 }.max() ?? 125
                let radialClearance = previousOrbit + (previousRingRadius + ringRadius) * 1.08 + 240
                let chordClearance = 2 * ringRadius * 1.08 + 240
                let orbitForRing = count > 1
                    ? chordClearance / max(2 * sin(.pi / Double(count)), 0.001)
                    : radialClearance
                let orbit = max(radialClearance, orbitForRing)
                for (item, group) in ringGroups.enumerated() {
                    let angle = Double(item) * 2 * .pi / Double(count) + Double(ring % 2) * .pi / Double(count)
                    centers[group.id] = Point(x: cos(angle) * orbit, y: sin(angle) * orbit)
                }
                previousOrbit = orbit
                previousRingRadius = ringRadius
                nextIndex += count
                ring += 1
            }
        }
        // Center the packed composition as a whole. Translation preserves all
        // clearances and makes the initial camera fit independent of Me's slot.
        let centerX = groups.compactMap { centers[$0.id]?.x }.reduce(0, +) / Double(groups.count)
        let centerY = groups.compactMap { centers[$0.id]?.y }.reduce(0, +) / Double(groups.count)
        var result = Composition()
        for group in groups {
            let initial = centers[group.id]!
            let center = Point(x: initial.x - centerX, y: initial.y - centerY)
            result.basins[group.id] = Basin(center: center, radius: radii[group.id] ?? 125)
            for (id, point) in local[group.id] ?? [:] {
                result.slots[id] = Point(x: center.x + point.x, y: center.y + point.y)
            }
        }
        return result
    }
}
