import SpriteKit
import SwiftUI

// MARK: - GoldfishGraphScene
/// Full interactive SpriteKit scene for the relationship graph.
/// Replaces PlaceholderGraphScene with force-directed physics layout,
/// edges, tap selection, LOD, viewport culling, and camera controls.
final class GoldfishGraphScene: SKScene, GraphSceneDelegate {

    // MARK: - Delegate
    weak var graphDelegate: GraphViewModel?

    // MARK: - Camera
    private let cameraNode = SKCameraNode()
    private var currentZoom: CGFloat = 1.0

    // MARK: - Delta-Time Clamping
    private var lastUpdateTime: TimeInterval = 0
    private let maxDeltaTime: TimeInterval = 1.0 / 30.0  // Cap at ~33ms to prevent lag-spike explosions

    // MARK: - Content
    private let contentNode = SKNode()
    private var personNodes: [UUID: ScenePersonNode] = [:]
    private var edgeNodes: [String: SKShapeNode] = [:]
    private var graphLevelsCache: [GraphLevel] = []

    // MARK: - Pond Labels & Clouds
    private var pondLabels: [String: SKLabelNode] = [:]    // circleName -> label
    private var pondClouds: [String: SKShapeNode] = [:]    // circleName -> cloud background
    /// Cached cloud radii to avoid rebuilding paths every frame
    private var pondCloudCachedRadius: [String: CGFloat] = [:]
    
    struct PondInfo {
        let circleName: String
        let color: String
        let memberIDs: [UUID]
    }
    private var pondInfos: [PondInfo] = []

    struct PondMetrics {
        let name: String
        let center: CGPoint
        let radius: CGFloat
        let memberIDs: [UUID]
    }
    private var currentPondMetrics: [PondMetrics] = []

    // MARK: - Drag-Snap Connection
    private var snapPreviewLine: SKShapeNode?
    private var snapTargetID: UUID?
    private let snapDistance: CGFloat = 50

    // MARK: - Gesture State
    private var lastPinchScale: CGFloat = 1.0
    private var selectedNodeID: UUID?

    // MARK: - Physics Settle & Focus Mode
    private var physicsSettled = false
    private var soloedPondName: String? = nil
    
    /// Rolling per-frame kinetic energy used for energy-based settling.
    private var frameEnergyHistory: [CGFloat] = []
    private let energyHistoryWindowSize = 10
    
    // MARK: - Search State
    private var activeSearchIDs: Set<UUID>? = nil
    
    /// Whether `didMove(to:)` has fired — physics world isn't ready before this.
    private var sceneReady = false
    /// Levels received before the scene was ready.
    private var pendingLevels: [GraphLevel]?

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        // Deep midnight teal / aquatic tone
        backgroundColor = UIColor(red: 0x06/255, green: 0x14/255, blue: 0x1B/255, alpha: 1.0)
        anchorPoint = CGPoint(x: 0.5, y: 0.5)

        addChild(cameraNode)
        camera = cameraNode
        addChild(contentNode)

        physicsWorld.gravity = .zero
        physicsWorld.speed = 1.0

        // NOTE: No SKFieldNode here — all forces are computed manually in update()

        setupGestures(in: view)
        
