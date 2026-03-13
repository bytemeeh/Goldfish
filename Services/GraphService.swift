import Foundation
import SwiftData

// MARK: - Graph Layout Types

/// A single level in the BFS-computed graph layout.
/// Level 0 is the `isMe` root; each subsequent level contains contacts
/// one hop further away in the relationship graph.
struct GraphLevel {
    /// The distance from the root (0 = me, 1 = direct connections, etc.)
    let depth: Int

    /// Contacts at this level, grouped by their primary circle for visual clustering.
    var circleGroups: [CircleGroup]

    /// All contacts at this level, flattened across circle groups.
    var allContacts: [Person] {
        circleGroups.flatMap(\.contacts)
    }
}

/// A group of contacts within a single circle at a given graph level.
/// Used for visual clustering in the graph view.
struct CircleGroup {
    /// The circle these contacts belong to. Nil for the "Uncircled" group.
    let circle: GoldfishCircle?

    /// The contacts in this group at this level.
    var contacts: [Person]

    /// Display name: circle name, or "Uncircled" for contacts not in any circle.
    var displayName: String {
        circle?.name ?? "Uncircled"
    }

    /// Display color: circle color hex, or a neutral gray for uncircled.
    var displayColor: String {
        circle?.color ?? "#808080"
    }
}

// MARK: - GraphService

/// Pure logic layer for graph algorithms. Does NOT perform any persistence —
/// it operates on arrays of `Person` and `Relationship` objects provided by the caller
/// or fetched from a `ModelContext`.
///
/// Responsibilities:
/// - Cycle detection for directional relationships
/// - BFS graph traversal for layout computation
/// - Descendant traversal for cascading selection
/// - Full-text search with ranked results
struct GraphService {

    // MARK: - Cycle Detection

    /// Checks whether creating a new directional relationship would form
    /// an ancestry cycle (i.e., a person becoming their own ancestor).
    ///
    /// **Only runs for directional types** (mother, father, child).
    /// Symmetric types (friend, sibling, spouse, coworker) skip this check
    /// because mutual connections are natural.
    ///
    /// **Algorithm:** BFS from `toContact`, traversing upward through existing
    /// directional relationships. If the traversal ever reaches `fromContact`,
    /// adding this edge would create a cycle.
    ///
    /// - Parameters:
    ///   - from: The subject contact (the person in the `type` role).
    ///   - to: The object contact.
    ///   - type: The relationship type being created.
    ///   - context: ModelContext for fetching existing relationships.
    /// - Returns: `true` if creating this relationship would form a cycle.
    func wouldCreateCycle(
        from: Person,
        to: Person,
        type: RelationshipType,
        context: ModelContext
    ) -> Bool {
        // Symmetric types cannot create ancestry cycles
        guard type.isDirectional else { return false }

        // Self-relationships are always a cycle for directional types
        guard from.id != to.id else { return true }

        // BFS: Starting from `to`, walk through directional relationships.
        // If we reach `from`, then adding from→to creates a cycle.
        //
        // We traverse "child" edges forward (outgoing where type is child)
        // and "parent" edges backward (outgoing where type is mother/father),
        // depending on what we're adding.
        //
        // Simplified approach: traverse ALL directional edges reachable from `to`
        // (in both directions) and check if `from` is reachable.
        // This is conservative — it prevents any directional loop.

        var visited: Set<UUID> = [to.id]
        var queue: [Person] = [to]

        while !queue.isEmpty {
            let current = queue.removeFirst()

            // Traverse outgoing directional relationships
            for rel in current.outgoingRelationships {
                let relType = RelationshipType(rawValue: rel.typeRawValue) ?? .other
                guard relType.isDirectional else { continue }

                let neighbor = rel.toContact
                if neighbor.id == from.id { return true }
                if !visited.contains(neighbor.id) {
                    visited.insert(neighbor.id)
                    queue.append(neighbor)
                }
            }

            // Traverse incoming directional relationships
            for rel in current.incomingRelationships {
                let relType = RelationshipType(rawValue: rel.typeRawValue) ?? .other
                guard relType.isDirectional else { continue }

                let neighbor = rel.fromContact
                if neighbor.id == from.id { return true }
                if !visited.contains(neighbor.id) {
                    visited.insert(neighbor.id)
                    queue.append(neighbor)
                }
            }
        }

        return false
    }

