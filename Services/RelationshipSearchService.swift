import Foundation

@MainActor
struct RelationshipSearchPath: Identifiable {
    nonisolated let id: String
    let people: [Person]
    let roles: [RelationshipQueryRole]

    init(people: [Person], roles: [RelationshipQueryRole]) {
        self.people = people
        self.roles = roles
        self.id = people.map { $0.id.uuidString }.joined(separator: "/") + roles.map(\.rawValue).joined(separator: "/")
    }
    var person: Person { people.last! }
    var trailIDs: [UUID] { people.map(\.id) }
    var summary: String {
        guard let first = people.first else { return "" }
        return zip(roles, people.dropFirst()).reduce(first.isMe ? "You" : first.name) { result, pair in
            result + " → " + pair.0.label.lowercased() + " " + (pair.1.isMe ? "You" : pair.1.name)
        }
    }
}

@MainActor
struct RelationshipSearchResponse {
    let query: RelationshipQuery?
    var paths: [RelationshipSearchPath]
    let anchorMatches: [Person]
    var message: String?
    let isTruncated: Bool

    var matchedContactCount: Int { Set(paths.map { $0.person.id }).count }
}

/// Resolves parsed questions against saved relationships in the supplied scope.
@MainActor
struct RelationshipSearchService {
    private let maximumPaths = 128
    private let maximumStates = 4096

    func search(_ query: RelationshipQuery, people: [Person]) -> RelationshipSearchResponse {
        let graph = RippleGraph(people: people)
        let all = graph.peopleByID.values.sorted(by: Self.precedes)
        let key = Self.normalized(query.anchor)
        let anchors: [Person]
        if ["me", "my", "you", "myself"].contains(key) {
            anchors = all.filter(\.isMe)
        } else {
            let exact = all.filter { Self.normalized($0.name) == key }
            anchors = exact.isEmpty ? all.filter { Self.normalized($0.name).split(separator: " ").first.map(String.init) == key } : exact
        }
        guard !anchors.isEmpty else {
            return RelationshipSearchResponse(query: query, paths: [], anchorMatches: [], message: "No contact named “\(query.anchor)” was found in this pond’s contacts. Try their saved name.", isTruncated: false)
        }
        guard !query.roles.isEmpty, query.roles.count <= 12 else {
            return RelationshipSearchResponse(query: query, paths: [], anchorMatches: anchors, message: "Use one to twelve saved relationships. For example, “my sibling”.", isTruncated: false)
        }

        // Cache adjacency once; paths may revisit a person because a finite
        // question such as “Sam’s friend’s friend” can legitimately lead to Sam.
        let adjacency = Dictionary(uniqueKeysWithValues: all.map { ($0.id, graph.neighbors(of: $0.id)) })
        var states = anchors.map { [$0] }
        var truncated = false
        var failedAt: Int?
        var lastNames: [String] = []
        for (index, role) in query.roles.enumerated() {
            var next: [[Person]] = []
            let limit = index == query.roles.count - 1 ? maximumPaths : maximumStates
            lastNames = Array(Set(states.compactMap { $0.last?.name })).sorted()
            outer: for path in states {
                guard let last = path.last else { continue }
                for neighbor in adjacency[last.id, default: []] where Self.matches(role, neighbor: neighbor) {
                    if next.count == limit { truncated = true; break outer }
                    next.append(path + [neighbor.person])
                }
            }
            states = next
            if states.isEmpty { failedAt = index; break }
        }

        let paths = states.map { RelationshipSearchPath(people: $0, roles: query.roles) }
        var notices: [String] = []
        if anchors.count > 1 {
            notices.append("\(anchors.count) contacts match “\(query.anchor)”. Results include each of them; use a full name to narrow your search.")
        }
        if let failedAt, !truncated {
            let names = lastNames.prefix(3).joined(separator: ", ")
            let context = lastNames.count <= 3 ? names : "the contacts reached so far"
            notices.append("No saved \(query.roles[failedAt].label.lowercased()) connection was found for \(context). The connection may not have been recorded yet.")
        }
        if truncated {
            notices.append(paths.isEmpty
                ? "No matching route was found within this search limit. Try a full name or a shorter chain to check more precisely."
                : "This question has many possible routes. Showing a limited set; try a full name or a more specific relationship to narrow it down.")
        }
        return RelationshipSearchResponse(query: query, paths: paths, anchorMatches: anchors,
                                          message: notices.isEmpty ? nil : notices.joined(separator: " "), isTruncated: truncated)
    }

    private static func matches(_ role: RelationshipQueryRole, neighbor: RippleNeighbor) -> Bool {
        let types = Set(neighbor.relationshipTypes)
        switch role {
        case .connection: return true
        case .friend: return types.contains(.friend)
        case .sibling: return types.contains(.sibling)
        case .partner: return !types.isDisjoint(with: [.partner, .spouse])
        case .spouse: return types.contains(.spouse)
        case .child: return types.contains(.child)
        case .parent: return !types.isDisjoint(with: [.parent, .mother, .father])
        case .mother: return types.contains(.mother)
        case .father: return types.contains(.father)
        case .coworker: return types.contains(.coworker)
        case .guardian: return types.contains(.guardian)
        case .pet: return types.contains(.pet)
        case .dog: return types.contains(.pet) && neighbor.person.contactKind == .dog
        case .cat: return types.contains(.pet) && neighbor.person.contactKind == .cat
        }
    }

    private static func normalized(_ name: String) -> String {
        name.replacingOccurrences(of: "’", with: "'")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func precedes(_ lhs: Person, _ rhs: Person) -> Bool {
        let left = normalized(lhs.name), right = normalized(rhs.name)
        return left == right ? lhs.id.uuidString < rhs.id.uuidString : left < right
    }
}
