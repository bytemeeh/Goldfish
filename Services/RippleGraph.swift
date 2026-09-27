import Foundation

/// The information needed to render a contact adjacent to another contact.
struct RippleNeighbor: Identifiable {
    let person: Person
    let roleLabel: String
    let symbolName: String
    let relationshipTypes: [RelationshipType]

    var id: UUID { person.id }
}

/// A bounded, deterministic view of the saved relationship graph.
@MainActor
struct RippleGraph {
    let peopleByID: [UUID: Person]
    let meID: UUID?

    private struct Edge {
        let relationship: Relationship
        let other: Person
    }

    private let edges: [UUID: [Edge]]

    init(people: [Person]) {
        var unique: [UUID: Person] = [:]
        for person in people where !person.isDeleted && unique[person.id] == nil {
            unique[person.id] = person
        }
        peopleByID = unique
        meID = unique.values.first(where: { $0.isMe })?.id

        var pairRelationships: [String: [Relationship]] = [:]
        var relationshipsByID = Set<UUID>()
        for person in unique.values {
            for relationship in person.allRelationships where !relationship.isDeleted && relationshipsByID.insert(relationship.id).inserted {
                let from = relationship.fromContact.id
                let to = relationship.toContact.id
                guard from != to, unique[from] != nil, unique[to] != nil else { continue }
                let key = Self.pairKey(from, to)
                pairRelationships[key, default: []].append(relationship)
            }
        }

        var built: [UUID: [Edge]] = [:]
        for relationships in pairRelationships.values {
            guard let first = relationships.first else { continue }
            let a = first.fromContact
            let b = first.toContact
            built[a.id, default: []].append(contentsOf: relationships.map { Edge(relationship: $0, other: b) })
            built[b.id, default: []].append(contentsOf: relationships.map { Edge(relationship: $0, other: a) })
        }
        edges = built
    }

    func neighbors(of id: UUID, excluding excluded: Set<UUID> = []) -> [RippleNeighbor] {
        guard peopleByID[id] != nil else { return [] }
        var grouped: [UUID: [Edge]] = [:]
        for edge in edges[id, default: []] where !excluded.contains(edge.other.id) {
            grouped[edge.other.id, default: []].append(edge)
        }
        return grouped.keys.compactMap { otherID in
            guard let person = peopleByID[otherID], let candidates = grouped[otherID] else { return nil }
            let ordered = candidates.sorted { Self.edgePrecedes($0, $1, anchorID: id) }
            let types = ordered.map { Self.effectiveType($0.relationship, anchorID: id) }
                .reduce(into: [RelationshipType]()) { result, type in
                    if !result.contains(type) { result.append(type) }
                }
                .sorted { Self.typeIndex($0) < Self.typeIndex($1) }
            let primary = ordered.first!
            let primaryType = Self.effectiveType(primary.relationship, anchorID: id)
            let label: String
            if primaryType == .pet && person.isPet, let species = person.petSpeciesLabel, !species.isEmpty {
                label = species
            } else if primaryType == .other {
                label = "Connection"
            } else {
                label = primaryType.displayName
            }
            return RippleNeighbor(person: person, roleLabel: label, symbolName: primaryType.symbolName, relationshipTypes: types)
        }
        .sorted {
            let nameOrder = $0.person.name.localizedCaseInsensitiveCompare($1.person.name)
            return nameOrder == .orderedSame ? $0.id.uuidString < $1.id.uuidString : nameOrder == .orderedAscending
        }
    }

    func role(of contactID: UUID, relativeTo anchorID: UUID) -> RippleNeighbor? {
        neighbors(of: anchorID).first { $0.id == contactID }
    }

    func shortestPath(from start: UUID, to target: UUID) -> [UUID]? {
        guard peopleByID[start] != nil, peopleByID[target] != nil else { return nil }
        if start == target { return [start] }
        var queue = [start]
        var predecessor: [UUID: UUID] = [:]
        var visited: Set<UUID> = [start]
        var index = 0
        while index < queue.count {
            let current = queue[index]; index += 1
            for neighbor in neighbors(of: current) {
                guard visited.insert(neighbor.id).inserted else { continue }
                predecessor[neighbor.id] = current
                if neighbor.id == target {
                    var path = [target]
                    var cursor = target
                    while let parent = predecessor[cursor] { path.append(parent); cursor = parent }
                    return path.reversed()
                }
                queue.append(neighbor.id)
            }
        }
        return nil
    }

    func initialTrail(to id: UUID) -> [UUID] {
        guard peopleByID[id] != nil, let meID, let path = shortestPath(from: meID, to: id) else { return [] }
        return path
    }

    /// Keeps the caller's exploration order while accepting only current graph edges.
    /// The first invalid edge, duplicate, or cycle ends the usable trail.
    func validatedTrail(_ trail: [UUID]) -> [UUID] {
        guard let first = trail.first, peopleByID[first] != nil else { return [] }
        var result = [first]
        var seen: Set<UUID> = [first]
        for next in trail.dropFirst() {
            guard peopleByID[next] != nil, !seen.contains(next), isConnected(result.last!, next) else { break }
            result.append(next)
            seen.insert(next)
        }
        return result
    }

    private func isConnected(_ lhs: UUID, _ rhs: UUID) -> Bool {
        edges[lhs, default: []].contains { $0.other.id == rhs }
    }

    private static func pairKey(_ lhs: UUID, _ rhs: UUID) -> String {
        let a = lhs.uuidString, b = rhs.uuidString
        return a < b ? a + b : b + a
    }

    private static func typeIndex(_ type: RelationshipType) -> Int {
        RelationshipType.allCases.firstIndex(of: type) ?? Int.max
    }

    private static func effectiveType(_ relationship: Relationship, anchorID: UUID) -> RelationshipType {
        // `effectiveType(for:)` describes the person passed to it. The neighbor
        // is the other endpoint, so this intentionally resolves the reciprocal
        // role from the anchor's perspective.
        let anchor = peopleAnchor(relationship, id: anchorID)
        return relationship.effectiveType(for: relationship.otherContact(from: anchor))
    }

    private static func peopleAnchor(_ relationship: Relationship, id: UUID) -> Person {
        relationship.fromContact.id == id ? relationship.fromContact : relationship.toContact
    }

    private static func edgePrecedes(_ lhs: Edge, _ rhs: Edge, anchorID: UUID) -> Bool {
        if lhs.relationship.isPrimary != rhs.relationship.isPrimary { return lhs.relationship.isPrimary }
        let lt = typeIndex(effectiveType(lhs.relationship, anchorID: anchorID))
        let rt = typeIndex(effectiveType(rhs.relationship, anchorID: anchorID))
        if lt != rt { return lt < rt }
        return lhs.relationship.id.uuidString < rhs.relationship.id.uuidString
    }
}