    // MARK: - Graph Layout (BFS)

    /// Builds a hierarchical graph layout via BFS from the `isMe` root contact.
    ///
    /// - Level 0: The `isMe` contact
    /// - Level 1: All contacts directly related to Me
    /// - Level 2: Contacts related to Level 1 (not yet placed)
    /// - ...and so on
    ///
    /// At each level, contacts are grouped by their primary circle for visual
    /// clustering in the graph view. Contacts not in any circle go into an
    /// "Uncircled" group.
    ///
    /// **Orphans** (contacts with no relationships) are intentionally excluded
    /// from the graph layout — they appear in a separate "Unlinked" list section.
    ///
    /// - Parameters:
    ///   - root: The `isMe` contact to use as BFS origin.
    ///   - context: ModelContext for fetching circle memberships.
    /// - Returns: An array of `GraphLevel` from depth 0 outward.
    func buildGraphLevels(
        root: Person,
        context: ModelContext
    ) -> [GraphLevel] {
        var visited: Set<UUID> = [root.id]
        var currentLevel: [Person] = [root]
        var levels: [GraphLevel] = []
        var depth = 0

        while !currentLevel.isEmpty {
            // Group contacts at this level by their primary circle
            let grouped = groupByCircle(currentLevel)
            levels.append(GraphLevel(depth: depth, circleGroups: grouped))

            // Find next level: all unvisited neighbors (exclude demo contacts)
            var nextLevel: [Person] = []
            for person in currentLevel {
                let neighbors = getNeighbors(of: person)
                for neighbor in neighbors {
                    guard !neighbor.isDemo else { continue }
                    if !visited.contains(neighbor.id) {
                        visited.insert(neighbor.id)
                        nextLevel.append(neighbor)
                    }
                }
            }

            currentLevel = nextLevel
            depth += 1
        }
        
        // At this point we have connected levels. Let's record which circles already exist and at what depth.
        var existingCircleDepth: [UUID: Int] = [:]
        for (lvlIndex, level) in levels.enumerated() {
            for group in level.circleGroups {
                if let circleId = group.circle?.id {
                    existingCircleDepth[circleId] = lvlIndex
                }
            }
        }

        // Include orphan contacts (not reachable via relationships) as the outermost level
        // OR merge them into existing circles if they share a pond.
        // Exclude demo contacts.
        let allPersons = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        let orphans = allPersons.filter { !visited.contains($0.id) && !$0.isDemo }
        
        var trueOrphans: [Person] = []
        
        for orphan in orphans {
            // Check if this orphan belongs to any circle that already exists in the graph
            let activeCircles = orphan.circleContacts.filter { !$0.manuallyExcluded }.map { $0.circle }
            var merged = false
            for circle in activeCircles {
                if let existingDepth = existingCircleDepth[circle.id] {
                    // Find the group in that level
                    if let groupIndex = levels[existingDepth].circleGroups.firstIndex(where: { $0.circle?.id == circle.id }) {
                        levels[existingDepth].circleGroups[groupIndex].contacts.append(orphan)
                        merged = true
                        break
                    }
                }
            }
            if !merged {
                trueOrphans.append(orphan)
            }
        }

        if !trueOrphans.isEmpty {
            let orphanGroups = groupByCircle(trueOrphans)
            levels.append(GraphLevel(depth: depth, circleGroups: orphanGroups))
        }

        return levels
    }
    
