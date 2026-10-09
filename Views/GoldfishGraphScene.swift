import SpriteKit
import SwiftUI

// MARK: - Graph Design Tokens (SpriteKit / UIColor mirror of GoldfishDS)
/// concrete RGBA against a trait collection. SKScene colors do NOT auto-adapt to
/// light/dark, so the scene resolves these against `traitForResolution` at build time
/// and re-resolves on `traitCollectionDidChange`. The line palette mirrors
/// `GoldfishDS.pondTone` EXACTLY (same fixed names + FNV-1a hash + modulo) so the
/// SwiftUI and SpriteKit sides always agree.
enum GraphInk {
    /// Trait used to resolve appearance-dependent colors. Updated by the scene at
    /// setup and whenever the interface style changes.
    static var traitForResolution: UITraitCollection = .current

    private static var isDark: Bool {
        traitForResolution.userInterfaceStyle == .dark
    }
    private static func pick(light: UInt32, dark: UInt32) -> UIColor {
        UIColor(hex: isDark ? dark : light)
    }

    /// The map canvas: warm off-white paper by day, near-black night map after dark.
    static var background: UIColor { pick(light: 0xF5F0EB, dark: 0x1A1614) }
    static var indigo: UIColor { pick(light: 0xB74F3A, dark: 0xC96A54) }
    static var separator: UIColor { ink(0.18) }
    static var stationFill: UIColor { pick(light: 0xEDE7E0, dark: 0x2A2420) }

    static func ink(_ opacity: CGFloat) -> UIColor {
        pick(light: 0x1A1614, dark: 0xF5F0EB).withAlphaComponent(traitForResolution.accessibilityContrast == .high && opacity >= 0.25 ? max(0.75, opacity) : min(1, max(0, opacity)))
    }

    /// Convenience semantic ink tokens.
    static var label: UIColor { ink(1.0) }
    static var secondaryLabel: UIColor { ink(0.62) }
    static var tertiaryLabel: UIColor { ink(0.40) }

    static func contrastText(on color: UIColor) -> UIColor {
        GoldfishDS.avatarInk(on: color)
    }

    static var gold: UIColor { UIColor(hex: 0xD9A441) }
    static func pondTone(_ pondName: String?) -> UIColor {
        UIColor(GoldfishDS.pondTone(pondName)).resolvedColor(with: traitForResolution)
    }
    static func graphTone(_ group: GoldfishCircle?) -> UIColor {
        UIColor(GoldfishDS.graphTone(group)).resolvedColor(with: traitForResolution)
    }
    static func serifFont(size: CGFloat, weight: UIFont.Weight = .medium) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        return UIFont(descriptor: base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor, size: size)
    }

}

/// Resolves a completed marker drag against the drawn pond boundaries. The
/// helper deliberately works on the same content-space paths that SpriteKit
/// renders, so gesture feedback and the drop decision cannot disagree about
/// which side of a border the marker occupies.
enum PondDragBoundary {
    /// Returns a pond only when the marker started outside that pond and ended
    /// clearly inside it. The six screen-point boundary margin prevents a
    /// marker resting on a stroke from producing a move proposal due to touch
    /// jitter. Candidates are sorted to keep overlapping-path behavior stable.
    static func target(
        from originalPoint: CGPoint,
        to finalPoint: CGPoint,
        sourcePondID: String?,
        basins: [String: CGPath],
        zoom: CGFloat
    ) -> String? {
        guard zoom.isFinite, zoom > 0,
              originalPoint.x.isFinite, originalPoint.y.isFinite,
              finalPoint.x.isFinite, finalPoint.y.isFinite else { return nil }

        let deadbandWidth = 12 / zoom
        guard deadbandWidth.isFinite, deadbandWidth > 0 else { return nil }

        let orderedBasins = basins.sorted { $0.key < $1.key }
        for (name, path) in orderedBasins {
            guard name != sourcePondID else { continue }
            guard path.boundingBoxOfPath.isNull == false,
                  path.boundingBoxOfPath.isEmpty == false else { continue }

            // A destination must be a genuine boundary transition. This also
            // suppresses an initial touch on an overlapping target basin.
            guard path.contains(finalPoint), !path.contains(originalPoint) else { continue }

            let boundary = path.copy(
                strokingWithWidth: deadbandWidth,
                lineCap: .round,
                lineJoin: .round,
                miterLimit: 10
            )
            // Only the destination needs clearance. The source marker may
            // legitimately begin close to its edge; the deliberate drag
            // threshold already filters incidental movement there.
            guard !boundary.contains(finalPoint) else { continue }
            return name
        }
        return nil
    }
}

// MARK: - GoldfishGraphScene
/// Deterministic radial ponds, retaining the current graph interactions and display forest.
final class GoldfishGraphScene: SKScene, GraphSceneDelegate {

    /// The SpriteView's own bounds are authoritative for walkthrough viewport
    /// placement; SwiftUI layout probes can briefly report a provisional frame.
    var onViewportChange: ((CGSize, CGRect) -> Void)?

    // MARK: - Delegate
    weak var graphDelegate: GraphViewModel?
    /// The guided profile lesson retains its explicit tap-to-profile action.
    var opensRipplesOnTap = true
    var showsMeDuringGuidedTour = false {
        didSet {
            guard oldValue != showsMeDuringGuidedTour, sceneReady else { return }
            refreshMapMePosition()
            if let meNode = personNodes.values.first(where: { $0.isMe }) {
                meNode.position = presentedPosition(for: meNode.personID)
            }
            evaluateNodeVisibility(animated: false)
            updateLOD()
            arrangeNameLabels()
            renderEdges()
            if showsMeDuringGuidedTour { fitToComposition(animated: true) }
        }
    }

    // MARK: - Camera
    private let cameraNode = SKCameraNode()
    private var currentZoom: CGFloat = 1.0
    private var actualCameraZoom: CGFloat {
        let scale = cameraNode.xScale
        return scale.isFinite && scale > 0 ? 1 / scale : currentZoom
    }

#if DEBUG
    var currentZoomForDebug: CGFloat { currentZoom }
#endif

    // MARK: - Content
    private let contentNode = SKNode()
    private var personNodes: [UUID: PersonNode] = [:]
    private var edgeNodes: [String: SKShapeNode] = [:]
    private var graphLevelsCache: [GraphLevel] = []

    // MARK: - Layout
    /// Deterministic resting slot for each node. Me keeps a canonical slot for
    /// graph semantics and walkthroughs; the overview does not reserve space for it.
    private var layoutSlots: [UUID: CGPoint] = [:]
    private var mapMePosition: CGPoint = .zero
    private let initialRadius: CGFloat = 130
    private let basinStrokeWidth: CGFloat = 1.2

    private var pondBasins: [String: SKNode] = [:]   // circleName -> track container
    private var pondLabels: [String: SKLabelNode] = [:]
    private struct PondInfo {
        let id: String
        let title: String
        let color: UIColor
        let memberIDs: [UUID]
    }
    private var pondInfos: [PondInfo] = []
    /// User translations are kept separate from the deterministic base slots so
    /// a disclosure/layout rebuild can reapply them without accumulating drift.
    private var pondLayoutOffsets: [String: CGPoint] = [:]
    private var availableGroups: [GoldfishCircle] = []
    func didUpdateGroups(_ groups: [GoldfishCircle]) { availableGroups = groups }

    func didRestoreAutomaticPondLayout() {
        cancelPondDrag()
        setPondLayoutOffsets([:])
    }
    private func groupTitle(_ id: String) -> String { pondInfos.first { $0.id == id }?.title ?? "" }
    private func groupTone(_ id: String) -> UIColor { pondInfos.first { $0.id == id }?.color ?? GraphInk.ink(0.4) }

    /// rendering, labels and hit-testing (line solo / double-tap).
    private struct PondGeometry {
        let name: String
        let memberIDs: [UUID]
        let bisector: CGFloat        // radians, the line's departure angle
        let isEmpty: Bool            // line with no stations → short stub track
        let basinPath: CGPath?       // hit zone: the track stroked to lineHitWidth
        let discCenter: CGPoint      // track midpoint (legacy anchor)
        let labelAnchor: CGPoint     // terminus signage position
        let labelDirection: [CGPoint]
    }
    private var pondGeometries: [String: PondGeometry] = [:]

    // MARK: - Drag-Snap Connection
    private var snapPreviewLine: SKShapeNode?
    private var snapTargetID: UUID?
    private let snapDistance: CGFloat = 50

    // MARK: - Gesture State
    private var lastPinchScale: CGFloat = 1.0
    private var selectedNodeID: UUID?

    // MARK: - Progressive Pond Disclosure
    /// Visibility is supplied by the pure disclosure graph service. The scene
    /// keeps every contact and every resting slot, then only fades/hides nodes
    /// and edges whose IDs are absent from the snapshot.
    private var disclosureSnapshot: PondDisclosureSnapshot?
    private var disclosureCameraBeforeFocus: (position: CGPoint, zoom: CGFloat)?

    // MARK: - Focus Mode
    private var soloedPondName: String? = nil
    private var cameraBeforePondFocus: (position: CGPoint, zoom: CGFloat)?

    /// A short map row (typically caused by large accessibility text in the
    /// surrounding SwiftUI header/footer) cannot carry every full name without
    /// turning the overview into a collision field. Keep names for focus and
    /// selection, while the overview uses the same deterministic initials tokens
    /// already used at far zoom. Accessibility and List retain full names.
    private var usesCompactOverviewIdentity: Bool {
        guard selectedNodeID == nil,
              size.height.isFinite, size.height < 420 else { return false }
        return visibleIdentityCount > 8
    }

    private var visibleIdentityCount: Int {
        let visibleIDs = disclosureSnapshot?.visibleIDs
            ?? Set(graphLevelsCache.flatMap(\.allContacts).map(\.id))
        if let soloedPondName,
           let pondIDs = pondInfos.first(where: { $0.id == soloedPondName })?.memberIDs {
            let meIDs = Set(graphLevelsCache.flatMap(\.allContacts).filter(\.isMe).map(\.id))
            return visibleIDs.intersection(Set(pondIDs).union(meIDs)).count
        }
        return visibleIDs.count
    }

    /// Last zoom at which pond labels were counter-scaled (per-frame guard).
    private var lastLabelScaleZoom: CGFloat = 1.0

    // MARK: - Search State
    private var activeSearchIDs: Set<UUID>? = nil

    /// Whether `didMove(to:)` has fired.
    private var sceneReady = false
    private var ownedGestures: [UIGestureRecognizer] = []
    private var traitRegistration: (any UITraitChangeRegistration)?
    private var motionObserver: NSObjectProtocol?
    override func willMove(from view: SKView) {
        for gesture in ownedGestures { view.removeGestureRecognizer(gesture) }
        ownedGestures.removeAll()
        if let traitRegistration { view.unregisterForTraitChanges(traitRegistration) }
        traitRegistration = nil
        if let motionObserver { NotificationCenter.default.removeObserver(motionObserver) }
        motionObserver = nil
        sceneReady = false
        cancelPondDrag()
        touchesCancelled([], with: nil)
        super.willMove(from: view)
    }
    /// Levels received before the scene was ready.
    private var pendingLevels: [GraphLevel]?
    private var initialFitCompleted = false
    /// The model snapshot follows the graph on first mount. Frame that first
    /// direct-contact presentation once, unless the user already moved the map.
    private var awaitsInitialDisclosureFit = true
    private var userAdjustedCameraBeforeInitialDisclosure = false
    /// Once chosen, refreshes rebuild this same direct-first coordinate system
    /// from model-owned direct IDs rather than expanded visibility.
    private var directFirstLayoutActive = false

    /// Measured overlays reserve the correct edge of the graph viewport.
    var topObscuredInset: CGFloat = 0 {
        didSet {
            guard oldValue != topObscuredInset, sceneReady else { return }
            fitToComposition(animated: true)
        }
    }
    var bottomObscuredInset: CGFloat = 0 {
        didSet {
            guard oldValue != bottomObscuredInset, sceneReady else { return }
            fitToComposition(animated: true)
        }
    }

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        // Resolve dynamic system colors against the hosting view's trait collection so
        // the scene matches the current light/dark appearance (SKScene colors do not
        // auto-adapt). Re-resolved in traitCollectionDidChange below.
        GraphInk.traitForResolution = view.traitCollection
        backgroundColor = .clear
        anchorPoint = CGPoint(x: 0.5, y: 0.5)

        // SKScene colors don't auto-adapt to light/dark, so observe the hosting view's
        // interface-style changes and re-skin every cached color when it flips.
        traitRegistration = view.registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self, UITraitPreferredContentSizeCategory.self]) { [weak self] (v: UIView, previous: UITraitCollection) in
            guard let self else { return }
            GraphInk.traitForResolution = v.traitCollection
            self.reskinForCurrentTrait()
        }

        if cameraNode.parent == nil { addChild(cameraNode) }
        camera = cameraNode
        if contentNode.parent == nil { addChild(contentNode) }

        // No physics world is used — the layout is fully deterministic.
        physicsWorld.gravity = .zero
        physicsWorld.speed = 0

        setupGestures(in: view)
        motionObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, UIAccessibility.isReduceMotionEnabled else { return }
            self.interruptCameraAnimation()
            self.contentNode.enumerateChildNodes(withName: "//*") { node, _ in node.removeAllActions() }
            for node in self.personNodes.values { node.setScale(1) }
            self.applyLayout(animated: false)
            self.fitToComposition(animated: false)
            self.evaluateNodeVisibility(animated: false)
        }

        sceneReady = true
        notifyViewportChange(in: view)
        if let pending = pendingLevels {
            pendingLevels = nil
            updateGraph(pending)
        }
    }

    /// Re-applies resolved system colors to every cached node after a light/dark switch.
    private func reskinForCurrentTrait() {
        backgroundColor = .clear

        updateNodesAndEdges(levels: graphLevelsCache)
        // Edges.
        for (edgeKey, edgeNode) in edgeNodes {
            edgeNode.strokeColor = strokeColorForEdge(edgeKey)
        }
        snapPreviewLine?.strokeColor = GraphInk.indigo.withAlphaComponent(0.7)

        for (name, label) in pondLabels {
            label.attributedText = pondLabelText(for: name)
        }

        // Basins + person nodes.
        renderBasins(animated: false)
        renderEdges()
        for node in personNodes.values { node.reskinForCurrentTrait() }
        fitToComposition(animated: false)
        evaluateNodeVisibility(animated: false)
    }

    // MARK: - Gesture Setup

    private func setupGestures(in view: SKView) {
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        view.addGestureRecognizer(pinch)
        ownedGestures.append(pinch)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        view.addGestureRecognizer(pan)
        ownedGestures.append(pan)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        view.addGestureRecognizer(doubleTap)
        ownedGestures.append(doubleTap)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        longPress.cancelsTouchesInView = false
        view.addGestureRecognizer(longPress)
        ownedGestures.append(longPress)
    }

    // MARK: - GraphSceneDelegate

    func didUpdateGraphLevels(_ levels: [GraphLevel]) {
        graphLevelsCache = levels
        if sceneReady {
            updateGraph(levels)
        } else {
            pendingLevels = levels
        }
    }

    /// Applies the model-owned disclosure snapshot without changing any node
    /// position or ordinary camera state. Painted pond outlines intentionally
    /// grow around newly presented members while cached full geometry stays put.
    func didUpdateDisclosure(_ snapshot: PondDisclosureSnapshot) {
        let previous = disclosureSnapshot
        let hadEmphasis = previous?.focusRootID != nil || !(previous?.pathHighlightIDs.isEmpty ?? true)
        let hasEmphasis = snapshot.focusRootID != nil || !snapshot.pathHighlightIDs.isEmpty
        if !hadEmphasis && hasEmphasis {
            disclosureCameraBeforeFocus = (cameraNode.position, actualCameraZoom)
        }
        disclosureSnapshot = snapshot
        if !directFirstLayoutActive, reconcileDirectFirstLayout(allowActivation: true) {
            applyLayout(animated: false)
        }
        if previous?.pathHighlightIDs != snapshot.pathHighlightIDs,
           let meID = graphLevelsCache.flatMap(\.allContacts).first(where: \.isMe)?.id,
           let meNode = personNodes[meID] {
            refreshMapMePosition()
            meNode.position = presentedPosition(for: meID)
        }
        renderBasins(animated: false)
        renderLabels()
        evaluateNodeVisibility(animated: !awaitsInitialDisclosureFit)
        updateLOD()
        arrangeNameLabels()
        renderEdges()
        if hadEmphasis && !hasEmphasis {
            let saved = disclosureCameraBeforeFocus
            disclosureCameraBeforeFocus = nil
            if let saved { restoreCamera(saved) }
        } else if hasEmphasis {
            let focusChanged = previous?.focusRootID != snapshot.focusRootID
            let clusterExpanded = previous?.focusedIDs != snapshot.focusedIDs
            let pathChanged = previous?.pathHighlightIDs != snapshot.pathHighlightIDs
            if focusChanged || clusterExpanded || pathChanged {
                fitFocusedCluster(animated: true)
            }
        }
        fitInitialDisclosureIfNeeded()
    }

    func didSelectContact(_ id: UUID?) {
        highlightNode(id)
    }

    func didUpdateZoom(_ zoom: CGFloat) {
        noteUserCameraAdjustment()
        let clamped = min(max(zoom, 0.001), 4.0)
        currentZoom = clamped
        let action = SKAction.scale(to: 1.0 / clamped, duration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.25)
        action.timingMode = .easeInEaseOut
        if sceneReady { cameraNode.run(action, withKey: "cameraScale") }
        else { cameraNode.setScale(1 / clamped) }
        updateLOD()
        updatePondLabelScales()
        refreshMapMePosition()
        if let meNode = personNodes.values.first(where: { $0.isMe }) {
            meNode.position = presentedPosition(for: meNode.personID)
        }
        arrangeNameLabels()
        renderEdges()
    }

    func didUpdateCameraPosition(_ position: CGPoint) {
        noteUserCameraAdjustment()
        let action = SKAction.move(to: position, duration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.25)
        action.timingMode = .easeInEaseOut
        if sceneReady { cameraNode.run(action, withKey: "cameraMove") }
        else { cameraNode.position = position }
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard size.width >= 50 && size.height >= 50 else { return }
        if let view { notifyViewportChange(in: view) }
        if sceneReady && oldSize != size {
            // The inspector has a stable footprint while selecting/expanding.
            // An actual size change (rotation or Dynamic Type) needs a fresh
            // fit so the Pond stays inside its new viewport.
            if disclosureSnapshot?.focusRootID != nil {
                fitFocusedCluster(animated: false)
            } else {
                fitToComposition(animated: false)
            }
        }
    }

    private func notifyViewportChange(in view: SKView) {
        guard view.window != nil else { return }
        let frame = view.convert(view.bounds, to: nil)
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--ui-layout-trace") {
            print("[GoldfishLayout] SKView bounds=\(view.bounds) frame=\(frame) scene=\(size) insets=(\(topObscuredInset),\(bottomObscuredInset)) zoom=\(currentZoom)")
        }
