import SwiftUI
import SpriteKit
import Combine

// MARK: - Data Change Notification
extension Notification.Name {
    /// Posted whenever a contact is edited / created / connected anywhere in the app.
    /// The graph (and list) observe this to re-fetch and rebuild stale node visuals.
    static let goldfishDataDidChange = Notification.Name("goldfishDataDidChange")
}

// MARK: - Graph Scene Delegate
/// Protocol to communicate from ViewModel -> SpriteKit Scene
@MainActor
protocol GraphSceneDelegate: AnyObject {
    func didUpdateGroups(_ groups: [GoldfishCircle])
    func didUpdateGraphLevels(_ levels: [GraphLevel])
    func didSelectContact(_ id: UUID?)
    func didUpdateZoom(_ zoom: CGFloat)
    func didUpdateCameraPosition(_ position: CGPoint)
    func centerOnContact(_ id: UUID)
    func centerOnMe()
    func centerOnPond(name: String)
    func didUpdatePondFilter(_ name: String?)
    func requestConnection(from: UUID, to: UUID)
    func didUpdateSearchMatches(_ ids: Set<UUID>?)
    func animateNewConnection(from: UUID, to: UUID)
    func didLongPressContact(_ id: UUID)
    func fitToGraph()
    func didUpdateRipple(focus: PondRippleFocus?, neighbors: [RippleNeighbor])
    func didUpdateDisclosure(_ snapshot: PondDisclosureSnapshot)
    func offscreenContactIDs(_ ids: Set<UUID>) -> Set<UUID>
    func locateContacts(_ ids: Set<UUID>)
    func activateContactChoice(_ id: UUID)
}

extension GraphSceneDelegate {
    func didUpdateRipple(focus: PondRippleFocus?, neighbors: [RippleNeighbor]) {}
    func didUpdateDisclosure(_ snapshot: PondDisclosureSnapshot) {}
    func offscreenContactIDs(_ ids: Set<UUID>) -> Set<UUID> { ids }
    func locateContacts(_ ids: Set<UUID>) {}
    func activateContactChoice(_ id: UUID) {}
}

/// One bounded disclosure event presented by the graph chrome. A fresh event
/// identifier lets SwiftUI restart transient feedback even for the same people.
struct PondRevealFeedback: Identifiable, Equatable {
    let id: UUID
    let revealedIDs: Set<UUID>
    let offscreenIDs: Set<UUID>

    init(id: UUID = UUID(), revealedIDs: Set<UUID>, offscreenIDs: Set<UUID>) {
        self.id = id
        self.revealedIDs = revealedIDs
        self.offscreenIDs = offscreenIDs.intersection(revealedIDs)
    }

    var count: Int { revealedIDs.count }
    var hasOffscreenContacts: Bool { !offscreenIDs.isEmpty }
}

/// The value needed to present a ripple explorer from the pond.
///
/// Keeping only identifiers and display metadata here lets the graph reload
/// safely while the explorer is presented. The explorer resolves the current
/// `Person` from the data manager when it loads.
struct PondRippleFocus: Identifiable, Equatable {
    let id: UUID
    let contactID: UUID
    let initialTrail: [UUID]?
    let searchRouteSummary: String?

    init(
        id: UUID = UUID(),
        contactID: UUID,
        initialTrail: [UUID]? = nil,
        searchRouteSummary: String? = nil
    ) {
        self.id = id
        self.contactID = contactID
        self.initialTrail = initialTrail
        self.searchRouteSummary = searchRouteSummary
    }
}

// MARK: - GraphViewModel
@MainActor
final class GraphViewModel: ObservableObject {
    
    // MARK: - Dependencies
    private let dataManager: GoldfishDataManager
    
    // MARK: - Scene Communication
    weak var sceneDelegate: GraphSceneDelegate? {
        didSet {
            publishRippleSnapshot()
            publishDisclosure()
        }
    }
    
    // MARK: - State
    
    /// Flag to prevent infinite feedback loops when updating from the scene
    private var isUpdatingFromScene = false
    