    /// Demo-mode-aware variant of `buildGraphLevels`.
    /// When `demoMode` is true, only traverses to demo contacts.
    /// When `demoMode` is false, only traverses to real contacts.
    /// The root (`isMe`) is always included as the graph anchor.
    func buildGraphLevels(
        root: Person,
        context: ModelContext,
        demoMode: Bool
    ) -> [GraphLevel] {
        var visited: Set<UUID> = [root.id]
        var currentLevel: [Person] = [root]
        var levels: [GraphLevel] = []
        var depth = 0

        while !currentLevel.isEmpty {
            let grouped = groupByCircle(currentLevel)
            levels.append(GraphLevel(depth: depth, circleGroups: grouped))

            var nextLevel: [Person] = []
            for person in currentLevel {
                let neighbors = getNeighbors(of: person)
                for neighbor in neighbors {
                    // Only include neighbors matching the demo mode filter
                    // (Me contact is always at root, never filtered here)
                    guard neighbor.isDemo == demoMode else { continue }
                    if !visited.contains(neighbor.id) {
                        visited.insert(neighbor.id)
                        nextLevel.append(neighbor)
                    }
                }
            }

            currentLevel = nextLevel
            depth += 1
        }
        
        var existingCircleDepth: [UUID: Int] = [:]
        for (lvlIndex, level) in levels.enumerated() {
            for group in level.circleGroups {
                if let circleId = group.circle?.id {
                    existingCircleDepth[circleId] = lvlIndex
                }
            }
        }

        // Only consider orphans matching the demo mode filter
        let allPersons = (try? context.fetch(FetchDescriptor<Person>())) ?? []
        let orphans = allPersons.filter { !visited.contains($0.id) && $0.isDemo == demoMode }
        
        var trueOrphans: [Person] = []
        
        for orphan in orphans {
            let activeCircles = orphan.circleContacts.filter { !$0.manuallyExcluded }.map { $0.circle }
            var merged = false
            for circle in activeCircles {
                if let existingDepth = existingCircleDepth[circle.id] {
                    if let groupIndex = levels[existingDepth].circleGroups.firstIndex(where: { $0.circle?.id == circle.id }) {
                        levels[existingDepth].circleGroups[groupIndex].contacts.append(orphan)
                        merged = true
                        break
                    }
                }
            }
            if !merged {
                trueOrphans.append(orphan)
            }
        }

        if !trueOrphans.isEmpty {
            let orphanGroups = groupByCircle(trueOrphans)
            levels.append(GraphLevel(depth: depth, circleGroups: orphanGroups))
        }

        return levels
    }

    /// Returns all direct neighbors of a person (both directions, all types).
    private func getNeighbors(of person: Person) -> [Person] {
        var neighbors: [Person] = []
        for rel in person.outgoingRelationships {
            neighbors.append(rel.toContact)
        }
        for rel in person.incomingRelationships {
            neighbors.append(rel.fromContact)
        }
        return neighbors
    }

    /// Groups a set of contacts by their primary circle.
    /// Contacts in multiple circles are assigned to their first non-excluded circle.
    /// Contacts in no circle are grouped under "Uncircled" (nil circle).
    ///
    /// **Reordering logic**: Contacts within a group are sorted based on their mutual connectivity
    /// to ensure connected people appear closer together in the graph's circular layout.
    private func groupByCircle(_ contacts: [Person]) -> [CircleGroup] {
        var groups: [UUID: (circle: GoldfishCircle, contacts: [Person])] = [:]
        var uncircled: [Person] = []

        for person in contacts {
            let activeCircles = person.circleContacts
                .filter { !$0.manuallyExcluded }
            if let primaryMembership = activeCircles.first {
                let circle = primaryMembership.circle
                if groups[circle.id] != nil {
                    groups[circle.id]!.contacts.append(person)
                } else {
                    groups[circle.id] = (circle: circle, contacts: [person])
                }
            } else {
                uncircled.append(person)
            }
        }

        // Apply connection-aware sorting to each group
        for (id, var group) in groups {
            group.contacts = sortByConnectivity(group.contacts)
            groups[id] = group
        }
        uncircled = sortByConnectivity(uncircled)

        // Sort groups by circle sortOrder
        var result = groups.values
            .sorted { $0.circle.sortOrder < $1.circle.sortOrder }
            .map { CircleGroup(circle: $0.circle, contacts: $0.contacts) }

        // Add uncircled group at the end if there are any
        if !uncircled.isEmpty {
            result.append(CircleGroup(circle: nil, contacts: uncircled))
        }

        return result
    }

