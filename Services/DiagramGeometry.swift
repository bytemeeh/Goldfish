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
            // Small ponds need identity-sized stations rather than a decorative
            // tight ring. These fixed patterns leave at least 210–220 world
            // units between centers (and a wider 4-person grid), so first names
            // can stay below their coins at phone-width overview zooms.
            switch members.count {
            case 0:
                break
            case 1:
                slots[members[0]] = .zero
            case 2:
                slots[members[0]] = Point(x: -110, y: 0)
                slots[members[1]] = Point(x: 110, y: 0)
            case 3:
                slots[members[0]] = Point(x: 0, y: 115)
                slots[members[1]] = Point(x: -110, y: -80)
                slots[members[2]] = Point(x: 110, y: -80)
            case 4:
                slots[members[0]] = Point(x: -160, y: 160)
                slots[members[1]] = Point(x: 160, y: 160)
                slots[members[2]] = Point(x: -160, y: -160)
                slots[members[3]] = Point(x: 160, y: -160)
            case 5...12:
                let count = members.count
                let radius = 220 / (2 * sin(.pi / Double(count)))
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
                    slots[members[index]] = Point(x: cos(angle) * Double(ring) * 185,
                                                 y: sin(angle) * Double(ring) * 185)
                    index += 1
                }
                ring += 1
            }
            local[group.id] = slots
            // Measure actual slots, including the outer partial ring; never estimate by count.
            radii[group.id] = max(minimumBasinRadius,
                                  (slots.values.map { hypot($0.x, $0.y) }.max() ?? 0) + 90)
        }
        // Pack ponds on measured concentric rings. The former single orbit left
        // a permanent empty bay for Me in the middle of the map; the first pond
        // now occupies that space, with later rings balanced around it.
        var centers: [String: Point] = [:]
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
            let radialClearance = previousOrbit + previousRingRadius + ringRadius + 240
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