    @Published var selectedContactID: UUID? {
        didSet {
            sceneDelegate?.didSelectContact(selectedContactID)
        }
    }
    
    @Published var searchMatchedIDs: Set<UUID>? {
        didSet {
            sceneDelegate?.didUpdateSearchMatches(searchMatchedIDs)
            if let ids = searchMatchedIDs, ids.count == 1, let id = ids.first {
                centerOnContact(id)
            }
        }
    }
    

    
    @Published var selectedPondFilter: String? {
        didSet {
            sceneDelegate?.didUpdatePondFilter(selectedPondFilter)
        }
    }
    
    // We use @SceneStorage in the View, but track it here for logic
    @Published var zoomLevel: CGFloat = 1.0 {
        didSet {
            guard !isUpdatingFromScene else { return }
            let clamped = min(max(zoomLevel, 0.001), 4.0)
            if clamped != zoomLevel {
                zoomLevel = clamped  // triggers didSet once more, then guard exits
                return
            }
            sceneDelegate?.didUpdateZoom(zoomLevel)
        }
    }
    
    @Published var cameraPosition: CGPoint = .zero {
        didSet {
            guard !isUpdatingFromScene else { return }
            sceneDelegate?.didUpdateCameraPosition(cameraPosition)
        }
    }
    
    @Published var graphLevels: [GraphLevel]?
    @Published var isLoading: Bool = false
    @Published var hasNoData: Bool = false
    @Published var errorMessage: String?
    private(set) var groups: [GoldfishCircle] = []
    
    /// When `true`, only demo contacts are shown in the graph.
    var isDemoMode: Bool = false {
        didSet {
            guard oldValue != isDemoMode else { return }
            closeRipple()
            levelsLoaded = false
        }
    }
    
    /// When set, triggers the Add Relationship sheet for drag-to-connect
    @Published var pendingConnectionFrom: UUID?
    @Published var pendingConnectionTo: UUID?
    
    @Published var pendingPondMovePerson: UUID?
    @Published var pendingPondMoveTarget: String?
    
    @Published var pendingActionContactID: UUID?

    /// More than one visible contact occupied the stationary tap target. The
    /// route is left untouched until the user chooses one of these candidates.
    @Published private(set) var pendingContactChoiceIDs: [UUID] = []

    /// Latest non-empty reveal, used for transient count and explicit Locate UI.
    @Published private(set) var latestPondReveal: PondRevealFeedback?

    /// A focused relationship view leaves the pond camera and membership intact.
    @Published private(set) var rippleFocus: PondRippleFocus?

    /// The current ordered path through the in-canvas ripple.
    var rippleTrail: [UUID] { rippleFocus?.initialTrail ?? [] }

    /// The person at the end of the current ripple trail.
    var rippleCurrentPerson: Person? {
        guard let currentID = rippleTrail.last ?? rippleFocus?.contactID else { return nil }
        return rippleGraph?.peopleByID[currentID]
    }

    /// Connections from the current person, excluding people already on the trail.
    var rippleNeighbors: [RippleNeighbor] {
        guard let currentID = rippleTrail.last ?? rippleFocus?.contactID else { return [] }
        return rippleGraph?.neighbors(of: currentID, excluding: Set(rippleTrail)) ?? []
    }

    /// The four connections represented on the current in-canvas ripple page.
    var visibleRippleNeighbors: [RippleNeighbor] {
        guard ripplePageCount > 0 else { return [] }
        let start = ripplePage * 4
        guard start < rippleNeighbors.count else { return [] }
        return Array(rippleNeighbors.dropFirst(start).prefix(4))
    }

    @Published private(set) var ripplePage: Int = 0
    @Published private(set) var ripplePageCount: Int = 0

    @Published private(set) var pondDisclosureSnapshot: PondDisclosureSnapshot = .empty
    private var pondDisclosure: PondDisclosure?

