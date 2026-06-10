import SpriteKit

// MARK: - PersonNode
/// A composite SKNode representing a single person in the graph.
final class PersonNode: SKNode {

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

    init(person: GraphNode, depth: Int) {
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
                circleShape.fillColor = GoldfishUIColor(hex: person.hexColor) ?? UIColor.systemGray3
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

        // Premium drop shadow
        let shadowNode = SKShapeNode(circleOfRadius: radius)
        shadowNode.fillColor = .black
        shadowNode.strokeColor = .clear
        shadowNode.alpha = 0.15
        shadowNode.position = CGPoint(x: 0, y: -4)
        shadowNode.zPosition = -3
        addChild(shadowNode)
        
        addChild(glowNode)
        addChild(hoverGlowNode)
        addChild(circleShape)
        
        // Inner glass rim
        let innerRim = SKShapeNode(circleOfRadius: radius - 1)
        innerRim.fillColor = .clear
        innerRim.strokeColor = UIColor.white.withAlphaComponent(0.2)
        innerRim.lineWidth = 1.5
        innerRim.zPosition = 1.5 // Above circle/photo but below text
        addChild(innerRim)
        
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
        update(with: person, depth: depth, inPond: false) // We'll fix this properly in update
    }

    // MARK: - Update

    func update(with person: GraphNode, depth: Int, inPond: Bool) {
        let previousRadius: CGFloat = isMe ? 28 : (self.currentDepth > 1 ? 16 : 22)
        self.currentDepth = depth
        let radius: CGFloat = isMe ? 28 : (depth > 1 ? 16 : 22)
        let isAssigned = inPond || !person.isOrphan

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
                    circleShape.fillColor = GoldfishUIColor(hex: person.hexColor) ?? UIColor.systemGray3
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
            circleShape.strokeColor = GoldfishUIColor(hex: person.hexColor) ?? UIColor.systemGray3
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

// MARK: - UIColor Hex Helper
func GoldfishUIColor(hex: String) -> UIColor? {
    let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var int: UInt64 = 0
    Scanner(string: hex).scanHexInt64(&int)
    guard hex.count == 6 else { return nil }
    let r = CGFloat((int >> 16) & 0xFF) / 255
    let g = CGFloat((int >> 8) & 0xFF) / 255
    let b = CGFloat(int & 0xFF) / 255
    return UIColor(red: r, green: g, blue: b, alpha: 1.0)
}