        // Apply any levels that arrived before the scene was ready
        sceneReady = true
        if let pending = pendingLevels {
            pendingLevels = nil
            updateGraph(pending)
        }
    }

    // MARK: - Gesture Setup

    private func setupGestures(in view: SKView) {
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        view.addGestureRecognizer(pinch)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        view.addGestureRecognizer(pan)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)
        
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        view.addGestureRecognizer(longPress)
    }

    // MARK: - GraphSceneDelegate

    func didUpdateGraphLevels(_ levels: [GraphLevel]) {
        graphLevelsCache = levels
        if sceneReady {
            updateGraph(levels)
        } else {
            // Scene not presented yet — defer until didMove(to:)
            pendingLevels = levels
        }
    }

    func didSelectContact(_ id: UUID?) {
        highlightNode(id)
    }

    func didUpdateZoom(_ zoom: CGFloat) {
        let clamped = min(max(zoom, 0.1), 4.0)
        currentZoom = clamped
        let action = SKAction.scale(to: 1.0 / clamped, duration: 0.25)
        action.timingMode = .easeInEaseOut
        cameraNode.run(action, withKey: "cameraScale")
        updateLOD()
    }

    func didUpdateCameraPosition(_ position: CGPoint) {
        let action = SKAction.move(to: position, duration: 0.25)
        action.timingMode = .easeInEaseOut
        cameraNode.run(action, withKey: "cameraMove")
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        // Ensure camera and content are still aligned if size changes
        // P0-3 Fix: Prevent catastrophic zoom bugs by ignoring invalid sizes
        guard size.width >= 50 && size.height >= 50 else { return }
        
        if oldSize == .zero && size != .zero {
            graphDelegate?.resetCamera()
        }
    }

    func centerOnContact(_ id: UUID) {
        guard let node = personNodes[id] else { return }
        
        // Always zoom to a comfortable level when centering on a contact
        let targetZoom: CGFloat = 1.0
        let moveAction = SKAction.move(to: node.position, duration: 0.5)
        moveAction.timingMode = .easeInEaseOut
        
        let scaleAction = SKAction.scale(to: 1.0 / targetZoom, duration: 0.5)
        scaleAction.timingMode = .easeInEaseOut
        
        cameraNode.run(moveAction, withKey: "cameraMove")
        cameraNode.run(scaleAction, withKey: "cameraScale")
        
        currentZoom = targetZoom
        updateLOD()
        graphDelegate?.updateCameraFromScene(position: node.position, zoom: targetZoom)
    }
    
    func centerOnMe() {
        // Find the user's ("Me") node
        for (id, node) in personNodes {
            if node.isMe {
                centerOnContact(id)
                return
            }
        }
        
        // Fallback: If no "Me" node, center on the very first node found instead of zooming all the way out.
        if let firstID = personNodes.keys.first {
            centerOnContact(firstID)
            return
        }
        
        // Fallback to fitting the whole graph if literally no nodes
        fitToGraph()
    }
    
    func centerOnPond(name: String) {
        let info = pondInfos.first(where: { $0.circleName == name })
        let memberIDs = info?.memberIDs ?? []
        fitToNodes(memberIDs, minZoom: 0.3, maxZoom: 1.0, padding: 80.0)
    }
    
    func fitToGraph() {
        let allIDs = Array(personNodes.keys)
        // Adaptive zoom: use contact count to determine comfortable zoom bounds
        let count = allIDs.count
        let adaptiveMaxZoom: CGFloat
        if count <= 5 {
            adaptiveMaxZoom = 1.2      // Few contacts — cozy, close-up view
        } else if count <= 15 {
            adaptiveMaxZoom = 0.9      // Medium network — balanced overview
        } else if count <= 30 {
            adaptiveMaxZoom = 0.6      // Larger network — pull back for overview
        } else {
            adaptiveMaxZoom = 0.4      // Big network — bird's eye
        }
        fitToNodes(allIDs, minZoom: 0.15, maxZoom: adaptiveMaxZoom, padding: 100.0)
    }
    
    /// Zooms out to show all ponds while keeping the "Me" node at the center of the viewport.
    func fitToGraphCenteredOnMe() {
        // Find the Me node position (our camera center)
        var mePosition: CGPoint = .zero
        for (_, node) in personNodes {
            if node.isMe {
                mePosition = node.position
                break
            }
        }
        
        let allNodes = Array(personNodes.values)
        guard !allNodes.isEmpty else { return }
        
        // Find the maximum distance from Me to any node
        var maxDistance: CGFloat = 100  // minimum baseline
        for node in allNodes {
            let px = node.position.x
            let py = node.position.y
            guard px.isFinite && py.isFinite else { continue }
            let dx = px - mePosition.x
            let dy = py - mePosition.y
            let dist = hypot(dx, dy)
            maxDistance = max(maxDistance, dist)
        }
        
        // The viewport needs to fit a circle of radius maxDistance + padding around Me
        let padding: CGFloat = 120
        let requiredRadius = maxDistance + padding
        let diameter = requiredRadius * 2
        
        let viewDimWidth = size.width
        let viewDimHeight = size.height
        guard viewDimWidth > 0 && viewDimHeight > 0 else { return }
        
        let zoomX = viewDimWidth / diameter
        let zoomY = viewDimHeight / diameter
        var targetZoom = min(zoomX, zoomY)
        
        // Clamp
        if !targetZoom.isFinite || targetZoom <= 0 { targetZoom = 1.0 }
        
        // Adaptive max zoom based on contact count
        let count = allNodes.count
        let adaptiveMaxZoom: CGFloat
        if count <= 5 {
            adaptiveMaxZoom = 1.0
        } else if count <= 15 {
            adaptiveMaxZoom = 0.8
        } else if count <= 30 {
            adaptiveMaxZoom = 0.5
        } else {
            adaptiveMaxZoom = 0.35
        }
        targetZoom = min(max(targetZoom, 0.1), adaptiveMaxZoom)
        
        let moveAction = SKAction.move(to: mePosition, duration: 0.5)
        moveAction.timingMode = .easeInEaseOut
        
        let scaleAction = SKAction.scale(to: 1.0 / targetZoom, duration: 0.5)
        scaleAction.timingMode = .easeInEaseOut
        
        cameraNode.run(moveAction, withKey: "cameraMove")
        cameraNode.run(scaleAction, withKey: "cameraScale")
        
        currentZoom = targetZoom
        updateLOD()
        graphDelegate?.updateCameraFromScene(position: mePosition, zoom: targetZoom)
    }
    
    private func fitToNodes(_ ids: [UUID], minZoom: CGFloat, maxZoom: CGFloat, padding: CGFloat) {
        let nodes = ids.compactMap { personNodes[$0] }
        guard !nodes.isEmpty else { return }
        
        var minX: CGFloat = .greatestFiniteMagnitude
        var maxX: CGFloat = -.greatestFiniteMagnitude
        var minY: CGFloat = .greatestFiniteMagnitude
        var maxY: CGFloat = -.greatestFiniteMagnitude
        
        for node in nodes {
            let px = node.position.x
            let py = node.position.y
            // FIX 4 — Guard against NaN/Infinity coordinates that cause grey-screen
            guard px.isFinite && py.isFinite else { continue }
            minX = min(minX, px)
            maxX = max(maxX, px)
            minY = min(minY, py)
            maxY = max(maxY, py)
        }
        
        // If all positions were invalid, bail out gracefully with identity scale.
        guard minX < maxX || minY < maxY else {
            cameraNode.setScale(1.0)
            return
        }
        
        let width = max(maxX - minX, 100) + (padding * 2)
        let height = max(maxY - minY, 100) + (padding * 2)
        
        let cx = (minX + maxX) / 2
        let cy = (minY + maxY) / 2
        // Clamp center as well — should always be finite after the guard above
        guard cx.isFinite && cy.isFinite else {
            cameraNode.setScale(1.0)
            return
        }
        let target = CGPoint(x: cx, y: cy)
        
        let viewDimWidth = size.width
        let viewDimHeight = size.height
        guard viewDimWidth > 0 && viewDimHeight > 0 else { return }
        
        let zoomX = viewDimWidth / width
        let zoomY = viewDimHeight / height
        var targetZoom = min(zoomX, zoomY)
        
        // Clamp the derived scale — prevents setScale(NaN) / setScale(Infinity)
        if !targetZoom.isFinite || targetZoom <= 0 { targetZoom = 1.0 }
        targetZoom = min(max(targetZoom, minZoom), maxZoom)
        
        let moveAction = SKAction.move(to: target, duration: 0.5)
        moveAction.timingMode = .easeInEaseOut
        
        let scaleAction = SKAction.scale(to: 1.0 / targetZoom, duration: 0.5)
        scaleAction.timingMode = .easeInEaseOut
        
        cameraNode.run(moveAction, withKey: "cameraMove")
        cameraNode.run(scaleAction, withKey: "cameraScale")
        
        currentZoom = targetZoom
        updateLOD()
        graphDelegate?.updateCameraFromScene(position: target, zoom: targetZoom)
    }

    func didUpdatePondFilter(_ name: String?) {
        soloedPondName = name
        evaluateNodeVisibility()
    }

    func requestConnection(from: UUID, to: UUID) {
        // No-op: This is handled by GraphViewModel, not by the scene
    }
    
    func didUpdateSearchMatches(_ ids: Set<UUID>?) {
        activeSearchIDs = ids
        evaluateNodeVisibility(animated: false)
    }
    
    func didLongPressContact(_ id: UUID) {
        // Handled by GraphViewModel
    }
    
    func animateNewConnection(from: UUID, to: UUID) {
        guard let nodeA = personNodes[from], let nodeB = personNodes[to] else { return }
        
        // 1. Visual pulse on both nodes
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.15, duration: 0.1),
            SKAction.scale(to: 1.0, duration: 0.2)
        ])
        nodeA.run(pulse)
        nodeB.run(pulse)
        
        // 2. Intelligent repositioning: if the two nodes are too close,
        //    find a good angle to place nodeA at restLength from nodeB
        //    that avoids overlapping other nearby nodes.
        let idealSpacing: CGFloat = 100.0  // matches FDG restLength
        let currentDist = hypot(nodeA.position.x - nodeB.position.x,
                                nodeA.position.y - nodeB.position.y)
        
        if currentDist < idealSpacing * 1.2, let bodyA = nodeA.physicsBody, bodyA.isDynamic {
            // Scan angles in 30° increments to find the best position
            let angleSteps = 12
            var bestAngle: CGFloat = 0
            var bestMinDist: CGFloat = -1
            
            for step in 0..<angleSteps {
                let candidateAngle = (CGFloat(step) / CGFloat(angleSteps)) * 2.0 * .pi
                let candidateX = nodeB.position.x + cos(candidateAngle) * idealSpacing
                let candidateY = nodeB.position.y + sin(candidateAngle) * idealSpacing
                
                // Find the minimum distance from this candidate to all OTHER nodes
                var minDistToOthers: CGFloat = .greatestFiniteMagnitude
                for (id, otherNode) in personNodes {
                    guard id != from && id != to else { continue }
                    let d = hypot(candidateX - otherNode.position.x,
                                  candidateY - otherNode.position.y)
                    minDistToOthers = min(minDistToOthers, d)
                }
                
                // Pick the angle that maximizes distance to nearest neighbor
                if minDistToOthers > bestMinDist {
                    bestMinDist = minDistToOthers
                    bestAngle = candidateAngle
                }
            }
            
            let targetX = nodeB.position.x + cos(bestAngle) * idealSpacing
            let targetY = nodeB.position.y + sin(bestAngle) * idealSpacing
            let targetPos = CGPoint(x: targetX, y: targetY)
            
            // Stop current velocity and animate to the ideal position
            bodyA.velocity = .zero
            let moveAction = SKAction.move(to: targetPos, duration: 0.3)
            moveAction.timingMode = .easeInEaseOut
            nodeA.run(moveAction)
        }
        
        // 3. Wake physics to let the graph settle naturally after the reposition
        physicsWorld.speed = 1.0
        physicsSettled = false
        frameEnergyHistory.removeAll()
    }

    func forceReorder() {
        // Any reorder (manual or auto) supersedes a pending auto-untangle check
        removeAction(forKey: Self.autoReorderActionKey)

        // Recompute targets with fresh, dynamic geometry.
        // scheduleAutoReorder: false — a reorder pass must never schedule
        // another check, otherwise overlapping geometry could loop forever.
        updateGraph(graphLevelsCache, scheduleAutoReorder: false)
        
        // Freeze physics so it can't fight the animation
        physicsWorld.speed = 0
        
        // Animate every node to its exact target over 0.4s
        for (_, node) in personNodes {
            guard let body = node.physicsBody, body.isDynamic else { continue }
            body.velocity = .zero
            node.removeAction(forKey: "reorder")
            
            let move = SKAction.move(to: node.targetPosition, duration: 0.4)
            move.timingMode = .easeInEaseOut
            node.run(move, withKey: "reorder")
        }
        
        // After animation completes, wake physics for micro-settling
        let wait = SKAction.wait(forDuration: 0.45)
        let wake = SKAction.run { [weak self] in
            self?.physicsSettled = false
            self?.frameEnergyHistory.removeAll()
            self?.physicsWorld.speed = 1.0
        }
        self.run(SKAction.sequence([wait, wake]), withKey: "reorderWake")
    }

    // MARK: - Auto-Reorder (automatic pond untangling)

    /// SKAction key for the debounced auto-reorder check. Re-running with the
    /// same key replaces any pending check, so rapid successive graph updates
    /// collapse into a single pass.
    private static let autoReorderActionKey = "autoReorderCheck"
    /// Delay after a graph update before checking for overlap — long enough
    /// for the spring physics to move nodes toward their targets, and just
    /// ahead of the initial +1.5s fitToGraph so the fit sees the untangled layout.
    private let autoReorderDebounceDelay: TimeInterval = 1.0
    /// Retry delay when a check fires while the user is mid-gesture.
    private let autoReorderGestureRetryDelay: TimeInterval = 0.8
    /// Two pond bounding circles must intrude by more than this fraction of
    /// their combined radii before an automatic reorder is triggered (>15%).
    private let autoReorderOverlapFraction: CGFloat = 0.15

    /// Schedules a debounced check that auto-runs the reorder routine when
    /// pond clusters visibly overlap. Cheap no-op when the layout is clean.
    private func scheduleAutoReorderCheck(after delay: TimeInterval? = nil) {
        removeAction(forKey: Self.autoReorderActionKey)
        let wait = SKAction.wait(forDuration: delay ?? autoReorderDebounceDelay)
        let check = SKAction.run { [weak self] in
            self?.performAutoReorderIfNeeded()
        }
        run(SKAction.sequence([wait, check]), withKey: Self.autoReorderActionKey)
    }

    private func performAutoReorderIfNeeded() {
        // Never reorder while the user is mid-gesture — retry shortly after.
        if draggedNode != nil || draggedPondName != nil {
            scheduleAutoReorderCheck(after: autoReorderGestureRetryDelay)
            return
        }
        guard pondsNeedUntangling() else { return }
        forceReorder()
    }

    /// `true` when two pond bounding circles intersect meaningfully or a node
    /// sits inside a foreign pond's cloud — the visual tangle the manual
    /// reorder button exists to fix. Uses `currentPondMetrics`, which
    /// `update()` refreshes every frame before actions are evaluated.
    private func pondsNeedUntangling() -> Bool {
        let metrics = currentPondMetrics
        guard !metrics.isEmpty else { return false }

        // 1. Pond vs pond: circles overlapping by >15% of their combined radii
        for i in 0..<metrics.count {
            for j in (i + 1)..<metrics.count {
                let a = metrics[i]
                let b = metrics[j]
                let dist = hypot(a.center.x - b.center.x, a.center.y - b.center.y)
                let combined = a.radius + b.radius
                guard dist.isFinite, combined > 0 else { continue }
                if (combined - dist) > combined * autoReorderOverlapFraction {
                    return true
                }
            }
        }

        // 2. Intermingling: a non-ME node sitting inside a foreign pond cloud
        for (id, node) in personNodes {
            guard !node.isMe else { continue }
            let pos = node.position
            guard pos.x.isFinite && pos.y.isFinite else { continue }
            for metric in metrics where !metric.memberIDs.contains(id) {
                let dist = hypot(pos.x - metric.center.x, pos.y - metric.center.y)
                if dist < metric.radius {
                    return true
                }
            }
        }

        return false
    }

    /// Tracks which edge keys exist (for rendering). Springs are no longer used.
    private var edgeConnections: Set<String> = []
    private var initialFitCompleted = false

    // MARK: - Graph Building

    private func updateGraph(_ levels: [GraphLevel], scheduleAutoReorder: Bool = true) {
        updateNodesAndEdges(levels: levels)
        evaluateNodeVisibility(animated: false)

        // Auto-untangle: after initial load and membership/structure changes,
        // run a debounced check for overlapping ponds and trigger the same
        // routine as the manual reorder button. Not scheduled from
        // forceReorder itself (see scheduleAutoReorder: false there).
        if scheduleAutoReorder {
            scheduleAutoReorderCheck()
        }

        if !initialFitCompleted {
            // Fit the entire graph into view after physics settles a bit
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.fitToGraph()
                self?.initialFitCompleted = true
            }
        }
    }

    private func updateNodesAndEdges(levels: [GraphLevel]) {
        physicsSettled = false
        physicsWorld.speed = 1.0
        
        // NOTE: No SKFieldNode gravity — all forces computed manually in update()

        // 1. Identify current vs new persons
        let currentPersonIDs = Set(personNodes.keys)
        let allContacts = levels.flatMap(\.allContacts)
        let newPersonIDs = Set(allContacts.map(\.id))
        var newNodeIDs: Set<UUID> = []  // Track newly-created nodes for deterministic spawn positioning
        
        // Remove nodes for persons no longer in graph
        for id in currentPersonIDs where !newPersonIDs.contains(id) {
            personNodes[id]?.removeFromParent()
            personNodes.removeValue(forKey: id)
        }
        
        // Update or create person nodes
        for level in levels {
            let levelContacts = level.allContacts
            let count = levelContacts.count
            
            // P0-1 Fix: Dynamically scale radius based on contact count to prevent physics explosion
            let radius = CGFloat(level.depth * 100) + max(35.0, CGFloat(count) * 14.0)

            for (index, person) in levelContacts.enumerated() {
                if let node = personNodes[person.id] {
                    // Update existing node if needed
                    node.update(with: person, depth: level.depth)
                } else {
                    // Create new node
                    let personNode = ScenePersonNode(person: person, depth: level.depth)
                    
                    // FIX 1 — Pre-scatter: Never spawn at (0,0). Place every node on a
                    // deterministic ring PLUS a random polar offset so F=k/d² never
                    // approaches infinity.  The minimum guaranteed separation is 50 pt.
                    let angle = (CGFloat(index) / CGFloat(max(count, 1))) * 2 * .pi
                    let scatterRadius = CGFloat.random(in: 30...80)
                    let scatterAngle = angle + CGFloat.random(in: -0.3...0.3)
                    let x = cos(scatterAngle) * (radius + scatterRadius)
                    let y = sin(scatterAngle) * (radius + scatterRadius)
                    
                    personNode.position = CGPoint(x: x, y: y)

                    let physicsRadius: CGFloat = person.isMe ? 50 : (level.depth > 1 ? 34 : 40)
                    let body = SKPhysicsBody(circleOfRadius: physicsRadius)
                    body.mass = 1.0
                    body.linearDamping = 4.0
                    body.angularDamping = 2.0
                    body.allowsRotation = false
                    body.categoryBitMask = 1
                    body.collisionBitMask = 0
                    body.fieldBitMask = 0  // No SKFieldNode forces — all manual

                    // Anchor "Me" node: immovable hub prevents multi-body solver instability
                    if person.isMe {
                        body.isDynamic = false
                        personNode.position = .zero
                    } else {
                        body.isDynamic = true
                    }
                    personNode.physicsBody = body

                    // NOTE: No SKFieldNode repulsion child — Coulomb repulsion is manual

                    contentNode.addChild(personNode)
                    personNodes[person.id] = personNode
                    newNodeIDs.insert(person.id)
                }
            }
        }

        // 2. Update Pond Info
        pondInfos.removeAll()
        var pondMembers: [String: (color: String, ids: Set<UUID>)] = [:]
        for (_, personNode) in personNodes {
            guard let person = allContacts.first(where: { $0.id == personNode.personID }) else { continue }
            // ME node is the graph anchor — never include it in any pond
            guard !person.isMe else { continue }
            
            let activeCircles = person.circleContacts.filter { !$0.manuallyExcluded }
            for membership in activeCircles {
                let circle = membership.circle
                if pondMembers[circle.name] != nil {
                    pondMembers[circle.name]!.ids.insert(person.id)
                } else {
                    pondMembers[circle.name] = (color: circle.color, ids: [person.id])
                }
            }
        }

        // Update pond labels & clouds (Incremental)
        let currentPondNames = Set(pondLabels.keys)
        let newPondNames = Set(pondMembers.keys)
        
        // Remove old pond labels + clouds
        for name in currentPondNames where !newPondNames.contains(name) {
            pondLabels[name]?.removeFromParent()
            pondLabels.removeValue(forKey: name)
            pondClouds[name]?.removeFromParent()
            pondClouds.removeValue(forKey: name)
            pondCloudCachedRadius.removeValue(forKey: name)
        }
        
        // Update or create pond data + labels + clouds
        for (name, info) in pondMembers {
            let pondInfo = PondInfo(circleName: name, color: info.color, memberIDs: Array(info.ids))
            pondInfos.append(pondInfo)
            
            let pondColor = GoldfishUIColor(hex: info.color) ?? UIColor.systemGray3

            // Create label if needed
            if pondLabels[name] == nil {
                let label = SKLabelNode(text: name)
                label.fontName = "SFProRounded-Bold"
                label.fontSize = 16
                label.fontColor = pondColor
                label.horizontalAlignmentMode = .center
                label.verticalAlignmentMode = .top
                label.zPosition = -1
                
                contentNode.addChild(label)
                pondLabels[name] = label
            }
            
            // Create cloud background if needed
            if pondClouds[name] == nil {
                let cloud = SKShapeNode(circleOfRadius: 80) // placeholder; updated in update()
                cloud.fillColor = pondColor.withAlphaComponent(0.06)
                cloud.strokeColor = pondColor.withAlphaComponent(0.18)
                cloud.lineWidth = 1.5
                cloud.glowWidth = 4.0
                cloud.zPosition = -5
                cloud.alpha = 0.9
                contentNode.addChild(cloud)
                pondClouds[name] = cloud
                pondCloudCachedRadius[name] = 80
            }
        }

        // ── Geometric target positions ──
        // Compute deterministic arc positions for every node.
        // ME stays at origin; each pond gets an angular sector around ME;
        // members are evenly spaced on an arc within their sector.
        do {
            var pondOrder: [String] = []
            for info in pondInfos {
                if !pondOrder.contains(info.circleName) {
                    pondOrder.append(info.circleName)
                }
            }
            let pondCount = max(pondOrder.count, 1)
            
            // Pre-compute per-pond cluster radii and estimated visual radii
            // so arcRadius can adapt to the largest pond.
            var pondClusterRadii: [String: CGFloat] = [:]
            var largestEstimatedPondRadius: CGFloat = 55  // baseline for a single-member pond
            
            for pondName in pondOrder {
                guard let info = pondInfos.first(where: { $0.circleName == pondName }) else { continue }
                let memberCount = info.memberIDs.count
                // sqrt scaling: prevents explosion for large ponds
                let clusterR: CGFloat = memberCount <= 1 ? 0.0 : max(40, sqrt(CGFloat(memberCount)) * 45)
                pondClusterRadii[pondName] = clusterR
                // Estimated visual radius matches cloud padding logic in update()
                let estimatedVisualRadius: CGFloat = memberCount <= 1 ? 55.0 : clusterR + 60
                largestEstimatedPondRadius = max(largestEstimatedPondRadius, estimatedVisualRadius)
            }
            
            // Arc radius: far enough that the largest pond can't reach ME at (0,0)
            let arcRadius: CGFloat = max(350, largestEstimatedPondRadius * 2.5)
            
            for (pondIndex, pondName) in pondOrder.enumerated() {
                guard let info = pondInfos.first(where: { $0.circleName == pondName }) else { continue }
                let members = info.memberIDs
                let memberCount = members.count
                guard memberCount > 0 else { continue }
                
                // Each pond gets a distinct anchor point
                let pondAngle = (CGFloat(pondIndex) / CGFloat(pondCount)) * 2 * .pi - .pi / 2  // start from top
                let anchorX = cos(pondAngle) * arcRadius
                let anchorY = sin(pondAngle) * arcRadius
                
                // Spread members in a tight cluster around the pond anchor
                let clusterRadius: CGFloat = pondClusterRadii[pondName] ?? 0
                
                for (memberIndex, memberID) in members.enumerated() {
                    guard let node = personNodes[memberID] else { continue }
                    
                    let memberAngle = (CGFloat(memberIndex) / CGFloat(max(memberCount, 1))) * 2 * .pi
                    let tx = anchorX + cos(memberAngle) * clusterRadius
                    let ty = anchorY + sin(memberAngle) * clusterRadius
                    node.targetPosition = CGPoint(x: tx, y: ty)
                    
                    // Also set initial position for new nodes
                    if newNodeIDs.contains(memberID) {
                        node.position = CGPoint(x: tx, y: ty)
                    }
                }
            }
            
            // Unassigned nodes: place at bottom
            for (_, node) in personNodes {
                if node.isMe { node.targetPosition = .zero; continue }
                let inPond = pondInfos.contains { $0.memberIDs.contains(node.personID) }
                if !inPond {
                    node.targetPosition = CGPoint(x: 0, y: -arcRadius - 100)
                }
            }
        }

        // 3. Update Edges and Springs (Incremental)
        var desiredEdges: Set<String> = []
        for (personID, _) in personNodes {
            guard let person = allContacts.first(where: { $0.id == personID }) else { continue }
            for rel in person.allRelationships {
                let otherID = rel.fromContact.id == personID ? rel.toContact.id : rel.fromContact.id
                let edgeKey = [personID.uuidString, otherID.uuidString].sorted().joined(separator: "_")
                if personNodes[otherID] != nil {
                    desiredEdges.insert(edgeKey)
                }
            }
        }
        
        // Remove old edges (no springs to clean up — they're gone)
        for edgeKey in Array(edgeNodes.keys) where !desiredEdges.contains(edgeKey) {
            edgeNodes[edgeKey]?.removeFromParent()
            edgeNodes.removeValue(forKey: edgeKey)
        }
        edgeConnections = desiredEdges
        
        // Create new edge rendering nodes (NO SKPhysicsJointSpring — Hooke's law is manual)
        for edgeKey in desiredEdges {
            if edgeNodes[edgeKey] == nil {
                let edgeNode = SKShapeNode()
                // Warm highlight color (terracotta/goldfish theme)
                edgeNode.strokeColor = UIColor(red: 212/255, green: 116/255, blue: 78/255, alpha: 0.5)
                edgeNode.lineWidth = 2.0
                edgeNode.alpha = 0.6
                edgeNode.zPosition = -1
                edgeNode.name = edgeKey
                edgeNode.glowWidth = 1.0
                
                let parts = edgeKey.split(separator: "_")
                if parts.count == 2,
                   let id1 = UUID(uuidString: String(parts[0])),
                   let id2 = UUID(uuidString: String(parts[1])) {
                    let data = NSMutableDictionary()
                    data["id1"] = id1
                    data["id2"] = id2
                    edgeNode.userData = data
                }
                
                contentNode.addChild(edgeNode)
                edgeNodes[edgeKey] = edgeNode
            }
        }

        // Snap preview line (static)
        if snapPreviewLine == nil {
            let preview = SKShapeNode()
            preview.strokeColor = UIColor(red: 183/255, green: 79/255, blue: 58/255, alpha: 0.55)
            preview.lineWidth = 1.5
            preview.isHidden = true
            preview.zPosition = 10
            contentNode.addChild(preview)
            snapPreviewLine = preview
        }

        // Energy-based settling: didSimulatePhysics() watches kinetic energy.
        physicsWorld.speed = 1.0  // Never run above 1.0 — custom sim handles pacing
        physicsSettled = false
        frameEnergyHistory.removeAll()
        lastUpdateTime = 0  // Reset dt tracking for fresh simulation
        
        evaluateNodeVisibility()
    }


    
    private func applyIdleFloatingAnimation() {
        // No-op: floating animation removed to prevent any drift after settling
    }

    // computeQuadrantForces() removed — was dead code with stale hardcoded anchorRadius

    // MARK: - Path Logic
    
    /// Calculates a curved path (Bézier) from one point to another, 
    /// attempting to avoid other nodes in the process.
    private func calculateCurvedPath(from start: CGPoint, to end: CGPoint, avoiding personIDs: Set<UUID>) -> CGPath {
        let midX = (start.x + end.x) / 2
        let midY = (start.y + end.y) / 2
        var controlPoint = CGPoint(x: midX, y: midY)
        
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = max(hypot(dx, dy), 1.0)
        
        // Perpendicular vector for offset
        let perpX = -dy / distance
        let perpY = dx / distance
        
        // Find nodes that might be in the way
        // Line segment is from start to end. Nodes within a certain distance of this segment push the mid-point.
        var totalOffset: CGFloat = 0
        let avoidanceRadius: CGFloat = 80.0
        
        for (id, node) in personNodes {
            guard !personIDs.contains(id) else { continue }
            
            // Distance from node to line segment
            let nodePos = node.position
            let t = max(0, min(1, ((nodePos.x - start.x) * dx + (nodePos.y - start.y) * dy) / (distance * distance)))
            let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
            let distToLine = hypot(nodePos.x - projection.x, nodePos.y - projection.y)
            
            if distToLine < avoidanceRadius {
                // Node is close to the line. Calculate repulsion.
                // Which side of the line is the node on?
                let crossProduct = (end.x - start.x) * (nodePos.y - start.y) - (end.y - start.y) * (nodePos.x - start.x)
                let side: CGFloat = crossProduct >= 0 ? 1 : -1
                
                // Repel the curve to the opposite side
                let force = (avoidanceRadius - distToLine) * 1.5
                totalOffset -= side * force
            }
        }
        
        // Add a base organic curve even if no nodes are in the way
        let baseCurvature: CGFloat = 15.0
        totalOffset += (totalOffset == 0) ? baseCurvature : 0
        
        // Cap the offset to avoid extreme loops
        let maxOffset = distance * 0.4
        totalOffset = max(-maxOffset, min(maxOffset, totalOffset))
        
        controlPoint.x += perpX * totalOffset
        controlPoint.y += perpY * totalOffset
        
        let path = CGMutablePath()
        path.move(to: start)
        path.addQuadCurve(to: end, control: controlPoint)
        return path
    }



    // MARK: - Update Loop (Custom Deterministic FDG Simulation)

    override func update(_ currentTime: TimeInterval) {
        // ── dt clamping: prevent lag-spike explosions ──
        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
            return  // Skip the first frame (no valid dt yet)
        }
        let dt = min(currentTime - lastUpdateTime, maxDeltaTime)
        lastUpdateTime = currentTime

        let nodesArray = Array(personNodes.values)

        // ── Pond metrics (computed first so pond forces can use them) ──
        var allMetrics: [PondMetrics] = []
        for info in pondInfos {
            let memberNodes = info.memberIDs.compactMap { personNodes[$0] }
            guard !memberNodes.isEmpty else {
                pondLabels[info.circleName]?.isHidden = true
                pondClouds[info.circleName]?.isHidden = true
                continue
            }

            var cx: CGFloat = 0, cy: CGFloat = 0
            for node in memberNodes { cx += node.position.x; cy += node.position.y }
            cx /= CGFloat(memberNodes.count)
            cy /= CGFloat(memberNodes.count)

            var maxDist: CGFloat = 0
            for node in memberNodes {
                let d = hypot(node.position.x - cx, node.position.y - cy)
                if d > maxDist { maxDist = d }
            }
            let pondRadius = memberNodes.count == 1 ? CGFloat(55) : maxDist + 60

            allMetrics.append(PondMetrics(name: info.circleName, center: CGPoint(x: cx, y: cy), radius: pondRadius, memberIDs: info.memberIDs))
        }
        currentPondMetrics = allMetrics

        // ── Simplified 2-force physics: spring-to-target + Coulomb repulsion ──
        // Each node has a pre-computed targetPosition (set in updateNodesAndEdges).
        // Force 1: Spring pulling toward that target for guaranteed convergence.
        // Force 2: Coulomb repulsion to prevent overlap.
        if !physicsSettled {
            let kRepulsion: CGFloat = 3000.0
            let kTarget: CGFloat = 0.20
            let maxSpeed: CGFloat = 200.0
            let damping: CGFloat = 0.90

            let substeps = 3
            let subDt = dt / Double(substeps)

            for _ in 0..<substeps {
                for i in 0..<nodesArray.count {
                    let nodeA = nodesArray[i]
                    guard let bodyA = nodeA.physicsBody, bodyA.isDynamic else { continue }

                    var forceX: CGFloat = 0
                    var forceY: CGFloat = 0

                    // Force 1: Spring to target position
                    let tdx = nodeA.targetPosition.x - nodeA.position.x
                    let tdy = nodeA.targetPosition.y - nodeA.position.y
                    forceX += tdx * kTarget
                    forceY += tdy * kTarget

                    // Force 2: Coulomb repulsion from all other nodes
                    let maxRepulsionDist: CGFloat = 200.0
                    for j in 0..<nodesArray.count where i != j {
                        let nodeB = nodesArray[j]
                        let dx = nodeA.position.x - nodeB.position.x
                        let dy = nodeA.position.y - nodeB.position.y
                        let distSq = max(dx * dx + dy * dy, 1.0)
                        let dist = sqrt(distSq)
                        let falloff = max(0, 1.0 - dist / maxRepulsionDist)
                        let force = (kRepulsion / distSq) * falloff * falloff

                        forceX += (dx / dist) * force
                        forceY += (dy / dist) * force
                    }

                    // Integrate velocity
                    var vx = (bodyA.velocity.dx + forceX * CGFloat(subDt)) * damping
                    var vy = (bodyA.velocity.dy + forceY * CGFloat(subDt)) * damping

                    let speed = hypot(vx, vy)
                    if speed > maxSpeed {
                        vx = vx / speed * maxSpeed
                        vy = vy / speed * maxSpeed
                    }

                    bodyA.velocity = CGVector(dx: vx, dy: vy)
                }

                // Apply velocities
                for node in nodesArray {
                    guard let body = node.physicsBody, body.isDynamic else { continue }
                    node.position.x += body.velocity.dx * CGFloat(subDt)
                    node.position.y += body.velocity.dy * CGFloat(subDt)
                }
            }
        }

        // ── Update edge line paths ──
        for (edgeKey, edgeNode) in edgeNodes {
            let ids = edgeKey.split(separator: "_")
            guard ids.count == 2,
                  let uuidA = UUID(uuidString: String(ids[0])),
                  let uuidB = UUID(uuidString: String(ids[1])),
                  let nodeA = personNodes[uuidA],
                  let nodeB = personNodes[uuidB] else { continue }

            edgeNode.path = calculateCurvedPath(from: nodeA.position, to: nodeB.position, avoiding: [uuidA, uuidB])
        }

        // ── Update pond labels & cloud backgrounds (position at cluster centroid) ──
        for metric in allMetrics {
            if let label = pondLabels[metric.name] {
                label.position = CGPoint(x: metric.center.x, y: metric.center.y - metric.radius - 16)
                label.isHidden = false
            }
            
            // Update cloud shape: move to centroid, only rebuild path when radius changes significantly
            if let cloud = pondClouds[metric.name] {
                cloud.position = metric.center
                cloud.isHidden = false
                
                let cachedR = pondCloudCachedRadius[metric.name] ?? 0
                let cloudPadding: CGFloat = 30
                let targetRadius = metric.radius + cloudPadding
                
                // Only rebuild the path if radius changed by more than 8pt (avoids per-frame alloc)
                if abs(targetRadius - cachedR) > 8 {
                    cloud.path = CGPath(ellipseIn: CGRect(
                        x: -targetRadius, y: -targetRadius,
                        width: targetRadius * 2, height: targetRadius * 2
                    ), transform: nil)
                    pondCloudCachedRadius[metric.name] = targetRadius
                }
            }
        }

        // ── Viewport culling ──
        guard let cam = camera else { return }
        let halfW = size.width / (2.0 * currentZoom) + 200
        let halfH = size.height / (2.0 * currentZoom) + 200
        let visibleRect = CGRect(
            x: cam.position.x - halfW,
            y: cam.position.y - halfH,
            width: halfW * 2,
            height: halfH * 2
        )

        for (_, node) in personNodes {
            let pos = node.position
            if pos.x.isFinite && pos.y.isFinite {
                node.isHidden = !visibleRect.contains(pos)
            }
        }
    }

    // MARK: - Energy-Based Physics Settling
    // FIX 2 — Replace the blind DispatchQueue timer.
    // This method is called by SpriteKit every frame AFTER simulation completes,
    // so it is the only safe chokepoint to freeze/wake the world without race conditions.
    override func didSimulatePhysics() {
        guard !physicsSettled else { return }
        
        // Sum total manhattan-velocity across all dynamic bodies
        var totalVelocity: CGFloat = 0
        var dynamicNodeCount: Int = 0
        for node in personNodes.values {
            guard let body = node.physicsBody, body.isDynamic else { continue }
            totalVelocity += abs(body.velocity.dx) + abs(body.velocity.dy)
            dynamicNodeCount += 1
        }
        
        // Use average per-node velocity so threshold doesn't scale with node count
        let perNodeVelocity = dynamicNodeCount > 0 ? totalVelocity / CGFloat(dynamicNodeCount) : 0
        
        // Maintain a rolling window to avoid triggering on a single quiet frame
        frameEnergyHistory.append(perNodeVelocity)
        if frameEnergyHistory.count > energyHistoryWindowSize {
            frameEnergyHistory.removeFirst()
        }
        
        // Only settle when the rolling average is below the threshold
        let averageVelocity = frameEnergyHistory.reduce(0, +) / CGFloat(max(frameEnergyHistory.count, 1))
        
        if frameEnergyHistory.count == energyHistoryWindowSize && averageVelocity < 4.0 {
            // Fully freeze: zero out all velocities so nothing drifts
            for node in personNodes.values {
                node.physicsBody?.velocity = .zero
                node.removeAction(forKey: "floating")
            }
            physicsWorld.speed = 0.0
            physicsSettled = true
            frameEnergyHistory.removeAll()
        }
    }

    // MARK: - LOD

    private func updateLOD() {
        for (_, node) in personNodes {
            if currentZoom < 0.3 {
                node.showDotOnly()
            } else if currentZoom < 0.5 {
                node.hideLabel()
            } else {
                node.showFull()
            }
        }
    }

    // MARK: - Selection

    private func highlightNode(_ id: UUID?) {
        if let prevID = selectedNodeID, let prevNode = personNodes[prevID] {
            prevNode.setSelected(false)
        }
        selectedNodeID = id
        if let id = id, let node = personNodes[id] {
            node.setSelected(true)
        }
    }
    
    // MARK: - Search Filtering
    
    private func evaluateNodeVisibility(animated: Bool = true) {
        let duration: TimeInterval = animated ? 0.3 : 0.0
        let isSearchActive = activeSearchIDs != nil
        let isSoloActive = soloedPondName != nil
        
        let soloedPondInfo = soloedPondName.flatMap { name in pondInfos.first { $0.circleName == name } }
        let soloedNodeIDs = Set(soloedPondInfo?.memberIDs ?? [])
        
        for (id, node) in personNodes {
            var alpha: CGFloat = 1.0
            var popToFront = false
            
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
                    // keep alpha
                } else {
                    alpha = min(alpha, 0.15)
                }
            }
            
            let action = SKAction.fadeAlpha(to: alpha, duration: duration)
            action.timingMode = .easeInEaseOut
            node.run(action)
            node.zPosition = popToFront ? 5 : 0
        }
        
        for (_, edge) in edgeNodes {
            var targetEdgeAlpha: CGFloat = 0.6
            
            let id1 = edge.userData?["id1"] as? UUID
            let id2 = edge.userData?["id2"] as? UUID
            
            if isSearchActive {
                if let s1 = id1, let s2 = id2, let searches = activeSearchIDs {
                    if searches.contains(s1) || searches.contains(s2) {
                        targetEdgeAlpha = 0.3
                    } else {
                        targetEdgeAlpha = 0.05
                    }
                } else {
                    targetEdgeAlpha = 0.05
                }
            } else if isSoloActive {
                if let s1 = id1, let s2 = id2 {
                    let n1Visible = soloedNodeIDs.contains(s1) || personNodes[s1]?.isMe == true
                    let n2Visible = soloedNodeIDs.contains(s2) || personNodes[s2]?.isMe == true
                    
                    if n1Visible && n2Visible {
                        targetEdgeAlpha = 0.6
                    } else if n1Visible || n2Visible {
                        targetEdgeAlpha = 0.15
                    } else {
                        targetEdgeAlpha = 0.05
                    }
                } else {
                    targetEdgeAlpha = 0.05
                }
            }
            
            let action = SKAction.fadeAlpha(to: targetEdgeAlpha, duration: duration)
            action.timingMode = .easeInEaseOut
            edge.run(action)
        }
        
        
        for (name, label) in pondLabels {
            let isThisSolo = (name == soloedPondName)
            let labelAlpha: CGFloat = isSearchActive ? 0.1 : (isSoloActive ? (isThisSolo ? 1.0 : 0.1) : 1.0)
            let action = SKAction.fadeAlpha(to: labelAlpha, duration: duration)
            action.timingMode = .easeInEaseOut
            label.run(action)
        }
        
        // Clouds follow the same dimming logic as labels
        for (name, cloud) in pondClouds {
            let isThisSolo = (name == soloedPondName)
            let cloudAlpha: CGFloat = isSearchActive ? 0.03 : (isSoloActive ? (isThisSolo ? 0.9 : 0.05) : 0.9)
            let action = SKAction.fadeAlpha(to: cloudAlpha, duration: duration)
            action.timingMode = .easeInEaseOut
            cloud.run(action)
        }
    }

    // MARK: - Touches (Drag nodes + Tap to select + 1-finger camera pan)

    private var draggedNode: ScenePersonNode?
    private var dragStartLocation: CGPoint = .zero
    private var lastTouchLocation: CGPoint = .zero
    private var touchHasMoved = false
    private var hoverPondName: String? = nil
    // private var longPressTimer: Timer? = nil // Removed manual timer logic
    
    // Pond dragging state
    private var draggedPondName: String?
    private var draggedPondMemberNodes: [ScenePersonNode] = []

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        guard let view = self.view else { return }
        let location = touch.location(in: contentNode)
        dragStartLocation = location
        lastTouchLocation = touch.location(in: view)
        touchHasMoved = false

        // Check if we tapped a node (zoom-aware radius, nearest visible match)
        let hitRadius = max(35, 30 / currentZoom)
        var nearestNode: ScenePersonNode?
        var nearestDistance: CGFloat = .greatestFiniteMagnitude
        for (_, node) in personNodes {
            guard !node.isHidden, node.alpha >= 0.3 else { continue }
            let distance = hypot(location.x - node.position.x, location.y - node.position.y)
            if distance < hitRadius && distance < nearestDistance {
                nearestDistance = distance
                nearestNode = node
            }
        }
        if let node = nearestNode {
            draggedNode = node
            node.physicsBody?.isDynamic = false
            node.physicsBody?.categoryBitMask = 0  // Disable category to stop pushing others away
            node.physicsBody?.collisionBitMask = 0 // Disable collision while dragging
            node.removeAction(forKey: "floating")

            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

            if physicsSettled {
                physicsWorld.speed = 1.0
            }

            let scaleUp = SKAction.scale(to: 1.2, duration: 0.15)
            scaleUp.timingMode = .easeOut
            node.run(scaleUp)

            return
        }
        
        // No node hit — check if touch is inside a pond cloud (pick smallest pond for precision)
        var bestPondName: String? = nil
        var bestPondRadius: CGFloat = .greatestFiniteMagnitude
        for metric in currentPondMetrics {
            let dist = hypot(location.x - metric.center.x, location.y - metric.center.y)
            if dist < metric.radius && metric.radius < bestPondRadius {
                bestPondName = metric.name
                bestPondRadius = metric.radius
            }
        }
        if let pondName = bestPondName {
            draggedPondName = pondName
            draggedPondMemberNodes = currentPondMetrics
                .first(where: { $0.name == pondName })?
                .memberIDs
                .compactMap { personNodes[$0] } ?? []
            for member in draggedPondMemberNodes {
                member.physicsBody?.isDynamic = false
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if physicsSettled { physicsWorld.speed = 1.0 }
            return
        }
        
        draggedNode = nil
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        
        // Pond dragging: translate all members by delta
        if draggedPondName != nil {
            let location = touch.location(in: contentNode)
            let dx = location.x - dragStartLocation.x
            let dy = location.y - dragStartLocation.y
            for member in draggedPondMemberNodes {
                member.position.x += dx
                member.position.y += dy
                member.targetPosition.x += dx
                member.targetPosition.y += dy
            }
            dragStartLocation = location
            touchHasMoved = true
            return
        }

        if let node = draggedNode {
            // Dragging a node - add Y offset so node is visible above finger
            let location = touch.location(in: contentNode)
            let movedDistance = hypot(location.x - dragStartLocation.x, location.y - dragStartLocation.y)
            if movedDistance > 8 { 
                touchHasMoved = true 
            }
            
            // Fat finger offset: apply +40 to Y only if we've moved
            let targetY = touchHasMoved ? location.y + 40 : location.y
            node.position = CGPoint(x: location.x, y: targetY)

            // Snap detection: find closest other node
            var closestDist: CGFloat = snapDistance
            var closestID: UUID?
            for (id, otherNode) in personNodes {
                guard id != node.personID else { continue }
                let d = hypot(location.x - otherNode.position.x, location.y - otherNode.position.y)
                if d < closestDist {
                    closestDist = d
                    closestID = id
                }
            }

            let previousSnapTargetID = snapTargetID
            if let prevTargetID = snapTargetID, prevTargetID != closestID {
                personNodes[prevTargetID]?.setHoverGlow(false)
            }
            snapTargetID = closestID
            if let targetID = closestID, let targetNode = personNodes[targetID] {
                if previousSnapTargetID != targetID {
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                targetNode.setHoverGlow(true)

                // Show dashed preview line
                let curvedPath = calculateCurvedPath(from: node.position, to: targetNode.position, avoiding: [node.personID, targetID])
                
                // Create a dashed pattern
                let pattern: [CGFloat] = [6, 4]
                snapPreviewLine?.path = curvedPath.copy(dashingWithPhase: 0, lengths: pattern)
                snapPreviewLine?.isHidden = false
                
                if hoverPondName != nil {
                    hoverPondName = nil
                }
            } else {
                snapPreviewLine?.isHidden = true
                snapPreviewLine?.path = nil
                
                // ME node should never show pond hover feedback
                if !(draggedNode?.isMe ?? false) {
                    // We are not snapping to a node. Are we inside a pond?
                    var foundPondName: String? = nil
                    for metric in currentPondMetrics {
                        // FIX: Only hover if the node is NOT already in this pond
                        if !metric.memberIDs.contains(node.personID) {
                            let dist = hypot(node.position.x - metric.center.x, node.position.y - metric.center.y)
                            if dist <= metric.radius {
                                foundPondName = metric.name
                                break
                            }
                        }
                    }
                    
                    hoverPondName = foundPondName
                }
            }
        } else {
            // 1-finger camera pan (no node grabbed)
            guard let view = self.view else { return }
            let screenLocation = touch.location(in: view)
            let dx = -(screenLocation.x - lastTouchLocation.x) / currentZoom
            let dy = (screenLocation.y - lastTouchLocation.y) / currentZoom
            cameraNode.position = CGPoint(
                x: cameraNode.position.x + dx,
                y: cameraNode.position.y + dy
            )
            lastTouchLocation = screenLocation
            let movedPx = hypot(screenLocation.x - lastTouchLocation.x, screenLocation.y - lastTouchLocation.y)
            if movedPx > 8 { touchHasMoved = true }
            touchHasMoved = true  // Any move counts as a camera pan
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        // longPressTimer?.invalidate()
        // longPressTimer = nil
        
        // Release pond drag if active
        if draggedPondName != nil {
            for member in draggedPondMemberNodes {
                member.physicsBody?.isDynamic = !member.isMe
                member.physicsBody?.velocity = .zero
            }
            draggedPondName = nil
            draggedPondMemberNodes = []
            touchHasMoved = false
            if physicsSettled {
                physicsWorld.speed = 1.0
                physicsSettled = false
                frameEnergyHistory.removeAll()
            }
            return
        }
        
        guard let touch = touches.first, let node = draggedNode else { return }
        
        let scaleDown = SKAction.scale(to: 1.0, duration: 0.15)
        scaleDown.timingMode = .easeIn
        node.run(scaleDown)
        
        node.physicsBody?.isDynamic = !node.isMe
        node.physicsBody?.categoryBitMask = 1  // Re-enable category
        node.physicsBody?.collisionBitMask = 0 // Keep collision disabled
        node.physicsBody?.velocity = .zero
        if physicsSettled {
            applyIdleFloatingAnimation() // restart floating
        }

        // Persist the manual reposition so settling physics doesn't pull the node back
        if touchHasMoved {
            node.targetPosition = node.position
        }

        // Check for snap-to-connect or pond move
        if touchHasMoved {
            if let targetID = snapTargetID {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                graphDelegate?.requestConnection(from: node.personID, to: targetID)
            } else if let pondName = hoverPondName, !node.isMe {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                graphDelegate?.requestPondMove(for: node.personID, to: pondName)
            }
        } else if !touchHasMoved {
            if touch.tapCount == 2 {
                graphDelegate?.selectContact(node.personID)
            } else {
                highlightNode(node.personID)
            }
        }

        // Clean up preview
        if let targetID = snapTargetID { personNodes[targetID]?.setHoverGlow(false) }
        hoverPondName = nil
        snapPreviewLine?.isHidden = true
        snapPreviewLine?.path = nil
        snapTargetID = nil
        draggedNode = nil
        touchHasMoved = false
        
        if physicsSettled {
            physicsWorld.speed = 1.0
            physicsSettled = false
            frameEnergyHistory.removeAll()
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // longPressTimer?.invalidate()
        // longPressTimer = nil
        
        // Release pond drag if active
        if draggedPondName != nil {
            for member in draggedPondMemberNodes {
                member.physicsBody?.isDynamic = !member.isMe
            }
            draggedPondName = nil
            draggedPondMemberNodes = []
            touchHasMoved = false
            return
        }
        
        guard let node = draggedNode else { return }
        node.physicsBody?.isDynamic = !node.isMe
        node.physicsBody?.categoryBitMask = 1  // Re-enable category
        node.physicsBody?.collisionBitMask = 0 // Keep collision disabled
        // Persist the manual reposition so settling physics doesn't pull the node back
        if touchHasMoved {
            node.targetPosition = node.position
        }
        if let targetID = snapTargetID { personNodes[targetID]?.setHoverGlow(false) }
        hoverPondName = nil
        snapPreviewLine?.isHidden = true
        snapPreviewLine?.path = nil
        snapTargetID = nil
        draggedNode = nil
        touchHasMoved = false
        
        if physicsSettled {
            physicsWorld.speed = 1.0
            physicsSettled = false
            frameEnergyHistory.removeAll()
        }
    }

    // MARK: - Gesture Handlers

    @objc private func handlePinch(_ sender: UIPinchGestureRecognizer) {
        guard self.view != nil else { return }
        
        switch sender.state {
        case .began:
            lastPinchScale = sender.scale
        case .changed:
            let delta = sender.scale / lastPinchScale
            let newZoom = currentZoom * delta
            
            // Clamp magnification
            if newZoom >= 0.1 && newZoom <= 4.0 {
                currentZoom = newZoom
                cameraNode.setScale(1.0 / currentZoom)
            }
            lastPinchScale = sender.scale
            updateLOD()
            
            // P0-6 Fix: Ensure ViewModel knows the exact zoom so +/- buttons calculate correctly
            graphDelegate?.updateCameraFromScene(position: cameraNode.position, zoom: currentZoom)
            
        case .ended:
            graphDelegate?.updateCameraFromScene(position: cameraNode.position, zoom: currentZoom)
        default:
            break
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view = self.view else { return }
        let translation = gesture.translation(in: view)

        switch gesture.state {
        case .changed:
            let dx = -translation.x / currentZoom
            let dy = translation.y / currentZoom
            cameraNode.position = CGPoint(
                x: cameraNode.position.x + dx,
                y: cameraNode.position.y + dy
            )
            gesture.setTranslation(.zero, in: view)
        case .ended:
            graphDelegate?.updateCameraFromScene(position: cameraNode.position, zoom: currentZoom)
        default:
            break
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard let view = self.view else { return }
        let screenLocation = gesture.location(in: view)
        let location = convertPoint(fromView: screenLocation)
        
        // Did we tap in a pond?
        var tappedPondName: String? = nil
        for metric in currentPondMetrics {
            let dist = hypot(location.x - metric.center.x, location.y - metric.center.y)
            if dist <= metric.radius {
                tappedPondName = metric.name
                break
            }
        }
        
        if let pondName = tappedPondName {
            soloPond(name: pondName)
        } else {
            unsoloAll()
            currentZoom = 1.0
            let moveAction = SKAction.move(to: .zero, duration: 0.3)
            let scaleAction = SKAction.scale(to: 1.0, duration: 0.3)
            moveAction.timingMode = .easeInEaseOut
            scaleAction.timingMode = .easeInEaseOut
            cameraNode.run(moveAction, withKey: "cameraMove")
            cameraNode.run(scaleAction, withKey: "cameraScale")
            updateLOD()
            graphDelegate?.updateCameraFromScene(position: .zero, zoom: 1.0)
        }
    }
    
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let view = self.view else { return }
        let screenLocation = gesture.location(in: view)
        let sceneLocation = convertPoint(fromView: screenLocation)
        let contentLocation = contentNode.convert(sceneLocation, from: self)
        
        // Check if we long-pressed a node (zoom-aware radius, nearest visible match)
        let hitRadius = max(35, 30 / currentZoom)
        var nearestID: UUID?
        var nearestDistance: CGFloat = .greatestFiniteMagnitude
        for (id, node) in personNodes {
            guard !node.isHidden, node.alpha >= 0.3 else { continue }
            let distance = hypot(contentLocation.x - node.position.x, contentLocation.y - node.position.y)
            if distance < hitRadius && distance < nearestDistance {
                nearestDistance = distance
                nearestID = id
            }
        }
        if let id = nearestID {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task { @MainActor in
                graphDelegate?.didLongPressContact(id)
            }
            highlightNode(id)

            // cancel drag if active
            if draggedNode?.personID == id {
                touchesCancelled(Set(), with: nil)
            }
        }
    }

    private func soloPond(name: String) {
        if soloedPondName == name {
            unsoloAll()
            return
        }
        soloedPondName = name
        evaluateNodeVisibility()
        
        // Zoom to centroid of pond
        let info = pondInfos.first { $0.circleName == name }
        guard let pInfo = info else { return }
        let memberNodes = pInfo.memberIDs.compactMap { personNodes[$0] }
        guard !memberNodes.isEmpty else { return }
        
        var cx: CGFloat = 0, cy: CGFloat = 0
        for node in memberNodes { cx += node.position.x; cy += node.position.y }
        cx /= CGFloat(memberNodes.count)
        cy /= CGFloat(memberNodes.count)
        
        let moveAction = SKAction.move(to: CGPoint(x: cx, y: cy), duration: 0.4)
        moveAction.timingMode = .easeInEaseOut
        cameraNode.run(moveAction, withKey: "cameraMove")
    }

    private func unsoloAll() {
        soloedPondName = nil
        evaluateNodeVisibility()
    }
}

// MARK: - ScenePersonNode
/// A composite SKNode representing a single person in the graph.
final class ScenePersonNode: SKNode {

    let personID: UUID
    let isMe: Bool
    private(set) var currentDepth: Int
    /// Pre-computed geometric target position for the simplified spring-to-target physics.
    var targetPosition: CGPoint = .zero
    private var meAmbientGlow: SKShapeNode?
    private let circleShape: SKShapeNode
    private var initialsLabel: SKLabelNode
    private let nameLabel: SKLabelNode
    private let glowNode: SKShapeNode
    private let hoverGlowNode: SKShapeNode
    private let starLabel: SKLabelNode?
    private let unassignedLabel: SKLabelNode
    private let dotNode: SKShapeNode
    private var cropNode: SKCropNode?
    /// Tracks whether this node currently shows a photo (for change detection in update).
    private var hasPhoto: Bool = false

    private var lodState: LODState = .full
    private enum LODState { case full, noLabel, dotOnly }

    init(person: Person, depth: Int) {
        self.personID = person.id
        self.isMe = person.isMe
        self.currentDepth = depth

        // ME node is physically larger, secondary contacts are smaller
        let radius: CGFloat = person.isMe ? 28 : (depth > 1 ? 16 : 22)

        // Circle shape (ring)
        // Always create unassignedLabel
        let uLabel = SKLabelNode(text: "unassigned")
        uLabel.fontName = "SFProText-Italic"
        uLabel.fontSize = 9
        uLabel.fontColor = UIColor.secondaryLabel
        uLabel.verticalAlignmentMode = .top
        uLabel.horizontalAlignmentMode = .center
        uLabel.position = CGPoint(x: 0, y: -(radius + 26))
        uLabel.zPosition = 2
        uLabel.isHidden = true
        unassignedLabel = uLabel
        
        circleShape = SKShapeNode(circleOfRadius: radius)
        circleShape.zPosition = 1

        // Photo or initials fallback
        if let data = person.photoData, let image = UIImage(data: data) {
            let texture = SKTexture(image: image)
            let photoSprite = SKSpriteNode(texture: texture, size: CGSize(width: radius * 2, height: radius * 2))

            let crop = SKCropNode()
            let maskShape = SKShapeNode(circleOfRadius: radius - 1)
            maskShape.fillColor = .white
            crop.maskNode = maskShape
            crop.addChild(photoSprite)
            crop.zPosition = 1

            circleShape.fillColor = .clear
            initialsLabel = SKLabelNode()

            cropNode = crop
        } else {
            if person.isMe {
                // ME node gets a warm amber/gold fill
                circleShape.fillColor = UIColor(red: 232/255, green: 162/255, blue: 56/255, alpha: 1.0)
            } else {
                var hash = 0
                for char in person.name {
                    hash = (hash &* 31) &+ Int(char.asciiValue ?? 0)
                }
                hash = abs(hash)
                let hue = CGFloat(hash % 360) / 360.0
                circleShape.fillColor = UIColor(hue: hue, saturation: 0.4, brightness: 0.85, alpha: 1.0)
            }

            initialsLabel = SKLabelNode(text: person.initials)
            initialsLabel.fontName = person.isMe ? "SFProRounded-Bold" : "SFProRounded-Semibold"
            initialsLabel.fontSize = radius * (person.isMe ? 0.65 : 0.75)
            initialsLabel.fontColor = .white
            initialsLabel.verticalAlignmentMode = .center
            initialsLabel.horizontalAlignmentMode = .center
            initialsLabel.zPosition = 2

            cropNode = nil
        }

        // Track initial photo state for change detection in update(with:)
        hasPhoto = (person.photoData != nil)

        // Name label — ME gets bold, slightly larger font
        nameLabel = SKLabelNode(text: person.name)
        nameLabel.fontName = person.isMe ? "SFProText-Semibold" : "SFProText-Regular"
        nameLabel.fontSize = person.isMe ? 12 : 11
        nameLabel.fontColor = UIColor.label
        nameLabel.verticalAlignmentMode = .top
        nameLabel.horizontalAlignmentMode = .center
        nameLabel.position = CGPoint(x: 0, y: -(radius + 12))
        nameLabel.zPosition = 2

        // Selection glow
        glowNode = SKShapeNode(circleOfRadius: radius + 6)
        glowNode.strokeColor = UIColor(red: 183/255, green: 79/255, blue: 58/255, alpha: 0.35)
        glowNode.lineWidth = 4
        glowNode.fillColor = .clear
        glowNode.isHidden = true
        glowNode.zPosition = -1
        
        // Hover drag glow
        hoverGlowNode = SKShapeNode(circleOfRadius: radius + 4)
        hoverGlowNode.strokeColor = UIColor.white.withAlphaComponent(0.8)
        hoverGlowNode.lineWidth = 3
        hoverGlowNode.fillColor = .clear
        hoverGlowNode.isHidden = true
        hoverGlowNode.zPosition = -1

        // Favorite star
        if person.isFavorite {
            starLabel = SKLabelNode(text: "★")
            starLabel?.fontSize = 12
            starLabel?.fontColor = UIColor.systemYellow
            starLabel?.position = CGPoint(x: radius * 0.7, y: radius * 0.5)
            starLabel?.zPosition = 3
        } else {
            starLabel = nil
        }

        // Dot for extreme zoom-out — ME dot is larger
        dotNode = SKShapeNode(circleOfRadius: person.isMe ? 6 : 4)
        dotNode.fillColor = circleShape.fillColor != .clear ? circleShape.fillColor : circleShape.strokeColor
        dotNode.strokeColor = .clear
        dotNode.isHidden = true

        super.init()

        self.name = person.id.uuidString

        // ME ambient glow — a warm halo behind the node
        if person.isMe {
            let ambientGlow = SKShapeNode(circleOfRadius: radius + 10)
            ambientGlow.fillColor = UIColor(red: 232/255, green: 162/255, blue: 56/255, alpha: 0.12)
            ambientGlow.strokeColor = UIColor(red: 232/255, green: 162/255, blue: 56/255, alpha: 0.25)
            ambientGlow.lineWidth = 2
            ambientGlow.glowWidth = 6
            ambientGlow.zPosition = -2
            meAmbientGlow = ambientGlow
            addChild(ambientGlow)
            
            // Subtle breathing pulse on the glow
            let pulseUp = SKAction.group([
                SKAction.fadeAlpha(to: 1.0, duration: 2.0),
                SKAction.scale(to: 1.08, duration: 2.0)
            ])
            pulseUp.timingMode = .easeInEaseOut
            let pulseDown = SKAction.group([
                SKAction.fadeAlpha(to: 0.6, duration: 2.0),
                SKAction.scale(to: 1.0, duration: 2.0)
            ])
            pulseDown.timingMode = .easeInEaseOut
            ambientGlow.run(SKAction.repeatForever(SKAction.sequence([pulseUp, pulseDown])), withKey: "mePulse")
        }

        addChild(glowNode)
        addChild(hoverGlowNode)
        addChild(circleShape)
        if let crop = cropNode {
            addChild(crop)
        } else {
            addChild(initialsLabel)
        }
        addChild(nameLabel)
        if let star = starLabel { addChild(star) }
        addChild(unassignedLabel)
        addChild(dotNode)
        
        // Apply initial styling
        update(with: person, depth: depth)
    }

    // MARK: - Update

    func update(with person: Person, depth: Int) {
        let previousRadius: CGFloat = isMe ? 28 : (self.currentDepth > 1 ? 16 : 22)
        self.currentDepth = depth
        let radius: CGFloat = isMe ? 28 : (depth > 1 ? 16 : 22)
        let activeCircles = person.circleContacts.filter { !$0.manuallyExcluded }
        let hasCircle = !activeCircles.isEmpty
        let isAssigned = hasCircle || !person.isOrphan

        // ── Dynamic photo swap ──
        let nowHasPhoto = person.photoData != nil
        if nowHasPhoto != hasPhoto {
            if nowHasPhoto, let data = person.photoData, let image = UIImage(data: data) {
                // Photo was added — create cropNode, hide initials
                let texture = SKTexture(image: image)
                let photoSprite = SKSpriteNode(texture: texture, size: CGSize(width: radius * 2, height: radius * 2))
                let crop = SKCropNode()
                let maskShape = SKShapeNode(circleOfRadius: radius - 1)
                maskShape.fillColor = .white
                crop.maskNode = maskShape
                crop.addChild(photoSprite)
                crop.zPosition = 1
                cropNode?.removeFromParent()
                addChild(crop)
                cropNode = crop
                initialsLabel.isHidden = true
                circleShape.fillColor = .clear
            } else {
                // Photo was removed — restore initials
                cropNode?.removeFromParent()
                cropNode = nil
                initialsLabel.text = person.initials
                initialsLabel.isHidden = false
                if isMe {
                    circleShape.fillColor = UIColor(red: 232/255, green: 162/255, blue: 56/255, alpha: 1.0)
                } else {
                    var hash = 0
                    for char in person.name {
                        hash = (hash &* 31) &+ Int(char.asciiValue ?? 0)
                    }
                    hash = abs(hash)
                    let hue = CGFloat(hash % 360) / 360.0
                    circleShape.fillColor = UIColor(hue: hue, saturation: 0.4, brightness: 0.85, alpha: 1.0)
                }
            }
            hasPhoto = nowHasPhoto
        }

        // Reset path to standard circle
        let path = CGMutablePath()
        path.addArc(center: .zero, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: true)

        if isMe {
            circleShape.path = path
            // Warm golden-amber ring for ME
            circleShape.strokeColor = UIColor(red: 232/255, green: 162/255, blue: 56/255, alpha: 1.0)
            circleShape.lineWidth = 3.5
            circleShape.glowWidth = 4
            unassignedLabel.isHidden = true
        } else if isAssigned {
            circleShape.path = path
            let circleColorHex = activeCircles.first?.circle.color
            circleShape.strokeColor = circleColorHex.flatMap { GoldfishUIColor(hex: $0) } ?? UIColor.systemGray3
            circleShape.lineWidth = 2.5
            unassignedLabel.isHidden = true
        } else {
            let dashedPath = path.copy(dashingWithPhase: 0, lengths: [4, 4])
            circleShape.path = dashedPath
            circleShape.strokeColor = UIColor.systemGray3
            circleShape.lineWidth = 2.0
            unassignedLabel.isHidden = (lodState != .full)
        }

        nameLabel.text = person.name
        nameLabel.position = CGPoint(x: 0, y: -(radius + 12))
        initialsLabel.fontSize = radius * (isMe ? 0.65 : 0.75)
        
        if previousRadius != radius {
            if let oldBody = self.physicsBody {
                let newBodyRadius: CGFloat = isMe ? 50 : (depth > 1 ? 34 : 40)
                let newBody = SKPhysicsBody(circleOfRadius: newBodyRadius)
                newBody.mass = oldBody.mass
                newBody.linearDamping = oldBody.linearDamping
                newBody.angularDamping = oldBody.angularDamping
                newBody.allowsRotation = oldBody.allowsRotation
                newBody.categoryBitMask = oldBody.categoryBitMask
                newBody.collisionBitMask = oldBody.collisionBitMask
                newBody.fieldBitMask = oldBody.fieldBitMask
                newBody.isDynamic = oldBody.isDynamic
                newBody.velocity = oldBody.velocity
                self.physicsBody = newBody
            }
            
            // Update other radius-dependent visual elements
            unassignedLabel.position = CGPoint(x: 0, y: -(radius + 26))
            starLabel?.position = CGPoint(x: radius * 0.7, y: radius * 0.5)
            
            let glowPath = CGMutablePath()
            glowPath.addArc(center: .zero, radius: radius + 6, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
            glowNode.path = glowPath
            
            let hoverGlowPath = CGMutablePath()
            hoverGlowPath.addArc(center: .zero, radius: radius + 4, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
            hoverGlowNode.path = hoverGlowPath
            
            if let crop = cropNode, let sprite = crop.children.first as? SKSpriteNode {
                sprite.size = CGSize(width: radius * 2, height: radius * 2)
                let newMask = SKShapeNode(circleOfRadius: radius - 1)
                newMask.fillColor = .white
                crop.maskNode = newMask
            }
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - LOD

    func showFull() {
        guard lodState != .full else { return }
        lodState = .full
        circleShape.isHidden = false
        nameLabel.isHidden = false
        
        // Only show unassignedLabel if it's currently meant to be shown (i.e. not assigned and not me)
        if circleShape.lineWidth == 2.0 && !isMe {
            unassignedLabel.isHidden = false
        }
        
        initialsLabel.isHidden = false
        cropNode?.isHidden = false
        dotNode.isHidden = true
    }

    func hideLabel() {
        guard lodState != .noLabel else { return }
        lodState = .noLabel
        circleShape.isHidden = false
        nameLabel.isHidden = true
        unassignedLabel.isHidden = true
        initialsLabel.isHidden = false
        cropNode?.isHidden = false
        dotNode.isHidden = true
    }

    func showDotOnly() {
        guard lodState != .dotOnly else { return }
        lodState = .dotOnly
        circleShape.isHidden = true
        nameLabel.isHidden = true
        unassignedLabel.isHidden = true
        initialsLabel.isHidden = true
        cropNode?.isHidden = true
        dotNode.isHidden = false
    }

    // MARK: - Selection

    func setSelected(_ selected: Bool) {
        glowNode.isHidden = !selected
        if selected {
            let pulseUp = SKAction.scale(to: 1.1, duration: 0.15)
            let pulseDown = SKAction.scale(to: 1.0, duration: 0.15)
            run(SKAction.sequence([pulseUp, pulseDown]))
        }
    }
    
    func setHoverGlow(_ hovered: Bool) {
        hoverGlowNode.isHidden = !hovered
        if hovered && hoverGlowNode.action(forKey: "pulse") == nil {
            let pulseUp = SKAction.scale(to: 1.15, duration: 0.4)
            pulseUp.timingMode = .easeInEaseOut
            let pulseDown = SKAction.scale(to: 1.0, duration: 0.4)
            pulseDown.timingMode = .easeInEaseOut
            hoverGlowNode.run(SKAction.repeatForever(SKAction.sequence([pulseUp, pulseDown])), withKey: "pulse")
        } else if !hovered {
            hoverGlowNode.removeAction(forKey: "pulse")
            hoverGlowNode.xScale = 1.0
            hoverGlowNode.yScale = 1.0
        }
    }
}


// GoldfishUIColor(hex:) lives in Views/Components/PersonNode.swift
