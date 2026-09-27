import Foundation

/// Stable multi-source breadth-first ownership. Cycles and peer edges remain in
/// the relationship model; only this display forest chooses one parent per person.
enum RelationshipForest {
    struct Result {
        var parent: [UUID: UUID] = [:]
        var root: [UUID: UUID] = [:]
    }

    static func build(roots: [UUID], neighbors: [UUID: [UUID]], allowed: Set<UUID>) -> Result {
        var result = Result()
        var seen = Set<UUID>()
        var queue: [UUID] = []
        for root in roots where allowed.contains(root) && seen.insert(root).inserted {
            queue.append(root)
            result.root[root] = root
        }
        var cursor = 0
        while cursor < queue.count {
            let parent = queue[cursor]
            cursor += 1
            for child in (neighbors[parent] ?? []).sorted(by: { $0.uuidString < $1.uuidString }) {
                guard allowed.contains(child), seen.insert(child).inserted else { continue }
                result.parent[child] = parent
                result.root[child] = result.root[parent]
                queue.append(child)
            }
        }
        return result
    }
}
