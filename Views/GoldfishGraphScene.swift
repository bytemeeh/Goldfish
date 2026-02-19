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

    // MARK: - Gesture State
    private var lastPinchScale: CGFloat = 1.0
    private var selectedNodeID: UUID?

    // MARK: - Physics Settle
    private var settleTimer: Timer?
    private var physicsSettled = false

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = UIColor.systemBackground
        anchorPoint = CGPoint(x: 0.5, y: 0.5)

        addChild(cameraNode)
        camera = cameraNode
        addChild(contentNode)

        physicsWorld.gravity = .zero
        physicsWorld.speed = 1.0

        // Weak radial gravity to keep graph centered
        let gravity = SKFieldNode.radialGravityField()
        gravity.strength = 0.3
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
        pan.minimumNumberOfTouches = 1
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

    // MARK: - Graph Building

    private func updateGraph(_ levels: [GraphLevel]) {
        contentNode.removeAllChildren()
        personNodes.removeAll()
        edgeNodes.removeAll()
        physicsSettled = false
        physicsWorld.speed = 1.0

        // Re-add gravity field
        let gravity = SKFieldNode.radialGravityField()
        gravity.strength = 0.3
        gravity.falloff = 0.5
        gravity.position = .zero
        contentNode.addChild(gravity)

        // Build all person nodes
        for level in levels {
            let radius = CGFloat(level.depth * 140 + 20)
            let allContacts = level.allContacts
            let count = allContacts.count

            for (index, person) in allContacts.enumerated() {
                let angle = count > 1
                    ? (CGFloat(index) / CGFloat(count)) * 2 * .pi
                    : 0
                let x = count > 1 ? radius * cos(angle) : 0
                let y = count > 1 ? radius * sin(angle) : 0

                let personNode = PersonNode(person: person, depth: level.depth)
                personNode.position = CGPoint(x: x, y: y)

                // Physics body
                let body = SKPhysicsBody(circleOfRadius: 25)
                body.mass = 1.0
                body.linearDamping = 3.0
                body.angularDamping = 5.0
                body.isDynamic = !person.isMe
                body.allowsRotation = false
                body.categoryBitMask = 1
                body.collisionBitMask = 1
                body.fieldBitMask = 1
                personNode.physicsBody = body

                contentNode.addChild(personNode)
                personNodes[person.id] = personNode
            }
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
            }
        }
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

    // MARK: - Touches (Tap to select)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: contentNode)

        for (personID, node) in personNodes {
            let distance = hypot(location.x - node.position.x, location.y - node.position.y)
            if distance < 30 {
                graphDelegate?.selectContact(personID)
                return
            }
        }

        // Tapped empty space — deselect
        graphDelegate?.selectContact(nil)
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

// MARK: - PersonNode
/// A composite SKNode representing a single person in the graph.
final class PersonNode: SKNode {

    let personID: UUID
    private let circleShape: SKShapeNode
    private let initialsLabel: SKLabelNode
    private let nameLabel: SKLabelNode
    private let glowNode: SKShapeNode
    private let starLabel: SKLabelNode?
    private let dotNode: SKShapeNode
    private var cropNode: SKCropNode?

    private var lodState: LODState = .full
    private enum LODState { case full, noLabel, dotOnly }

    init(person: Person, depth: Int) {
        self.personID = person.id

        let radius: CGFloat = 22

        // Circle shape (ring)
        circleShape = SKShapeNode(circleOfRadius: radius)
        let circleColorHex = person.circleContacts.first?.circle.color
        circleShape.strokeColor = circleColorHex.flatMap { GoldfishUIColor(hex: $0) } ?? UIColor.systemGray3
        circleShape.lineWidth = 2.5
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
        glowNode.strokeColor = UIColor(red: 124/255, green: 58/255, blue: 237/255, alpha: 0.35)
        glowNode.lineWidth = 4
        glowNode.fillColor = .clear
        glowNode.isHidden = true
        glowNode.zPosition = -1

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
        addChild(circleShape)
        if let crop = cropNode {
            addChild(crop)
        } else {
            addChild(initialsLabel)
        }
        addChild(nameLabel)
        if let star = starLabel { addChild(star) }
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
        initialsLabel.isHidden = false
        cropNode?.isHidden = false
        dotNode.isHidden = true
    }

    func hideLabel() {
        guard lodState != .noLabel else { return }
        lodState = .noLabel
        circleShape.isHidden = false
        nameLabel.isHidden = true
        initialsLabel.isHidden = false
        cropNode?.isHidden = false
        dotNode.isHidden = true
    }

    func showDotOnly() {
        guard lodState != .dotOnly else { return }
        lodState = .dotOnly
        circleShape.isHidden = true
        nameLabel.isHidden = true
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