    var disclosureSnapshot: PondDisclosureSnapshot { pondDisclosureSnapshot }
    var disclosureTrail: [UUID] { pondDisclosureSnapshot.trail }
    var selectedPondContactID: UUID? { pondDisclosureSnapshot.selectedID }
    var disclosureCurrentPerson: Person? {
        guard let id = pondDisclosureSnapshot.selectedID ?? pondDisclosureSnapshot.trail.last else { return nil }
        return pondDisclosure?.peopleByID[id]
    }
    func disclosureRole(for id: UUID) -> RippleNeighbor? {
        let anchor: UUID?
        if pondDisclosureSnapshot.trail.last == id {
            anchor = pondDisclosureSnapshot.trail.dropLast().last
        } else {
            anchor = pondDisclosureSnapshot.parents[id] ?? pondDisclosureSnapshot.trail.last
        }
        guard let anchor else { return nil }
        return rippleGraph?.role(of: id, relativeTo: anchor)
    }
    func hiddenPondNeighborCount(for id: UUID) -> Int {
        pondDisclosure?.hiddenNeighborCount(for: id) ?? 0
    }
    func isPondConnectionsExpanded(_ id: UUID) -> Bool {
        pondDisclosure?.isExpanded(id) ?? false
    }
    func canShowPondConnections(_ id: UUID) -> Bool {
        pondDisclosure?.canExpand(id) ?? false
    }

    /// Bumps each time the user confirms a new connection. The walkthrough
    /// observes this to detect the "drag-to-link" step being completed.
    @Published var linkCreatedTick: Int = 0
    
    @Published var levelsLoaded = false
    private var isLoadingInProgress = false
    
    // MARK: - Init
    init(dataManager: GoldfishDataManager) {
        self.dataManager = dataManager
    }
    
    // MARK: - Methods
    func loadGraph() {
        guard !levelsLoaded, !isLoadingInProgress else { return }
        // SwiftData work is synchronous on the main actor. No queued stale load
        // can overwrite a subsequent demo switch or deletion.
        isLoadingInProgress = true
        isLoading = true
        defer { isLoading = false; isLoadingInProgress = false }
        do {
            groups = try dataManager.fetchAllCircles()
            if let selected = selectedPondFilter, selected != "unassigned", !groups.contains(where: { $0.id.uuidString == selected }) {
                selectedPondFilter = nil
            }
            let levels = try dataManager.buildGraphLayout(demoMode: isDemoMode) ?? []
            graphLevels = levels
            if selectedPondFilter == "unassigned", !levels.flatMap(\.allContacts).contains(where: { !$0.isMe && $0.primaryCircle == nil }) {
                selectedPondFilter = nil
            }
            hasNoData = !levels.flatMap(\.allContacts).contains(where: { !$0.isMe })
            // Reconcile the in-canvas route against the new graph before the
            // scene rebuilds its nodes, so a deleted focus cannot be revived
            // by the scene's graph snapshot.
            levelsLoaded = true
            invalidateRippleFocusIfNeeded()
            let contacts = levels.flatMap(\.allContacts)
            if var disclosure = pondDisclosure {
                disclosure.reload(people: contacts)
                pondDisclosure = disclosure
            } else {
                pondDisclosure = PondDisclosure(people: contacts)
            }
            sceneDelegate?.didUpdateGroups(groups)
            sceneDelegate?.didUpdateGraphLevels(levels)
            publishRippleSnapshot()
            publishDisclosure()
            errorMessage = nil
        } catch {
            graphLevels = []
            sceneDelegate?.didUpdateGraphLevels([])
            closeRipple()
            errorMessage = error.localizedDescription
        }
    }

    func refreshGraph() { levelsLoaded = false; loadGraph() }

    func selectContact(_ id: UUID?) {
        selectedContactID = id
        if let id = id, rippleFocus == nil, pondDisclosureSnapshot.selectedID != id {
            centerOnContact(id)
        }
    }

