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
        /// Stable layout personality. Callers with a display title use it so
        /// equivalent imported/sample maps keep the same composition even when
        /// their persisted pond UUIDs differ.
        var seed: String? = nil
    }
    struct Basin {
        let center: Point
        let radius: Double
    }
    struct Composition {
        var slots: [UUID: Point] = [:]
        var basins: [String: Basin] = [:]
    }

    private static func angleVariation(_ id: String) -> Double {
        let hash = id.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
        return (Double(hash % 1001) / 1000 - 0.5) * 0.05
    }

    static func octilinear(from start: Point, to end: Point) -> [Point] {
        let dx = end.x - start.x, dy = end.y - start.y
        guard [dx, dy, start.x, start.y].allSatisfy(\.isFinite) else { return [] }
        let diagonal = min(abs(dx), abs(dy))
        if diagonal == 0 || abs(abs(dx) - abs(dy)) < 0.000001 { return [start, end] }
        return [start, Point(x: start.x + diagonal * (dx < 0 ? -1 : 1),
                             y: start.y + diagonal * (dy < 0 ? -1 : 1)), end]
    }

    static func radial(_ groups: [Group], minimumBasinRadius: Double = 0,
                       relatedPonds: [(String, String)] = []) -> Composition {
        guard !groups.isEmpty else { return Composition() }
        // Preserve the caller's first (central) pond. Fill neighboring orbit
        // slots with connected ponds before unrelated ones so the map conveys
        // real relationships without changing anyone's saved membership.
        var orderedGroups: [Group] = []
        var remaining = groups
        var weights: [String: [String: Int]] = [:]
        for (left, right) in relatedPonds where left != right {
            weights[left, default: [:]][right, default: 0] += 1
            weights[right, default: [:]][left, default: 0] += 1
        }
        var scores: [String: Int] = [:]
        if !remaining.isEmpty {
            let first = remaining.removeFirst()
            orderedGroups.append(first)
            for (neighbor, weight) in weights[first.id] ?? [:] {
                scores[neighbor, default: 0] += weight
            }
        }
        while !remaining.isEmpty {
            let best = remaining.indices.max { a, b in
                let left = scores[remaining[a].id] ?? 0
                let right = scores[remaining[b].id] ?? 0
                return left == right ? a > b : left < right
            }!
            let chosen = remaining.remove(at: best)
            orderedGroups.append(chosen)
            for (neighbor, weight) in weights[chosen.id] ?? [:] {
                scores[neighbor, default: 0] += weight
            }
        }
        var local: [String: [UUID: Point]] = [:]
        var radii: [String: Double] = [:]
        var assigned: Set<UUID> = []
        for group in orderedGroups {
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
                slots[members[0]] = Point(x: -235, y: 235)
                slots[members[1]] = Point(x: 235, y: 235)
                slots[members[2]] = Point(x: -235, y: -235)
                slots[members[3]] = Point(x: 235, y: -235)
            case 5:
                // Stagger two rows with a full label-and-coin clearance between
                // them. Wider same-row spacing keeps centered first names apart
                // when the complete map is framed on a phone.
                slots[members[0]] = Point(x: -420, y: 250)
                slots[members[1]] = Point(x: 0, y: 250)
                slots[members[2]] = Point(x: 420, y: 250)
                slots[members[3]] = Point(x: -210, y: -250)
                slots[members[4]] = Point(x: 210, y: -250)
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
        if orderedGroups.count <= 5 {
            if orderedGroups.count == 2 {
                let clearance = ((radii[orderedGroups[0].id] ?? 125) + (radii[orderedGroups[1].id] ?? 125)) * 1.08 + 240
                centers[orderedGroups[0].id] = Point(x: -clearance * 0.46, y: -clearance * 0.20)
                centers[orderedGroups[1].id] = Point(x: clearance * 0.46, y: clearance * 0.20)
            } else {
                centers[orderedGroups[0].id] = .zero
            }
            if orderedGroups.count > 2 {
                let ringGroups = Array(orderedGroups.dropFirst())
                let count = ringGroups.count
                let centerRadius = radii[orderedGroups[0].id] ?? 125
                let ringRadius = ringGroups.map { radii[$0.id] ?? 125 }.max() ?? 125
                let radialClearance = (centerRadius + ringRadius) * 1.08 + 240
                let chordClearance = 2 * ringRadius * 1.08 + 240
                let orbit = count > 1
                    ? max(radialClearance, chordClearance / max(2 * sin(.pi / Double(count)), 0.001))
                    : radialClearance
                for (index, group) in ringGroups.enumerated() {
                    let phase = count == 2 ? .pi / 4 : .pi / Double(count)
                    let step = count == 2 ? 5 * .pi / 6 : 2 * .pi / Double(count)
                    let angle = Double(index) * step + phase + angleVariation(group.seed ?? group.id)
                    // The spare orbit room absorbs small irregular angles and
                    // keeps headings apart at phone overview zoom.
                    centers[group.id] = Point(x: cos(angle) * orbit * 1.06, y: sin(angle) * orbit * 1.06)
                }
            }
        } else {
            // Pack larger maps on measured concentric rings. The first pond
            // occupies the center; later rings balance the complete map around it.
            let centerRadius = radii[orderedGroups[0].id] ?? 125
            centers[orderedGroups[0].id] = .zero
            var nextIndex = 1
            var ring = 1
            var previousOrbit = 0.0
            var previousRingRadius = centerRadius
            while nextIndex < orderedGroups.count {
                let count = min(ring * 6, orderedGroups.count - nextIndex)
                let ringGroups = Array(orderedGroups[nextIndex..<(nextIndex + count)])
                let ringRadius = ringGroups.map { radii[$0.id] ?? 125 }.max() ?? 125
                let radialClearance = previousOrbit + (previousRingRadius + ringRadius) * 1.08 + 240
                let chordClearance = 2 * ringRadius * 1.08 + 240
                let orbitForRing = count > 1
                    ? chordClearance / max(2 * sin(.pi / Double(count)), 0.001)
                    : radialClearance
                let orbit = max(radialClearance, orbitForRing) * 1.06
                for (item, group) in ringGroups.enumerated() {
                    let angle = Double(item) * 2 * .pi / Double(count) + Double(ring % 2) * .pi / Double(count) + angleVariation(group.seed ?? group.id)
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
        let centerX = orderedGroups.compactMap { centers[$0.id]?.x }.reduce(0, +) / Double(orderedGroups.count)
        let centerY = orderedGroups.compactMap { centers[$0.id]?.y }.reduce(0, +) / Double(orderedGroups.count)
        var result = Composition()
        for group in orderedGroups {
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
