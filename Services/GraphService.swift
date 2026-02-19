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
    let circleGroups: [CircleGroup]

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
    let contacts: [Person]

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

            // Find next level: all unvisited neighbors
            var nextLevel: [Person] = []
            for person in currentLevel {
                let neighbors = getNeighbors(of: person)
                for neighbor in neighbors {
                    if !visited.contains(neighbor.id) {
                        visited.insert(neighbor.id)
                        nextLevel.append(neighbor)
                    }
                }
            }

            currentLevel = nextLevel
            depth += 1
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
    private func groupByCircle(_ contacts: [Person]) -> [CircleGroup] {
        var groups: [UUID: (circle: GoldfishCircle, contacts: [Person])] = [:]
        var uncircled: [Person] = []
        // Sentinel UUID for uncircled group ordering
        let uncircledKey = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

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
    func search(query: String, context: ModelContext) throws -> [Person] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let lowered = trimmed.lowercased()

        // BUG 3 FIX: Single fetch — load all persons once, run every filter in-memory.
        // Previously this method fetched 2-3 times (predicate + allPersons + circles).
        // At 1000 contacts that was O(3N) fetches. Now it's O(N) with one fetch.
        let allPersons = try context.fetch(FetchDescriptor<Person>())

        // 1. Name / email / phone / notes filter (replaces the predicate fetch)
        let fieldMatches = allPersons.filter { person in
            person.name.localizedCaseInsensitiveContains(trimmed) ||
            (person.email ?? "").localizedCaseInsensitiveContains(trimmed) ||
            (person.phone ?? "").localizedCaseInsensitiveContains(trimmed) ||
            (person.notes ?? "").localizedCaseInsensitiveContains(trimmed)
        }

        // 2. Tag match (tags is [String], can't express in #Predicate)
        let tagMatches = allPersons.filter { person in
            person.tags.contains { $0.localizedCaseInsensitiveContains(trimmed) }
        }

        // 3. Circle name match — fetch circles separately (lightweight),
        //    but resolve contacts from the already-loaded allPersons array
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
        let circleMatches = allPersons.filter { circleContactIds.contains($0.id) }

        // 4. Relationship type label match
        let matchingRelTypes = RelationshipType.allCases.filter {
            $0.displayName.localizedCaseInsensitiveContains(trimmed)
        }
        let relTypeMatches: [Person] = matchingRelTypes.isEmpty ? [] : allPersons.filter { person in
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
