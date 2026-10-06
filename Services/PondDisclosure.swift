import Foundation

/// A directed edge in the currently disclosed portion of the relationship graph.
struct PondDisclosureEdge: Hashable, Equatable {
    let from: UUID
    let to: UUID
}

/// The complete value snapshot consumed by the pond scene and inspector.
struct PondDisclosureSnapshot: Equatable {
    let visibleIDs: Set<UUID>
    let directIDs: Set<UUID>
    let expandedIDs: Set<UUID>
    let selectedID: UUID?
    let trail: [UUID]
    let hiddenNeighborCounts: [UUID: Int]
    let hiddenByPond: [String: [UUID]]
    let unlinkedIDs: Set<UUID>
    let revealedEdges: [PondDisclosureEdge]
    let parents: [UUID: UUID]
    var focusRootID: UUID? = nil
    var focusedIDs: Set<UUID> = []
    var focusedEdges: [PondDisclosureEdge] = []
    var pathHighlightIDs: [UUID] = []

    static let empty = PondDisclosureSnapshot(
        visibleIDs: [], directIDs: [], expandedIDs: [], selectedID: nil,
        trail: [], hiddenNeighborCounts: [:], hiddenByPond: [:],
        unlinkedIDs: [], revealedEdges: [], parents: [:],
        focusRootID: nil, focusedIDs: [], focusedEdges: [], pathHighlightIDs: []
    )
}

/// Pure, deterministic state for progressive pond disclosure.
///
/// The graph has no tree assumption: branch disclosures are edges from explicit
/// open nodes, while visibility is recomputed from all roots on every mutation.
@MainActor
struct PondDisclosure {
    private(set) var peopleByID: [UUID: Person]
    private(set) var snapshot: PondDisclosureSnapshot

    private var graph: RippleGraph
    private var branchReveals: [UUID: Set<UUID>] = [:]
    private var expandedIDs: Set<UUID> = []
    private var pondRevealedIDs: Set<UUID> = []
    private var searchRoute: [UUID] = []
    private var searchVisibleIDs: Set<UUID> = []
    private var trail: [UUID] = []
    private var selectedID: UUID?
    private var focusRootID: UUID?
    private var pathHighlightIDs: [UUID] = []

    init(people: [Person]) {
        var unique: [UUID: Person] = [:]
        for person in people where !person.isDeleted && unique[person.id] == nil {
            unique[person.id] = person
        }
        self.peopleByID = unique
        self.graph = RippleGraph(people: Array(unique.values))
        self.snapshot = .empty
        rebuildSnapshot()
    }

    /// Replaces the backing scope while retaining valid disclosure state.
    mutating func reload(people: [Person]) {
        var unique: [UUID: Person] = [:]
        for person in people where !person.isDeleted && unique[person.id] == nil {
            unique[person.id] = person
        }
        peopleByID = unique
        graph = RippleGraph(people: Array(unique.values))
        branchReveals = branchReveals.reduce(into: [:]) { result, entry in
            guard peopleByID[entry.key] != nil else { return }
            let connected = Set(graph.neighbors(of: entry.key).map(\.id))
            let targets = entry.value.filter { peopleByID[$0] != nil && connected.contains($0) }
            if !targets.isEmpty { result[entry.key] = targets }
        }
        expandedIDs = expandedIDs.filter { peopleByID[$0] != nil }
        pondRevealedIDs = pondRevealedIDs.filter { peopleByID[$0] != nil }
        searchRoute = graph.validatedTrail(searchRoute)
        searchVisibleIDs = Set(searchRoute)
        trail = graph.validatedTrail(trail)
        if let selectedID, peopleByID[selectedID] == nil { self.selectedID = nil }
        if let focusRootID, peopleByID[focusRootID] == nil { self.focusRootID = nil }
        pathHighlightIDs = graph.validatedTrail(pathHighlightIDs).filter { peopleByID[$0] != nil }
        rebuildSnapshot()
    }

