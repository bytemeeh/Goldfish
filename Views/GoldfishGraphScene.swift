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

    // MARK: - Content
    private let contentNode = SKNode()
    private var personNodes: [UUID: PersonNode] = [:]
    private var edgeNodes: [String: SKShapeNode] = [:]
    private var graphLevelsCache: [GraphLevel] = []

    // MARK: - Pond Outlines
    private var pondOutlines: [String: SKShapeNode] = [:]  // circleName -> outline shape
    private var pondLabels: [String: SKLabelNode] = [:]    // circleName -> label
    private struct PondInfo {
        let circleName: String
        let color: String
        let memberIDs: [UUID]
    }
    private var pondInfos: [PondInfo] = []

    private struct PondMetrics {
        let name: String
        let center: CGPoint
        let radius: CGFloat
        let memberIDs: [UUID]
    }

    // MARK: - Drag-Snap Connection
    private var snapPreviewLine: SKShapeNode?
    private var snapTargetID: UUID?
    private let snapDistance: CGFloat = 50

    // MARK: - Gesture State
    private var lastPinchScale: CGFloat = 1.0
    private var selectedNodeID: UUID?

    // MARK: - Physics Settle & Focus Mode
    private var settleTimer: Timer?
    private var physicsSettled = false
    private var soloedPondName: String? = nil
    
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

        // Weak radial gravity to keep graph centered
        let gravity = SKFieldNode.radialGravityField()
        gravity.strength = 0.1
        gravity.falloff = 0.5
        gravity.position = .zero
        contentNode.addChild(gravity)

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
        fitToNodes(allIDs, minZoom: 0.1, maxZoom: 2.0, padding: 120.0)
    }
    
    private func fitToNodes(_ ids: [UUID], minZoom: CGFloat, maxZoom: CGFloat, padding: CGFloat) {
        let nodes = ids.compactMap { personNodes[$0] }
        guard !nodes.isEmpty else { return }
        
        var minX: CGFloat = .greatestFiniteMagnitude
        var maxX: CGFloat = -.greatestFiniteMagnitude
        var minY: CGFloat = .greatestFiniteMagnitude
        var maxY: CGFloat = -.greatestFiniteMagnitude
        
        for node in nodes {
            minX = min(minX, node.position.x)
            maxX = max(maxX, node.position.x)
            minY = min(minY, node.position.y)
            maxY = max(maxY, node.position.y)
        }
        
        let width = max(maxX - minX, 100) + (padding * 2)
        let height = max(maxY - minY, 100) + (padding * 2)
        
        let cx = (minX + maxX) / 2
        let cy = (minY + maxY) / 2
        let target = CGPoint(x: cx, y: cy)
        
        let viewDimWidth = size.width
        let viewDimHeight = size.height
        guard viewDimWidth > 0 && viewDimHeight > 0 else { return }
        
        let zoomX = viewDimWidth / width
        let zoomY = viewDimHeight / height
        var targetZoom = min(zoomX, zoomY)
        
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
        guard let name = name else {
            // Restore normal appearance
            let restoreAction = SKAction.fadeAlpha(to: 1.0, duration: 0.3)
            for (_, node) in personNodes { node.run(restoreAction) }
            for (_, outline) in pondOutlines { outline.run(restoreAction) }
            for (_, edge) in edgeNodes { edge.run(SKAction.fadeAlpha(to: 0.6, duration: 0.3)) }
            return
        }
        
        // Find member IDs
        let memberIDs = pondInfos.first(where: { $0.circleName == name })?.memberIDs ?? []
        let memberSet = Set(memberIDs)
        
        let dimAction = SKAction.fadeAlpha(to: 0.15, duration: 0.3)
        let highlightAction = SKAction.fadeAlpha(to: 1.0, duration: 0.3)
        
        for (id, node) in personNodes {
            if memberSet.contains(id) || node.isMe {
                node.run(highlightAction)
            } else {
                node.run(dimAction)
            }
        }
        
        for (pondName, outline) in pondOutlines {
            outline.run(pondName == name ? highlightAction : dimAction)
        }
        
        for (key, edge) in edgeNodes {
            let parts = key.split(separator: "-")
            if parts.count == 2,
               let u1 = UUID(uuidString: String(parts[0])),
               let u2 = UUID(uuidString: String(parts[1])) {
                let p1InPond = memberSet.contains(u1)
                let p2InPond = memberSet.contains(u2)
                let p1IsMe = personNodes[u1]?.isMe == true
                let p2IsMe = personNodes[u2]?.isMe == true
                
                let isRelevant = (p1InPond && p2InPond) || (p1InPond && p2IsMe) || (p2InPond && p1IsMe)
                
                edge.run(isRelevant ? SKAction.fadeAlpha(to: 0.6, duration: 0.3) : dimAction)
            }
        }
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
        
        // 1. Visual pulse
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.15, duration: 0.1),
            SKAction.scale(to: 1.0, duration: 0.2)
        ])
        nodeA.run(pulse)
        nodeB.run(pulse)
        
        // 2. Physical "tug" impulse
        let dx = nodeB.position.x - nodeA.position.x
        let dy = nodeB.position.y - nodeA.position.y
        let distance = max(hypot(dx, dy), 1)
        let impulseMag: CGFloat = 800.0
        
        let impulseA = CGVector(dx: (dx / distance) * impulseMag, dy: (dy / distance) * impulseMag)
        let impulseB = CGVector(dx: (-dx / distance) * impulseMag, dy: (-dy / distance) * impulseMag)
        
        nodeA.physicsBody?.applyImpulse(impulseA)
        nodeB.physicsBody?.applyImpulse(impulseB)
        
        // 3. Temporarily speed up physics to settle the new connection
        physicsWorld.speed = 1.0
        physicsSettled = false
        
        settleTimer?.invalidate()
        settleTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.physicsWorld.speed = 0.0  // Fully freeze physics on settle
                self?.physicsSettled = true
                self?.applyIdleFloatingAnimation()
            }
        }
    }

    private var edgeSprings: [String: SKPhysicsJointSpring] = [:]
    private var initialFitCompleted = false

    // MARK: - Graph Building

    private func updateGraph(_ levels: [GraphLevel]) {
        updateNodesAndEdges(levels: levels)
        evaluateNodeVisibility(animated: false)

        if !initialFitCompleted {
            // Use fitToGraph after physics has had time to spread nodes out
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.fitToGraph()
                self?.initialFitCompleted = true
            }
        }
    }

    private func updateNodesAndEdges(levels: [GraphLevel]) {
        physicsSettled = false
        physicsWorld.speed = 1.0
        
        // Ensure gravity field exists
        if contentNode.childNode(withName: "gravityField") == nil {
            let gravity = SKFieldNode.radialGravityField()
            gravity.name = "gravityField"
            gravity.strength = 0.1
            gravity.falloff = 0.5
            gravity.position = .zero
            contentNode.addChild(gravity)
        }

        // 1. Identify current vs new persons
        let currentPersonIDs = Set(personNodes.keys)
        let allContacts = levels.flatMap(\.allContacts)
        let newPersonIDs = Set(allContacts.map(\.id))
        
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
            let radius = CGFloat(level.depth * 140) + max(40.0, CGFloat(count) * 18.0)

            for (index, person) in levelContacts.enumerated() {
                if let node = personNodes[person.id] {
                    // Update existing node if needed
                    node.update(with: person)
                } else {
                    // Create new node
                    let personNode = PersonNode(person: person, depth: level.depth)
                    
                    let angle = (CGFloat(index) / CGFloat(max(count, 1))) * 2 * .pi
                    // Add more random jitter to ensure they never start at exactly the same point
                    let jitterX = CGFloat.random(in: -30...30)
                    let jitterY = CGFloat.random(in: -30...30)
                    
                    // All levels (including 0) should use the radius for initial circular placement
                    let x = radius * cos(angle) + jitterX
                    let y = radius * sin(angle) + jitterY
                    
                    personNode.position = CGPoint(x: x, y: y)

                    let body = SKPhysicsBody(circleOfRadius: 70)
                    body.mass = 1.0
                    body.linearDamping = 4.0 // Increased to prevent orbital spinning
                    body.angularDamping = 2.0
                    body.isDynamic = true
                    body.allowsRotation = false
                    body.categoryBitMask = 1
                    body.collisionBitMask = 0 // Disabled physical collision to allow radial repulsion exclusively
                    body.fieldBitMask = 1
                    personNode.physicsBody = body

                    // Add a repulsion field to keep other nodes away
                    let repulsion = SKFieldNode.radialGravityField()
                    repulsion.strength = -0.6 // Stronger repulsion
                    repulsion.falloff = 1.0
                    repulsion.region = SKRegion(radius: 120)
                    personNode.addChild(repulsion)

                    contentNode.addChild(personNode)
                    personNodes[person.id] = personNode
                }
            }
        }

        // 2. Update Pond Info
        pondInfos.removeAll()
        var pondMembers: [String: (color: String, ids: Set<UUID>)] = [:]
        for (_, personNode) in personNodes {
            guard let person = allContacts.first(where: { $0.id == personNode.personID }) else { continue }
            
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

        // Update pond shapes/labels (Incremental)
        let currentPondNames = Set(pondOutlines.keys)
        let newPondNames = Set(pondMembers.keys)
        
        // Remove old ponds
        for name in currentPondNames where !newPondNames.contains(name) {
            pondOutlines[name]?.removeFromParent()
            pondOutlines.removeValue(forKey: name)
            pondLabels[name]?.removeFromParent()
            pondLabels.removeValue(forKey: name)
        }
        
        // Update or create ponds
        for (name, info) in pondMembers {
            let pondInfo = PondInfo(circleName: name, color: info.color, memberIDs: Array(info.ids))
            pondInfos.append(pondInfo)

            if pondOutlines[name] == nil {
                let outline = SKShapeNode()
                outline.strokeColor = (GoldfishUIColor(hex: info.color) ?? UIColor.systemGray3).withAlphaComponent(0.20)
                outline.fillColor = (GoldfishUIColor(hex: info.color) ?? UIColor.systemGray3).withAlphaComponent(0.08)
                outline.lineWidth = 2.0
                outline.zPosition = -2
                contentNode.addChild(outline)
                pondOutlines[name] = outline

                let label = SKLabelNode(text: name)
                label.fontName = "SFProText-Semibold"
                label.fontSize = 13
                label.fontColor = (GoldfishUIColor(hex: info.color) ?? UIColor.systemGray3).withAlphaComponent(0.85)
                label.horizontalAlignmentMode = .center
                label.verticalAlignmentMode = .bottom
                label.zPosition = -1
                
                contentNode.addChild(label)
                pondLabels[name] = label
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
        
        // Remove old edges and springs
        for edgeKey in Array(edgeNodes.keys) where !desiredEdges.contains(edgeKey) {
            edgeNodes[edgeKey]?.removeFromParent()
            edgeNodes.removeValue(forKey: edgeKey)
            if let spring = edgeSprings[edgeKey] {
                physicsWorld.remove(spring)
                edgeSprings.removeValue(forKey: edgeKey)
            }
        }
        
        // Create new edges and springs
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
                contentNode.addChild(edgeNode)
                edgeNodes[edgeKey] = edgeNode
                
                // Add spring joint
                let ids = edgeKey.split(separator: "_")
                guard ids.count == 2,
                      let uuidA = UUID(uuidString: String(ids[0])),
                      let uuidB = UUID(uuidString: String(ids[1])),
                      let nodeA = personNodes[uuidA],
                      let nodeB = personNodes[uuidB],
                      let bodyA = nodeA.physicsBody,
                      let bodyB = nodeB.physicsBody else { continue }

                let spring = SKPhysicsJointSpring.joint(
                    withBodyA: bodyA,
                    bodyB: bodyB,
                    anchorA: nodeA.position,
                    anchorB: nodeB.position
                )
                spring.frequency = 0.4
                spring.damping = 0.6
                physicsWorld.add(spring)
                edgeSprings[edgeKey] = spring
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

        // Settle logic
        physicsWorld.speed = 2.0
        physicsSettled = false
        settleTimer?.invalidate()
        settleTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.physicsWorld.speed = 0.0  // Fully freeze physics on settle
                self?.physicsSettled = true
                self?.applyIdleFloatingAnimation()
            }
        }
        
        evaluateNodeVisibility()
    }


    
    private func applyIdleFloatingAnimation() {
        for (_, node) in personNodes {
            // Subtle bob up and down
            let duration = Double.random(in: 2.0...3.0)
            let moveUp = SKAction.moveBy(x: 0, y: 4, duration: duration)
            moveUp.timingMode = .easeInEaseOut
            let moveDown = SKAction.moveBy(x: 0, y: -4, duration: duration)
            moveDown.timingMode = .easeInEaseOut
            let seq = SKAction.sequence([moveUp, moveDown])
            node.run(SKAction.repeatForever(seq), withKey: "floating")
        }
    }

    /// Pulls nodes toward vertical column positions so ponds stack top-to-bottom
    /// with clear separation, allowing smooth vertical scrolling between them.
    private func applyQuadrantForces() {
        // Reduced vertical spacing for better visibility on mobile
        let verticalSpacing: CGFloat = 450 

        // Assign each pond a vertical slot centered around y=0
        var assignedAnchors: [String: CGPoint] = [:]
        var slotIndex = 0

        // Collect unique pond names in consistent order
        var pondOrder: [String] = []
        for info in pondInfos {
            if !pondOrder.contains(info.circleName) {
                pondOrder.append(info.circleName)
            }
        }
        
        let unassignedKey = "Unassigned_Pond"
        var hasUnassigned = false
        for (_, node) in personNodes {
            let circleName = pondInfos.first(where: { $0.memberIDs.contains(node.personID) })?.circleName
            if circleName == nil && !node.isMe {
                hasUnassigned = true
                break
            }
        }
        if hasUnassigned {
            pondOrder.append(unassignedKey)
        }

        // Center the column so it straddles y=0 or starts at y=0 if few ponds
        let count = pondOrder.count
        let totalHeight = CGFloat(max(count - 1, 0)) * verticalSpacing
        let startY = totalHeight / 2

        for name in pondOrder {
            let y = startY - CGFloat(slotIndex) * verticalSpacing
            assignedAnchors[name] = CGPoint(x: 0, y: y)
            slotIndex += 1
        }

        for (_, node) in personNodes {
            guard let body = node.physicsBody else { continue }
            
            // Special handling for "Me" - always keep centered
            if node.isMe {
                let dx = -node.position.x
                let dy = -node.position.y
                let dist = max(hypot(dx, dy), 1)
                let forceMag: CGFloat = 60.0
                body.applyForce(CGVector(dx: (dx/dist)*forceMag, dy: (dy/dist)*forceMag))
                continue
            }
            
            // Find which pond this node belongs to
            let circleName = pondInfos.first(where: { $0.memberIDs.contains(node.personID) })?.circleName ?? unassignedKey
            guard let target = assignedAnchors[circleName] else { continue }
            
            // Apply a force towards the assigned vertical slot
            let dx = target.x - node.position.x
            let dy = target.y - node.position.y
            let distance = max(hypot(dx, dy), 1)
            let forceMagnitude: CGFloat = 40.0
            
            let force = CGVector(dx: (dx / distance) * forceMagnitude, dy: (dy / distance) * forceMagnitude)
            body.applyForce(force)
        }
    }

    /// Prevents ponds from overlapping by applying repulsive forces between their member nodes
    /// if their calculated boundaries are too close.
    private func applyPondRepulsion(metrics: [PondMetrics]) {
        guard metrics.count > 1 else { return }
        
        for i in 0..<metrics.count {
            for j in i+1..<metrics.count {
                let m1 = metrics[i]
                let m2 = metrics[j]
                
                let dx = m1.center.x - m2.center.x
                let dy = m1.center.y - m2.center.y
                let distance = max(hypot(dx, dy), 1)
                
                // Minimum distance = sum of radii + generous safety margin
                let minDistance = m1.radius + m2.radius + 220
                
                if distance < minDistance {
                    // Ponds overlap or are too close
                    let overlap = minDistance - distance
                    let overlapRatio = overlap / minDistance
                    // Very strong repulsion that scales sharply with overlap severity
                    let repulsionStrength: CGFloat = 80.0 * overlapRatio * overlapRatio + 30.0
                    
                    let rx = (dx / distance) * repulsionStrength
                    let ry = (dy / distance) * repulsionStrength
                    
                    let force1 = CGVector(dx: rx, dy: ry)
                    let force2 = CGVector(dx: -rx, dy: -ry)
                    
                    // Apply to all nodes in pond 1
                    for id in m1.memberIDs {
                        personNodes[id]?.physicsBody?.applyForce(force1)
                    }
                    // Apply to all nodes in pond 2
                    for id in m2.memberIDs {
                        personNodes[id]?.physicsBody?.applyForce(force2)
                    }
                }
            }
        }
    }

    /// Prevents non-members (e.g., unassigned nodes) from drifting inside ponds they don't belong to.
    private func applyPondNodeRepulsion(metrics: [PondMetrics]) {
        for metric in metrics {
            let pondCenter = metric.center
            // Add a safety buffer to the pond radius
            let repulseRadius = metric.radius + 80
            let memberSet = Set(metric.memberIDs)
            
            for (id, node) in personNodes {
                // Ignore "Me" node and actual pond members
                if memberSet.contains(id) { continue }
                
                let dx = node.position.x - pondCenter.x
                let dy = node.position.y - pondCenter.y
                let distance = max(hypot(dx, dy), 1)
                
                if distance < repulseRadius {
                    let overlap = repulseRadius - distance
                    let overlapRatio = overlap / repulseRadius
                    
                    // Repel the non-member node away from the pond center
                    let repulsionStrength: CGFloat = 60.0 * overlapRatio * overlapRatio + 20.0
                    
                    let rx = (dx / distance) * repulsionStrength
                    let ry = (dy / distance) * repulsionStrength
                    
                    node.physicsBody?.applyForce(CGVector(dx: rx, dy: ry))
                }
            }
        }
    }

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

    /// Creates an organic wobbly path around a center point, matching the demo's drawPondPath().
    private func pondShapePath(center: CGPoint, radius: CGFloat, seed: CGFloat) -> CGPath {
        let pts = 16
        var points: [CGPoint] = []
        for i in 0..<pts {
            let a = (CGFloat(i) / CGFloat(pts)) * 2 * .pi
            let wobble = radius
                + sin(a * 2 + seed) * (radius * 0.15)
                + cos(a * 3 + seed * 0.7) * (radius * 0.10)
                + sin(a * 5 - seed) * (radius * 0.05)
            points.append(CGPoint(
                x: center.x + wobble * cos(a),
                y: center.y + wobble * sin(a)
            ))
        }

        let path = CGMutablePath()
        // Start at midpoint between last and first
        let startX = (points[pts - 1].x + points[0].x) / 2
        let startY = (points[pts - 1].y + points[0].y) / 2
        path.move(to: CGPoint(x: startX, y: startY))

        for i in 0..<pts {
            let next = points[(i + 1) % pts]
            let midX = (points[i].x + next.x) / 2
            let midY = (points[i].y + next.y) / 2
            path.addQuadCurve(to: CGPoint(x: midX, y: midY), control: points[i])
        }
        path.closeSubpath()
        return path
    }

    private func findPerson(id: UUID, in levels: [GraphLevel]) -> Person? {
        for level in levels {
            if let person = level.allContacts.first(where: { $0.id == id }) {
                return person
            }
        }
        return nil
    }

    // MARK: - Update Loop

    override func update(_ currentTime: TimeInterval) {
        let nodesArray = Array(personNodes.values)
        
        if !physicsSettled {
            // Prevent exact overlaps by giving a tiny nudge if nodes are too close
            if nodesArray.count > 1 {
                for i in 0..<nodesArray.count {
                for j in i+1..<nodesArray.count {
                    let n1 = nodesArray[i]
                    let n2 = nodesArray[j]
                    let dx = n1.position.x - n2.position.x
                    let dy = n1.position.y - n2.position.y
                    let d2 = dx*dx + dy*dy
                    if d2 < 25 { // Within 5 pixels
                        let impulse = CGVector(dx: CGFloat.random(in: -10...10), dy: CGFloat.random(in: -10...10))
                        n1.physicsBody?.applyImpulse(impulse)
                        n2.physicsBody?.applyImpulse(impulse)
                    }
                }
            }
        }
        
        // P0-5 Fix: Limit maximum velocity to prevent nodes from flying off uncontrollably
        for node in nodesArray {
            if let body = node.physicsBody {
                let maxSpeed: CGFloat = 800.0
                let speedStr = hypot(body.velocity.dx, body.velocity.dy)
                if speedStr > maxSpeed {
                    body.velocity = CGVector(dx: body.velocity.dx / speedStr * maxSpeed, dy: body.velocity.dy / speedStr * maxSpeed)
                }
            }
        }

        if !physicsSettled {
            applyQuadrantForces()
        }

        // 1. Calculate current metrics for all active ponds
        var allMetrics: [PondMetrics] = []
        for info in pondInfos {
            let memberNodes = info.memberIDs.compactMap { personNodes[$0] }
            guard !memberNodes.isEmpty else {
                pondOutlines[info.circleName]?.isHidden = true
                pondLabels[info.circleName]?.isHidden = true
                continue
            }

            // Compute centroid
            var cx: CGFloat = 0, cy: CGFloat = 0
            for node in memberNodes { cx += node.position.x; cy += node.position.y }
            cx /= CGFloat(memberNodes.count)
            cy /= CGFloat(memberNodes.count)

            // Compute max member distance
            var maxDist: CGFloat = 0
            for node in memberNodes {
                let d = hypot(node.position.x - cx, node.position.y - cy)
                if d > maxDist { maxDist = d }
            }
            let pondRadius = memberNodes.count == 1 ? CGFloat(55) : maxDist + 60
            
            allMetrics.append(PondMetrics(name: info.circleName, center: CGPoint(x: cx, y: cy), radius: pondRadius, memberIDs: info.memberIDs))
        }

        if !physicsSettled {
            // 2. Apply repulsion between ponds to prevent overlap
            applyPondRepulsion(metrics: allMetrics)
            
            // 2.5 Apply repulsion for unassigned/non-member nodes so they don't sit inside ponds
            applyPondNodeRepulsion(metrics: allMetrics)
        }

        // 3. Update edge line paths to follow node positions
        for (edgeKey, edgeNode) in edgeNodes {
            let ids = edgeKey.split(separator: "_")
            guard ids.count == 2,
                  let uuidA = UUID(uuidString: String(ids[0])),
                  let uuidB = UUID(uuidString: String(ids[1])),
                  let nodeA = personNodes[uuidA],
                  let nodeB = personNodes[uuidB] else { continue }

            edgeNode.path = calculateCurvedPath(from: nodeA.position, to: nodeB.position, avoiding: [uuidA, uuidB])
        }

        // 4. Update pond outlines to follow node positions (and use metrics)
        for metric in allMetrics {
            guard let outline = pondOutlines[metric.name] else { continue }
            
            let cx = metric.center.x
            let cy = metric.center.y
            let pondRadius = metric.radius
            
            let center = CGPoint(x: cx, y: cy)
            let seed = CGFloat(metric.name.count * 3)
            outline.path = pondShapePath(center: center, radius: pondRadius, seed: seed)
            outline.isHidden = false

            // Update label position (above pond)
            if let label = pondLabels[metric.name] {
                label.position = CGPoint(x: cx, y: cy + pondRadius + 14)
                label.isHidden = false
            }
        }

        // Viewport culling
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
            node.isHidden = !visibleRect.contains(node.position)
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
                if soloedNodeIDs.contains(id) {
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
        
        let edgeAlpha: CGFloat = isSearchActive ? 0.05 : (isSoloActive ? 0.05 : 0.6)
        for (_, edge) in edgeNodes {
            let action = SKAction.fadeAlpha(to: edgeAlpha, duration: duration)
            action.timingMode = .easeInEaseOut
            edge.run(action)
        }
        
        for (name, outline) in pondOutlines {
            let isThisSolo = (name == soloedPondName)
            let pondAlpha: CGFloat = isSearchActive ? 0.05 : (isSoloActive ? (isThisSolo ? 1.0 : 0.1) : 0.20)
            let fillAlpha: CGFloat = isSearchActive ? 0.02 : (isSoloActive ? (isThisSolo ? 0.08 : 0.02) : 0.08)
            
            let colorHex = pondInfos.first(where: { $0.circleName == name })?.color ?? ""
            let baseColor = GoldfishUIColor(hex: colorHex) ?? UIColor.systemGray3
            
            outline.strokeColor = baseColor.withAlphaComponent(pondAlpha)
            outline.fillColor = baseColor.withAlphaComponent(fillAlpha)
        }
        
        for (name, label) in pondLabels {
            let isThisSolo = (name == soloedPondName)
            let labelAlpha: CGFloat = isSearchActive ? 0.1 : (isSoloActive ? (isThisSolo ? 1.0 : 0.1) : 0.7)
            let action = SKAction.fadeAlpha(to: labelAlpha, duration: duration)
            action.timingMode = .easeInEaseOut
            label.run(action)
        }
    }

    // MARK: - Touches (Drag nodes + Tap to select + 1-finger camera pan)

    private var draggedNode: PersonNode?
    private var dragStartLocation: CGPoint = .zero
    private var lastTouchLocation: CGPoint = .zero
    private var touchHasMoved = false
    private var hoverPondName: String? = nil
    // private var longPressTimer: Timer? = nil // Removed manual timer logic

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: contentNode)
        dragStartLocation = location
        lastTouchLocation = touch.location(in: self.view!)
        touchHasMoved = false

        // Check if we tapped a node
        for (_, node) in personNodes {
            let distance = hypot(location.x - node.position.x, location.y - node.position.y)
            if distance < 35 {
                
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
        }
        draggedNode = nil
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }

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

            if let prevTargetID = snapTargetID, prevTargetID != closestID {
                personNodes[prevTargetID]?.setHoverGlow(false)
            }
            snapTargetID = closestID
            if let targetID = closestID, let targetNode = personNodes[targetID] {
                if snapTargetID != targetID {
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                targetNode.setHoverGlow(true)

                // Show dashed preview line
                let curvedPath = calculateCurvedPath(from: node.position, to: targetNode.position, avoiding: [node.personID, targetID])
                
                // Create a dashed pattern
                let pattern: [CGFloat] = [6, 4]
                snapPreviewLine?.path = curvedPath.copy(dashingWithPhase: 0, lengths: pattern)
                snapPreviewLine?.isHidden = false
                
                // Clear pond hover if we just snapped back to a node
                if let old = hoverPondName {
                    pondOutlines[old]?.strokeColor = UIColor.white.withAlphaComponent(0.2)
                    pondOutlines[old]?.fillColor = .clear
                    hoverPondName = nil
                }
            } else {
                snapPreviewLine?.isHidden = true
                snapPreviewLine?.path = nil
                
                // We are not snapping to a node. Are we inside a pond?
                var foundPondName: String? = nil
                for info in pondInfos {
                    if let outline = pondOutlines[info.circleName], let path = outline.path {
                        if path.contains(node.position) {
                            foundPondName = info.circleName
                            break
                        }
                    }
                }
                
                if let old = hoverPondName, old != foundPondName {
                    pondOutlines[old]?.strokeColor = UIColor.white.withAlphaComponent(0.2)
                    pondOutlines[old]?.fillColor = .clear
                }
                
                hoverPondName = foundPondName
                
                if let new = hoverPondName {
                    pondOutlines[new]?.strokeColor = .white
                    pondOutlines[new]?.fillColor = UIColor.white.withAlphaComponent(0.05)
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
        
        guard let touch = touches.first, let node = draggedNode else { return }
        
        let scaleDown = SKAction.scale(to: 1.0, duration: 0.15)
        scaleDown.timingMode = .easeIn
        node.run(scaleDown)
        
        node.physicsBody?.isDynamic = true
        node.physicsBody?.categoryBitMask = 1  // Re-enable category
        node.physicsBody?.collisionBitMask = 0 // Keep collision disabled
        node.physicsBody?.velocity = .zero
        if physicsSettled {
            applyIdleFloatingAnimation() // restart floating
        }

        // Check for snap-to-connect or pond move
        if touchHasMoved {
            if let targetID = snapTargetID {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
                graphDelegate?.requestConnection(from: node.personID, to: targetID)
            } else if let pondName = hoverPondName {
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
        if let old = hoverPondName {
            pondOutlines[old]?.strokeColor = UIColor.white.withAlphaComponent(0.2)
            pondOutlines[old]?.fillColor = .clear
            hoverPondName = nil
        }
        snapPreviewLine?.isHidden = true
        snapPreviewLine?.path = nil
        snapTargetID = nil
        draggedNode = nil
        touchHasMoved = false
        
        if physicsSettled {
            physicsWorld.speed = 1.0
            physicsSettled = false
            settleTimer?.invalidate()
            settleTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.physicsWorld.speed = 0.0  // Fully freeze physics on settle
                    self?.physicsSettled = true
                    self?.applyIdleFloatingAnimation()
                }
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        // longPressTimer?.invalidate()
        // longPressTimer = nil
        
        guard let node = draggedNode else { return }
        node.physicsBody?.isDynamic = true
        node.physicsBody?.categoryBitMask = 1  // Re-enable category
        node.physicsBody?.collisionBitMask = 0 // Keep collision disabled
        if let targetID = snapTargetID { personNodes[targetID]?.setHoverGlow(false) }
        if let old = hoverPondName {
            pondOutlines[old]?.strokeColor = UIColor.white.withAlphaComponent(0.2)
            pondOutlines[old]?.fillColor = .clear
            hoverPondName = nil
        }
        snapPreviewLine?.isHidden = true
        snapPreviewLine?.path = nil
        snapTargetID = nil
        draggedNode = nil
        touchHasMoved = false
        
        if physicsSettled {
            physicsWorld.speed = 1.0
            physicsSettled = false
            settleTimer?.invalidate()
            settleTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.physicsWorld.speed = 0.0  // Fully freeze physics on settle
                    self?.physicsSettled = true
                    self?.applyIdleFloatingAnimation()
                }
            }
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
        for info in pondInfos {
            if let outline = pondOutlines[info.circleName], let path = outline.path {
                if path.contains(location) {
                    tappedPondName = info.circleName
                    break
                }
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
        
        // Check if we long-pressed a node
        for (id, node) in personNodes {
            let distance = hypot(contentLocation.x - node.position.x, contentLocation.y - node.position.y)
            if distance < 35 {
                
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task { @MainActor in
                    graphDelegate?.didLongPressContact(id)
                }
                highlightNode(id)
                
                // cancel drag if active
                if draggedNode?.personID == id {
                    touchesCancelled(Set(), with: nil)
                }
                
                return
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

// MARK: - PersonNode
/// A composite SKNode representing a single person in the graph.
final class PersonNode: SKNode {

    let personID: UUID
    let isMe: Bool
    private let circleShape: SKShapeNode
    private let initialsLabel: SKLabelNode
    private let nameLabel: SKLabelNode
    private let glowNode: SKShapeNode
    private let hoverGlowNode: SKShapeNode
    private let starLabel: SKLabelNode?
    private let unassignedLabel: SKLabelNode
    private let dotNode: SKShapeNode
    private var cropNode: SKCropNode?

    private var lodState: LODState = .full
    private enum LODState { case full, noLabel, dotOnly }

    init(person: Person, depth: Int) {
        self.personID = person.id
        self.isMe = person.isMe

        let radius: CGFloat = 22

        // Circle shape (ring)
        // Always create unassignedLabel
        let uLabel = SKLabelNode(text: "unassigned")
        uLabel.fontName = "SFProText-Italic"
        uLabel.fontSize = 9
        uLabel.fontColor = UIColor.secondaryLabel
        uLabel.verticalAlignmentMode = .top
        uLabel.horizontalAlignmentMode = .center
        uLabel.position = CGPoint(x: 0, y: -(radius + 20))
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
            var hash = 0
            for char in person.name {
                hash = (hash &* 31) &+ Int(char.asciiValue ?? 0)
            }
            hash = abs(hash)
            let hue = CGFloat(hash % 360) / 360.0
            circleShape.fillColor = UIColor(hue: hue, saturation: 0.4, brightness: 0.85, alpha: 1.0)

            initialsLabel = SKLabelNode(text: person.initials)
            initialsLabel.fontName = "SFProRounded-Semibold"
            initialsLabel.fontSize = radius * 0.75
            initialsLabel.fontColor = .white
            initialsLabel.verticalAlignmentMode = .center
            initialsLabel.horizontalAlignmentMode = .center
            initialsLabel.zPosition = 2

            cropNode = nil
        }

        // Name label
        nameLabel = SKLabelNode(text: person.name)
        nameLabel.fontName = "SFProText-Regular"
        nameLabel.fontSize = 11
        nameLabel.fontColor = UIColor.label
        nameLabel.verticalAlignmentMode = .top
        nameLabel.horizontalAlignmentMode = .center
        nameLabel.position = CGPoint(x: 0, y: -(radius + 6))
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

        // Dot for extreme zoom-out
        dotNode = SKShapeNode(circleOfRadius: 4)
        dotNode.fillColor = circleShape.fillColor != .clear ? circleShape.fillColor : circleShape.strokeColor
        dotNode.strokeColor = .clear
        dotNode.isHidden = true

        super.init()

        self.name = person.id.uuidString

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
        update(with: person)
    }

    // MARK: - Update

    func update(with person: Person) {
        let radius: CGFloat = 22
        let activeCircles = person.circleContacts.filter { !$0.manuallyExcluded }
        let hasCircle = !activeCircles.isEmpty
        let isAssigned = hasCircle || !person.isOrphan

        // Reset path to standard circle
        let path = CGMutablePath()
        path.addArc(center: .zero, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: true)

        if isMe {
            circleShape.path = path
            circleShape.strokeColor = .white
            circleShape.lineWidth = 4.0
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

// MARK: - UIColor Hex Helper (private to this file)
private func GoldfishUIColor(hex: String) -> UIColor? {
    let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&int)
    guard hex.count == 6 else { return nil }
    let r = CGFloat((int >> 16) & 0xFF) / 255
    let g = CGFloat((int >> 8) & 0xFF) / 255
    let b = CGFloat(int & 0xFF) / 255
    return UIColor(red: r, green: g, blue: b, alpha: 1.0)
}