    func openRipple(
        _ id: UUID,
        initialTrail: [UUID]? = nil,
        searchRouteSummary: String? = nil,
        summary: String? = nil
    ) {
        if !levelsLoaded {
            loadGraph()
        }
        guard isValidRippleContact(id) else { return }

        selectedContactID = nil
        let graph = rippleGraph
        let route: [UUID]
        let resolvedSummary = summary ?? searchRouteSummary
        let routeSummary: String?
        if let initialTrail {
            route = validatedRoute(initialTrail, endingAt: id, graph: graph)
            routeSummary = resolvedSummary
        } else if let existing = rippleFocus, let index = rippleTrail.firstIndex(of: id) {
            route = Array(rippleTrail.prefix(index + 1))
            routeSummary = resolvedSummary ?? existing.searchRouteSummary
        } else if let currentID = rippleTrail.last,
                  graph?.neighbors(of: currentID, excluding: Set(rippleTrail)).contains(where: { $0.id == id }) == true {
            route = graph?.validatedTrail(rippleTrail + [id]) ?? [id]
            routeSummary = resolvedSummary ?? rippleFocus?.searchRouteSummary
        } else {
            route = rootRoute(to: id, graph: graph)
            routeSummary = resolvedSummary
        }

        // A non-route tap on the current person is intentionally a no-op. The
        // pond chrome owns the explicit collapse action.
        if id == rippleTrail.last, initialTrail == nil, resolvedSummary == nil { return }

        let validRoute = route.isEmpty ? [id] : route
        rippleFocus = PondRippleFocus(
            contactID: id,
            initialTrail: validRoute,
            searchRouteSummary: routeSummary
        )
        pondDisclosure?.revealRoute(validRoute, selecting: id)
        publishRippleSnapshot(resetPage: true)
        publishDisclosure()
    }

    func closeRipple() {
        rippleFocus = nil
        ripplePage = 0
        ripplePageCount = 0
        pendingContactChoiceIDs.removeAll()
        latestPondReveal = nil
        pondDisclosure?.reset()
        pondDisclosureSnapshot = pondDisclosure?.snapshot ?? .empty
        sceneDelegate?.didUpdateRipple(focus: nil, neighbors: [])
        sceneDelegate?.didUpdateDisclosure(pondDisclosureSnapshot)
    }

    func togglePondConnections(id: UUID) {
        let visibleBefore = pondDisclosureSnapshot.visibleIDs
        pondDisclosure?.togglePondConnections(id: id)
        publishDisclosure()
        publishRevealFeedback(visibleBefore: visibleBefore)
    }

    func togglePondConnections(_ id: UUID) {
        togglePondConnections(id: id)
    }

    func togglePondConnections(for id: UUID) {
        togglePondConnections(id: id)
    }

    func showMorePondConnections(id: UUID) {
        let visibleBefore = pondDisclosureSnapshot.visibleIDs
        pondDisclosure?.showMorePondConnections(id: id)
        publishDisclosure()
        publishRevealFeedback(visibleBefore: visibleBefore)
    }

    func showMorePondConnections(_ id: UUID) {
        showMorePondConnections(id: id)
    }

    func showMorePondConnections(for id: UUID) {
        showMorePondConnections(id: id)
    }

    func collapseAllPondConnections() {
        pondDisclosure?.collapseAllPondConnections()
        rippleFocus = nil
        ripplePage = 0
        ripplePageCount = 0
        pendingContactChoiceIDs.removeAll()
        latestPondReveal = nil
        sceneDelegate?.didUpdateRipple(focus: nil, neighbors: [])
        publishDisclosure()
    }

    func revealHiddenPeople(in pondID: String) {
        let visibleBefore = pondDisclosureSnapshot.visibleIDs
        pondDisclosure?.revealHiddenPeople(in: pondID)
        publishDisclosure()
        publishRevealFeedback(visibleBefore: visibleBefore)
    }

    func revealHiddenPeople(pondID: String) {
        revealHiddenPeople(in: pondID)
    }

    func selectPondContact(id: UUID?) {
        pondDisclosure?.selectPondContact(id: id)
        publishDisclosure()
    }

    func selectPondContact(_ id: UUID?) {
        selectPondContact(id: id)
    }