    /// Sorts a list of persons such that those with mutual connections are adjacent.
    /// Uses a "Greedy Degree + Neighbor" heuristic.
    private func sortByConnectivity(_ contacts: [Person]) -> [Person] {
        guard contacts.count > 2 else { return contacts }
        
        var remaining = Set(contacts)
        var sorted: [Person] = []
        
        // Helper to count connections within the set
        func internalConnectionCount(_ p: Person) -> Int {
            let neighbors = Set(getNeighbors(of: p).map(\.id))
            return contacts.filter { neighbors.contains($0.id) }.count
        }
        
        // 1. Start with the most connected person
        if let first = remaining.max(by: { internalConnectionCount($0) < internalConnectionCount($1) }) {
            sorted.append(first)
            remaining.remove(first)
        }
        
        // 2. Iteratively add the person most connected to the already-sorted set
        while !remaining.isEmpty {
            let sortedIDs = Set(sorted.map(\.id))
            
            if let next = remaining.max(by: { a, b in
                let aConn = Set(getNeighbors(of: a).map(\.id)).intersection(sortedIDs).count
                let bConn = Set(getNeighbors(of: b).map(\.id)).intersection(sortedIDs).count
                if aConn != bConn { return aConn < bConn }
                // Tie-breaker: overall internal degree
                return internalConnectionCount(a) < internalConnectionCount(b)
            }) {
                sorted.append(next)
                remaining.remove(next)
            } else {
                // Should not happen if contacts is non-empty
                break
            }
        }
        
        return sorted
    }

    // MARK: - Descendants (Directional Traversal)

    /// Returns all contacts reachable from the given contact through
    /// directional outgoing relationships.
    ///
    /// This traverses "downward" in the family tree:
    /// - From a parent, it follows child relationships
    /// - Useful for cascading selection in share/export UI
    ///
    /// The traversal follows edges where `fromContact` is the given person
    /// (or a discovered descendant) and the type is directional.
    ///
    /// - Parameter contact: The starting contact.
    /// - Returns: All reachable contacts (excluding the starting contact itself).
    func getDescendants(of contact: Person) -> [Person] {
        var visited: Set<UUID> = [contact.id]
        var queue: [Person] = [contact]
        var descendants: [Person] = []

        while !queue.isEmpty {
            let current = queue.removeFirst()

            // Follow outgoing directional relationships where this person is the "parent" role
            // i.e., from=current, type=mother/father means current is parent of toContact
            for rel in current.outgoingRelationships {
                let relType = RelationshipType(rawValue: rel.typeRawValue) ?? .other
                // A parent (mother/father) → their toContact is the child
                guard relType == .mother || relType == .father else { continue }

                let child = rel.toContact
                if !visited.contains(child.id) {
                    visited.insert(child.id)
                    descendants.append(child)
                    queue.append(child)
                }
            }

            // Also follow incoming "child" relationships where toContact=current
            // i.e., from=child, to=current, type=child means the fromContact is current's child
            for rel in current.incomingRelationships {
                let relType = RelationshipType(rawValue: rel.typeRawValue) ?? .other
                guard relType == .child else { continue }

                let child = rel.fromContact
                if !visited.contains(child.id) {
                    visited.insert(child.id)
                    descendants.append(child)
                    queue.append(child)
                }
            }
        }

        return descendants
    }

    // MARK: - Search