    /// Selects a contact and opens its relationships without toggling an open
    /// branch closed. Contacts inside the focused branch keep that branch's
    /// original root; a contact outside it starts a new focus.
    mutating func activatePondContact(id: UUID) {
        guard id != meID, peopleByID[id] != nil, snapshot.visibleIDs.contains(id) else { return }
        if focusRootID == nil || !snapshot.focusedIDs.contains(id) {
            focusRootID = id
        }
        if !expandedIDs.contains(id), canActivateBranch(id) {
            expandedIDs.insert(id)
            revealNext(for: id)
        }
        selectedID = id
        pathHighlightIDs.removeAll()
        trail = selectionTrail(to: id)
        rebuildSnapshot()
    }

    /// Clears the branch highlight and inspector selection while keeping every
    /// explicitly opened branch available in the pond.
    mutating func clearPondFocus() {
        focusRootID = nil
        selectedID = nil
        trail.removeAll()
        pathHighlightIDs.removeAll()
        rebuildSnapshot()
    }

    /// Clears pond-only focus and compatibility route state while preserving
    /// explicitly expanded branches and manually revealed pond contacts.
    mutating func leavePondView() {
        focusRootID = nil
        selectedID = nil
        trail.removeAll()
        searchRoute.removeAll()
        searchVisibleIDs.removeAll()
        pathHighlightIDs.removeAll()
        rebuildSnapshot()
    }

    /// Temporarily highlights the currently selected contact's saved route.
    /// This does not change the branch anchor or disclosure state.
    mutating func showConnectionPath() {
        pathHighlightIDs = graph.validatedTrail(trail)
        rebuildSnapshot()
    }

    mutating func clearConnectionPath() {
        guard !pathHighlightIDs.isEmpty else { return }
        pathHighlightIDs.removeAll()
        rebuildSnapshot()
    }

    /// Opens or collapses the selected person's relationship branch.
    mutating func togglePondConnections(id: UUID) {
        guard peopleByID[id] != nil, snapshot.visibleIDs.contains(id) else { return }
        let selectedTrail = selectionTrail(to: id)
        pathHighlightIDs.removeAll()
        if expandedIDs.contains(id) {
            expandedIDs.remove(id)
            branchReveals.removeValue(forKey: id)
        } else {
            guard canExpand(id) else {
                selectedID = id
                trail = selectedTrail
                rebuildSnapshot()
                return
            }
            expandedIDs.insert(id)
            revealNext(for: id)
        }
        selectedID = id
        trail = selectedTrail
        rebuildSnapshot()
    }

    /// Adds the next bounded batch to an already visible branch.
    mutating func showMorePondConnections(id: UUID) {
        guard peopleByID[id] != nil, snapshot.visibleIDs.contains(id) else { return }
        expandedIDs.insert(id)
        revealNext(for: id)
        selectedID = id
        pathHighlightIDs.removeAll()
        trail = selectionTrail(to: id)
        rebuildSnapshot()
    }

    /// Closes every explicit branch and reveal, returning to the direct-only
    /// baseline. Search-route roots are cleared at the same boundary.
    mutating func collapseAllPondConnections() {
        expandedIDs.removeAll()
        branchReveals.removeAll()
        pondRevealedIDs.removeAll()
        searchRoute.removeAll()
        searchVisibleIDs.removeAll()
        trail.removeAll()
        selectedID = nil
        focusRootID = nil
        pathHighlightIDs.removeAll()
        rebuildSnapshot()
    }

    /// Reveals the next four otherwise hidden members of a pond.
    mutating func revealHiddenPeople(in pondID: String) {
        let candidates = hiddenPeople(in: pondID)
        for id in candidates.prefix(4) {
            pondRevealedIDs.insert(id)
        }
        rebuildSnapshot()
    }

    /// Selects a visible contact for the inline inspector.
    mutating func selectPondContact(id: UUID?) {
        guard let id else {
            selectedID = nil
            trail.removeAll()
            pathHighlightIDs.removeAll()
            rebuildSnapshot()
            return
        }
        guard snapshot.visibleIDs.contains(id) else { return }
        if selectedID != id { pathHighlightIDs.removeAll() }
        selectedID = id
        trail = selectionTrail(to: id)
        rebuildSnapshot()
    }