    /// Moves the inspector to a breadcrumb ancestor without closing any other
    /// disclosed branch or changing the active pond filter.
    @discardableResult
    func selectDisclosureTrailAncestor(_ id: UUID) -> Bool {
        guard pondDisclosure?.selectTrailAncestor(id: id) == true else { return false }
        if let index = rippleTrail.firstIndex(of: id) {
            rippleFocus = PondRippleFocus(
                contactID: id,
                initialTrail: Array(rippleTrail.prefix(index + 1)),
                searchRouteSummary: rippleFocus?.searchRouteSummary
            )
            publishRippleSnapshot(resetPage: true)
        }
        publishDisclosure()
        return true
    }

    func presentContactChoices(_ ids: [UUID]) {
        var seen: Set<UUID> = []
        pendingContactChoiceIDs = ids.filter { id in
            seen.insert(id).inserted && isValidRippleContact(id)
        }
    }

    func choosePendingContact(_ id: UUID) {
        guard pendingContactChoiceIDs.contains(id) else { return }
        pendingContactChoiceIDs.removeAll()
        sceneDelegate?.activateContactChoice(id)
    }

    func cancelPendingContactChoice() {
        pendingContactChoiceIDs.removeAll()
    }

    func locateLatestPondReveal() {
        guard let latestPondReveal else { return }
        sceneDelegate?.locateContacts(latestPondReveal.revealedIDs)
        self.latestPondReveal = nil
    }

    func dismissPondRevealFeedback() {
        latestPondReveal = nil
    }

    func returnToRipple(at index: Int) {
        guard rippleTrail.indices.contains(index) else { return }
        let id = rippleTrail[index]
        rippleFocus = PondRippleFocus(
            contactID: id,
            initialTrail: Array(rippleTrail.prefix(index + 1)),
            searchRouteSummary: rippleFocus?.searchRouteSummary
        )
        publishRippleSnapshot(resetPage: true)
    }

    func nextRipplePage() {
        guard ripplePage + 1 < ripplePageCount else { return }
        ripplePage += 1
        publishRippleSnapshot()
    }

    func previousRipplePage() {
        guard ripplePage > 0 else { return }
        ripplePage -= 1
        publishRippleSnapshot()
    }

    /// Returns connections beyond this person, excluding the current trail and
    /// the person itself. This powers the compact +N badges.
    func rippleFurtherCount(for id: UUID) -> Int {
        guard rippleFocus != nil else { return 0 }
        return rippleGraph?.neighbors(of: id, excluding: Set(rippleTrail + [id])).count ?? 0
    }

    private func isValidRippleContact(_ id: UUID) -> Bool {
        let contacts = (graphLevels ?? []).flatMap(\.allContacts)
        guard let person = contacts.first(where: { $0.id == id }), !person.isDeleted else {
            return false
        }
        // The graph always includes Me, while every other node belongs to the
        // currently active personal/sample scope.
        return person.isMe || person.isDemo == isDemoMode
    }

    private func invalidateRippleFocusIfNeeded() {
        guard let focus = rippleFocus else { return }
        if !isValidRippleContact(focus.contactID) {
            closeRipple()
            return
        }

        let route = validatedRoute(focus.initialTrail ?? [], endingAt: focus.contactID, graph: rippleGraph)
        let validRoute = route.isEmpty ? [focus.contactID] : route
        if validRoute != (focus.initialTrail ?? []) {
            rippleFocus = PondRippleFocus(
                id: focus.id,
                contactID: focus.contactID,
                initialTrail: validRoute,
                searchRouteSummary: focus.searchRouteSummary
            )
        }
    }

    private var rippleGraph: RippleGraph? {
        guard let graphLevels else { return nil }
        return RippleGraph(people: graphLevels.flatMap(\.allContacts))
    }

    private func rootRoute(to id: UUID, graph: RippleGraph?) -> [UUID] {
        guard let graph, graph.peopleByID[id] != nil else { return [id] }
        let path = graph.initialTrail(to: id)
        return path.last == id ? path : [id]
    }