    /// Searches contacts across multiple fields with ranked results.
    ///
    /// **Search fields:** name, email, phone, notes, tags
    ///
    /// **Ranking:**
    /// 1. Exact name match (case-insensitive)
    /// 2. Name starts with query
    /// 3. Name contains query
    /// 4. Match in other fields (email, phone, notes, tags)
    ///
    /// Also supports searching by circle name and relationship type label.
    ///
    /// - Parameters:
    ///   - query: The search string (case-insensitive, partial match).
    ///   - context: ModelContext for performing the fetch.
    /// - Returns: Contacts sorted by match relevance.
    func search(query: String, context: ModelContext, demoMode: Bool = false) throws -> [Person] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let lowered = trimmed.lowercased()

        // Single fetch — load all persons once, run every filter in-memory.
        let allPersons = try context.fetch(FetchDescriptor<Person>())
        
        // Only search among contacts that are actually visible (matching demo mode,
        // and excluding the "Me" contact which is never shown in lists or highlighted).
        let candidates = allPersons.filter { !$0.isMe && $0.isDemo == demoMode }

        // 1. Name / email / phone / notes filter
        let fieldMatches = candidates.filter { person in
            person.name.localizedCaseInsensitiveContains(trimmed) ||
            (person.email ?? "").localizedCaseInsensitiveContains(trimmed) ||
            (person.phone ?? "").localizedCaseInsensitiveContains(trimmed) ||
            (person.notes ?? "").localizedCaseInsensitiveContains(trimmed)
        }

        // 2. Tag match (tags is [String], can't express in #Predicate)
        let tagMatches = candidates.filter { person in
            person.tags.contains { $0.localizedCaseInsensitiveContains(trimmed) }
        }

        // 3. Circle name match — fetch circles separately (lightweight),
        //    but resolve contacts from the already-loaded candidates array
        let circleDescriptor = FetchDescriptor<GoldfishCircle>(
            predicate: #Predicate<GoldfishCircle> { circle in
                circle.name.localizedStandardContains(trimmed)
            }
        )
        let matchingCircles = try context.fetch(circleDescriptor)
        let circleContactIds = Set(
            matchingCircles.flatMap { circle in
                circle.circleContacts
                    .filter { !$0.manuallyExcluded }
                    .map(\.contact.id)
            }
        )
        let circleMatches = candidates.filter { circleContactIds.contains($0.id) }

        // 4. Relationship type label match
        let matchingRelTypes = RelationshipType.allCases.filter {
            $0.displayName.localizedCaseInsensitiveContains(trimmed)
        }
        let relTypeMatches: [Person] = matchingRelTypes.isEmpty ? [] : candidates.filter { person in
            person.allRelationships.contains { rel in
                let relType = RelationshipType(rawValue: rel.typeRawValue) ?? .other
                return matchingRelTypes.contains(relType)
            }
        }

        // Merge all matches (deduplicated)
        var seen: Set<UUID> = []
        var allMatches: [Person] = []
        for person in fieldMatches + tagMatches + circleMatches + relTypeMatches {
            if !seen.contains(person.id) {
                seen.insert(person.id)
                allMatches.append(person)
            }
        }

        // Rank results
        let ranked = allMatches.sorted { a, b in
            rankScore(for: a, query: lowered) > rankScore(for: b, query: lowered)
        }

        return ranked
    }

    /// Computes a relevance score for ranking search results.
    /// Higher score = better match.
    private func rankScore(for person: Person, query: String) -> Int {
        let name = person.name.lowercased()

        // Exact name match
        if name == query { return 100 }

        // Name starts with query
        if name.hasPrefix(query) { return 80 }

        // Name contains query
        if name.contains(query) { return 60 }

        // Email/phone match
        if person.email?.lowercased().contains(query) == true { return 40 }
        if person.phone?.lowercased().contains(query) == true { return 40 }

        // Tag match
        if person.tags.contains(where: { $0.lowercased().contains(query) }) { return 30 }

        // Notes match
        if person.notes?.lowercased().contains(query) == true { return 20 }

        // Circle/relationship type match (lowest priority)
        return 10
    }
}
