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
    }

    // MARK: - GraphSceneDelegate

    func didUpdateGraphLevels(_ levels: [GraphLevel]) {
        graphLevelsCache = levels
        updateGraph(levels)
    }

    func didSelectContact(_ id: UUID?) {
        highlightNode(id)
    }

    func didUpdateZoom(_ zoom: CGFloat) {
        let clamped = min(max(zoom, 0.1), 4.0)
        currentZoom = clamped
        let action = SKAction.scale(to: 1.0 / clamped, duration: 0.25)
        action.timingMode = .easeInEaseOut
        cameraNode.run(action)
        updateLOD()
    }

    func didUpdateCameraPosition(_ position: CGPoint) {
        let action = SKAction.move(to: position, duration: 0.25)
        action.timingMode = .easeInEaseOut
        cameraNode.run(action)
    }

    func centerOnContact(_ id: UUID) {
        guard let node = personNodes[id] else { return }
        let action = SKAction.move(to: node.position, duration: 0.4)
        action.timingMode = .easeInEaseOut
        cameraNode.run(action)
    }

    func requestConnection(from: UUID, to: UUID) {
        // No-op: This is handled by GraphViewModel, not by the scene
    }
    
    func didUpdateSearchMatches(_ ids: Set<UUID>?) {
        activeSearchIDs = ids
        applySearchDimming()
    }

    // MARK: - Graph Building

    private func updateGraph(_ levels: [GraphLevel]) {
        contentNode.removeAllChildren()
        personNodes.removeAll()
        edgeNodes.removeAll()
        pondOutlines.removeAll()
        pondLabels.removeAll()
        pondInfos.removeAll()
        physicsSettled = false
        physicsWorld.speed = 1.0

        // Re-add gravity field
        let gravity = SKFieldNode.radialGravityField()
        gravity.strength = 0.1
        gravity.falloff = 0.5
        gravity.position = .zero
        contentNode.addChild(gravity)

        // Build all person nodes
        for level in levels {
            let radius = CGFloat(level.depth * 140 + 20)
            let allContacts = level.allContacts
            let count = allContacts.count

            for (index, person) in allContacts.enumerated() {
                let angle = (CGFloat(index) / CGFloat(max(count, 1))) * 2 * .pi
                let x = level.depth > 0 ? radius * cos(angle) : 0
                let y = level.depth > 0 ? radius * sin(angle) : 0

                let personNode = PersonNode(person: person, depth: level.depth)
                personNode.position = CGPoint(x: x, y: y)

                // Physics body
                let body = SKPhysicsBody(circleOfRadius: 40) // Increased for better label spacing collision
                body.mass = 1.0
                body.linearDamping = 6.0 // Higher damping to settle efficiently
                body.angularDamping = 8.0
                body.isDynamic = !person.isMe
                body.allowsRotation = false
                body.categoryBitMask = 1
                body.collisionBitMask = 1 // Enable physics collisions between nodes to push apart text
                body.fieldBitMask = 1
                personNode.physicsBody = body

                contentNode.addChild(personNode)
                personNodes[person.id] = personNode
            }
        }

        // Build pond info from all unique contacts
        // We use all active circles for each person so they can belong to multiple ponds.
        var pondMembers: [String: (color: String, ids: Set<UUID>)] = [:]
        for (_, personNode) in personNodes {
            guard let person = levels.flatMap(\.allContacts).first(where: { $0.id == personNode.personID }) else { continue }
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

        // Create pond outline shapes and labels
        for (name, info) in pondMembers {
            let pondInfo = PondInfo(circleName: name, color: info.color, memberIDs: Array(info.ids))
            pondInfos.append(pondInfo)

            // Outline shape
            let outline = SKShapeNode()
            outline.strokeColor = (GoldfishUIColor(hex: info.color) ?? UIColor.systemGray3).withAlphaComponent(0.20)
            outline.fillColor = (GoldfishUIColor(hex: info.color) ?? UIColor.systemGray3).withAlphaComponent(0.08)
            outline.lineWidth = 2.0
            outline.zPosition = -2
            contentNode.addChild(outline)
            pondOutlines[name] = outline

            // Label
            let label = SKLabelNode(text: name)
            label.fontName = "SFProText-Semibold"
            label.fontSize = 11
            label.fontColor = (GoldfishUIColor(hex: info.color) ?? UIColor.systemGray3).withAlphaComponent(0.7)
            label.horizontalAlignmentMode = .center
            label.verticalAlignmentMode = .bottom
            label.zPosition = -1
            
            // Add watercolor blob decoration behind the label
            let blob = SKShapeNode()
            blob.fillColor = (GoldfishUIColor(hex: info.color) ?? UIColor.systemGray3).withAlphaComponent(0.25)
            blob.strokeColor = .clear
            blob.zPosition = -9
            
            // Generate a wavy path to simulate a organic drop of watercolor
            let path = CGMutablePath()
            let pts = 12
            let center = CGPoint(x: 0, y: 8) // Shift slightly up to center behind the text
            let blobRadius: CGFloat = 34
            let startWobbleSeed = CGFloat(abs(name.hashValue))
            for i in 0..<pts {
                let a = CGFloat(i) * 2.0 * .pi / CGFloat(pts)
                let noise = sin(a * 4 + startWobbleSeed) * 5 + cos(a * 3 - startWobbleSeed) * 4
                let r = blobRadius + noise
                let pt = CGPoint(x: center.x + r * cos(a), y: center.y + r * sin(a))
                if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
            }
            path.closeSubpath()
            blob.path = path
            label.addChild(blob)
            
            contentNode.addChild(label)
            pondLabels[name] = label
        }

        // Build edges based on relationships
        var drawnEdges: Set<String> = []
        for (personID, _) in personNodes {
            guard let person = findPerson(id: personID, in: levels) else { continue }
            for rel in person.allRelationships {
                let otherID = rel.fromContact.id == personID ? rel.toContact.id : rel.fromContact.id
                let edgeKey = [personID.uuidString, otherID.uuidString].sorted().joined(separator: "-")
                guard !drawnEdges.contains(edgeKey), personNodes[otherID] != nil else { continue }
                drawnEdges.insert(edgeKey)

                let edgeNode = SKShapeNode()
                edgeNode.strokeColor = UIColor.systemGray3
                edgeNode.lineWidth = 1.0
                edgeNode.alpha = 0.6
                edgeNode.zPosition = -1
                edgeNode.name = edgeKey
                contentNode.addChild(edgeNode)
                edgeNodes[edgeKey] = edgeNode
            }
        }

        // Create the snap preview line (hidden by default)
        let preview = SKShapeNode()
        preview.strokeColor = UIColor(red: 183/255, green: 79/255, blue: 58/255, alpha: 0.55)
        preview.lineWidth = 1.5
        preview.isHidden = true
        preview.zPosition = 10
        // Dashed line pattern
        preview.path = nil
        contentNode.addChild(preview)
        snapPreviewLine = preview

        // Add spring joints between connected nodes
        for (edgeKey, _) in edgeNodes {
            let ids = edgeKey.split(separator: "-")
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
            spring.frequency = 0.8
            spring.damping = 0.4
            physicsWorld.add(spring)
        }

        // After 3 seconds, reduce physics speed to dampen jitter
        settleTimer?.invalidate()
        settleTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.physicsWorld.speed = 0.1
                self?.physicsSettled = true
                self?.applyIdleFloatingAnimation()
            }
        }
        
        applySearchDimming()
    }
    
    private func applyIdleFloatingAnimation() {
        for (_, node) in personNodes {
            if node.isMe { continue }
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

    /// Pulls nodes toward distinct screen quadrants based on their primary circle
    /// to organically separate groups visually.
    private func applyQuadrantForces() {
        // Define a few anchor points around the center to keep ponds separated
        let anchors: [CGPoint] = [
            CGPoint(x: -450, y: 450),  // Top-Left
            CGPoint(x: 450, y: 450),   // Top-Right
            CGPoint(x: -450, y: -450), // Bottom-Left
            CGPoint(x: 450, y: -450),  // Bottom-Right
            CGPoint(x: 0, y: 550),     // Top
            CGPoint(x: 0, y: -550),    // Bottom
            CGPoint(x: -550, y: 0),    // Left
            CGPoint(x: 550, y: 0)      // Right
        ]

        var assignedAnchors: [String: CGPoint] = [:]
        var anchorIndex = 0

        for (_, node) in personNodes {
            guard let body = node.physicsBody else { continue }
            
            // "Me" node should not move at all
            if node.isMe {
                body.isDynamic = false
                continue
            }
            // Let's use pondInfos to figure out which circle this node belongs to.
            // A node can be in multiple ponds, we'll just pick the first one we find it in for gravity.
            guard let circleName = pondInfos.first(where: { $0.memberIDs.contains(node.personID) })?.circleName else { continue }
            if assignedAnchors[circleName] == nil {
                assignedAnchors[circleName] = anchors[anchorIndex % anchors.count]
                anchorIndex += 1
            }
            
            guard let target = assignedAnchors[circleName] else { continue }
            
            // Apply a gentle force towards the assigned anchor
            let dx = target.x - node.position.x
            let dy = target.y - node.position.y
            let distance = max(hypot(dx, dy), 1)
            let forceMagnitude: CGFloat = 12.0 // Strong enough to keep ponds well away from center
            
            let force = CGVector(dx: (dx / distance) * forceMagnitude, dy: (dy / distance) * forceMagnitude)
            body.applyForce(force)
        }
    }

    // MARK: - Path Logic

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
        // Keep the 'Me' node strictly pinned to the center
        let meNode = personNodes.values.first { $0.isMe }
        if let me = meNode {
            me.position = .zero
            me.physicsBody?.velocity = .zero
            me.physicsBody?.angularVelocity = 0
            if draggedNode !== me {
                me.physicsBody?.isDynamic = false
            }
        }

        applyQuadrantForces()

        // Update edge line paths to follow node positions
        for (edgeKey, edgeNode) in edgeNodes {
            let ids = edgeKey.split(separator: "-")
            guard ids.count == 2,
                  let uuidA = UUID(uuidString: String(ids[0])),
                  let uuidB = UUID(uuidString: String(ids[1])),
                  let nodeA = personNodes[uuidA],
                  let nodeB = personNodes[uuidB] else { continue }

            let path = CGMutablePath()
            path.move(to: nodeA.position)
            path.addLine(to: nodeB.position)
            edgeNode.path = path
        }

        // Update pond outlines to follow node positions
        for info in pondInfos {
            guard let outline = pondOutlines[info.circleName] else { continue }
            let memberNodes = info.memberIDs.compactMap { personNodes[$0] }
            guard !memberNodes.isEmpty else {
                outline.isHidden = true
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
            let pondRadius = maxDist + 45 // Give some breathing room inside the pond
            
            // Push pond center away from origin so the "Me" node never appears inside a pond.
            let meClearance: CGFloat = 30 // minimum gap between pond edge and Me node
            let distFromOrigin = hypot(cx, cy)
            let minCenterDist = pondRadius + meClearance
            if distFromOrigin < minCenterDist && distFromOrigin > 0.1 {
                let scale = minCenterDist / distFromOrigin
                cx *= scale
                cy *= scale
            } else if distFromOrigin <= 0.1 {
                // Pond centroid is right on top of Me – push it in a deterministic direction
                let angle = CGFloat(info.circleName.hashValue % 360) * .pi / 180
                cx = minCenterDist * cos(angle)
                cy = minCenterDist * sin(angle)
            }
            
            let center = CGPoint(x: cx, y: cy)
            let seed = CGFloat(info.circleName.count * 3)
            outline.path = pondShapePath(center: center, radius: pondRadius, seed: seed)
            outline.isHidden = false

            // Update label position (above pond)
            if let label = pondLabels[info.circleName] {
                label.position = CGPoint(x: cx, y: cy + pondRadius + 8)
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
    
    private func applySearchDimming() {
        let duration: TimeInterval = 0.3
        
        let targetAlphaNode: CGFloat = activeSearchIDs == nil ? 1.0 : 0.2
        let targetAlphaEdge: CGFloat = activeSearchIDs == nil ? 0.6 : 0.05
        let targetAlphaPond: CGFloat = activeSearchIDs == nil ? 0.20 : 0.05
        let targetAlphaPondFill: CGFloat = activeSearchIDs == nil ? 0.08 : 0.02
        let targetAlphaText: CGFloat = activeSearchIDs == nil ? 0.7 : 0.1
        
        for (id, node) in personNodes {
            let isMatched = activeSearchIDs?.contains(id) ?? true
            let alpha = isMatched ? 1.0 : targetAlphaNode
            // Matched nodes pop to front
            node.zPosition = isMatched ? 5 : 0
            
            let action = SKAction.fadeAlpha(to: alpha, duration: duration)
            action.timingMode = .easeInEaseOut
            node.run(action)
        }
        
        for (_, edge) in edgeNodes {
            let action = SKAction.fadeAlpha(to: targetAlphaEdge, duration: duration)
            action.timingMode = .easeInEaseOut
            edge.run(action)
        }
        
        for (name, outline) in pondOutlines {
            // Outlines stroke
            let oldStroke = (GoldfishUIColor(hex: pondInfos.first(where: { $0.circleName == name })?.color ?? "") ?? UIColor.systemGray3).withAlphaComponent(targetAlphaPond)
            let oldFill = (GoldfishUIColor(hex: pondInfos.first(where: { $0.circleName == name })?.color ?? "") ?? UIColor.systemGray3).withAlphaComponent(targetAlphaPondFill)
            outline.strokeColor = oldStroke
            outline.fillColor = oldFill
        }
        
        for (_, label) in pondLabels {
            let action = SKAction.fadeAlpha(to: targetAlphaText, duration: duration)
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
                // Prevent dragging the 'Me' node
                guard !node.isMe else { return }
                
                draggedNode = node
                node.physicsBody?.isDynamic = false
                node.physicsBody?.categoryBitMask = 0  // Disable category to stop pushing others away
                node.physicsBody?.collisionBitMask = 0 // Disable collision while dragging
                node.removeAction(forKey: "floating")
                
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                
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
            if movedDistance > 8 { touchHasMoved = true }
            
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
                let linePath = CGMutablePath()
                linePath.move(to: node.position)
                linePath.addLine(to: targetNode.position)
                snapPreviewLine?.path = linePath
                snapPreviewLine?.isHidden = false
                // Create a dashed pattern
                let pattern: [CGFloat] = [6, 4]
                snapPreviewLine?.path = linePath.copy(dashingWithPhase: 0, lengths: pattern)
                
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
        guard let touch = touches.first else { return }
        
        if let node = draggedNode {
            let scaleDown = SKAction.scale(to: 1.0, duration: 0.15)
            scaleDown.timingMode = .easeIn
            node.run(scaleDown)
            
            if !node.isMe {
                node.physicsBody?.isDynamic = true
                node.physicsBody?.categoryBitMask = 1  // Re-enable category
                node.physicsBody?.collisionBitMask = 1 // Re-enable collision
                node.physicsBody?.velocity = .zero
                if physicsSettled {
                    applyIdleFloatingAnimation() // restart floating
                }
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
        } else {
            if !touchHasMoved {
                if touch.tapCount == 2 {
                    unsoloAll()
                    currentZoom = 1.0
                    let moveAction = SKAction.move(to: .zero, duration: 0.3)
                    let scaleAction = SKAction.scale(to: 1.0, duration: 0.3)
                    moveAction.timingMode = .easeInEaseOut
                    scaleAction.timingMode = .easeInEaseOut
                    cameraNode.run(SKAction.group([moveAction, scaleAction]))
                    updateLOD()
                    graphDelegate?.updateCameraFromScene(position: .zero, zoom: 1.0)
                } else {
                    highlightNode(nil)
                }
            }
        }
        touchHasMoved = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let node = draggedNode, !node.isMe {
            node.physicsBody?.isDynamic = true
            node.physicsBody?.categoryBitMask = 1  // Re-enable category
            node.physicsBody?.collisionBitMask = 1 // Re-enable collision
        }
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
    }

    // MARK: - Gesture Handlers

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            lastPinchScale = currentZoom
        case .changed:
            let newZoom = min(max(lastPinchScale * gesture.scale, 0.1), 4.0)
            currentZoom = newZoom
            cameraNode.setScale(1.0 / newZoom)
            updateLOD()
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
            cameraNode.run(SKAction.group([moveAction, scaleAction]))
            updateLOD()
            graphDelegate?.updateCameraFromScene(position: .zero, zoom: 1.0)
        }
    }

    private func soloPond(name: String) {
        if soloedPondName == name {
            unsoloAll()
            return
        }
        soloedPondName = name
        // Dim other ponds and nodes not in this pond
        let info = pondInfos.first { $0.circleName == name }
        let validIDs = info?.memberIDs ?? []
        let validIDSet = Set(validIDs)
        
        let fadeAction = SKAction.fadeAlpha(to: 0.15, duration: 0.3)
        let restoreAction = SKAction.fadeAlpha(to: 1.0, duration: 0.3)
        
        for (id, node) in personNodes {
            if validIDSet.contains(id) || node.isMe {
                node.run(restoreAction)
            } else {
                node.run(fadeAction)
            }
        }
        for (pondName, outline) in pondOutlines {
            outline.run(pondName == name ? restoreAction : SKAction.fadeAlpha(to: 0.1, duration: 0.3))
        }
        for (pondName, label) in pondLabels {
            label.run(pondName == name ? restoreAction : SKAction.fadeAlpha(to: 0.1, duration: 0.3))
        }
        for (_, edge) in edgeNodes {
            edge.run(SKAction.fadeAlpha(to: 0.05, duration: 0.3))
        }
        
        // Zoom to centroid of pond
        guard let pInfo = info else { return }
        let memberNodes = pInfo.memberIDs.compactMap { personNodes[$0] }
        guard !memberNodes.isEmpty else { return }
        
        var cx: CGFloat = 0, cy: CGFloat = 0
        for node in memberNodes { cx += node.position.x; cy += node.position.y }
        cx /= CGFloat(memberNodes.count)
        cy /= CGFloat(memberNodes.count)
        
        let moveAction = SKAction.move(to: CGPoint(x: cx, y: cy), duration: 0.4)
        moveAction.timingMode = .easeInEaseOut
        cameraNode.run(moveAction)
    }

    private func unsoloAll() {
        soloedPondName = nil
        let restoreAction = SKAction.fadeAlpha(to: 1.0, duration: 0.3)
        for (_, node) in personNodes { node.run(restoreAction) }
        for (_, outline) in pondOutlines { outline.run(restoreAction) }
        for (_, label) in pondLabels { label.run(restoreAction) }
        for (_, edge) in edgeNodes { edge.run(SKAction.fadeAlpha(to: 0.6, duration: 0.3)) }
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
    private let unassignedLabel: SKLabelNode?
    private let dotNode: SKShapeNode
    private var cropNode: SKCropNode?

    private var lodState: LODState = .full
    private enum LODState { case full, noLabel, dotOnly }

    init(person: Person, depth: Int) {
        self.personID = person.id
        self.isMe = person.isMe

        let radius: CGFloat = 22

        // Circle shape (ring)
        let activeCircles = person.circleContacts.filter { !$0.manuallyExcluded }
        let hasCircle = !activeCircles.isEmpty
        
        if isMe {
            circleShape = SKShapeNode(circleOfRadius: radius)
            circleShape.strokeColor = .white
            circleShape.lineWidth = 4.0
            unassignedLabel = nil
        } else if hasCircle {
            circleShape = SKShapeNode(circleOfRadius: radius)
            let circleColorHex = activeCircles.first?.circle.color
            circleShape.strokeColor = circleColorHex.flatMap { GoldfishUIColor(hex: $0) } ?? UIColor.systemGray3
            circleShape.lineWidth = 2.5
            unassignedLabel = nil
        } else {
            // Unassigned contacts get a dashed border per spec
            let path = CGMutablePath()
            path.addArc(center: .zero, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: true)
            
            // Create dashed pattern: 4px dash, 4px gap
            let dashedPath = path.copy(dashingWithPhase: 0, lengths: [4, 4])
            circleShape = SKShapeNode(path: dashedPath)
            circleShape.strokeColor = UIColor.systemGray3
            circleShape.lineWidth = 2.0
            
            let uLabel = SKLabelNode(text: "unassigned")
            uLabel.fontName = "SFProText-Italic"
            uLabel.fontSize = 9
            uLabel.fontColor = UIColor.secondaryLabel
            uLabel.verticalAlignmentMode = .top
            uLabel.horizontalAlignmentMode = .center
            // Name label is at -(radius + 6) which is -28. We place this slightly below.
            uLabel.position = CGPoint(x: 0, y: -(radius + 20))
            uLabel.zPosition = 2
            unassignedLabel = uLabel
        }
        
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
        if let uLab = unassignedLabel { addChild(uLab) }
        addChild(dotNode)
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
        unassignedLabel?.isHidden = false
        initialsLabel.isHidden = false
        cropNode?.isHidden = false
        dotNode.isHidden = true
    }

    func hideLabel() {
        guard lodState != .noLabel else { return }
        lodState = .noLabel
        circleShape.isHidden = false
        nameLabel.isHidden = true
        unassignedLabel?.isHidden = true
        initialsLabel.isHidden = false
        cropNode?.isHidden = false
        dotNode.isHidden = true
    }

    func showDotOnly() {
        guard lodState != .dotOnly else { return }
        lodState = .dotOnly
        circleShape.isHidden = true
        nameLabel.isHidden = true
        unassignedLabel?.isHidden = true
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