    private func validatedRoute(_ route: [UUID], endingAt id: UUID, graph: RippleGraph?) -> [UUID] {
        guard let graph else { return [id] }
        let validated = graph.validatedTrail(route)
        if let index = validated.firstIndex(of: id) {
            return Array(validated.prefix(index + 1))
        }
        return rootRoute(to: id, graph: graph)
    }

    private func publishRippleSnapshot(resetPage: Bool = false) {
        let count = rippleNeighbors.count
        let pageCount = rippleFocus == nil ? 0 : max(1, (count + 3) / 4)
        ripplePageCount = pageCount
        if resetPage || pageCount == 0 {
            ripplePage = 0
        } else {
            ripplePage = min(ripplePage, pageCount - 1)
        }
        sceneDelegate?.didUpdateRipple(focus: rippleFocus, neighbors: visibleRippleNeighbors)
    }

    private func publishDisclosure() {
        pondDisclosureSnapshot = pondDisclosure?.snapshot ?? .empty
        sceneDelegate?.didUpdateDisclosure(pondDisclosureSnapshot)
    }

    private func publishRevealFeedback(visibleBefore: Set<UUID>) {
        let revealed = pondDisclosureSnapshot.visibleIDs.subtracting(visibleBefore)
        guard !revealed.isEmpty else {
            latestPondReveal = nil
            return
        }
        let offscreen = sceneDelegate?.offscreenContactIDs(revealed) ?? revealed
        latestPondReveal = PondRevealFeedback(revealedIDs: revealed, offscreenIDs: offscreen)
    }
    
    func centerOnContact(_ id: UUID) {
        sceneDelegate?.centerOnContact(id)
    }
    
    func centerOnPond(name: String) {
        if selectedPondFilter == name {
            // Toggle off if already selected
            selectedPondFilter = nil
            sceneDelegate?.fitToGraph()
        } else {
            selectedPondFilter = name
            sceneDelegate?.centerOnPond(name: name)
        }
    }
    
    func zoomIn() {
        zoomLevel = min(zoomLevel * 1.2, 4.0)
        // didSet already calls sceneDelegate?.didUpdateZoom — no second call needed
    }

    func zoomOut() {
        zoomLevel = max(zoomLevel / 1.2, 0.001)
        // didSet already calls sceneDelegate?.didUpdateZoom — no second call needed
    }
    
    func resetCamera() {
        sceneDelegate?.centerOnMe()
    }
    
    // MARK: - Scene Feedback
    /// Called by the scene when user drags camera
    func updateCameraFromScene(position: CGPoint, zoom: CGFloat) {
        isUpdatingFromScene = true
        if self.cameraPosition != position {
            self.cameraPosition = position
        }
        if self.zoomLevel != zoom {
            self.zoomLevel = zoom
        }
        isUpdatingFromScene = false
    }
    
    /// Called by the scene when user drags a node onto another node
    func requestConnection(from sourceID: UUID, to targetID: UUID) {
        pendingConnectionFrom = sourceID
        pendingConnectionTo = targetID
    }
    
    func confirmConnection() {
        guard let fromID = pendingConnectionFrom, let toID = pendingConnectionTo else { return }
        // The animation will be triggered by GraphContainerView after the data is updated
        // But we can also trigger it directly if we want it to feel immediate
        sceneDelegate?.animateNewConnection(from: fromID, to: toID)
        linkCreatedTick += 1
    }
    
    /// Called after the marker crosses into a different pond and is released.
    func requestPondMove(for personID: UUID, to pondName: String) {
        guard let person = graphLevels?.flatMap(\.allContacts).first(where: { $0.id == personID }),
              !person.isDeleted, !person.isMe, person.isDemo == isDemoMode,
              (person.primaryCircle?.id.uuidString ?? "unassigned") != pondName,
              pondName == "unassigned" || groups.contains(where: { $0.id.uuidString == pondName }) else { return }
        pendingPondMovePerson = personID
        pendingPondMoveTarget = pondName
    }
    
    /// Called by the scene when a user long presses a node
    func didLongPressContact(_ id: UUID) {
        pendingActionContactID = id
    }
}