    /// Selects an earlier person on the route currently shown by the inspector.
    /// This deliberately changes only route focus: every open branch and every
    /// explicitly revealed contact remains available on the canvas.
    @discardableResult
    mutating func selectTrailAncestor(id: UUID) -> Bool {
        guard let index = trail.firstIndex(of: id), snapshot.visibleIDs.contains(id) else {
            return false
        }
        selectedID = id
        pathHighlightIDs.removeAll()
        trail = Array(trail.prefix(index + 1))
        rebuildSnapshot()
        return true
    }

    /// Reveals a caller-provided ordered search/profile route without opening any
    /// relationship branches. Invalid route segments are discarded at the first
    /// break; branch disclosure remains an explicit user action.
    mutating func revealRoute(_ route: [UUID], selecting id: UUID? = nil) {
        let validated = graph.validatedTrail(route)
        searchRoute = validated
        searchVisibleIDs = Set(validated)
        trail = validated
        if let id, peopleByID[id] != nil {
            if selectedID != id { pathHighlightIDs.removeAll() }
            selectedID = id
        }
        rebuildSnapshot()
    }

    /// Clears all explicit disclosure state, returning to Me + direct contacts.
    mutating func reset() {
        branchReveals.removeAll()
        expandedIDs.removeAll()
        pondRevealedIDs.removeAll()
        searchRoute.removeAll()
        searchVisibleIDs.removeAll()
        trail.removeAll()
        selectedID = nil
        focusRootID = nil
        pathHighlightIDs.removeAll()
        rebuildSnapshot()
    }

    func isExpanded(_ id: UUID) -> Bool { snapshot.expandedIDs.contains(id) }

    /// Whether opening this branch can reveal a hidden contact or retain a
    /// visible indirect contact through this additional relationship path.
    func canExpand(_ id: UUID) -> Bool {
        guard peopleByID[id] != nil, snapshot.visibleIDs.contains(id), !isExpanded(id) else { return false }
        let ancestors = Set(pathTo(id))
        let candidates = graph.neighbors(of: id).filter { !ancestors.contains($0.id) }
        var persistentRoots = snapshot.directIDs
        persistentRoots.formUnion(searchVisibleIDs)
        persistentRoots.formUnion(pondRevealedIDs)
        if let meID { persistentRoots.insert(meID) }
        return candidates.contains {
            !snapshot.visibleIDs.contains($0.id) || !persistentRoots.contains($0.id)
        }
    }

    func hiddenNeighborCount(for id: UUID) -> Int {
        snapshot.hiddenNeighborCounts[id] ?? 0
    }

    private var meID: UUID? { graph.meID }

    /// A tap should persist a branch edge that a compatibility route already
    /// made visible. The ordinary disclosure affordance can still use
    /// `canExpand` to decide whether there is meaningful expansion work.
    private func canActivateBranch(_ id: UUID) -> Bool {
        if canExpand(id) { return true }
        let ancestors = Set(pathTo(id))
        return graph.neighbors(of: id).contains {
            $0.id != meID && snapshot.visibleIDs.contains($0.id) && !ancestors.contains($0.id)
        }
    }

    private func pondID(for person: Person) -> String {
        person.primaryCircle?.id.uuidString ?? "unassigned"
    }

    private func hiddenPeople(in pondID: String) -> [UUID] {
        snapshot.hiddenByPond[pondID] ?? []
    }

    /// Adds up to four new contacts. Already-visible candidates are recorded as
    /// edges without consuming the new-contact budget.
    private mutating func revealNext(for id: UUID) {
        let visible = snapshot.visibleIDs
        var newCount = 0
        var reveals = branchReveals[id, default: []]
        for neighbor in graph.neighbors(of: id) {
            guard !reveals.contains(neighbor.id) else { continue }
            let isNew = !visible.contains(neighbor.id)
            if isNew {
                guard newCount < 4 else { continue }
                newCount += 1
            }
            reveals.insert(neighbor.id)
        }
        branchReveals[id] = reveals
    }