#endif
        guard frame.width.isFinite, frame.height.isFinite,
              frame.minX.isFinite, frame.minY.isFinite,
              frame.width >= 240, frame.height >= 100 else { return }
        onViewportChange?(view.bounds.size, frame)
    }

    /// Re-publish the live SpriteView frame after SwiftUI installs its observer.
    func reportViewport() {
        if let view { notifyViewportChange(in: view) }
    }

    func centerOnContact(_ id: UUID) {
        guard let node = personNodes[id] else { return }
        let targetZoom: CGFloat = 1.0
        let moveAction = SKAction.move(to: node.position, duration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.5)
        moveAction.timingMode = .easeInEaseOut
        let scaleAction = SKAction.scale(to: 1.0 / targetZoom, duration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.5)
        scaleAction.timingMode = .easeInEaseOut
        cameraNode.run(moveAction, withKey: "cameraMove")
        cameraNode.run(scaleAction, withKey: "cameraScale")
        currentZoom = targetZoom
        updateLOD()
        updatePondLabelScales()
        graphDelegate?.updateCameraFromScene(position: node.position, zoom: targetZoom)
    }

    func centerOnMe() {
        for (id, node) in personNodes where node.isMe {
            centerOnContact(id)
            return
        }
        if let firstID = personNodes.keys.first {
            centerOnContact(firstID)
            return
        }
        fitToGraph()
    }

    func centerOnPond(name: String) {
        // Solo pond: camera fits that pond's basin.
        if let geo = pondGeometries[name] {
            fitToRect(basinBoundingRect(geo), minZoom: 0.001, maxZoom: 1.3, padding: 32, screenInset: 36)
        }
    }

    func fitToGraph() {
        fitToComposition(animated: true)
    }

    /// Returns requested contacts that are not currently presented inside the
    /// usable camera viewport. This is a read-only query and never moves the map.
    func offscreenContactIDs(_ ids: Set<UUID>) -> Set<UUID> {
        let viewport = usableCameraRect
        return Set(ids.filter { id in
            guard let node = personNodes[id], nodeIsPresentedOnCanvas(node), !node.isHidden else { return true }
            let bounds = node.visibleIdentityBounds.offsetBy(dx: node.position.x, dy: node.position.y)
            return !viewport.intersects(bounds)
        })
    }

    /// Explicitly frames a reveal after the user asks to locate it. Disclosure
    /// itself never invokes this method, so branch changes retain the camera.
    func locateContacts(_ ids: Set<UUID>) {
        let bounds = ids.compactMap { id -> CGRect? in
            guard let node = personNodes[id], !node.isHidden else { return nil }
            return node.visibleIdentityBounds.offsetBy(dx: node.position.x, dy: node.position.y)
        }.reduce(nil as CGRect?) { partial, next in
            partial.map { $0.union(next) } ?? next
        }
        guard let bounds else { return }
        fitToRect(bounds, minZoom: 0.001, maxZoom: 1.3, padding: 44, screenInset: 24)
    }

    func activateContactChoice(_ id: UUID) {
        activatePondContact(id)
    }

    private var usableCameraRect: CGRect {
        // Camera actions update `currentZoom` to their destination immediately,
        // while xScale follows the presentation over time. Visibility queries
        // must describe what is rendered at this moment.
        let zoom = 1 / max(cameraNode.xScale, 0.001)
        let width = size.width / zoom
        let bottom = bottomObscuredInset / zoom
        let top = topObscuredInset / zoom
        return CGRect(
            x: cameraNode.position.x - width / 2,
            y: cameraNode.position.y - size.height / (2 * zoom) + bottom,
            width: width,
            height: max(0, size.height / zoom - bottom - top)
        )
    }

    /// Frame the whole composition so nothing clips.
    func fitAllNodesWithLabels(animated: Bool = true) {
        fitToComposition(animated: animated)
    }

    // MARK: - Camera Fitting

    /// Frame the focused pond without pulling the camera back toward Me's old origin.
    private func basinBoundingRect(_ geo: PondGeometry) -> CGRect {
        if let path = presentedPondPath(geo.name) {
            return path.boundingBoxOfPath
        }
        let r: CGFloat = 28 + 40   // disc radius + label margin
        return CGRect(x: geo.discCenter.x - r, y: geo.discCenter.y - r, width: r * 2, height: r * 2)
    }

    /// Fit the visible composition around its own bounds, independent of Me's
    /// canonical origin slot.
    private func fitToComposition(animated: Bool) {
        // Do not measure live labels here. Their counter-scale belongs to the
        // previous viewport. Analytical heading and identity allowances keep
        // fitting deterministic; only the screen-aware painted outline gets
        // one bounded recalculation after zoom changes.
        if let id = soloedPondName, let pond = pondGeometries[id] {
            fitToRect(basinBoundingRect(pond), minZoom: 0.001, maxZoom: 1.3,
                      padding: 32, screenInset: 36, animated: animated)
            return
        }
        func analyticalBounds(includeTitles: Bool = true) -> CGRect {
            var bounds = CGRect.null
            for geo in pondGeometries.values where pondIsPresented(geo.name) {
                bounds = bounds.union(basinBoundingRect(geo))
                guard includeTitles else { continue }
                let anchor = presentedPondLabelAnchor(geo.name)
                guard anchor.x.isFinite && anchor.y.isFinite else { continue }
                let titleSize = pondLabelText(for: geo.name).size()
                let zoom = max(currentZoom, 0.001)
                let width = titleSize.width / zoom
                let height = titleSize.height / zoom
                bounds = bounds.union(CGRect(x: anchor.x - width / 2, y: anchor.y,
                                             width: width, height: height))
            }
            let nodeReach: CGFloat = 22 * 1.4 + 8
            for node in personNodes.values where nodeIsPresentedOnCanvas(node) {
                let point = presentedPosition(for: node.personID)
                guard point.x.isFinite && point.y.isFinite else { continue }
                bounds = bounds.union(CGRect(x: point.x - nodeReach - 60, y: point.y - nodeReach - 40,
                                             width: nodeReach * 2 + 120, height: nodeReach * 2 + 60))
            }
            return bounds.isNull ? CGRect(x: -50, y: -50, width: 100, height: 100) : bounds
        }

        if disclosureSnapshot == nil {
            // Full-graph and accessibility previews must converge from geometry,
            // regardless of any counter-scale left by a previous viewport. Fit
            // that stable base first, then grow the fitted world rect monotonically
            // around the counter-scaled headings. The small screen-space margin
            // keeps the final heading frames clear of the viewport inset.
            let baseRect = analyticalBounds(includeTitles: false)
            var fittedRect = baseRect
            var needsFinalFit = false
            for _ in 0..<12 {
                fitToRect(fittedRect, minZoom: 0.001, maxZoom: 1.3,
                          padding: 0, screenInset: 42, animated: animated)
                let worldMargin = 10 / max(currentZoom, 0.001)
                var requiredRect = baseRect
                for label in pondLabels.values where !label.isHidden {
                    let frame = label.calculateAccumulatedFrame()
                    guard !frame.isNull && !frame.isInfinite else { continue }
                    requiredRect = requiredRect.union(
                        frame.insetBy(dx: -worldMargin, dy: -worldMargin)
                    )
                }
                let expandedRect = fittedRect.union(requiredRect)
                let tolerance = 0.25 / max(currentZoom, 0.001)
                if fittedRect.insetBy(dx: -tolerance, dy: -tolerance).contains(expandedRect) {
                    needsFinalFit = false
                    break
                }
                fittedRect = expandedRect
                needsFinalFit = true
            }
            if needsFinalFit {
                fitToRect(fittedRect, minZoom: 0.001, maxZoom: 1.3,
                          padding: 0, screenInset: 42, animated: animated)
            }
            return
        }
        let rect = analyticalBounds()
        fitToRect(rect, minZoom: 0.001, maxZoom: 1.3, padding: 0, screenInset: 42, animated: animated)
        let adjustedRect = analyticalBounds()
        if abs(adjustedRect.width - rect.width) > 0.5 || abs(adjustedRect.height - rect.height) > 0.5 {
            fitToRect(adjustedRect, minZoom: 0.001, maxZoom: 1.3, padding: 0, screenInset: 42, animated: animated)
        }
    }

    /// First-mount fit is the only disclosure mutation allowed to move the
    /// camera. Later selection, expansion and collapse retain the user's view.
    private func fitInitialDisclosureIfNeeded() {
        guard awaitsInitialDisclosureFit,
              disclosureSnapshot?.visibleIDs.isEmpty == false,
              !personNodes.isEmpty else { return }
        awaitsInitialDisclosureFit = false
        guard !userAdjustedCameraBeforeInitialDisclosure else { return }
        fitToComposition(animated: false)
    }

    private func noteUserCameraAdjustment() {
        userAdjustedCameraBeforeInitialDisclosure = true
        awaitsInitialDisclosureFit = false
    }

    /// Core fit: frame `rect` in content space and respect measured overlays.
    private func fitToRect(_ rect: CGRect, minZoom: CGFloat, maxZoom: CGFloat,
                           padding: CGFloat, screenInset: CGFloat = 0, animated: Bool = true,
                           biasToMe: Bool = false) {
        guard rect.width.isFinite && rect.height.isFinite else { return }

        let minX = rect.minX, maxX = rect.maxX
        let minY = rect.minY, maxY = rect.maxY
        let width = max(maxX - minX, 100) + padding * 2
        let height = max(maxY - minY, 100) + padding * 2
        let cx = (minX + maxX) / 2
        let cy = (minY + maxY) / 2
        guard cx.isFinite && cy.isFinite else { cameraNode.setScale(1.0); return }

        let viewDimWidth = size.width
        let viewDimHeight = size.height
        guard viewDimWidth > 0 && viewDimHeight > 0 else { return }

        // Preserve a usable camera region even during a size transition before
        // SwiftUI has delivered the new card measurement.
        let requestedTop = max(0, topObscuredInset)
        let requestedBottom = max(0, bottomObscuredInset)
        let requestedTotal = requestedTop + requestedBottom
        let maximumObscured = viewDimHeight - min(120, viewDimHeight * 0.3)
        let insetScale = requestedTotal > maximumObscured ? maximumObscured / max(requestedTotal, 1) : 1
        let topInset = requestedTop * insetScale
        let bottomInset = requestedBottom * insetScale
        let visibleHeight = viewDimHeight - topInset - bottomInset
        let verticalMargin = min(screenInset, visibleHeight * 0.2)
        let usableWidth = max(viewDimWidth - screenInset * 2, 1)
        let usableHeight = max(visibleHeight - verticalMargin * 2, 1)

        let zoomX = usableWidth / width
        let zoomY = usableHeight / height
        var targetZoom = min(zoomX, zoomY)
        if !targetZoom.isFinite || targetZoom <= 0 { targetZoom = 1.0 }
        targetZoom = min(max(targetZoom, minZoom), maxZoom)

        var center = CGPoint(x: cx, y: cy)
        if biasToMe && targetZoom.isFinite && targetZoom > 0 {
            let halfViewW = (usableWidth / targetZoom) / 2
            let halfViewH = (usableHeight / targetZoom) / 2
            let slackLeft = max(halfViewW - (cx - minX), 0)   // room to shift center left
            let slackRight = max(halfViewW - (maxX - cx), 0)  // room to shift center right
            let slackDown = max(halfViewH - (cy - minY), 0)   // room to shift center down
            let slackUp = max(halfViewH - (maxY - cy), 0)     // room to shift center up
            let desiredDX = (0 - cx) * 0.2
            let desiredDY = (0 - cy) * 0.2
            let appliedDX = max(-slackLeft, min(slackRight, desiredDX))
            let appliedDY = max(-slackDown, min(slackUp, desiredDY))
            center = CGPoint(x: cx + appliedDX, y: cy + appliedDY)
        }

        // SpriteKit's positive Y points up. Shift the camera toward the covered
        // edge so people land in the unobscured band on the opposite side.
        if targetZoom > 0 {
            center.y += ((topInset - bottomInset) / 2) / targetZoom
        }

        let duration: TimeInterval = animated && !UIAccessibility.isReduceMotionEnabled ? 0.5 : 0.0
        let moveAction = SKAction.move(to: center, duration: duration)
        moveAction.timingMode = .easeInEaseOut
        let scaleAction = SKAction.scale(to: 1.0 / targetZoom, duration: duration)
        scaleAction.timingMode = .easeInEaseOut

        let counterScale = SKAction.run { [weak self] in self?.updatePondLabelScales() }
        if duration == 0 || !sceneReady {
            cameraNode.removeAllActions()
            cameraNode.position = center
            cameraNode.setScale(1 / targetZoom)
        } else {
            cameraNode.run(moveAction, withKey: "cameraMove")
            cameraNode.run(SKAction.sequence([scaleAction, counterScale]), withKey: "cameraScale")
        }

        currentZoom = targetZoom
        updateLOD()
        updatePondLabelScales()
        graphDelegate?.updateCameraFromScene(position: center, zoom: targetZoom)
    }

    /// counter-scaling (capped so close zoom doesn't balloon anything).
    private func updatePondLabelScales() {
        // Signage remains readable in screen points when the composition is fitted.
        let zoom = max(currentZoom, 0.001)
        let scale = 1 / zoom
        renderBasins(animated: false)
        for label in pondLabels.values { label.setScale(scale) }
        for (name, label) in pondLabels where !label.isHidden {
            label.position = presentedPondLabelAnchor(name)
        }
        for basin in pondBasins.values {
            for child in basin.children {
                (child as? SKShapeNode)?.lineWidth = 1.2 / zoom
            }
        }
        for node in personNodes.values { node.updateScreenScale(zoom: zoom) }
        arrangePondLabels()
        arrangeNameLabels()
        for (key, edge) in edgeNodes { edge.lineWidth = edgeScreenWidth(key) / zoom }
        lastLabelScaleZoom = currentZoom
    }

    /// Keep progressive pond headings attached to their reserved title bands.
    private func arrangePondLabels() {
        let labels = pondLabels.keys.compactMap { name -> (String, SKLabelNode, CGPoint)? in
            guard let label = pondLabels[name], !label.isHidden else { return nil }
            return (name, label, presentedPondLabelAnchor(name))
        }.sorted { lhs, rhs in
            if lhs.2.y != rhs.2.y { return lhs.2.y > rhs.2.y }
            if lhs.2.x != rhs.2.x { return lhs.2.x < rhs.2.x }
            return lhs.0 < rhs.0
        }

        // Progressive ponds reserve an analytical in-bank title band.
        if disclosureSnapshot != nil {
            for (_, label, anchor) in labels { label.position = anchor }
            return
        }

        // Legacy/full-graph previews use their cached full basins. Accessibility
        // counter-scaling can make those outside headings collide, so retain the
        // deterministic bounded placer for that mode only.
        let zoom = max(currentZoom, 0.001)
        var occupied: [CGRect] = personNodes.values.compactMap { node in
            guard !node.isHidden, node.alpha > 0.25 else { return nil }
            let point = presentedPosition(for: node.personID)
            let bounds = node.visibleIdentityBounds.offsetBy(dx: point.x, dy: point.y)
            return bounds.isNull || bounds.isInfinite ? nil : bounds.insetBy(dx: -3 / zoom, dy: -2 / zoom)
        }
        for (_, label, anchor) in labels {
            label.position = anchor
            let baseFrame = label.calculateAccumulatedFrame()
            let horizontalStep = max(baseFrame.width * 0.72, 90 / zoom)
            let verticalStep = max(baseFrame.height * 1.25, 38 / zoom)
            let offsets: [CGPoint] = [
                .zero,
                CGPoint(x: 0, y: verticalStep), CGPoint(x: 0, y: -verticalStep),
                CGPoint(x: horizontalStep, y: 0), CGPoint(x: -horizontalStep, y: 0),
                CGPoint(x: horizontalStep, y: verticalStep), CGPoint(x: -horizontalStep, y: verticalStep),
                CGPoint(x: horizontalStep, y: -verticalStep), CGPoint(x: -horizontalStep, y: -verticalStep),
                CGPoint(x: 0, y: verticalStep * 2), CGPoint(x: 0, y: -verticalStep * 2)
            ]
            var chosenFrame: CGRect?
            for offset in offsets {
                label.position = CGPoint(x: anchor.x + offset.x, y: anchor.y + offset.y)
                let frame = label.calculateAccumulatedFrame().insetBy(dx: -3 / zoom, dy: -2 / zoom)
                if !occupied.contains(where: { $0.intersects(frame) }) {
                    chosenFrame = frame
                    break
                }
            }
            if let chosenFrame { occupied.append(chosenFrame) }
            else {
                label.position = anchor
                occupied.append(label.calculateAccumulatedFrame())
            }
        }
    }

    private func arrangeNameLabels() {
        let visible = personNodes.values.filter { !$0.isHidden && $0.wantsNameLabel }
            .sorted { a, b in a.isMe != b.isMe ? a.isMe : a.personID.uuidString < b.personID.uuidString }
        // Keep names at the standard screen size while collision checks use
        // their true counter-scaled frames.
        for node in visible { node.setNameScale(max(1, 0.85 / max(currentZoom, 0.001))) }
        for node in visible { node.setNameCollisionHidden(false) }
        let canUseDisclosureShortNames = disclosureSnapshot != nil && visibleIdentityCount <= 8
        let coinBounds = Dictionary(uniqueKeysWithValues: personNodes.values.compactMap { node -> (UUID, CGRect)? in
            guard !node.isHidden, node.alpha > 0.01,
                  let markerBounds = node.visibleMarkerBounds else { return nil }
            let point = presentedPosition(for: node.personID)
            return (node.personID, markerBounds.offsetBy(dx: point.x, dy: point.y))
        })
        var occupied: [CGRect] = pondLabels.values.filter { !$0.isHidden && $0.alpha > 0.5 }.map { $0.calculateAccumulatedFrame() }
        func suppressCrowdedContext(on node: PersonNode, at point: CGPoint) {
            guard node.contextRoleText != nil else { return }
            let roleBounds = node.contextRoleBounds.offsetBy(dx: point.x, dy: point.y)
            if occupied.contains(where: { $0.intersects(roleBounds) }) ||
                coinBounds.contains(where: { $0.key != node.personID && $0.value.intersects(roleBounds) }) {
                // The person's identity is primary. Role and age remain
                // available in the inspector when their secondary line would
                // crowd the neighboring canvas labels.
                node.setContextRole(nil, symbol: nil)
            }
        }
        for node in visible {
            let point = presentedPosition(for: node.personID)
            var placed = false
            // Names follow one visual rule throughout the map: centered below
            // the contact. When a heading crowds the standard gap, step the
            // centered label farther down before considering a shorter identity.
            // This keeps a consistent under-node rule without hiding names or
            // scattering them sideways.
            func placeBelowCoin(maxScreenOffset: CGFloat = 0) -> Bool {
                let zoom = max(currentZoom, 0.001)
                let steps = Int(maxScreenOffset / 8)
                for step in 0...steps {
                    node.placeName(zoom: zoom, extraBelow: CGFloat(step * 8) / zoom)
                    let bounds = node.nameBounds.offsetBy(dx: point.x, dy: point.y)
                        .insetBy(dx: -3 / zoom, dy: -2 / zoom)
                    guard !occupied.contains(where: { $0.intersects(bounds) }),
                          !coinBounds.contains(where: { $0.key != node.personID && $0.value.intersects(bounds) }) else {
                        continue
                    }
                    occupied.append(bounds)
                    return true
                }
                return false
            }
            placed = placeBelowCoin(maxScreenOffset: 8)
            if !placed && canUseDisclosureShortNames && !node.isMe &&
                !node.isSelected {
                // Keep small disclosed branches readable in the canvas. The
                // inspector and accessibility tree continue to expose the
                // full saved name.
                node.setDisclosureIdentityExpanded(false)
                node.showFull()
                // Keep the identity block attached beneath the contact when a
                // secondary annotation would prevent the full name from fitting.
                node.setContextRole(nil, symbol: nil)
                placed = placeBelowCoin(maxScreenOffset: 8)
            }
            if !placed && !node.isMe && !node.isSelected { node.setNameCollisionHidden(true) }
        }
        // Reserve every identity before secondary annotations. Iteration order
        // must not let one person's relationship label hide another's name.
        for node in visible {
            let point = presentedPosition(for: node.personID)
            suppressCrowdedContext(on: node, at: point)
            if node.contextRoleText != nil {
                occupied.append(node.contextRoleBounds.offsetBy(dx: point.x, dy: point.y))
            }
        }
    }

    func didUpdatePondFilter(_ name: String?) {
        var cameraToRestore: (position: CGPoint, zoom: CGFloat)?
        if name != nil, soloedPondName == nil {
            cameraBeforePondFocus = (cameraNode.position, currentZoom)
        } else if name == nil, soloedPondName != nil, let previous = cameraBeforePondFocus {
            cameraBeforePondFocus = nil
            cameraToRestore = previous
        }
        soloedPondName = name
        evaluateNodeVisibility(animated: true)
        renderBasins(animated: true)
        renderLabels()
        renderEdges()
        if let cameraToRestore { restoreCamera(cameraToRestore) }
        if name != nil { fitToComposition(animated: true) }
    }

    func requestConnection(from: UUID, to: UUID) {
        // No-op: handled by GraphViewModel.
    }

    func didUpdateSearchMatches(_ ids: Set<UUID>?) {
        if let ids {
            for id in ids {
                if let root = branchRootForNode[id] { collapsedBranchRoots.remove(root) }
            }
            hiddenBranchIDs = collapsedBranchRoots.reduce(into: Set<UUID>()) { result, root in
                result.formUnion(branchChildrenByRoot[root] ?? [])
            }
        }
        activeSearchIDs = ids
        renderBasins(animated: false)
        renderLabels()
        evaluateNodeVisibility(animated: false)
        renderEdges()
    }

    func didLongPressContact(_ id: UUID) {
        // Handled by GraphViewModel.
    }

    /// Pulse both endpoints when a new connection is confirmed. The reload through
    /// the delegate → updateGraph path animates everyone to their new slots, so there
    /// is no manual repositioning to do here.
    func animateNewConnection(from: UUID, to: UUID) {
        guard let nodeA = personNodes[from], let nodeB = personNodes[to] else { return }
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.15, duration: reduceMotion ? 0 : 0.1),
            SKAction.scale(to: 1.0, duration: reduceMotion ? 0 : 0.2)
        ])
        nodeA.run(pulse)
        nodeB.run(pulse)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let path = CGMutablePath()
        path.move(to: presentedPosition(for: from))
        path.addLine(to: presentedPosition(for: to))
        let ripple = SKShapeNode(path: path)
        ripple.name = "connectionRipple"
        ripple.strokeColor = GraphInk.indigo.withAlphaComponent(0.9)
        ripple.lineWidth = reduceMotion ? 1.6 : 3.0
        ripple.zPosition = -1
        ripple.alpha = 0.9
        contentNode.addChild(ripple)
        let duration: TimeInterval = reduceMotion ? 0 : 0.55
        if reduceMotion {
            ripple.run(SKAction.sequence([SKAction.wait(forDuration: 1.2), SKAction.removeFromParent()]))
        } else {
            ripple.run(SKAction.sequence([
                SKAction.group([SKAction.fadeOut(withDuration: duration), SKAction.scale(to: 1.08, duration: duration)]),
                SKAction.removeFromParent()
            ]))
        }
    }

    private func restoreCamera(_ state: (position: CGPoint, zoom: CGFloat)) {
        currentZoom = state.zoom
        cameraNode.removeAction(forKey: "cameraMove")
        cameraNode.removeAction(forKey: "cameraScale")
        if sceneReady && !UIAccessibility.isReduceMotionEnabled {
            let move = SKAction.move(to: state.position, duration: 0.28)
            let scale = SKAction.scale(to: 1 / max(state.zoom, 0.001), duration: 0.28)
            move.timingMode = .easeInEaseOut
            scale.timingMode = .easeInEaseOut
            cameraNode.run(move, withKey: "cameraMove")
            cameraNode.run(scale, withKey: "cameraScale")
        } else {
            cameraNode.position = state.position
            cameraNode.setScale(1 / max(state.zoom, 0.001))
        }
        updateLOD()
        updatePondLabelScales()
        graphDelegate?.updateCameraFromScene(position: state.position, zoom: state.zoom)
    }

    /// Edge keys currently rendered.
    private var edgeConnections: Set<String> = []

    private func edgeKey(_ a: UUID, _ b: UUID) -> String {
        [a.uuidString, b.uuidString].sorted().joined(separator: "_")
    }

    private func relationshipBetween(_ a: UUID, _ b: UUID) -> Relationship? {
        let people = graphLevelsCache.flatMap(\.allContacts)
        return people.first(where: { $0.id == a || $0.id == b })?.allRelationships.first { rel in
            (rel.fromContact.id == a && rel.toContact.id == b)
            || (rel.fromContact.id == b && rel.toContact.id == a)
        }
    }

    // MARK: - Graph Building

    private func uniqueContacts(_ levels: [GraphLevel]) -> [Person] {
        var byID: [UUID: Person] = [:]
        for person in levels.flatMap(\.allContacts) { byID[person.id] = person }
        return byID.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private func updateGraph(_ levels: [GraphLevel]) {
        cancelPondDrag()
        longPressPondCandidateID = nil
        longPressOwnedTouch = false
        longPressedContactID = nil
        let preserveCamera = initialFitCompleted
        let cameraState = (position: cameraNode.position, zoom: currentZoom)
        removeAction(forKey: "singleTap")
        updateNodesAndEdges(levels: levels)
        if let meID = levels.flatMap(\.allContacts).first(where: \.isMe)?.id {
            pondLayoutOffsets = graphDelegate?.pondLayoutOffsets(forMeID: meID) ?? [:]
        } else {
            graphDelegate?.restoreAutomaticPondLayout()
            pondLayoutOffsets.removeAll()
        }
        computeLayout(levels: levels)
        _ = reconcileDirectFirstLayout(allowActivation: true)
        refreshMapMePosition()
        if let ids = activeSearchIDs {
            for id in ids {
                if let root = branchRootForNode[id] { collapsedBranchRoots.remove(root) }
            }
            hiddenBranchIDs = collapsedBranchRoots.reduce(into: Set<UUID>()) { result, root in
                result.formUnion(branchChildrenByRoot[root] ?? [])
            }
        }
        applyLayout(animated: initialFitCompleted)
        evaluateNodeVisibility(animated: false)
        if preserveCamera {
            // Refreshes (including a profile dismissal) reconcile nodes in
            // place. Re-fitting here would unexpectedly recenter a user's
            // pan/zoom and is especially visible while disclosure is active.
            cameraNode.removeAction(forKey: "cameraMove")
            cameraNode.removeAction(forKey: "cameraScale")
            cameraNode.position = cameraState.position
            currentZoom = cameraState.zoom
            cameraNode.setScale(1 / max(cameraState.zoom, 0.001))
            updateLOD()
            updatePondLabelScales()
        } else {
            fitToComposition(animated: false)
        }
        fitInitialDisclosureIfNeeded()
        initialFitCompleted = true
    }

    private func updateNodesAndEdges(levels: [GraphLevel]) {
        // 1. Reconcile person nodes (create / update / remove). Nodes are plain
        //    SKNodes — no physics bodies.
        let currentPersonIDs = Set(personNodes.keys)
        let allContacts = uniqueContacts(levels)
        let newPersonIDs = Set(allContacts.map(\.id))

        for id in currentPersonIDs where !newPersonIDs.contains(id) {
            personNodes[id]?.removeFromParent()
            personNodes.removeValue(forKey: id)
        }

        for level in levels {
            for person in level.allContacts {
                if let node = personNodes[person.id] {
                    node.update(with: person)
                } else {
                    let personNode = PersonNode(person: person, depth: level.depth)
                    personNode.position = person.isMe ? .zero : CGPoint(x: 0, y: initialRadius)
                    contentNode.addChild(personNode)
                    personNodes[person.id] = personNode
                }
                personNodes[person.id]?.setDisclosureCue(hiddenCount: 0, expanded: false)
            }
        }

        // Group identity is its persistent UUID, never its mutable display name.
        var groupsByID: [String: GoldfishCircle] = [:]
        for group in availableGroups { groupsByID[group.id.uuidString] = group }
        var members: [String: Set<UUID>] = [:]
        for person in allContacts where !person.isMe {
            guard let group = person.primaryCircle else { continue }
            groupsByID[group.id.uuidString] = group
            members[group.id.uuidString, default: []].insert(person.id)
        }
        pondInfos = groupsByID.values.map { group in
            PondInfo(id: group.id.uuidString, title: group.name,
                     color: GraphInk.graphTone(group),
                     memberIDs: Array(members[group.id.uuidString] ?? []))
        }
        let unassigned = allContacts.filter { !$0.isMe && $0.primaryCircle == nil }.map(\.id)
        if !unassigned.isEmpty {
            pondInfos.append(PondInfo(id: "unassigned", title: "Unassigned", color: GraphInk.ink(0.60), memberIDs: unassigned))
        }
        let newIDs = Set(pondInfos.map(\.id))
        for id in Set(pondBasins.keys).subtracting(newIDs) {
            pondBasins.removeValue(forKey: id)?.removeFromParent()
            pondLabels.removeValue(forKey: id)?.removeFromParent()
        }
        if let solo = soloedPondName, !newIDs.contains(solo) { soloedPondName = nil }
        for info in pondInfos {
            if pondBasins[info.id] == nil {
                let basin = SKNode()
                basin.zPosition = -3
                contentNode.addChild(basin)
                pondBasins[info.id] = basin
            }
            pondLabels.removeValue(forKey: info.id)?.removeFromParent()
            let label = makePondLabel(info.id)
            contentNode.addChild(label)
            pondLabels[info.id] = label
        }

        // 4. Reconcile edges (rendering only — no springs).
        var desiredEdges: Set<String> = []
        for (personID, _) in personNodes {
            guard let person = allContacts.first(where: { $0.id == personID }) else { continue }
            for rel in person.allRelationships {
                let otherID = rel.fromContact.id == personID ? rel.toContact.id : rel.fromContact.id
                let key = edgeKey(personID, otherID)
                if personNodes[otherID] != nil { desiredEdges.insert(key) }
            }
        }
        for edgeKey in Array(edgeNodes.keys) where !desiredEdges.contains(edgeKey) {
            edgeNodes[edgeKey]?.removeFromParent()
            edgeNodes.removeValue(forKey: edgeKey)
        }
        edgeConnections = desiredEdges
        for edgeKey in desiredEdges {
            if edgeNodes[edgeKey] == nil {
                let edgeNode = SKShapeNode()
                edgeNode.strokeColor = strokeColorForEdge(edgeKey)
                edgeNode.lineWidth = 2.0
                edgeNode.lineCap = .round
                edgeNode.lineJoin = .round
                edgeNode.zPosition = -1
                edgeNode.name = edgeKey
                edgeNode.glowWidth = 0.0
                contentNode.addChild(edgeNode)
                edgeNodes[edgeKey] = edgeNode
            }
        }

        // Snap preview line (static).
        if snapPreviewLine == nil {
            let preview = SKShapeNode()
            preview.strokeColor = GraphInk.indigo.withAlphaComponent(0.7)
            preview.lineWidth = 1.5
            preview.isHidden = true
            preview.zPosition = 10
            contentNode.addChild(preview)
            snapPreviewLine = preview
        }
    }

    private func pondID(for personID: UUID) -> String? {
        pondGeometries.first { $0.value.memberIDs.contains(personID) }?.key
    }

    private func edgeIDs(_ edgeKey: String) -> [UUID] {
        edgeKey.split(separator: "_").compactMap { UUID(uuidString: String($0)) }
    }

    private func edgeTouchesMe(_ edgeKey: String) -> Bool {
        edgeIDs(edgeKey).contains { personNodes[$0]?.isMe == true }
    }

    private func edgeTouchesSelected(_ edgeKey: String) -> Bool {
        guard let selectedID = selectedNodeID ?? disclosureSnapshot?.selectedID else { return false }
        return edgeIDs(edgeKey).contains(selectedID)
    }

    private func edgeIsCrossPond(_ edgeKey: String) -> Bool {
        let ids = edgeIDs(edgeKey)
        guard ids.count == 2 else { return false }
        guard let a = pondID(for: ids[0]), let b = pondID(for: ids[1]) else { return false }
        return a != b
    }

    private var disclosedEdgeKeys: Set<String> {
        Set(disclosureSnapshot?.revealedEdges.map { edgeKey($0.from, $0.to) } ?? [])
    }

    /// Keep the overview to its disclosed backbone. Selection temporarily adds
    /// the chosen person's saved lines so their immediate context stays useful.
    private func edgeIsPresented(_ edgeKey: String) -> Bool {
        if edgeTouchesMe(edgeKey) && !meIsVisibleOnMap { return false }
        guard disclosureSnapshot != nil else { return true }
        guard let snapshot = disclosureSnapshot else { return false }
        if pathEdgeKeys(snapshot.pathHighlightIDs).contains(edgeKey) { return true }
        if snapshot.focusRootID != nil {
            if Set(snapshot.focusedEdges.map { self.edgeKey($0.from, $0.to) }).contains(edgeKey) { return true }
            if !edgeTouchesMe(edgeKey) && disclosedEdgeKeys.contains(edgeKey) { return true }
            return false
        }
        // In the all-pond overview, direct connections are represented by one
        // organization connector per pond. They are not individual relationship lines.
        if edgeTouchesMe(edgeKey) { return false }
        if disclosedEdgeKeys.contains(edgeKey) || edgeTouchesSelected(edgeKey) { return true }
        return edgeIDs(edgeKey).contains { activeSearchIDs?.contains($0) == true }
    }

    private func pathEdgeKeys(_ ids: [UUID]) -> Set<String> {
        guard ids.count > 1 else { return [] }
        return Set(zip(ids, ids.dropFirst()).map { edgeKey($0.0, $0.1) })
    }

    private func edgeScreenWidth(_ edgeKey: String) -> CGFloat {
        if edgeTouchesSelected(edgeKey) { return 1.5 }
        if edgeTouchesMe(edgeKey) { return 0.9 }
        return edgeIsCrossPond(edgeKey) ? 0.55 : 0.7
    }

    /// Quiet graph hierarchy: cross-pond links recede, while Me and the
    /// selected contact remain easy to trace without relying on color alone.
    private func strokeColorForEdge(_ edgeKey: String) -> UIColor {
        if let snapshot = disclosureSnapshot,
           pathEdgeKeys(snapshot.pathHighlightIDs).contains(edgeKey) {
            return GraphInk.indigo.withAlphaComponent(0.9)
        }
        if disclosureSnapshot?.focusRootID != nil,
           let snapshot = disclosureSnapshot,
           !snapshot.focusedIDs.isEmpty,
           !edgeIDs(edgeKey).allSatisfy(snapshot.focusedIDs.contains) {
            return GraphInk.ink(0.08)
        }
        if edgeTouchesSelected(edgeKey) { return GraphInk.indigo.withAlphaComponent(0.70) }
        if edgeTouchesMe(edgeKey) { return GraphInk.indigo.withAlphaComponent(0.32) }
        return edgeIsCrossPond(edgeKey) ? GraphInk.ink(0.13) : GraphInk.ink(0.22)
    }

    private func pondLabelAttributes(for name: String) -> [NSAttributedString.Key: Any] {
        [
            .font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: GraphInk.serifFont(size: 14), maximumPointSize: 22, compatibleWith: GraphInk.traitForResolution),
            .foregroundColor: GraphInk.label,
            .kern: 0.2,
        ]
    }

    private func pondLabelText(for name: String) -> NSAttributedString {
        let attributes = pondLabelAttributes(for: name)
        let fullTitle = groupTitle(name)
        var title = fullTitle
        let maxWidth = min(160, max(100, size.width - 72))
        while title.count > 1 {
            let candidate = title == fullTitle ? title : title + "…"
            if NSAttributedString(string: candidate, attributes: attributes).size().width <= maxWidth {
                return NSAttributedString(string: candidate, attributes: attributes)
            }
            title.removeLast()
        }
        return NSAttributedString(string: title + "…", attributes: attributes)
    }

    private func makePondLabel(_ name: String) -> SKLabelNode {
        let label = SKLabelNode()
        label.attributedText = pondLabelText(for: name)
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.zPosition = -1
        return label
    }

    //
    // Pure geometry: assigns every node a deterministic resting slot and builds each
    // the same map every launch.

    private var branchParentByChild: [UUID: UUID] = [:]
    private var branchRootForNode: [UUID: UUID] = [:]
    private var branchChildrenByRoot: [UUID: Set<UUID>] = [:]
    /// Branch roots currently collapsed by the user.
    private var collapsedBranchRoots: Set<UUID> = []
    /// Nodes hidden because their branch root is collapsed.
    private var hiddenBranchIDs: Set<UUID> = []
    private var branchEdgeLineNames: [String: String] = [:]

    private func computeLayout(levels: [GraphLevel]) {
        layoutSlots.removeAll()
        pondGeometries.removeAll()
        branchParentByChild.removeAll()
        branchRootForNode.removeAll()
        branchChildrenByRoot.removeAll()
        hiddenBranchIDs.removeAll()
        branchEdgeLineNames.removeAll()
        let contacts = uniqueContacts(levels)
        guard let me = contacts.first(where: { $0.isMe }) else { return }
        layoutSlots[me.id] = .zero
        let groups = computeLinePlans(allContacts: contacts, me: me).sorted {
            let order = $0.title.localizedCaseInsensitiveCompare($1.title)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
        let assigned = Set(groups.flatMap(\.memberIDs))
        let unassigned = contacts.filter { !$0.isMe && !assigned.contains($0.id) }.map(\.id)
        var inputs = groups.map { DiagramGeometry.Group(id: $0.id, members: $0.memberIDs) }
        if !unassigned.isEmpty { inputs.append(.init(id: "unassigned", members: unassigned)) }
        let composition = DiagramGeometry.radial(inputs)
        for (id, point) in composition.slots { layoutSlots[id] = CGPoint(x: point.x, y: point.y) }
        // DiagramGeometry deliberately starts from UUID order. Within a pond,
        // that can put a second-degree contact between Me and a direct contact
        // on the visible line. Keep its measured coordinates and basin intact,
        // but pair the nearest slots with the shortest saved paths from Me.
        // Unlinked members sort last, with name/UUID tie-breakers throughout.
        let graph = RippleGraph(people: contacts)
        let peopleByID = Dictionary(uniqueKeysWithValues: contacts.map { ($0.id, $0) })
        func distanceFromMe(_ id: UUID) -> Int {
            graph.shortestPath(from: me.id, to: id)?.count ?? Int.max
        }
        func namePrecedes(_ lhs: UUID, _ rhs: UUID) -> Bool {
            let left = peopleByID[lhs]?.name ?? ""
            let right = peopleByID[rhs]?.name ?? ""
            let order = left.localizedCaseInsensitiveCompare(right)
            return order == .orderedSame ? lhs.uuidString < rhs.uuidString : order == .orderedAscending
        }
        for input in inputs {
            let members = input.members.filter { composition.slots[$0] != nil }
            let orderedMembers = members.sorted { lhs, rhs in
                let leftDistance = distanceFromMe(lhs), rightDistance = distanceFromMe(rhs)
                if leftDistance != rightDistance { return leftDistance < rightDistance }
                return namePrecedes(lhs, rhs)
            }
            let orderedSlots = members.compactMap { composition.slots[$0] }.sorted { lhs, rhs in
                let leftDistance = hypot(lhs.x, lhs.y), rightDistance = hypot(rhs.x, rhs.y)
                if abs(leftDistance - rightDistance) > 0.000001 { return leftDistance < rightDistance }
                if abs(lhs.x - rhs.x) > 0.000001 { return lhs.x < rhs.x }
                return lhs.y < rhs.y
            }
            for (id, point) in zip(orderedMembers, orderedSlots) {
                layoutSlots[id] = CGPoint(x: point.x, y: point.y)
            }
        }
        for group in groups {
            guard let basin = composition.basins[group.id] else { continue }
            let center = CGPoint(x: basin.center.x, y: basin.center.y)
            let radius = CGFloat(basin.radius)
            let path = organicBasin(center: center, radius: radius, seed: CGFloat(groups.firstIndex { $0.id == group.id } ?? 0))
            pondGeometries[group.id] = PondGeometry(
                name: group.id, memberIDs: group.memberIDs, bisector: 0,
                isEmpty: group.memberIDs.isEmpty, basinPath: path, discCenter: center,
                labelAnchor: CGPoint(x: center.x, y: center.y + radius + 28),
                labelDirection: [center, CGPoint(x: center.x, y: center.y + radius)])
        }
        collapsedBranchRoots = Set(collapsedBranchRoots.filter { branchChildrenByRoot[$0]?.isEmpty == false })
        hiddenBranchIDs = collapsedBranchRoots.reduce(into: Set<UUID>()) { result, root in
            result.formUnion(branchChildrenByRoot[root] ?? [])
        }
    }

    /// Reconciles the cached full graph with a compact, deterministic overview
    /// made only from Me's direct contacts. Represented ponds move as a whole;
    /// hidden contacts retain their full-layout offsets for future disclosure,
    /// while direct contacts receive the baseline composition's exact slots.
    @discardableResult
    private func reconcileDirectFirstLayout(allowActivation: Bool) -> Bool {
        guard let disclosureSnapshot, !personNodes.isEmpty else { return false }
        if !directFirstLayoutActive {
            guard allowActivation, awaitsInitialDisclosureFit,
                  !userAdjustedCameraBeforeInitialDisclosure,
                  !disclosureSnapshot.directIDs.isEmpty else { return false }
            directFirstLayoutActive = true
        }

        let directIDs = disclosureSnapshot.directIDs.filter { layoutSlots[$0] != nil }
        guard !directIDs.isEmpty else { return false }
        let orderedPonds = pondInfos.sorted {
            let order = $0.title.localizedCaseInsensitiveCompare($1.title)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
        let directByPond: [(info: PondInfo, ids: [UUID])] = orderedPonds.compactMap { info in
            let ids = info.memberIDs.filter { directIDs.contains($0) }
            return ids.isEmpty ? nil : (info, ids)
        }
        guard !directByPond.isEmpty else { return false }

        let inputs = directByPond.map { DiagramGeometry.Group(id: $0.info.id, members: $0.ids) }
        // A one-person pond still needs room for its title and the person's
        // name. Reserve that space when placing groups, even though the
        // painted bank follows only the currently visible identities.
        let baseline = DiagramGeometry.radial(inputs, minimumBasinRadius: 220)
        let peopleByID = Dictionary(uniqueKeysWithValues: uniqueContacts(graphLevelsCache).map { ($0.id, $0) })

        for entry in directByPond {
            let pondID = entry.info.id
            guard let oldGeometry = pondGeometries[pondID],
                  let baselineBasin = baseline.basins[pondID] else { continue }
            let newCenter = CGPoint(x: baselineBasin.center.x, y: baselineBasin.center.y)
            let dx = newCenter.x - oldGeometry.discCenter.x
            let dy = newCenter.y - oldGeometry.discCenter.y

            let orderedDirect = entry.ids.sorted { lhs, rhs in
                let left = peopleByID[lhs]?.name ?? ""
                let right = peopleByID[rhs]?.name ?? ""
                let order = left.localizedCaseInsensitiveCompare(right)
                return order == .orderedSame ? lhs.uuidString < rhs.uuidString : order == .orderedAscending
            }
            let orderedBaselineSlots = entry.ids.compactMap { baseline.slots[$0] }.sorted { lhs, rhs in
                let leftDistance = hypot(lhs.x, lhs.y)
                let rightDistance = hypot(rhs.x, rhs.y)
                if abs(leftDistance - rightDistance) > 0.000001 { return leftDistance < rightDistance }
                if abs(lhs.x - rhs.x) > 0.000001 { return lhs.x < rhs.x }
                return lhs.y < rhs.y
            }
            let directSlots = Dictionary(uniqueKeysWithValues:
                zip(orderedDirect, orderedBaselineSlots).map { id, point in
                    (id, CGPoint(x: point.x, y: point.y))
                })
            let rootOffsets = directSlots.reduce(into: [UUID: CGPoint]()) { offsets, entry in
                guard let oldPoint = layoutSlots[entry.key] else { return }
                offsets[entry.key] = CGPoint(x: entry.value.x - oldPoint.x,
                                            y: entry.value.y - oldPoint.y)
            }
            for id in oldGeometry.memberIDs {
                if let directSlot = directSlots[id] {
                    layoutSlots[id] = directSlot
                } else if let point = layoutSlots[id] {
                    // Move a hidden branch with its direct parent. Translating
                    // only the pond center can leave a hidden center slot
                    // underneath a parent that was moved to the new center.
                    let offset = branchRootForNode[id].flatMap { rootOffsets[$0] }
                        ?? CGPoint(x: dx, y: dy)
                    layoutSlots[id] = CGPoint(x: point.x + offset.x, y: point.y + offset.y)
                }
            }

            // Root-relative translations can bring an unlinked reservation or
            // a second branch into an occupied slot. Resolve that only while
            // composing the initial layout; disclosure never moves stations.
            var occupied = Array(directSlots.values)
            for id in oldGeometry.memberIDs.sorted(by: { $0.uuidString < $1.uuidString })
                where directSlots[id] == nil {
                guard let proposed = layoutSlots[id] else { continue }
                func isFree(_ point: CGPoint) -> Bool {
                    occupied.allSatisfy { hypot($0.x - point.x, $0.y - point.y) >= 110 }
                }
                var reserved = proposed
                if !isFree(reserved) {
                    search: for ring in 1...max(2, oldGeometry.memberIDs.count) {
                        let count = ring * 8
                        for step in 0..<count {
                            let angle = CGFloat(step) * 2 * .pi / CGFloat(count)
                            let candidate = CGPoint(x: proposed.x + cos(angle) * CGFloat(ring) * 120,
                                                    y: proposed.y + sin(angle) * CGFloat(ring) * 120)
                            if isFree(candidate) {
                                reserved = candidate
                                break search
                            }
                        }
                    }
                    layoutSlots[id] = reserved
                }
                occupied.append(reserved)
            }

            var transform = CGAffineTransform(translationX: dx, y: dy)
            let translatedPath = oldGeometry.basinPath?.copy(using: &transform)
            pondGeometries[pondID] = PondGeometry(
                name: oldGeometry.name,
                memberIDs: oldGeometry.memberIDs,
                bisector: oldGeometry.bisector,
                isEmpty: oldGeometry.isEmpty,
                basinPath: translatedPath,
                discCenter: newCenter,
                labelAnchor: CGPoint(x: oldGeometry.labelAnchor.x + dx,
                                     y: oldGeometry.labelAnchor.y + dy),
                labelDirection: oldGeometry.labelDirection.map {
                    CGPoint(x: $0.x + dx, y: $0.y + dy)
                }
            )
        }
        // The compact baseline moves represented ponds, while latent ponds keep
        // their full-layout coordinates for later disclosure. Those saved
        // coordinates can now land on a compact pond. Resolve collisions once
        // during initial composition so expansion only reveals a stable pond.
        let representedPondIDs = Set(directByPond.map { $0.info.id })
        var occupiedPondBounds = representedPondIDs.compactMap { name -> CGRect? in
            guard let path = pondGeometries[name]?.basinPath else { return nil }
            return path.boundingBoxOfPath.insetBy(dx: -280, dy: -280)
        }
        let latentPonds = orderedPonds.filter { !representedPondIDs.contains($0.id) }
        for info in latentPonds {
            guard let geometry = pondGeometries[info.id], let basePath = geometry.basinPath else { continue }
            let originalBounds = basePath.boundingBoxOfPath
            var translation = CGPoint.zero
            if occupiedPondBounds.contains(where: { $0.intersects(originalBounds) }) {
                let step = max(max(originalBounds.width, originalBounds.height), 240) * 0.6
                let directions: [(CGFloat, CGFloat)] = [
                    (1, 0), (0, 1), (-1, 0), (0, -1),
                    (1, 1), (-1, 1), (-1, -1), (1, -1)
                ]
                search: for ring in 1...64 {
                    for (dx, dy) in directions {
                        let candidate = CGPoint(x: dx * step * CGFloat(ring),
                                                y: dy * step * CGFloat(ring))
                        let bounds = originalBounds.offsetBy(dx: candidate.x, dy: candidate.y)
                        if occupiedPondBounds.allSatisfy({ !$0.intersects(bounds) }) {
                            translation = candidate
                            break search
                        }
                    }
                }
                if translation == .zero {
                    let rightmostOccupiedX = occupiedPondBounds.map(\.maxX).max() ?? originalBounds.maxX
                    translation = CGPoint(x: rightmostOccupiedX + 240 - originalBounds.minX,
                                          y: 0)
                }
            }
            if translation != .zero {
                for id in geometry.memberIDs {
                    guard let point = layoutSlots[id] else { continue }
                    layoutSlots[id] = CGPoint(x: point.x + translation.x, y: point.y + translation.y)
                }
                var transform = CGAffineTransform(translationX: translation.x, y: translation.y)
                pondGeometries[info.id] = PondGeometry(
                    name: geometry.name,
                    memberIDs: geometry.memberIDs,
                    bisector: geometry.bisector,
                    isEmpty: geometry.isEmpty,
                    basinPath: geometry.basinPath?.copy(using: &transform),
                    discCenter: CGPoint(x: geometry.discCenter.x + translation.x,
                                        y: geometry.discCenter.y + translation.y),
                    labelAnchor: CGPoint(x: geometry.labelAnchor.x + translation.x,
                                         y: geometry.labelAnchor.y + translation.y),
                    labelDirection: geometry.labelDirection.map {
                        CGPoint(x: $0.x + translation.x, y: $0.y + translation.y)
                    }
                )
            }
            if let movedPath = pondGeometries[info.id]?.basinPath {
                occupiedPondBounds.append(movedPath.boundingBoxOfPath.insetBy(dx: -280, dy: -280))
            }
        }
        return true
    }

    /// Smooth, seeded basin silhouette, composed once per reload.
    private func organicBasin(center: CGPoint, radius: CGFloat, seed: CGFloat) -> CGPath {
        let points = (0..<12).map { index -> CGPoint in
            let a = CGFloat(index) * 2 * .pi / 12
            let r = radius * (1 + 0.035 * sin(a * 3 + seed))
            return CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r)
        }
        let path = CGMutablePath()
        let start = CGPoint(x: (points[11].x + points[0].x) / 2, y: (points[11].y + points[0].y) / 2)
        path.move(to: start)
        for index in points.indices {
            let next = points[(index + 1) % points.count]
            let end = CGPoint(x: (points[index].x + next.x) / 2, y: (points[index].y + next.y) / 2)
            path.addQuadCurve(to: end, control: points[index])
        }
        path.closeSubpath()
        return path
    }

    ///
    /// Direct contacts ride their own line. Secondary contacts connected to a
    private func computeLinePlans(allContacts: [Person], me: Person) -> [PondInfo] {
        let people = allContacts.filter { !$0.isMe }
        // A pond represents saved membership. Relationships connect ponds; they
        // must never silently move a person into their parent's or friend's pond.
        let groups = Dictionary(grouping: people) { $0.primaryCircle?.id.uuidString ?? "unassigned" }
        for (groupID, members) in groups {
            let allowed = Set(members.map(\.id))
            let roots = members.filter { person in
                person.allRelationships.contains { $0.otherContact(from: person).id == me.id }
            }.map(\.id).sorted { $0.uuidString < $1.uuidString }
            let neighbors = Dictionary(uniqueKeysWithValues: members.map { person in
                (person.id, person.allRelationships.map { $0.otherContact(from: person).id }
                    .filter { allowed.contains($0) }.sorted { $0.uuidString < $1.uuidString })
            })
            let forest = RelationshipForest.build(roots: roots, neighbors: neighbors, allowed: allowed)
            for (id, parent) in forest.parent {
                guard let root = forest.root[id] else { continue }
                branchParentByChild[id] = parent
                branchRootForNode[id] = root
                branchChildrenByRoot[root, default: []].insert(id)
                branchEdgeLineNames[edgeKey(parent, id)] = groupID
            }
        }
        return pondInfos.map { info in
            PondInfo(id: info.id, title: info.title, color: info.color,
                     memberIDs: (groups[info.id] ?? []).map(\.id))
        }
    }

    // MARK: - Apply Layout (animate nodes + render basins/edges/labels)

    private func applyLayout(animated: Bool) {
        refreshMapMePosition()
        // Move every node to its slot.
        for (id, node) in personNodes {
            guard layoutSlots[id] != nil else { continue }
            let slot = presentedPosition(for: id)
            node.removeAction(forKey: "slotMove")
            if animated {
                let move = SKAction.move(to: slot, duration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.45)
                move.timingMode = .easeOut
                node.run(move, withKey: "slotMove")
            } else {
                node.position = slot
            }
            node.setLabelPlacement(.below)
        }
        renderBasins(animated: animated)
        renderLabels()
        renderEdges()
    }

    /// Frames only the active relationship cluster, with no origin/Me bias.
    private func fitFocusedCluster(animated: Bool) {
        guard let snapshot = disclosureSnapshot else { return }
        let framedIDs = snapshot.focusedIDs.union(snapshot.pathHighlightIDs)
        guard !framedIDs.isEmpty else { return }
        let bounds = framedIDs.compactMap { id -> CGRect? in
            guard let node = personNodes[id], !node.isHidden else { return nil }
            let point = presentedPosition(for: id)
            return node.visibleIdentityBounds.offsetBy(dx: point.x, dy: point.y)
        }.reduce(nil as CGRect?) { partial, next in
            partial.map { $0.union(next) } ?? next
        }
        guard let bounds else { return }
        fitToRect(bounds, minZoom: 0.001, maxZoom: 1.3, padding: 44, screenInset: 28, animated: animated, biasToMe: false)
    }

    private func renderBasins(animated: Bool) {
        for (name, basin) in pondBasins {
            basin.removeAllChildren()
            guard pondGeometries[name] != nil, let path = presentedPondPath(name) else {
                basin.isHidden = true
                continue
            }
            basin.isHidden = !pondIsPresented(name)
            let shape = SKShapeNode(path: path)
            shape.fillColor = groupTone(name).withAlphaComponent(
                GraphInk.traitForResolution.accessibilityContrast == .high ? 0.18 : 0.10)
            shape.strokeColor = groupTone(name).withAlphaComponent(
                GraphInk.traitForResolution.accessibilityContrast == .high ? 0.8 : 0.38)
            shape.lineWidth = basinStrokeWidth
            basin.addChild(shape)
        }
        if let drag = pondDragState { highlightPondStyle(drag.pondID) }
    }

    private func renderLabels() {
        for (name, label) in pondLabels {
            guard pondGeometries[name] != nil else { label.isHidden = true; continue }
            label.isHidden = !pondIsPresented(name)
            label.position = presentedPondLabelAnchor(name)
            label.horizontalAlignmentMode = .center
            label.verticalAlignmentMode = .bottom
        }
        updatePondLabelScales()
    }

    /// comes from `strokeColorForEdge` — quiet ink, or marker red for Me-edges.
    private func renderEdges() {
        for (edgeKey, edgeNode) in edgeNodes {
            let ids = edgeKey.split(separator: "_")
            guard ids.count == 2,
                  let uuidA = UUID(uuidString: String(ids[0])),
                  let uuidB = UUID(uuidString: String(ids[1])),
                  let nodeA = personNodes[uuidA],
                  let nodeB = personNodes[uuidB] else { continue }
            edgeNode.path = curvedEdgePath(from: nodeA.position, to: nodeB.position)
            let hidden = disclosureSnapshot.map { snapshot in
                let visible: (UUID) -> Bool = { id in
                    (snapshot.visibleIDs.contains(id) || self.activeSearchIDs?.contains(id) == true) &&
                        (self.personNodes[id]?.isMe != true || self.meIsVisibleOnMap)
                }
                return !(visible(uuidA) && visible(uuidB)) || !self.edgeIsPresented(edgeKey)
            } ??
                (hiddenBranchIDs.contains(uuidA) || hiddenBranchIDs.contains(uuidB) ||
                    (edgeTouchesMe(edgeKey) && !meIsVisibleOnMap))
            edgeNode.isHidden = hidden
            if let lineName = branchEdgeLineNames[edgeKey] {
                edgeNode.strokeColor = groupTone(lineName).withAlphaComponent(
                    GraphInk.traitForResolution.accessibilityContrast == .high ? 1.0 : 0.68)
                edgeNode.lineWidth = edgeScreenWidth(edgeKey) / max(currentZoom, 0.001)
                edgeNode.lineCap = .round
                edgeNode.lineJoin = .round
                edgeNode.zPosition = -2
            } else {
                edgeNode.strokeColor = strokeColorForEdge(edgeKey)
                edgeNode.lineWidth = edgeScreenWidth(edgeKey) / max(currentZoom, 0.001)
                edgeNode.zPosition = edgeTouchesSelected(edgeKey) ? -1 : -3
            }
        }
    }

    private func curvedEdgePath(from start: CGPoint, to end: CGPoint) -> CGPath {
        let path = CGMutablePath()
        path.move(to: start)
        let dx = end.x - start.x, dy = end.y - start.y
        let bend = min(32, hypot(dx, dy) * 0.12)
        let length = max(1, hypot(dx, dy))
        path.addQuadCurve(to: end, control: CGPoint(x: (start.x + end.x) / 2 - dy / length * bend,
                                                   y: (start.y + end.y) / 2 + dx / length * bend))
        return path
    }

    override func update(_ currentTime: TimeInterval) {
        if personNodes.values.contains(where: { $0.action(forKey: "slotMove") != nil }) {
            renderEdges()
        }
    }

    // MARK: - LOD

    private func updateLOD() {
        let focusedIDs = soloedPondName.flatMap { name in
            Set(pondInfos.first { $0.id == name }?.memberIDs ?? [])
        } ?? []
        let peopleByID = Dictionary(uniqueKeysWithValues: uniqueContacts(graphLevelsCache).map { ($0.id, $0) })
        // Resolve roles from the selected person's perspective. Calling
        // Relationship.effectiveType directly here describes the selected
        // endpoint and reverses parent/child labels for its neighbour.
        let disclosureGraph = disclosureSnapshot.map { _ in
            RippleGraph(people: Array(peopleByID.values))
        }
        for (_, node) in personNodes {
            if let disclosure = disclosureSnapshot {
                let hiddenCount = disclosure.hiddenNeighborCounts[node.personID] ?? 0
                node.setDisclosureCue(hiddenCount: hiddenCount, expanded: disclosure.expandedIDs.contains(node.personID))
                let selected = disclosure.selectedID == node.personID
                node.setDisclosureHighlighted(selected)
                let visible = disclosure.visibleIDs.contains(node.personID)
                // Keep unselected canvas identities compact even when the
                // complete graph is large; the selected identity may use its
                // measured full name and the inspector retains all details.
                node.setDisclosureIdentityExpanded(
                    node.isMe || (selected && !disclosure.directIDs.contains(node.personID))
                )
                if node.isMe || selected || visible || disclosure.expandedIDs.contains(node.personID) || disclosure.trail.contains(node.personID) {
                    node.showFull()
                } else {
                    node.showDotOnly()
                }
                node.setContextRole(nil, symbol: nil)
                if !node.isMe,
                   (!disclosure.directIDs.contains(node.personID) || soloedPondName != nil),
                   let selectedID = disclosure.selectedID, selectedID != node.personID,
                   disclosure.visibleIDs.contains(node.personID),
                   let role = disclosureGraph?.role(of: node.personID, relativeTo: selectedID),
                   let person = peopleByID[node.personID] {
                    var roleText = role.roleLabel
                    if let age = disclosureAge(person) { roleText += " · Age \(age)" }
                    node.setContextRole(roleText, symbol: role.symbolName)
                }
            } else if node.isMe || node.personID == selectedNodeID || focusedIDs.contains(node.personID) ||
                (soloedPondName == nil && currentZoom >= 0.12 && !usesCompactOverviewIdentity) {
                node.setDisclosureCue(hiddenCount: 0, expanded: false)
                node.setContextRole(nil, symbol: nil)
                node.showFull()
            } else {
                node.setDisclosureCue(hiddenCount: 0, expanded: false)
                node.setContextRole(nil, symbol: nil)
                node.showDotOnly()
            }
            node.updateScreenScale(zoom: currentZoom)
        }
    }

    private func disclosureAge(_ person: Person) -> Int? {
        guard let birthday = person.birthday, birthday <= Date() else { return nil }
        return Calendar.current.dateComponents([.year], from: birthday, to: Date()).year
    }

    // MARK: - Selection

    private func highlightNode(_ id: UUID?) {
        if let prevID = selectedNodeID, let prevNode = personNodes[prevID] {
            prevNode.setSelected(false)
        }
        selectedNodeID = id
        if let id = id, let node = personNodes[id] {
            node.setSelected(true, maxLabelWidth: min(240, max(140, size.width * 0.62)))
        }
        updateLOD()
        arrangeNameLabels()
        renderEdges()
    }

    // MARK: - Search / Solo Filtering

    private func evaluateNodeVisibility(animated: Bool = true) {
        // A scene that has not been attached to an SKView has no action tick to
        // advance animations. Apply visibility immediately in that state so the
        // graph's logical state is deterministic for previews and layout tests.
        let duration: TimeInterval = animated && sceneReady && !UIAccessibility.isReduceMotionEnabled ? 0.3 : 0.0
        let isSearchActive = activeSearchIDs != nil
        let isSoloActive = soloedPondName != nil
        let focusedIDs = disclosureSnapshot?.focusedIDs ?? []
        let focusAndPathIDs = focusedIDs.union(disclosureSnapshot?.pathHighlightIDs ?? [])
        let hasRelationshipFocus = disclosureSnapshot?.focusRootID != nil
        let hasFocusedPresentation = hasRelationshipFocus || !(disclosureSnapshot?.pathHighlightIDs.isEmpty ?? true)

        let soloedPondInfo = soloedPondName.flatMap { name in pondInfos.first { $0.id == name } }
        let soloedNodeIDs = Set((soloedPondInfo?.memberIDs ?? []) + (pondGeometries[soloedPondName ?? ""]?.memberIDs ?? []))

        for (id, node) in personNodes {
            node.childNode(withName: "branchBadge")?.removeFromParent()
            var alpha: CGFloat = 1.0
            var popToFront = false
            let visibleByDisclosure = (disclosureSnapshot?.visibleIDs.contains(id) ?? true) &&
                (!node.isMe || meIsVisibleOnMap)
            let visibleBySearch = activeSearchIDs?.contains(id) == true &&
                (!node.isMe || meIsVisibleOnMap)
            let isHiddenByModel = !visibleByDisclosure && !visibleBySearch
            if isHiddenByModel {
                node.removeAllActions()
                node.position = presentedPosition(for: id)
                node.alpha = 0
                node.isHidden = true
                continue
            } else if node.isHidden {
                node.isHidden = false
                node.alpha = 0
            }

            if isSearchActive {
                if activeSearchIDs?.contains(id) == true {
                    alpha = 1.0
                    popToFront = true
                } else {
                    alpha = 0.2
                }
            }
            if isSoloActive {
                if soloedNodeIDs.contains(id) || node.isMe {
                    // keep
                } else {
                    alpha = min(alpha, 0.15)
                }
            }
            if hasFocusedPresentation && !isSearchActive {
                alpha = focusAndPathIDs.contains(id) ? 1.0 : min(alpha, 0.16)
            }
            if disclosureSnapshot != nil && !isSearchActive && !isSoloActive && !hasFocusedPresentation { alpha = 1.0 }
            if duration == 0 {
                node.removeAction(forKey: "visibility")
                node.alpha = alpha
            } else {
                let action = SKAction.fadeAlpha(to: alpha, duration: duration)
                action.timingMode = .easeInEaseOut
                node.run(action, withKey: "visibility")
            }
            node.zPosition = popToFront ? 5 : 0
        }

        // Edge tone alpha is baked into the stroke color; rest at full node alpha.
        for (edgeKey, edge) in edgeNodes {
            let ids = edgeKey.split(separator: "_").compactMap { UUID(uuidString: String($0)) }
            let endpointsVisible = ids.allSatisfy { id in
                disclosureSnapshot.map { $0.visibleIDs.contains(id) || activeSearchIDs?.contains(id) == true } ?? true
            }
            if !endpointsVisible || !edgeIsPresented(edgeKey) {
                edge.isHidden = true
                continue
            }
            edge.isHidden = false
            let inFocusedPond = ids.allSatisfy { soloedNodeIDs.contains($0) || personNodes[$0]?.isMe == true }
            let matchesSearch = ids.contains { activeSearchIDs?.contains($0) == true }
            let pathEdge = disclosureSnapshot.map { pathEdgeKeys($0.pathHighlightIDs).contains(edgeKey) } ?? false
            let edgeInFocus = ids.count == 2 && ids.allSatisfy(focusedIDs.contains)
            let edgeAlpha: CGFloat = isSearchActive ? (matchesSearch ? 1 : 0.05) :
                (hasFocusedPresentation ? ((edgeInFocus || pathEdge) ? 1 : 0.06) :
                    (disclosureSnapshot != nil ? 1 : (isSoloActive && !inFocusedPond ? 0.05 : 1)))
            let action = SKAction.fadeAlpha(to: edgeAlpha, duration: duration)
            action.timingMode = .easeInEaseOut
            edge.run(action)
        }

        for (name, basin) in pondBasins {
            basin.isHidden = !pondIsPresented(name)
            let isThisSolo = (name == soloedPondName)
            let focusMembers = disclosureSnapshot?.focusedIDs.union(disclosureSnapshot?.pathHighlightIDs ?? []) ?? []
            let inFocus = pondGeometries[name]?.memberIDs.contains(where: focusMembers.contains) == true
            let basinAlpha: CGFloat = isSearchActive ? 0.4 : (hasFocusedPresentation ? (inFocus ? 1.0 : 0.14) : (isSoloActive ? (isThisSolo ? 1.0 : 0.25) : 1.0))
            let action = SKAction.fadeAlpha(to: basinAlpha, duration: duration)
            action.timingMode = .easeInEaseOut
            basin.run(action, withKey: "visibility")
        }

        for (name, label) in pondLabels {
            label.isHidden = !pondIsPresented(name)
            let isThisSolo = (name == soloedPondName)
            let focusMembers = disclosureSnapshot?.focusedIDs.union(disclosureSnapshot?.pathHighlightIDs ?? []) ?? []
            let inFocus = pondGeometries[name]?.memberIDs.contains(where: focusMembers.contains) == true
            let labelAlpha: CGFloat = isSearchActive ? 0.1 : (hasFocusedPresentation ? (inFocus ? 1.0 : 0.12) : (isSoloActive ? (isThisSolo ? 1.0 : 0.1) : 1.0))
            let action = SKAction.fadeAlpha(to: labelAlpha, duration: duration)
            action.timingMode = .easeInEaseOut
            label.run(action, withKey: "visibility")
        }
    }

    // MARK: - Touches (Drag nodes + Tap to select + 1-finger camera pan)

    private var draggedNode: PersonNode?
    private var dragStartLocation: CGPoint = .zero
    /// Position and touch anchor captured before the marker is scaled or moved.
    private var dragOriginalPosition: CGPoint = .zero
    private var dragTouchOffset: CGPoint = .zero
    private var dragOriginalPondID: String?
    private var dragOriginalContainingPondIDs: Set<String> = []
    private var lastTouchLocation: CGPoint = .zero
    private var touchHasMoved = false
    private var touchContactCandidateIDs: [UUID] = []
    private var hoverPondName: String? = nil

    private struct PondDragState {
        let pondID: String
        let meID: UUID
        let startPoint: CGPoint
        let originalOffset: CGPoint
        var hasMoved: Bool
    }
    private var pondDragState: PondDragState?
    private var touchStartedOnPondID: String?
    private var longPressPondCandidateID: String?
    private var longPressStartContentPoint: CGPoint = .zero
    private var longPressOwnedTouch = false
    private var longPressedContactID: UUID?

    private func offset(for personID: UUID) -> CGPoint {
        guard let pondID = pondInfos.first(where: { $0.memberIDs.contains(personID) })?.id else { return .zero }
        return pondLayoutOffsets[pondID] ?? .zero
    }

    private var meIsExplicitPathEndpoint: Bool {
        guard let meID = graphLevelsCache.flatMap(\.allContacts).first(where: \.isMe)?.id else { return false }
        return disclosureSnapshot?.pathHighlightIDs.contains(meID) == true
    }

    private var meIsVisibleOnMap: Bool {
        showsMeDuringGuidedTour || meIsExplicitPathEndpoint
    }

    private func nodeIsPresentedOnCanvas(_ node: PersonNode) -> Bool {
        contactIsPresented(node.personID) && (!node.isMe || meIsVisibleOnMap)
    }

    private func presentedPosition(for personID: UUID) -> CGPoint {
        if personNodes[personID]?.isMe == true, meIsExplicitPathEndpoint {
            return mapMePosition
        }
        if personNodes[personID]?.isMe == true, !opensRipplesOnTap { return mapMePosition }
        let base = layoutSlots[personID] ?? personNodes[personID]?.position ?? .zero
        let delta = offset(for: personID)
        return CGPoint(x: base.x + delta.x, y: base.y + delta.y)
    }

    /// Cache a visible Me endpoint beside the active path (or direct contacts
    /// during the lesson). This runs only at layout, path, offset, or zoom
    /// transitions; camera fitting reads one stable position and cannot feed
    /// changes back into its own bounds.
    private func refreshMapMePosition() {
        guard let meID = graphLevelsCache.flatMap(\.allContacts).first(where: \.isMe)?.id else { return }
        guard meIsVisibleOnMap else {
            mapMePosition = layoutSlots[meID] ?? .zero
            return
        }
        let preferredIDs = disclosureSnapshot?.pathHighlightIDs.filter { $0 != meID }
            ?? disclosureSnapshot?.directIDs.filter { $0 != meID }
            ?? []
        let anchorIDs = preferredIDs.isEmpty
            ? personNodes.values.filter { !$0.isMe && contactIsPresented($0.personID) }.map(\.personID)
            : preferredIDs
        let slotRect: (UUID) -> CGRect? = { [self] id in
            guard let node = personNodes[id] else { return nil }
            let point = layoutSlots[id] ?? node.position
            let delta = offset(for: id)
            return node.visibleIdentityBounds.offsetBy(dx: point.x + delta.x, dy: point.y + delta.y)
        }
        let anchorBounds = anchorIDs.compactMap(slotRect).reduce(nil as CGRect?) { partial, next in
            partial.map { $0.union(next) } ?? next
        }
        guard let anchorBounds else {
            mapMePosition = layoutSlots[meID] ?? .zero
            return
        }
        let obstacles = personNodes.values.compactMap { node -> CGRect? in
            guard !node.isMe, contactIsPresented(node.personID) else { return nil }
            return slotRect(node.personID)
        } + pondGeometries.keys.compactMap { name -> CGRect? in
            guard let geometry = pondGeometries[name], let path = geometry.basinPath else { return nil }
            return translated(path, by: pondOffset(name))?.boundingBoxOfPath
        }
        let markerSize = CGSize(width: max(80, 64 / max(currentZoom, 0.001)),
                                height: max(100, 90 / max(currentZoom, 0.001)))
        let gap: CGFloat = 26 / max(currentZoom, 0.001)
        let directions: [(CGFloat, CGFloat)] = [
            (0, -1), (-1, 0), (1, 0), (0, 1),
            (-1, -1), (1, -1), (-1, 1), (1, 1)
        ]
        for ring in 0..<16 {
            let distance = gap + CGFloat(ring) * max(54, 40 / max(currentZoom, 0.001))
            for (dx, dy) in directions {
                let x = dx < 0 ? anchorBounds.minX - distance - markerSize.width / 2
                    : dx > 0 ? anchorBounds.maxX + distance + markerSize.width / 2 : anchorBounds.midX
                let y = dy < 0 ? anchorBounds.minY - distance - markerSize.height / 2
                    : dy > 0 ? anchorBounds.maxY + distance + markerSize.height / 2 : anchorBounds.midY
                let markerBounds = CGRect(x: x - markerSize.width / 2, y: y - markerSize.height / 2,
                                          width: markerSize.width, height: markerSize.height)
                if obstacles.allSatisfy({ !$0.insetBy(dx: -12, dy: -12).intersects(markerBounds) }) {
                    mapMePosition = CGPoint(x: x, y: y)
                    return
                }
            }
        }
        mapMePosition = CGPoint(x: anchorBounds.midX,
                                y: anchorBounds.minY - gap - markerSize.height / 2)
    }

    private func pondOffset(_ pondID: String) -> CGPoint { pondLayoutOffsets[pondID] ?? .zero }

    func setPondLayoutOffsets(_ offsets: [String: CGPoint]) {
        pondLayoutOffsets = offsets.filter { $0.value.x.isFinite && $0.value.y.isFinite }
        applyPresentedLayout(animated: false)
    }

    private func applyPresentedLayout(animated: Bool) {
        refreshMapMePosition()
        for (id, node) in personNodes {
            let point = presentedPosition(for: id)
            node.removeAction(forKey: "slotMove")
            if animated {
                let move = SKAction.move(to: point, duration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.45)
                move.timingMode = .easeOut
                node.run(move, withKey: "slotMove")
            } else {
                node.position = point
            }
        }
        renderBasins(animated: false)
        renderLabels()
        renderEdges()
        updatePondLabelScales()
        evaluateNodeVisibility(animated: false)
    }

    /// Starts a pond translation through the same path used by the UIKit
    /// long-press recognizer and the debug bridge.
    @discardableResult
    func beginPondDrag(pondID: String, at point: CGPoint) -> Bool {
        guard pondDragState == nil,
              point.x.isFinite, point.y.isFinite,
              let geometry = pondGeometries[pondID], pondIsPresented(pondID),
              let meID = graphLevelsCache.flatMap(\.allContacts).first(where: \.isMe)?.id else { return false }
        guard geometry.isEmpty || geometry.memberIDs.contains(where: contactIsPresented) else { return false }
        pondDragState = PondDragState(pondID: pondID, meID: meID, startPoint: point,
                                      originalOffset: pondOffset(pondID), hasMoved: false)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        highlightPondStyle(pondID)
        return true
    }

    func updatePondDrag(to point: CGPoint) {
        guard var drag = pondDragState, point.x.isFinite, point.y.isFinite else { return }
        let dx = point.x - drag.startPoint.x
        let dy = point.y - drag.startPoint.y
        guard drag.hasMoved || hypot(dx, dy) * currentZoom > 2 else { return }
        if !drag.hasMoved {
            drag.hasMoved = true
            pondDragState = drag
            UISelectionFeedbackGenerator().selectionChanged()
        }
        pondLayoutOffsets[drag.pondID] = CGPoint(x: drag.originalOffset.x + dx,
                                                 y: drag.originalOffset.y + dy)
        refreshMapMePosition()
        if let meNode = personNodes.values.first(where: { $0.isMe }) {
            meNode.position = presentedPosition(for: meNode.personID)
        }
        for id in pondGeometries[drag.pondID]?.memberIDs ?? [] {
            personNodes[id]?.position = presentedPosition(for: id)
        }
        renderBasins(animated: false)
        renderLabels()
        arrangePondLabels()
        arrangeNameLabels()
        renderEdges()
        updatePondLabelScales()
        highlightPondStyle(drag.pondID)
    }

    func endPondDrag() {
        guard let drag = pondDragState else { return }
        pondDragState = nil
        resetPondStyle(drag.pondID)
        if drag.hasMoved {
            let finalOffset = pondOffset(drag.pondID)
            graphDelegate?.savePondLayoutOffset(finalOffset, for: drag.pondID, meID: drag.meID)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    func cancelPondDrag() {
        guard let drag = pondDragState else { return }
        pondDragState = nil
        pondLayoutOffsets[drag.pondID] = drag.originalOffset
        refreshMapMePosition()
        if let meNode = personNodes.values.first(where: { $0.isMe }) {
            meNode.position = presentedPosition(for: meNode.personID)
        }
        resetPondStyle(drag.pondID)
        for id in pondGeometries[drag.pondID]?.memberIDs ?? [] {
            personNodes[id]?.position = presentedPosition(for: id)
        }
        renderBasins(animated: false)
        renderLabels()
        arrangeNameLabels()
        renderEdges()
        updatePondLabelScales()
    }

    private func pondHit(at point: CGPoint) -> String? {
        pondGeometries.keys.sorted().first { id in
            guard pondIsPresented(id) else { return false }
            let titleHit = pondLabels[id]?.calculateAccumulatedFrame()
                .insetBy(dx: -16 / max(currentZoom, 0.001), dy: -12 / max(currentZoom, 0.001)).contains(point) == true
            return titleHit || presentedPondPath(id)?.contains(point) == true
        }
    }

    private func contactIsPresented(_ id: UUID) -> Bool {
        if let disclosureSnapshot {
            return disclosureSnapshot.visibleIDs.contains(id) || activeSearchIDs?.contains(id) == true
        }
        return !hiddenBranchIDs.contains(id)
    }

    /// Saved geometry remains stable for disclosure and drag math. In the
    /// overview, draw a pond only while at least one of its members is shown.
    private func pondIsPresented(_ name: String) -> Bool {
        guard let geometry = pondGeometries[name] else { return false }
        if soloedPondName == name { return true }
        // Empty custom ponds remain visible as a title and small basin so
        // their placement can be changed before anyone joins them.
        if geometry.isEmpty { return true }
        guard disclosureSnapshot != nil else { return true }
        return geometry.memberIDs.contains(where: contactIsPresented)
    }

    /// The cached geometry owns every future station. The painted outline owns
    /// only the currently presented stations, so hidden population cannot make
    /// the direct-first overview microscopic. Its padding is clamped in world
    /// space while tracking the screen scale closely enough for identity coins.
    private func presentedPondPath(_ name: String) -> CGPath? {
        guard let geometry = pondGeometries[name], pondIsPresented(name) else { return nil }
        if disclosureSnapshot == nil { return translated(geometry.basinPath, by: pondOffset(name)) }
        let points = geometry.memberIDs.compactMap { id -> CGPoint? in
            guard contactIsPresented(id) else { return nil }
            return presentedPosition(for: id)
        }
        guard !points.isEmpty else {
            return soloedPondName == name ? translated(geometry.basinPath, by: pondOffset(name)) : nil
        }

        let zoom = max(currentZoom, 0.001)
        let horizontalPadding = min(170, 40 / zoom)
        let titleHeight = pondLabelText(for: name).size().height / zoom
        let titleGap = min(60, 12 / zoom)
        let nodeTopReach = 32 * max(1, 0.58 / zoom)
        let reservedTitleBand = titleHeight + titleGap + nodeTopReach + 8 / zoom
        let topPadding = max(min(420, 78 / zoom), reservedTitleBand)
        let bottomPadding = min(260, 62 / zoom)
        let minX = points.map(\.x).min() ?? geometry.discCenter.x
        let maxX = points.map(\.x).max() ?? geometry.discCenter.x
        let minY = points.map(\.y).min() ?? geometry.discCenter.y
        let maxY = points.map(\.y).max() ?? geometry.discCenter.y
        let contentWidth = maxX - minX + horizontalPadding * 2
        let titleWidth = pondLabelText(for: name).size().width / zoom + min(120, 32 / zoom)
        let width = max(contentWidth, titleWidth)
        let bounds = CGRect(
            x: (minX + maxX) / 2 - width / 2,
            y: minY - bottomPadding,
            width: max(width, horizontalPadding * 2),
            height: max(maxY - minY + bottomPadding + topPadding, bottomPadding + topPadding)
        )
        return organicPresentedBasin(in: bounds, seed: CGFloat(pondInfos.firstIndex { $0.id == name } ?? 0))
    }

    /// A gently irregular ellipse keeps the original soft pond language while
    /// allowing wide families and their attached heading to share one bank.
    private func organicPresentedBasin(in bounds: CGRect, seed: CGFloat) -> CGPath {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let rx = max(bounds.width / 2, 1)
        let ry = max(bounds.height / 2, 1)
        let points = (0..<16).map { index -> CGPoint in
            let angle = CGFloat(index) * 2 * .pi / 16
            let cosine = cos(angle), sine = sin(angle)
            let ripple = 1 + 0.018 * sin(angle * 3 + seed)
            return CGPoint(x: center.x + cosine * rx * ripple,
                           y: center.y + sine * ry * ripple)
        }
        let path = CGMutablePath()
        let start = CGPoint(x: (points[15].x + points[0].x) / 2,
                            y: (points[15].y + points[0].y) / 2)
        path.move(to: start)
        for index in points.indices {
            let next = points[(index + 1) % points.count]
            path.addQuadCurve(
                to: CGPoint(x: (points[index].x + next.x) / 2,
                            y: (points[index].y + next.y) / 2),
                control: points[index]
            )
        }
        path.closeSubpath()
        return path
    }

    private func presentedPondLabelAnchor(_ name: String) -> CGPoint {
        if disclosureSnapshot == nil {
            let anchor = pondGeometries[name]?.labelAnchor ?? .zero
            let offset = pondOffset(name)
            return CGPoint(x: anchor.x + offset.x, y: anchor.y + offset.y)
        }
        guard let bounds = presentedPondPath(name)?.boundingBoxOfPath else {
            let anchor = pondGeometries[name]?.labelAnchor ?? .zero
            let offset = pondOffset(name)
            return CGPoint(x: anchor.x + offset.x, y: anchor.y + offset.y)
        }
        let zoom = max(currentZoom, 0.001)
        let titleHeight = pondLabelText(for: name).size().height / zoom
        return CGPoint(x: bounds.midX, y: bounds.maxY - titleHeight - min(60, 12 / zoom))
    }

    private func translated(_ path: CGPath?, by offset: CGPoint) -> CGPath? {
        guard let path else { return nil }
        guard offset != .zero else { return path }
        var transform = CGAffineTransform(translationX: offset.x, y: offset.y)
        return path.copy(using: &transform)
    }

    /// Paths used by drag feedback and drop evaluation. Hidden basins cannot be
    /// destinations, even when their geometry is still cached; an empty basin
    /// remains eligible when focused and visibly rendered.
    private func visibleDragBasins() -> [String: CGPath] {
        pondGeometries.reduce(into: [:]) { result, entry in
            let name = entry.key
            guard let path = presentedPondPath(name),
                  let basin = pondBasins[name], !basin.isHidden, basin.alpha > 0.001 else { return }
            result[name] = path
        }
    }

    private func dragMarkerPosition(for touchLocation: CGPoint) -> CGPoint {
        CGPoint(x: touchLocation.x + dragTouchOffset.x,
                y: touchLocation.y + dragTouchOffset.y)
    }

    private func pondDropTarget(from originalPoint: CGPoint, to finalPoint: CGPoint) -> String? {
        let sourceID = dragOriginalPondID ?? dragOriginalContainingPondIDs.sorted().first
        return PondDragBoundary.target(
            from: originalPoint,
            to: finalPoint,
            sourcePondID: sourceID,
            basins: visibleDragBasins(),
            zoom: currentZoom
        )
    }

    /// Rechecks snap precedence at the release endpoint. UIKit may omit the
    /// final moved callback, so a preview from the prior frame is not allowed
    /// to win over the actual drop location.
    private func refreshSnapTarget(for node: PersonNode, at markerPoint: CGPoint) {
        var closestDist: CGFloat = snapDistance
        var closestID: UUID?
        for (id, otherNode) in personNodes {
            guard id != node.personID, !otherNode.isHidden, otherNode.alpha > 0.25 else { continue }
            let distance = hypot(markerPoint.x - otherNode.position.x,
                                 markerPoint.y - otherNode.position.y)
            if distance < closestDist {
                closestDist = distance
                closestID = id
            }
        }

        if let previousID = snapTargetID, previousID != closestID {
            personNodes[previousID]?.setHoverGlow(false)
        }
        snapTargetID = closestID
        if let targetID = closestID, let targetNode = personNodes[targetID] {
            targetNode.setHoverGlow(true)
            let curvedPath = curvedEdgePath(from: node.position, to: targetNode.position)
            snapPreviewLine?.path = curvedPath.copy(dashingWithPhase: 0, lengths: [6, 4])
            snapPreviewLine?.isHidden = false
        } else {
            snapPreviewLine?.isHidden = true
            snapPreviewLine?.path = nil
        }
    }

    private func interruptCameraAnimation() {
        cameraNode.removeAllActions()
        currentZoom = 1 / max(cameraNode.xScale, 0.001)
        updateLOD()
        updatePondLabelScales()
        graphDelegate?.updateCameraFromScene(position: cameraNode.position, zoom: currentZoom)
    }

    /// Visible contacts whose minimum hit regions contain this point, nearest
    /// first with an identifier tie-break for deterministic choice UI.
    private func contactNodes(at location: CGPoint) -> [PersonNode] {
        let visible = personNodes.values.filter { !$0.isHidden && $0.alpha > 0.25 }
        let zoom = 1 / max(cameraNode.xScale, 0.001)
        let radius = max(35, 22 / zoom)
        return visible.filter {
            hypot($0.position.x - location.x, $0.position.y - location.y) <= radius
        }.sorted {
            let a = hypot($0.position.x - location.x, $0.position.y - location.y)
            let b = hypot($1.position.x - location.x, $1.position.y - location.y)
            return a == b ? $0.personID.uuidString < $1.personID.uuidString : a < b
        }
    }

    private func contactNode(at location: CGPoint) -> PersonNode? {
        contactNodes(at: location).first
    }

    @discardableResult
    private func presentContactChoiceIfAmbiguous(_ ids: [UUID]) -> Bool {
        guard ids.count > 1 else { return false }
        graphDelegate?.presentContactChoices(ids)
        return true
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let activeTouchCount = event?.allTouches?.filter {
            $0.phase == .began || $0.phase == .moved || $0.phase == .stationary
        }.count ?? touches.count
        if max(touches.count, activeTouchCount) > 1 {
            touchesCancelled([], with: nil)
            longPressOwnedTouch = true
            touchHasMoved = true
            return
        }
        guard let touch = touches.first else { return }
        guard let view else { return }
        longPressOwnedTouch = false
        longPressedContactID = nil
        longPressPondCandidateID = nil
        interruptCameraAnimation()
        let location = touch.location(in: contentNode)
        longPressStartContentPoint = location
        dragStartLocation = location
        lastTouchLocation = touch.location(in: view)
        touchHasMoved = false
        let contactCandidates = contactNodes(at: location)
        touchContactCandidateIDs = contactCandidates.map(\.personID)
        // Both direct and disclosed contacts use the same gesture threshold:
        // a stationary touch explores; a deliberate drag can connect or move.
        if let node = contactCandidates.first {
            touchStartedOnPondID = nil
            draggedNode = node
            dragOriginalPosition = node.position
            dragTouchOffset = CGPoint(x: node.position.x - location.x,
                                      y: node.position.y - location.y)
            let basins = visibleDragBasins()
            dragOriginalContainingPondIDs = Set(basins.compactMap { name, path in
                path.contains(node.position) ? name : nil
            })
            dragOriginalPondID = pondID(for: node.personID) ?? dragOriginalContainingPondIDs.sorted().first
            node.removeAction(forKey: "bob")
            node.removeAction(forKey: "slotMove")
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            let scaleUp = SKAction.scale(to: 1.2, duration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.15)
            scaleUp.timingMode = .easeOut
            node.run(scaleUp)
            return
        }
        draggedNode = nil
        touchStartedOnPondID = pondHit(at: location)
        longPressPondCandidateID = touchStartedOnPondID
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let activeTouchCount = event?.allTouches?.filter {
            $0.phase == .began || $0.phase == .moved || $0.phase == .stationary
        }.count ?? touches.count
        if activeTouchCount > 1 {
            cancelPondDrag()
            longPressOwnedTouch = true
            touchHasMoved = true
            return
        }
        if pondDragState != nil {
            updatePondDrag(to: touch.location(in: contentNode))
            touchHasMoved = true
            return
        }
        if longPressOwnedTouch { return }

        if let node = draggedNode {
            let location = touch.location(in: contentNode)
            let movedDistance = hypot(location.x - dragStartLocation.x, location.y - dragStartLocation.y)
            // Keep a tap entirely stationary. Once the deliberate movement
            // threshold is crossed, preserve the finger-to-marker offset so
            // the marker does not jump across a pond border on activation.
            guard touchHasMoved || movedDistance * currentZoom > 8 else { return }
            if !touchHasMoved {
                touchHasMoved = true
                removeAction(forKey: "singleTap")
                // Once this gesture becomes a drag, its overlapping hit
                // candidates can no longer produce a chooser on release.
                touchContactCandidateIDs.removeAll()
            }
            node.position = dragMarkerPosition(for: location)

            // Snap detection: closest other node.
            var closestDist: CGFloat = snapDistance
            var closestID: UUID?
            for (id, otherNode) in personNodes {
                guard id != node.personID, !otherNode.isHidden, otherNode.alpha > 0.25 else { continue }
                let d = hypot(node.position.x - otherNode.position.x, node.position.y - otherNode.position.y)
                if d < closestDist { closestDist = d; closestID = id }
            }

            if let prevTargetID = snapTargetID, prevTargetID != closestID {
                personNodes[prevTargetID]?.setHoverGlow(false)
            }
            let changedTarget = snapTargetID != closestID
            snapTargetID = closestID
            if let targetID = closestID, let targetNode = personNodes[targetID] {
                if changedTarget { UISelectionFeedbackGenerator().selectionChanged() }
                targetNode.setHoverGlow(true)
                let curvedPath = curvedEdgePath(from: node.position, to: targetNode.position)
                snapPreviewLine?.path = curvedPath.copy(dashingWithPhase: 0, lengths: [6, 4])
                snapPreviewLine?.isHidden = false

                if let old = hoverPondName {
                    resetPondStyle(old)
                    hoverPondName = nil
                }
            } else {
                snapPreviewLine?.isHidden = true
                snapPreviewLine?.path = nil

                if !(draggedNode?.isMe ?? false) {
                    let foundPondName = pondDropTarget(from: dragOriginalPosition, to: node.position)
                    if let old = hoverPondName, old != foundPondName {
                        resetPondStyle(old)
                    }
                    hoverPondName = foundPondName
                    if let new = hoverPondName { highlightPondStyle(new) }
                }
            }
        } else {
            // 1-finger camera pan.
            guard let view = self.view else { return }
            let screenLocation = touch.location(in: view)
            if touchStartedOnPondID != nil {
                guard hypot(screenLocation.x - lastTouchLocation.x,
                            screenLocation.y - lastTouchLocation.y) > 8 else { return }
                touchStartedOnPondID = nil
                longPressPondCandidateID = nil
            }
            noteUserCameraAdjustment()
            let dx = -(screenLocation.x - lastTouchLocation.x) / currentZoom
            let dy = (screenLocation.y - lastTouchLocation.y) / currentZoom
            cameraNode.position = CGPoint(x: cameraNode.position.x + dx,
                                          y: cameraNode.position.y + dy)
            lastTouchLocation = screenLocation
            touchHasMoved = true
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        if pondDragState != nil {
            updatePondDrag(to: touch.location(in: contentNode))
            endPondDrag()
            touchStartedOnPondID = nil
            longPressPondCandidateID = nil
            longPressOwnedTouch = false
            return
        }
        if longPressOwnedTouch {
            if let id = longPressedContactID, draggedNode?.personID == id {
                personNodes[id]?.run(SKAction.scale(to: 1, duration: 0.12))
                draggedNode = nil
                touchHasMoved = false
            }
            longPressedContactID = nil
            longPressOwnedTouch = false
            touchStartedOnPondID = nil
            longPressPondCandidateID = nil
            return
        }
        guard let node = draggedNode else {
            if !touchHasMoved {
                let point = touch.location(in: contentNode)
                if let id = pondGeometries.keys.sorted().first(where: { id in
                    presentedPondPath(id)?.contains(point) == true ||
                    pondLabels[id]?.calculateAccumulatedFrame().insetBy(dx: -16 / max(currentZoom, 0.001), dy: -12 / max(currentZoom, 0.001)).contains(point) == true
                }) { soloPond(name: id) }
            }
            if let old = hoverPondName { resetPondStyle(old); hoverPondName = nil }
            graphDelegate?.updateCameraFromScene(position: cameraNode.position, zoom: currentZoom)
            touchStartedOnPondID = nil
            longPressPondCandidateID = nil
            return
        }

        let scaleDown = SKAction.scale(to: 1.0, duration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.15)
        scaleDown.timingMode = .easeIn
        node.run(scaleDown)

        // UIKit can deliver the final touch position without a preceding
        // touchesMoved callback. Evaluate the actual marker endpoint freshly,
        // using the same anchor captured at gesture begin.
        if touchHasMoved {
            node.position = dragMarkerPosition(for: touch.location(in: contentNode))
            refreshSnapTarget(for: node, at: node.position)
        }
        let dropPondName = touchHasMoved && !node.isMe && snapTargetID == nil
            ? pondDropTarget(from: dragOriginalPosition, to: node.position)
            : nil

        // Determine whether an action fired.
        if touchHasMoved {
            if let targetID = snapTargetID {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                graphDelegate?.requestConnection(from: node.personID, to: targetID)
            } else if let pondName = dropPondName {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                graphDelegate?.requestPondMove(for: node.personID, to: pondName)
            }
        } else {
            if touch.tapCount == 2 {
                // The double-tap recognizer owns the same disclosure action.
                removeAction(forKey: "singleTap")
            } else {
                if !presentContactChoiceIfAmbiguous(touchContactCandidateIDs) {
                    let id = node.personID
                    run(.sequence([.wait(forDuration: 0.32), .run { [weak self] in
                        self?.activatePondContact(id)
                    }]), withKey: "singleTap")
                }
            }
        }

        // Clean up preview state.
        if let targetID = snapTargetID { personNodes[targetID]?.setHoverGlow(false) }
        if let old = hoverPondName { resetPondStyle(old); hoverPondName = nil }
        snapPreviewLine?.isHidden = true
        snapPreviewLine?.path = nil
        snapTargetID = nil

        // No action → spring the node back to its layout slot (easeOut overshoot ~1.05).
        springBackToSlot(node)

        draggedNode = nil
        touchHasMoved = false
        dragOriginalPosition = .zero
        dragTouchOffset = .zero
        dragOriginalPondID = nil
        dragOriginalContainingPondIDs.removeAll()
        touchContactCandidateIDs.removeAll()
        touchStartedOnPondID = nil
        longPressPondCandidateID = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if pondDragState != nil { cancelPondDrag() }
        touchStartedOnPondID = nil
        longPressPondCandidateID = nil
        longPressOwnedTouch = false
        longPressedContactID = nil
        guard let node = draggedNode else {
            if let old = hoverPondName { resetPondStyle(old); hoverPondName = nil }
            removeAction(forKey: "singleTap")
            touchContactCandidateIDs.removeAll()
            return
        }
        removeAction(forKey: "singleTap")
        node.run(SKAction.scale(to: 1.0, duration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.15))
        if let targetID = snapTargetID { personNodes[targetID]?.setHoverGlow(false) }
        if let old = hoverPondName { resetPondStyle(old); hoverPondName = nil }
        snapPreviewLine?.isHidden = true
        snapPreviewLine?.path = nil
        snapTargetID = nil
        springBackToSlot(node)
        draggedNode = nil
        touchHasMoved = false
        dragOriginalPosition = .zero
        dragTouchOffset = .zero
        dragOriginalPondID = nil
        dragOriginalContainingPondIDs.removeAll()
        touchContactCandidateIDs.removeAll()
    }

    /// crisp ease-out, no overshoot (trains, not water) — then refresh its edges.
    private func springBackToSlot(_ node: PersonNode) {
        guard layoutSlots[node.personID] != nil else { return }
        let slot = presentedPosition(for: node.personID)
        node.removeAction(forKey: "slotMove")

        let slide = SKAction.move(to: slot, duration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.32)
        slide.timingMode = .easeOut
        let updateEdges = SKAction.run { [weak self] in self?.renderEdges() }
        node.run(SKAction.sequence([slide, updateEdges]), withKey: "slotMove")

        // Keep edges following during the slide.
        let follow = SKAction.repeat(
            SKAction.sequence([SKAction.run { [weak self] in self?.renderEdges() },
                               SKAction.wait(forDuration: 1.0 / 30.0)]),
            count: 12)
        node.run(follow)
    }

    // MARK: - Gesture Handlers

    @objc private func handlePinch(_ sender: UIPinchGestureRecognizer) {
        guard self.view != nil, pondDragState == nil else { return }
        switch sender.state {
        case .began:
            noteUserCameraAdjustment()
            interruptCameraAnimation()
            removeAction(forKey: "singleTap")
            lastPinchScale = sender.scale
        case .changed:
            let delta = sender.scale / lastPinchScale
            let newZoom = currentZoom * delta
            if newZoom >= 0.001 && newZoom <= 4.0 {
                currentZoom = newZoom
                cameraNode.setScale(1.0 / currentZoom)
            }
            lastPinchScale = sender.scale
            updateLOD()
            updatePondLabelScales()
            refreshMapMePosition()
            if let meNode = personNodes.values.first(where: { $0.isMe }) {
                meNode.position = presentedPosition(for: meNode.personID)
            }
            arrangeNameLabels()
            renderEdges()
            graphDelegate?.updateCameraFromScene(position: cameraNode.position, zoom: currentZoom)
        case .ended:
            graphDelegate?.updateCameraFromScene(position: cameraNode.position, zoom: currentZoom)
        default:
            break
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view = self.view, pondDragState == nil else { return }
        if gesture.state == .began { noteUserCameraAdjustment() }
        interruptCameraAnimation()
        removeAction(forKey: "singleTap")
        let translation = gesture.translation(in: view)
        switch gesture.state {
        case .changed:
            let dx = -translation.x / currentZoom
            let dy = translation.y / currentZoom
            cameraNode.position = CGPoint(x: cameraNode.position.x + dx,
                                          y: cameraNode.position.y + dy)
            gesture.setTranslation(.zero, in: view)
        case .ended:
            graphDelegate?.updateCameraFromScene(position: cameraNode.position, zoom: currentZoom)
        default:
            break
        }
    }

    private func activatePondContact(_ id: UUID) {
        if opensRipplesOnTap {
            graphDelegate?.activatePondContact(id: id)
        } else {
            graphDelegate?.selectContact(id)
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        removeAction(forKey: "singleTap")
        guard let view = self.view else { return }
        let screenLocation = gesture.location(in: view)
        let location = contentNode.convert(convertPoint(fromView: screenLocation), from: self)
        let candidates = contactNodes(at: location)
        if presentContactChoiceIfAmbiguous(candidates.map(\.personID)) {
            return
        }
        if let node = candidates.first {
            removeAction(forKey: "singleTap")
            activatePondContact(node.personID)
            return
        }
        var tappedPondName: String? = nil
        for name in pondGeometries.keys where pondIsPresented(name) {
            if let path = presentedPondPath(name), path.contains(location) {
                tappedPondName = name
                break
            }
        }

        if let pondName = tappedPondName {
            soloPond(name: pondName)
        } else {
            currentZoom = 1.0
            let moveAction = SKAction.move(to: .zero, duration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.3)
            let scaleAction = SKAction.scale(to: 1.0, duration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.3)
            moveAction.timingMode = .easeInEaseOut
            scaleAction.timingMode = .easeInEaseOut
            cameraNode.run(moveAction, withKey: "cameraMove")
            cameraNode.run(scaleAction, withKey: "cameraScale")
            updateLOD()
            updatePondLabelScales()
            graphDelegate?.updateCameraFromScene(position: .zero, zoom: 1.0)
        }
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard let view = self.view else { return }
        let screenLocation = gesture.location(in: view)
        let sceneLocation = convertPoint(fromView: screenLocation)
        let contentLocation = contentNode.convert(sceneLocation, from: self)
        if (gesture.state == .began || gesture.state == .changed), gesture.numberOfTouches != 1 {
            cancelPondDrag()
            longPressPondCandidateID = nil
            touchStartedOnPondID = nil
            longPressOwnedTouch = true
            touchHasMoved = true
            return
        }

        switch gesture.state {
        case .began:
            if let node = contactNode(at: contentLocation) {
                let id = node.personID
                if draggedNode?.personID == id { touchesCancelled([], with: nil) }
                longPressOwnedTouch = true
                longPressedContactID = id
                removeAction(forKey: "singleTap")
                touchContactCandidateIDs.removeAll()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                graphDelegate?.didLongPressContact(id)
                highlightNode(id)
            } else if let pondID = longPressPondCandidateID {
                interruptCameraAnimation()
                noteUserCameraAdjustment()
                longPressOwnedTouch = beginPondDrag(pondID: pondID, at: longPressStartContentPoint)
            }
        case .changed:
            updatePondDrag(to: contentLocation)
        case .ended:
            updatePondDrag(to: contentLocation)
            endPondDrag()
            touchStartedOnPondID = nil
            longPressPondCandidateID = nil
        case .cancelled, .failed:
            cancelPondDrag()
            touchStartedOnPondID = nil
            longPressPondCandidateID = nil
            longPressedContactID = nil
            longPressOwnedTouch = false
        default:
            break
        }
    }

    private func soloPond(name: String) {
        if soloedPondName == name {
            unsoloAll()
            return
        }
        if soloedPondName == nil { cameraBeforePondFocus = (cameraNode.position, currentZoom) }
        soloedPondName = name
        graphDelegate?.selectedPondFilter = name
        evaluateNodeVisibility()
        // Camera fits that pond's basin.
        if let geo = pondGeometries[name] {
            fitToRect(basinBoundingRect(geo), minZoom: 0.001, maxZoom: 1.3, padding: 32, screenInset: 36)
        }
    }

    private func unsoloAll() {
        let previous = cameraBeforePondFocus
        cameraBeforePondFocus = nil
        soloedPondName = nil
        graphDelegate?.selectedPondFilter = nil
        evaluateNodeVisibility()
        if let previous { restoreCamera(previous) }
    }

#if DEBUG
    /// Test bridges forward to the same state transitions used by UIKit.
    @discardableResult
    func debugBeginPondDrag(pondID: String, at point: CGPoint) -> Bool {
        beginPondDrag(pondID: pondID, at: point)
    }
    func debugUpdatePondDrag(to point: CGPoint) { updatePondDrag(to: point) }
    func debugEndPondDrag() { endPondDrag() }
    func debugCancelPondDrag() { cancelPondDrag() }
    func debugReloadGraph(_ levels: [GraphLevel]) {
        graphLevelsCache = levels
        updateGraph(levels)
    }
    var debugPondOffsets: [String: CGPoint] { pondLayoutOffsets }
    var debugPondDragIsActive: Bool { pondDragState != nil }
    var debugEdgePaths: [String: CGPath] {
        edgeNodes.compactMapValues(\.path)
    }

    /// Test bridge for the exact activation path used by a pointer tap. Keeping
    /// this forwarding-only avoids duplicating the delegate behavior in tests.
    func debugActivatePondContact(_ id: UUID) {
        activatePondContact(id)
    }

    func debugSetContactPosition(_ position: CGPoint, for id: UUID) {
        personNodes[id]?.position = position
    }

    func debugContactCandidateIDs(at point: CGPoint) -> [UUID] {
        contactNodes(at: point).map(\.personID)
    }

    @discardableResult
    func debugPresentContactChoice(at point: CGPoint) -> Bool {
        presentContactChoiceIfAmbiguous(debugContactCandidateIDs(at: point))
    }

    var debugFocusedPondName: String? { soloedPondName }
    var debugCameraPosition: CGPoint { cameraNode.position }
    var debugCameraZoom: CGFloat { currentZoom }
    var debugCameraBeforePondFocus: (position: CGPoint, zoom: CGFloat)? { cameraBeforePondFocus }
    var debugDimmedIDs: Set<UUID> {
        Set(personNodes.values.filter { !$0.isHidden && $0.alpha > 0 && $0.alpha <= 0.25 }.map(\.personID))
    }
    var debugFullIdentityIDs: Set<UUID> {
        Set(personNodes.values.filter { !$0.isHidden && $0.showsIdentity }.map(\.personID))
    }

    func debugLayout(_ levels: [GraphLevel]) -> [UUID: CGPoint] {
        graphLevelsCache = levels
        removeAction(forKey: "singleTap")
        updateNodesAndEdges(levels: levels)
        computeLayout(levels: levels)
        _ = reconcileDirectFirstLayout(allowActivation: true)
        applyLayout(animated: false)
        evaluateNodeVisibility(animated: false)
        updateLOD()
        arrangeNameLabels()
        return layoutSlots
    }
    var debugPondLabelPointSizes: [CGFloat] {
        pondLabels.values.compactMap { label in
            guard let font = label.attributedText?.attribute(.font, at: 0, effectiveRange: nil) as? UIFont else { return nil }
            return font.pointSize * label.xScale * currentZoom
        }
    }
    var debugMeShowsIdentity: Bool { personNodes.values.first { $0.isMe }?.showsIdentity ?? false }
    var debugMeIsVisible: Bool { personNodes.values.first { $0.isMe }.map { !$0.isHidden && $0.alpha > 0.01 } ?? false }
    var debugPresentedMePosition: CGPoint? {
        personNodes.values.first(where: { $0.isMe }).map { presentedPosition(for: $0.personID) }
    }
    var debugGroupIDs: Set<String> { Set(pondGeometries.keys) }
    var debugGroupMembers: [String: Set<UUID>] { pondGeometries.mapValues { Set($0.memberIDs) } }
    var debugLabelTexts: [String: String] { pondLabels.mapValues { $0.attributedText?.string ?? "" } }
    var debugGroupColors: [String: UIColor] { Dictionary(uniqueKeysWithValues: pondInfos.map { ($0.id, $0.color) }) }
    var debugParents: [UUID: UUID] { branchParentByChild }
    var debugHiddenIDs: Set<UUID> { hiddenBranchIDs }
    var debugVisibleEdgeCount: Int { edgeNodes.values.filter { !$0.isHidden }.count }
    var debugVisibleEdgeKeys: Set<String> { Set(edgeNodes.filter { !$0.value.isHidden }.map { $0.key }) }
    var debugOverviewConnectorCount: Int {
        contentNode.children.filter { $0.name?.hasPrefix("overviewPondConnector-") == true }.count
    }
    var debugMeCoinBounds: CGRect? {
        guard let node = personNodes.values.first(where: { $0.isMe }) else { return nil }
        return node.identityBounds.offsetBy(dx: node.position.x, dy: node.position.y)
    }
    var debugCompactIdentityIDs: Set<UUID> {
        Set(personNodes.values.filter { !$0.isMe && $0.compactIdentityIsVisible }.map(\.personID))
    }
    var debugCompactOverviewIdentity: Bool { usesCompactOverviewIdentity }
    var debugPondLabelBounds: [String: CGRect] {
        pondLabels.filter { !$0.value.isHidden }.mapValues { $0.calculateAccumulatedFrame() }
    }
    var debugPondBasinBounds: [String: CGRect] {
        pondBasins.filter { !$0.value.isHidden }.mapValues { $0.calculateAccumulatedFrame() }
    }
    /// Stable saved geometry, independent of presentation visibility.
    var debugPondGeometryBounds: [String: CGRect] {
        pondGeometries.compactMapValues { $0.basinPath?.boundingBoxOfPath }
    }
    var debugVisibleDragBasinBounds: [String: CGRect] {
        visibleDragBasins().mapValues(\.boundingBoxOfPath)
    }
    var debugPresentedPondPaths: [String: CGPath] { visibleDragBasins() }
    var debugVisibleIdentityBounds: [UUID: CGRect] {
        personNodes.compactMap { id, node -> (UUID, CGRect)? in
            guard !node.isHidden, node.alpha > 0.25 else { return nil }
            let point = presentedPosition(for: id)
            return (id, node.visibleIdentityBounds.offsetBy(dx: point.x, dy: point.y))
        }.reduce(into: [:]) { $0[$1.0] = $1.1 }
    }
    var debugVisibleCoinBounds: [UUID: CGRect] {
        personNodes.compactMap { id, node -> (UUID, CGRect)? in
            guard !node.isHidden, node.alpha > 0.01,
                  let bounds = node.visibleMarkerBounds else { return nil }
            let point = presentedPosition(for: id)
            return (id, bounds.offsetBy(dx: point.x, dy: point.y))
        }.reduce(into: [:]) { $0[$1.0] = $1.1 }
    }
    var debugVisibleNameLabelBounds: [UUID: CGRect] {
        personNodes.compactMap { id, node -> (UUID, CGRect)? in
            guard !node.isHidden, node.alpha > 0.01, node.nameLabelIsVisible else { return nil }
            let point = presentedPosition(for: id)
            return (id, node.nameLabelBounds.offsetBy(dx: point.x, dy: point.y))
        }.reduce(into: [:]) { $0[$1.0] = $1.1 }
    }
    /// IDs currently rendered by SpriteKit after disclosure/search visibility
    /// filtering. This is intentionally based on node state rather than the
    /// model snapshot so tests can catch stale visual nodes.
    var debugRenderedVisibleIDs: Set<UUID> {
        Set(personNodes.values.filter { !$0.isHidden && $0.alpha > 0.01 }.map(\.personID))
    }
    /// Node visibility at the start of a reveal, before its fade has ticked.
    /// An SKView without a window does not advance SpriteKit actions in tests.
    var debugRevealedNodeIDs: Set<UUID> {
        Set(personNodes.values.filter { !$0.isHidden }.map(\.personID))
    }
    var debugDisclosureRoleLabels: [UUID: String] {
        personNodes.compactMap { id, node -> (UUID, String)? in
            guard let role = node.contextRoleText else { return nil }
            return (id, role)
        }.reduce(into: [:]) { $0[$1.0] = $1.1 }
    }
    var debugDisclosureIdentityLabels: [UUID: String] {
        personNodes.compactMap { id, node -> (UUID, String)? in
            guard !node.isHidden, node.showsIdentity else { return nil }
            return (id, node.labelText)
        }.reduce(into: [:]) { $0[$1.0] = $1.1 }
    }
    var debugSelectedLabelText: String? {
        personNodes.values.first(where: { $0.isSelected })?.labelText
    }
    var debugNodePositions: [UUID: CGPoint] { personNodes.mapValues(\.position) }
    var debugDisclosureVisibleIDs: Set<UUID> { disclosureSnapshot?.visibleIDs ?? [] }
    var debugDisclosureDirectIDs: Set<UUID> { disclosureSnapshot?.directIDs ?? [] }
    var debugDisclosureExpandedIDs: Set<UUID> { disclosureSnapshot?.expandedIDs ?? [] }
    var debugDisclosureSelectedID: UUID? { disclosureSnapshot?.selectedID }
    var debugDisclosureTrail: [UUID] { disclosureSnapshot?.trail ?? [] }
    var debugDisclosureHiddenCounts: [UUID: Int] { disclosureSnapshot?.hiddenNeighborCounts ?? [:] }
    var debugDisclosureHiddenByPond: [String: Int] {
        disclosureSnapshot?.hiddenByPond.mapValues(\.count) ?? [:]
    }
    var debugDisclosureUnlinkedIDs: Set<UUID> { disclosureSnapshot?.unlinkedIDs ?? [] }
    var debugDisclosureIdentityBounds: [UUID: CGRect] {
        Dictionary(uniqueKeysWithValues: (disclosureSnapshot?.visibleIDs ?? []).compactMap { id in
            guard let node = personNodes[id] else { return nil }
            return (id, node.visibleIdentityBounds.offsetBy(dx: node.position.x, dy: node.position.y))
        })
    }
    #endif

    // MARK: - Line hover styling (drag-to-move feedback)

    private func resetPondStyle(_ name: String) {
        guard let basin = pondBasins[name] else { return }
        for child in basin.children {
            guard let shape = child as? SKShapeNode else { continue }
            shape.lineWidth = basinStrokeWidth
        }
    }

    private func highlightPondStyle(_ name: String) {
        guard let basin = pondBasins[name] else { return }
        for child in basin.children {
            guard let shape = child as? SKShapeNode else { continue }
            shape.lineWidth = basinStrokeWidth * 1.8
        }
    }
}

// MARK: - PersonNode
/// Matte contact medallions with a watercolor Me, readable names, and optional relationship annotations.
final class PersonNode: SKNode {
    let personID: UUID
    let isMe: Bool
    private let coin = SKNode()
    private let nameLabel = SKLabelNode()
    private let ring = SKShapeNode()
    private let hover = SKShapeNode()
    private let favorite = SKShapeNode(circleOfRadius: 3)
    private let disclosureCue = SKShapeNode()
    private let contextRole = SKNode()
    private let contextRoleLabel = SKLabelNode()
    private var contextRoleIcon: SKSpriteNode?
    private let petBadge = SKNode()
    private var disclosureHiddenCount = 0
    private var disclosureExpanded = false
    private var cachedIsPet = false
    /// Far-zoom identity token; it replaces anonymous dot-only LOD.
    private let compactToken = SKShapeNode(circleOfRadius: 7)
    private let compactMark = SKLabelNode()
    private var cachedName: String
    private var cachedPhoto: Data?
    private var cachedGroupColor: UIColor = .gray
    private var cachedPond: String?
    private var cachedFavorite = false
    private var nameHiddenByCollision = false
    private var lod = 0
    private var disclosureHighlighted = false
    private var disclosureIdentityExpanded = false
    private var radius: CGFloat { isMe ? 31 : 22 }
    enum LabelPlacement { case below, right }

    static func pondName(for person: Person) -> String? {
        person.primaryCircle?.name
    }
    static func firstName(_ name: String) -> String { gfFirstName(name) }
    static func firstTwoInitials(_ name: String) -> String {
        let words = name.split(separator: " ")
        guard let first = words.first else { return "?" }
        return (String(first.prefix(1)) + (words.count > 1 ? String(words.last!.prefix(1)) : "")).uppercased()
    }

    init(person: Person, depth: Int) {
        personID = person.id
        isMe = person.isMe
        cachedName = person.name
        super.init()
        name = person.id.uuidString
        addChild(coin)
        addChild(nameLabel)
        addChild(ring)
        addChild(hover)
        addChild(favorite)
        addChild(disclosureCue)
        disclosureCue.zPosition = 8
        addChild(petBadge)
        petBadge.zPosition = 7
        addChild(contextRole)
        contextRole.zPosition = 6
        contextRoleLabel.verticalAlignmentMode = .center
        contextRoleLabel.horizontalAlignmentMode = .left
        contextRole.addChild(contextRoleLabel)
        addChild(compactToken)
        addChild(compactMark)
        nameLabel.position = CGPoint(x: 0, y: -(radius + 9))
        nameLabel.verticalAlignmentMode = .top
        nameLabel.horizontalAlignmentMode = .center
        nameLabel.zPosition = 4
        for shape in [ring, hover] {
            shape.path = CGPath(ellipseIn: CGRect(x: -radius - 5, y: -radius - 5, width: (radius + 5) * 2, height: (radius + 5) * 2), transform: nil)
            shape.fillColor = .clear
            shape.lineWidth = 2
            shape.isHidden = true
        }
        favorite.position = CGPoint(x: radius, y: radius)
        favorite.zPosition = 5
        compactToken.zPosition = 4
        compactMark.zPosition = 5
        compactMark.verticalAlignmentMode = .center
        compactMark.horizontalAlignmentMode = .center
        update(with: person)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(with person: Person) {
        cachedName = person.name
        cachedPhoto = person.photoData
        cachedPond = Self.pondName(for: person)
        cachedGroupColor = GraphInk.graphTone(person.primaryCircle)
        cachedFavorite = person.isFavorite
        cachedIsPet = person.isPet
        reskinForCurrentTrait()
    }

    func reskinForCurrentTrait() {
        coin.removeAllChildren()
        let tone = isMe ? GraphInk.gold : cachedGroupColor.resolvedColor(with: GraphInk.traitForResolution)
        let photoImage = cachedPhoto.flatMap { UIImage(data: $0) }
        if isMe, photoImage == nil {
            if let image = UIImage(named: "WatercolorKoi") {
                let diameter = radius * 2
                let ratio = image.size.width / max(1, image.size.height)
                let size = ratio >= 1
                    ? CGSize(width: diameter, height: diameter / ratio)
                    : CGSize(width: diameter * ratio, height: diameter)
                coin.addChild(SKSpriteNode(texture: SKTexture(image: image), size: size))
            }
        } else {
            let crop = SKCropNode()
            let mask = SKShapeNode(circleOfRadius: radius)
            mask.fillColor = .white
            mask.strokeColor = .clear
            crop.maskNode = mask
            let base = SKShapeNode(circleOfRadius: radius)
            base.fillColor = tone
            base.strokeColor = .clear
            crop.addChild(base)
            if let image = photoImage {
                let ratio = image.size.width / max(1, image.size.height)
                let size = ratio >= 1 ? CGSize(width: radius * 2 * ratio, height: radius * 2) : CGSize(width: radius * 2, height: radius * 2 / ratio)
                crop.addChild(SKSpriteNode(texture: SKTexture(image: image), size: size))
            } else {
                // One quiet matte surface keeps the initials readable and avoids
                // competing flecks at small map sizes.
                let initials = SKLabelNode()
                initials.attributedText = NSAttributedString(string: Self.firstTwoInitials(cachedName), attributes: [
                    .font: GraphInk.serifFont(size: 16), .foregroundColor: GraphInk.contrastText(on: tone)
                ])
                initials.verticalAlignmentMode = .center
                crop.addChild(initials)
            }
            coin.addChild(crop)
            let rim = SKShapeNode(circleOfRadius: radius)
            rim.strokeColor = tone.withAlphaComponent(0.72)
            rim.fillColor = .clear
            rim.lineWidth = 1
            coin.addChild(rim)
        }
        let identity = disclosureIdentityExpanded ? fittedName(maxWidth: 132) : Self.firstName(cachedName)
        gfSetLabel(nameLabel, text: identity, size: 13, weight: .medium, color: GraphInk.label)
        ring.strokeColor = GraphInk.indigo
        if disclosureHighlighted { ring.strokeColor = GraphInk.indigo }
        hover.strokeColor = GraphInk.indigo
        favorite.fillColor = GraphInk.indigo
        favorite.strokeColor = .clear
        petBadge.removeAllChildren()
        if cachedIsPet {
            let base = SKShapeNode(circleOfRadius: 9)
            base.fillColor = GraphInk.background
            base.strokeColor = GraphInk.ink(0.35)
            petBadge.addChild(base)
            if let image = UIImage(systemName: "pawprint.fill")?.withTintColor(GraphInk.gold, renderingMode: .alwaysOriginal) {
                petBadge.addChild(SKSpriteNode(texture: SKTexture(image: image), size: CGSize(width: 12, height: 12)))
            }
        }
        if contextRoleLabel.attributedText?.string.isEmpty != false { contextRole.isHidden = true }
        compactToken.fillColor = GraphInk.background
        compactToken.strokeColor = tone
        compactToken.lineWidth = 1
        compactMark.attributedText = NSAttributedString(string: Self.firstTwoInitials(cachedName), attributes: [
            .font: GraphInk.serifFont(size: 9, weight: .medium),
            .foregroundColor: GraphInk.label
        ])
        applyLOD()
        if selected {
            ring.isHidden = false
            compactToken.lineWidth = 2
            compactToken.strokeColor = GraphInk.indigo
            gfSetLabel(nameLabel, text: fittedName(maxWidth: selectedLabelWidth ?? 220),
                       size: 13, weight: .medium, color: GraphInk.label)
        }
    }
    func setLabelPlacement(_ placement: LabelPlacement) { /* Editorial names always sit below their coins. */ }
    func setNameScale(_ scale: CGFloat) { nameLabel.setScale(scale) }
    func updateScreenScale(zoom: CGFloat) {
        let zoom = max(zoom, 0.001)
        let visualScale = max(1, (isMe ? 0.62 : 0.58) / zoom)
        coin.setScale(visualScale)
        ring.setScale(visualScale)
        hover.setScale(visualScale)
        // Counter-scale to a compact ~14-point screen token instead of letting
        // the far-zoom identity balloon with the camera.
        compactToken.setScale(max(1, 1 / zoom))
        compactMark.setScale(max(1, 1 / zoom))
        nameLabel.setScale(max(1, 0.85 / zoom))
        nameLabel.position = CGPoint(x: 0, y: -(radius * visualScale + 5 / zoom))
        nameLabel.horizontalAlignmentMode = .center
        nameLabel.verticalAlignmentMode = .top
        favorite.position = CGPoint(x: radius * visualScale, y: radius * visualScale)
        petBadge.setScale(1 / zoom)
        petBadge.position = CGPoint(x: radius * visualScale + 3 / zoom, y: -radius * visualScale + 2 / zoom)
        contextRole.setScale(1 / zoom)
        contextRole.position = CGPoint(x: -(contextRoleLabel.frame.width + 15) / 2,
                                      y: -(radius * visualScale + 28 / zoom))
        applyLOD()
    }
    func showFull() { lod = 0; applyLOD() }
    func setNameCollisionHidden(_ hidden: Bool) {
        nameHiddenByCollision = hidden
        nameLabel.isHidden = lod != 0 || nameHiddenByCollision
    }
    func showDotOnly() { lod = 2; applyLOD() }
    private func applyLOD() {
        coin.isHidden = lod == 2
        nameLabel.isHidden = lod != 0 || nameHiddenByCollision
        favorite.isHidden = !cachedFavorite || isMe || lod == 2
        compactToken.isHidden = lod != 2
        compactMark.isHidden = lod != 2
        petBadge.isHidden = !cachedIsPet || lod == 2
        disclosureCue.isHidden = disclosureHiddenCount == 0 && !disclosureExpanded
        contextRole.isHidden = lod != 0 || contextRoleLabel.attributedText?.string.isEmpty != false
    }
    /// A quiet chevron communicates that a person can reveal or collapse more
    /// connections without exposing a misleading relationship-distance count.
    func setDisclosureCue(hiddenCount: Int, expanded: Bool) {
        disclosureHiddenCount = max(0, hiddenCount)
        disclosureExpanded = expanded
        let path = CGMutablePath()
        if expanded {
            path.move(to: CGPoint(x: -5, y: 2)); path.addLine(to: CGPoint(x: 0, y: -3)); path.addLine(to: CGPoint(x: 5, y: 2))
        } else {
            path.move(to: CGPoint(x: -2, y: 5)); path.addLine(to: CGPoint(x: 3, y: 0)); path.addLine(to: CGPoint(x: -2, y: -5))
        }
        disclosureCue.path = path
        disclosureCue.strokeColor = GraphInk.secondaryLabel
        disclosureCue.fillColor = .clear
        disclosureCue.lineWidth = 1.3
        disclosureCue.lineCap = .round
        disclosureCue.lineJoin = .round
        disclosureCue.position = CGPoint(x: radius + 8, y: radius + 6)
        applyLOD()
    }

    /// Adds a compact relationship label when a selected or nearby contact has
    /// context to show. Pet identity continues to use its independent badge.
    func setContextRole(_ text: String?, symbol: String?) {
        contextRoleIcon?.removeFromParent()
        contextRoleIcon = nil
        guard let text, !text.isEmpty else {
            contextRoleLabel.attributedText = NSAttributedString(string: "")
            contextRole.isHidden = true
            return
        }
        gfSetLabel(contextRoleLabel, text: text, size: 10, weight: .regular, color: GraphInk.secondaryLabel)
        contextRoleLabel.position = CGPoint(x: 15, y: 0)
        if let symbol, let image = UIImage(systemName: symbol)?.withTintColor(GraphInk.secondaryLabel, renderingMode: .alwaysOriginal) {
            let icon = SKSpriteNode(texture: SKTexture(image: image), size: CGSize(width: 11, height: 11))
            icon.position = CGPoint(x: 5, y: 0)
            contextRole.addChild(icon)
            contextRoleIcon = icon
        }
        contextRole.isHidden = lod != 0
    }

    func setDisclosureIdentityExpanded(_ expanded: Bool) {
        disclosureIdentityExpanded = expanded
        let identity = expanded ? fittedName(maxWidth: 132) : Self.firstName(cachedName)
        gfSetLabel(nameLabel, text: identity, size: 13, weight: .medium, color: GraphInk.label)
    }

    func setDisclosureHighlighted(_ highlighted: Bool) {
        disclosureHighlighted = highlighted
        ring.strokeColor = GraphInk.indigo
        ring.isHidden = !(selected || highlighted)
    }
    var identityBounds: CGRect { coin.calculateAccumulatedFrame() }
    var visibleMarkerBounds: CGRect? {
        if compactIdentityIsVisible { return compactToken.calculateAccumulatedFrame() }
        return coin.isHidden ? nil : identityBounds
    }
    var visibleIdentityBounds: CGRect {
        var bounds: CGRect?
        if compactIdentityIsVisible {
            bounds = compactToken.calculateAccumulatedFrame()
        } else if !coin.isHidden {
            bounds = identityBounds
        }
        if !nameLabel.isHidden {
            let nameBounds = nameLabel.calculateAccumulatedFrame()
            bounds = bounds.map { $0.union(nameBounds) } ?? nameBounds
        }
        if !disclosureCue.isHidden {
            let cueBounds = disclosureCue.calculateAccumulatedFrame()
            bounds = bounds.map { $0.union(cueBounds) } ?? cueBounds
        }
        if !contextRole.isHidden {
            let roleBounds = contextRole.calculateAccumulatedFrame()
            bounds = bounds.map { $0.union(roleBounds) } ?? roleBounds
        }
        return bounds ?? .zero
    }
    var nameBounds: CGRect { nameLabel.calculateAccumulatedFrame() }
    func placeName(zoom: CGFloat, extraBelow: CGFloat = 0) {
        let zoom = max(zoom, 0.001)
        let reach = radius * coin.xScale + 6 / zoom
        nameLabel.horizontalAlignmentMode = .center
        nameLabel.verticalAlignmentMode = .top
        nameLabel.position = CGPoint(x: 0, y: -reach - max(0, extraBelow))
        // Relationship context is laid out immediately below the name, keeping
        // the entire identity block centered beneath the contact.
    }
    var showsIdentity: Bool { !coin.isHidden && !nameLabel.isHidden }
    var wantsNameLabel: Bool { lod == 0 }
    var nameLabelIsVisible: Bool { !nameLabel.isHidden }
    var nameLabelBounds: CGRect { nameLabel.calculateAccumulatedFrame() }
    var compactIdentityIsVisible: Bool { !compactToken.isHidden && !compactMark.isHidden }
    var labelText: String { nameLabel.attributedText?.string ?? "" }
    var contextRoleText: String? {
        let value = contextRoleLabel.attributedText?.string ?? ""
        return value.isEmpty ? nil : value
    }
    var contextRoleBounds: CGRect { contextRole.calculateAccumulatedFrame() }
    private var selected = false
    private var selectedLabelWidth: CGFloat?
    var isSelected: Bool { selected || disclosureHighlighted }
    func setSelected(_ selected: Bool, maxLabelWidth: CGFloat? = nil) {
        self.selected = selected
        if let maxLabelWidth { selectedLabelWidth = maxLabelWidth }
        ring.isHidden = !(selected || disclosureHighlighted)
        compactToken.lineWidth = selected ? 2 : 1
        compactToken.strokeColor = selected ? GraphInk.indigo : compactToken.strokeColor
        let labelText = selected ? fittedName(maxWidth: selectedLabelWidth ?? 220) :
            (disclosureIdentityExpanded ? fittedName(maxWidth: 132) : Self.firstName(cachedName))
        gfSetLabel(nameLabel, text: labelText, size: 13, weight: .medium, color: GraphInk.label)
    }

    private func fittedName(maxWidth: CGFloat) -> String {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFontMetrics(forTextStyle: .caption1).scaledFont(for: UIFont.systemFont(ofSize: 13, weight: .medium), maximumPointSize: 22, compatibleWith: GraphInk.traitForResolution)
        ]
        guard NSAttributedString(string: cachedName, attributes: attributes).size().width > maxWidth else { return cachedName }
        var value = cachedName
        while value.count > 1 {
            value.removeLast()
            let candidate = value.trimmingCharacters(in: .whitespaces) + "…"
            if NSAttributedString(string: candidate, attributes: attributes).size().width <= maxWidth { return candidate }
        }
        return "…"
    }
    func setHoverGlow(_ hovered: Bool) { hover.isHidden = !hovered }
}

private func gfSetLabel(_ label: SKLabelNode, text: String, size: CGFloat, weight: UIFont.Weight, color: UIColor) {
    label.attributedText = NSAttributedString(string: text, attributes: [
        .font: UIFontMetrics(forTextStyle: .caption1).scaledFont(for: UIFont.systemFont(ofSize: size, weight: weight), maximumPointSize: 22, compatibleWith: GraphInk.traitForResolution),
        .foregroundColor: color
    ])
}
