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
        var centers: [String: Point] = [:]
        for (index, group) in groups.enumerated() {
            let radius = radii[group.id] ?? 125
            let angle = .pi / 4 + Double(index) * 2 * .pi / Double(groups.count)
            let orbit = radius + 160
            // The Pond canvas is close to square once its inline inspector and
            // controls take their rows. Use the available horizontal space so
            // headings and banks do not stack into a narrow vertical strip.
            var center = Point(x: cos(angle) * orbit * 1.09, y: sin(angle) * orbit * 1.03)
            let distance = hypot(center.x, center.y)
            let keepMeClear = max(1, (radius + 120) / max(distance, 1))
            center.x *= keepMeClear
            center.y *= keepMeClear
            centers[group.id] = center
        }
        // One measured expansion guarantees separation even for uneven dense groups.
        var expansion = 1.0
        for (index, a) in groups.enumerated() {
            for b in groups.dropFirst(index + 1) {
                let ac = centers[a.id]!, bc = centers[b.id]!
                let needed = ((radii[a.id] ?? 125) + (radii[b.id] ?? 125)) * 1.08 + 240
                expansion = max(expansion, needed / max(hypot(ac.x - bc.x, ac.y - bc.y), 1))
            }
        }
        var result = Composition()
        for group in groups {
            let initial = centers[group.id]!
            let center = Point(x: initial.x * expansion, y: initial.y * expansion)
            result.basins[group.id] = Basin(center: center, radius: radii[group.id] ?? 125)
            for (id, point) in local[group.id] ?? [:] {
                result.slots[id] = Point(x: center.x + point.x, y: center.y + point.y)
            }
        }
        return result
    }
}