    private func reachableIDs() -> Set<UUID> {
        var roots = searchVisibleIDs.union(pondRevealedIDs)
        if let meID { roots.insert(meID) }
        if let meID { roots.formUnion(graph.neighbors(of: meID).map(\.id)) }

        var result = roots.filter { peopleByID[$0] != nil }
        var queue = Array(result).sorted { $0.uuidString < $1.uuidString }
        var index = 0
        while index < queue.count {
            let current = queue[index]
            index += 1
            guard expandedIDs.contains(current) else { continue }
            for next in branchReveals[current, default: []].sorted(by: { $0.uuidString < $1.uuidString }) {
                guard peopleByID[next] != nil, result.insert(next).inserted else { continue }
                queue.append(next)
            }
        }
        return result
    }

    private mutating func rebuildSnapshot() {
        let direct: Set<UUID> = meID.map { Set(graph.neighbors(of: $0).map(\.id)) } ?? []
        let reachable = reachableIDs()
        var visible = reachable.union(direct)
        if let meID { visible.insert(meID) }

        // Drop open records that can no longer be reached. This prevents a
        // detached cycle from keeping itself visible after its parent closes.
        expandedIDs.formIntersection(visible)
        branchReveals = branchReveals.filter { expandedIDs.contains($0.key) }
        if let focusRootID, !visible.contains(focusRootID) { self.focusRootID = nil }
        pathHighlightIDs = pathHighlightIDs.filter { visible.contains($0) }

        var edges: [PondDisclosureEdge] = []
        if let meID {
            edges.append(contentsOf: graph.neighbors(of: meID)
                .filter { visible.contains($0.id) }
                .map { PondDisclosureEdge(from: meID, to: $0.id) })
        }
        for source in expandedIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            for target in branchReveals[source, default: []].sorted(by: { $0.uuidString < $1.uuidString })
                where visible.contains(target) {
                edges.append(PondDisclosureEdge(from: source, to: target))
            }
        }
        for pair in zip(searchRoute, searchRoute.dropFirst()) {
            let edge = PondDisclosureEdge(from: pair.0, to: pair.1)
            if visible.contains(edge.from) && visible.contains(edge.to) { edges.append(edge) }
        }
        var seenEdges = Set<PondDisclosureEdge>()
        edges = edges.filter { seenEdges.insert($0).inserted }

        let adjacency = Dictionary(grouping: edges, by: \.from)
        var parents: [UUID: UUID] = [:]
        var visited = Set<UUID>()
        var roots: [UUID] = []
        if let meID { roots.append(meID) }
        roots.append(contentsOf: direct.sorted { $0.uuidString < $1.uuidString })
        roots.append(contentsOf: pondRevealedIDs.sorted { $0.uuidString < $1.uuidString })
        roots.append(contentsOf: searchRoute)
        for root in roots where visible.contains(root) && visited.insert(root).inserted {
            var queue = [root]
            var index = 0
            while index < queue.count {
                let current = queue[index]
                index += 1
                for edge in adjacency[current, default: []] where visible.contains(edge.to) {
                    guard visited.insert(edge.to).inserted else { continue }
                    if edge.to != meID { parents[edge.to] = current }
                    queue.append(edge.to)
                }
            }
        }
        let hidden = Set(peopleByID.keys).subtracting(visible)
        var hiddenByPond: [String: [UUID]] = [:]
        for id in hidden {
            guard let person = peopleByID[id] else { continue }
            hiddenByPond[pondID(for: person), default: []].append(id)
        }
        for key in hiddenByPond.keys {
            hiddenByPond[key]?.sort { lhs, rhs in
                let left = peopleByID[lhs]?.name ?? ""
                let right = peopleByID[rhs]?.name ?? ""
                let order = left.localizedCaseInsensitiveCompare(right)
                return order == .orderedSame ? lhs.uuidString < rhs.uuidString : order == .orderedAscending
            }
        }

