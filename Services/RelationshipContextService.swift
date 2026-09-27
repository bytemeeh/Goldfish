import Foundation

/// Human-readable relationship context for one contact in a caller-supplied scope.
///
/// Callers decide the scope (for example, the real or sample pond) by choosing
/// which people to pass to ``RelationshipContextService``. Pond membership is
/// exposed separately so a shared pond is never presented as a relationship.
struct ContactRelationshipContext: Equatable {
    enum Connection: Equatable {
        case direct(primary: RelationshipType, additional: [RelationshipType])
        case indirect(path: [UUID], throughName: String)
    }

    let contactID: UUID
    let connection: Connection
    let summary: String
    let compactSummary: String
}

@MainActor
struct RelationshipContextService {
    private struct Edge {
        let relationship: Relationship
        let other: Person
    }

    private let peopleByID: [UUID: Person]
    private let meID: UUID?
    private let edges: [UUID: [Edge]]

    init(people: [Person]) {
        var uniquePeople: [UUID: Person] = [:]
        for person in people where !person.isDeleted && uniquePeople[person.id] == nil {
            uniquePeople[person.id] = person
        }
        peopleByID = uniquePeople
        meID = uniquePeople.values.first(where: \.isMe)?.id

        var uniqueRelationships: [UUID: Relationship] = [:]
        for person in uniquePeople.values {
            for relationship in person.allRelationships where !relationship.isDeleted {
                guard relationship.fromContact.id != relationship.toContact.id,
                      uniquePeople[relationship.fromContact.id] != nil,
                      uniquePeople[relationship.toContact.id] != nil else { continue }
                uniqueRelationships[relationship.id] = relationship
            }
        }

        var builtEdges: [UUID: [Edge]] = [:]
        for relationship in uniqueRelationships.values {
            builtEdges[relationship.fromContact.id, default: []].append(
                Edge(relationship: relationship, other: relationship.toContact)
            )
            builtEdges[relationship.toContact.id, default: []].append(
                Edge(relationship: relationship, other: relationship.fromContact)
            )
        }
        edges = builtEdges
    }

    func context(for person: Person) -> ContactRelationshipContext? {
        guard !person.isMe, peopleByID[person.id] != nil, let meID else { return nil }

        let directEdges = edges[meID, default: []].filter { $0.other.id == person.id }
        if !directEdges.isEmpty {
            let roles = orderedDistinctRoles(in: directEdges, for: person)
            guard let primary = roles.first else { return nil }
            let additional = Array(roles.dropFirst())
            let summary = directSummary(for: person, primary: primary, additional: additional)
            return ContactRelationshipContext(
                contactID: person.id,
                connection: .direct(primary: primary, additional: additional),
                summary: summary,
                compactSummary: summary
            )
        }

        guard let path = shortestPath(from: meID, to: person.id), path.count > 2,
              let through = peopleByID[path[1]] else { return nil }
        return ContactRelationshipContext(
            contactID: person.id,
            connection: .indirect(path: path, throughName: through.name),
            summary: "Connected through \(through.name)",
            compactSummary: "Through \(through.name)"
        )
    }

    func summary(for person: Person) -> String? {
        context(for: person)?.summary
    }

    func compactSummary(for person: Person) -> String? {
        context(for: person)?.compactSummary
    }

    /// Pond membership is intentionally independent of graph connectivity.
    func pondSummary(for person: Person) -> String? {
        guard let name = person.primaryCircle?.name.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }
        return "Pond: \(name)"
    }

    private func orderedDistinctRoles(in directEdges: [Edge], for person: Person) -> [RelationshipType] {
        let sorted = directEdges.sorted { lhs, rhs in
            if lhs.relationship.isPrimary != rhs.relationship.isPrimary {
                return lhs.relationship.isPrimary
            }
            let lhsRole = lhs.relationship.effectiveType(for: person)
            let rhsRole = rhs.relationship.effectiveType(for: person)
            let lhsIndex = Self.roleIndex(lhsRole)
            let rhsIndex = Self.roleIndex(rhsRole)
            if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
            if lhs.relationship.createdAt != rhs.relationship.createdAt {
                return lhs.relationship.createdAt < rhs.relationship.createdAt
            }
            return lhs.relationship.id.uuidString < rhs.relationship.id.uuidString
        }

        return sorted.reduce(into: [RelationshipType]()) { result, edge in
            let role = edge.relationship.effectiveType(for: person)
            if !result.contains(role) { result.append(role) }
        }
    }

    private func directSummary(
        for person: Person,
        primary: RelationshipType,
        additional: [RelationshipType]
    ) -> String {
        let roleNames = [directRoleName(primary, person: person)] + additional.map {
            directRoleName($0, person: person)
        }
        if roleNames.count == 1 {
            return primary == .other ? "Connected to you" : "Your \(roleNames[0])"
        }
        if roleNames.count == 2 {
            return "Your \(roleNames[0]) and \(roleNames[1])"
        }
        return "Your \(roleNames.dropLast().joined(separator: ", ")), and \(roleNames.last!)"
    }

    private func directRoleName(_ role: RelationshipType, person: Person) -> String {
        if role == .pet, person.isPet, let species = person.petSpeciesLabel,
           !species.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return species.lowercased()
        }
        if role == .other { return "connection" }
        return role.displayName.lowercased()
    }

    private func shortestPath(from start: UUID, to target: UUID) -> [UUID]? {
        if start == target { return [start] }
        var queue = [start]
        var visited: Set<UUID> = [start]
        var predecessor: [UUID: UUID] = [:]
        var cursor = 0

        while cursor < queue.count {
            let current = queue[cursor]
            cursor += 1
            for edge in orderedNeighbors(of: current) where visited.insert(edge.other.id).inserted {
                predecessor[edge.other.id] = current
                if edge.other.id == target {
                    var path = [target]
                    var step = target
                    while let parent = predecessor[step] {
                        path.append(parent)
                        step = parent
                    }
                    return path.reversed()
                }
                queue.append(edge.other.id)
            }
        }
        return nil
    }

    private func orderedNeighbors(of personID: UUID) -> [Edge] {
        var firstEdgeByContact: [UUID: Edge] = [:]
        for edge in edges[personID, default: []] {
            let current = firstEdgeByContact[edge.other.id]
            if current == nil || edgePrecedes(edge, current!, anchorID: personID) {
                firstEdgeByContact[edge.other.id] = edge
            }
        }
        return firstEdgeByContact.values.sorted { lhs, rhs in
            let order = lhs.other.name.localizedStandardCompare(rhs.other.name)
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.other.id.uuidString < rhs.other.id.uuidString
        }
    }

    private func edgePrecedes(_ lhs: Edge, _ rhs: Edge, anchorID: UUID) -> Bool {
        if lhs.relationship.isPrimary != rhs.relationship.isPrimary {
            return lhs.relationship.isPrimary
        }
        let lhsRole = role(of: lhs.relationship, seenFrom: anchorID)
        let rhsRole = role(of: rhs.relationship, seenFrom: anchorID)
        let lhsIndex = Self.roleIndex(lhsRole)
        let rhsIndex = Self.roleIndex(rhsRole)
        if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
        return lhs.relationship.id.uuidString < rhs.relationship.id.uuidString
    }

    private func role(of relationship: Relationship, seenFrom anchorID: UUID) -> RelationshipType {
        let other = relationship.fromContact.id == anchorID
            ? relationship.toContact
            : relationship.fromContact
        return relationship.effectiveType(for: other)
    }

    private static func roleIndex(_ role: RelationshipType) -> Int {
        RelationshipType.allCases.firstIndex(of: role) ?? Int.max
    }
}