        var hiddenNeighborCounts: [UUID: Int] = [:]
        for id in peopleByID.keys {
            hiddenNeighborCounts[id] = graph.neighbors(of: id).filter { !visible.contains($0.id) }.count
        }
        let unlinked: Set<UUID> = Set(peopleByID.keys.filter { id in
            guard id != meID else { return false }
            guard let meID else { return true }
            return graph.shortestPath(from: meID, to: id) == nil
        })
        let (focusedIDs, focusedEdges) = focusedBranch(visible: visible)
        let currentSelected = selectedID.flatMap { visible.contains($0) ? $0 : nil }
        selectedID = currentSelected
        trail = graph.validatedTrail(trail).filter { visible.contains($0) }
        if let currentSelected, trail.last != currentSelected {
            trail = pathTo(currentSelected, parents: parents)
        }
        snapshot = PondDisclosureSnapshot(
            visibleIDs: visible,
            directIDs: direct,
            expandedIDs: expandedIDs,
            selectedID: currentSelected,
            trail: trail,
            hiddenNeighborCounts: hiddenNeighborCounts,
            hiddenByPond: hiddenByPond,
            unlinkedIDs: unlinked,
            revealedEdges: edges,
            parents: parents,
            focusRootID: focusRootID,
            focusedIDs: focusedIDs,
            focusedEdges: focusedEdges,
            pathHighlightIDs: pathHighlightIDs
        )
    }

    /// Builds a bounded view from the active contact. The anchor's visible
    /// saved neighbors are always included, then traversal follows only edges
    /// explicitly revealed by open branches. Me and the anchor's upstream route
    /// are barriers, so cycles cannot escape back to the pond roots.
    private func focusedBranch(visible: Set<UUID>) -> (Set<UUID>, [PondDisclosureEdge]) {
        guard let root = focusRootID, visible.contains(root) else { return ([], []) }
        var blocked = Set(pathTo(root).dropLast())
        if let meID { blocked.insert(meID) }
        blocked.remove(root)

        var focused: Set<UUID> = [root]
        var edges: [PondDisclosureEdge] = []
        var queue = [root]
        var index = 0
        while index < queue.count {
            let source = queue[index]
            index += 1
            let targets: [UUID]
            if source == root {
                // The contact's own saved neighbors are meaningful context even
                // when another branch made them visible first.
                targets = graph.neighbors(of: root).map(\.id)
            } else if expandedIDs.contains(source) {
                targets = branchReveals[source, default: []].sorted { $0.uuidString < $1.uuidString }
            } else {
                targets = []
            }
            for target in targets where visible.contains(target) && !blocked.contains(target) {
                edges.append(PondDisclosureEdge(from: source, to: target))
                if focused.insert(target).inserted { queue.append(target) }
            }
        }
        return (focused, edges)
    }

    /// Keep the route the user followed when a contact is shared by branches.
    /// The shortest saved path may be different from the relationship in focus.
    private func selectionTrail(to id: UUID) -> [UUID] {
        if let index = trail.firstIndex(of: id) { return Array(trail.prefix(index + 1)) }
        if let previous = trail.last,
           graph.neighbors(of: previous).contains(where: { $0.id == id }) {
            return graph.validatedTrail(trail + [id])
        }
        return pathTo(id)
    }

    private func pathTo(_ id: UUID) -> [UUID] {
        pathTo(id, parents: snapshot.parents)
    }

    private func pathTo(_ id: UUID, parents: [UUID: UUID]) -> [UUID] {
        guard peopleByID[id] != nil else { return [] }
        var result = [id]
        var cursor = id
        var seen: Set<UUID> = [id]
        while let parent = parents[cursor], seen.insert(parent).inserted {
            result.append(parent)
            cursor = parent
        }
        return Array(result.reversed())
    }
}
