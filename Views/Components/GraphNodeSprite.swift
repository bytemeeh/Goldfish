import SpriteKit
import UIKit

// MARK: - GraphNodeSprite
/// Reusable `SKNode` subclass representing a single Person in the graph.
///
/// Visual hierarchy:
/// ```
/// GraphNodeSprite (SKNode)
///  ├─ strokeRing (SKShapeNode) — circle color or goldfishNodeStroke
///  ├─ photoCircle (SKSpriteNode or SKShapeNode) — photo texture or pastel initials
///  ├─ initialsLabel (SKLabelNode) — shown when no photo
///  ├─ nameLabel (SKLabelNode) — "SF Pro Text" 11pt, below circle
///  ├─ selectionGlow (SKShapeNode) — accent halo, hidden by default
///  └─ favoriteBadge (SKShapeNode) — gold star, shown if isFavorite
/// ```
///
/// Each sprite stores its `personID` and `depth` for lookups in the scene.
final class GraphNodeSprite: SKNode {

    // MARK: - Constants

    static let nodeRadius: CGFloat = 25
    static let nameOffset: CGFloat = -34
    static let maxNameLength = 12
    static let glowRadius: CGFloat = 32
    static let badgeSize: CGFloat = 12
    static let dotRadius: CGFloat = 4

    // MARK: - Public State

    let personID: UUID
    let depth: Int
    var circleColorHex: String?

    // MARK: - Child Nodes

    private let strokeRing = SKShapeNode()
    private var photoSprite: SKSpriteNode?
    private var initialsCircle: SKShapeNode?
    private let initialsLabel = SKLabelNode()
    private let nameLabel = SKLabelNode()
    private let selectionGlow = SKShapeNode()
    private let nudgeGlow = SKShapeNode()
    private var favoriteBadge: SKShapeNode?
    private var dotNode: SKShapeNode?

    /// Tracks current LOD mode to avoid redundant updates.
    private var currentLOD: LODLevel = .full

    enum LODLevel {
        case full       // zoom >= 0.5: photo + name + badge
        case compact    // 0.3 <= zoom < 0.5: photo only, no name
        case dot        // zoom < 0.3: 4pt colored dot only
    }

    // MARK: - Init

    init(
        personID: UUID,
        name: String,
        depth: Int,
        photoData: Data?,
        colorHex: String?,
        circleColorHex: String?,
        isFavorite: Bool
    ) {
        self.personID = personID
        self.depth = depth
        self.circleColorHex = circleColorHex
        super.init()

        self.name = personID.uuidString

        setupStrokeRing(circleColorHex: circleColorHex)
        setupPhoto(photoData: photoData, name: name, colorHex: colorHex)
        setupNameLabel(name: name)
        setupSelectionGlow()
        setupNudgeGlow()
        if isFavorite { setupFavoriteBadge() }
        setupDotNode(colorHex: colorHex, name: name)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // MARK: - Setup Helpers

    private func setupStrokeRing(circleColorHex: String?) {
        let radius = Self.nodeRadius + 2
        
        // Deterministic wobble based on node ID
        let seed = CGFloat(abs(personID.uuidString.hashValue) % 100) / 100.0 * 2 * .pi
        
        let path = CGMutablePath()
        let pts = 12
        var points: [CGPoint] = []
        for i in 0..<pts {
            let a = (CGFloat(i) / CGFloat(pts)) * 2 * .pi
            // Slight organic imperfection
            let wobble = radius + sin(a * 3 + seed) * 1.5 + cos(a * 5 - seed) * 1.0
            points.append(CGPoint(x: wobble * cos(a), y: wobble * sin(a)))
        }
        
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
        
        strokeRing.path = path
        // Watercolor fill and thicker stroke to look painted
        if let hex = circleColorHex {
            let color = SKColor(hexString: hex)
            strokeRing.fillColor = color.withAlphaComponent(0.1)
            strokeRing.strokeColor = color.withAlphaComponent(0.8)
            strokeRing.lineWidth = 2.5
        } else {
            strokeRing.fillColor = .clear
            strokeRing.strokeColor = SKColor.goldfishNodeStroke.withAlphaComponent(0.6)
            strokeRing.lineWidth = 2.0
        }
        strokeRing.zPosition = 0
        addChild(strokeRing)
    }

    private func setupPhoto(photoData: Data?, name: String, colorHex: String?) {
        let r = Self.nodeRadius
        if let data = photoData, let image = UIImage(data: data) {
            // Circular photo texture
            let circularImage = Self.circularCrop(image, size: CGSize(width: r * 2, height: r * 2))
            let texture = SKTexture(image: circularImage)
            let sprite = SKSpriteNode(texture: texture, size: CGSize(width: r * 2, height: r * 2))
            sprite.zPosition = 1
            photoSprite = sprite
            addChild(sprite)
        } else {
            // Pastel circle with initials
            let bgColor = Self.pastelColor(for: name, colorHex: colorHex)
            let circle = SKShapeNode(circleOfRadius: r)
            circle.fillColor = bgColor
            circle.strokeColor = .clear
            circle.zPosition = 1
            initialsCircle = circle
            addChild(circle)

            let initials = Self.computeInitials(name)
            initialsLabel.text = initials
            initialsLabel.fontName = "SFProRounded-Semibold"
            initialsLabel.fontSize = r * 0.8
            initialsLabel.fontColor = .white
            initialsLabel.verticalAlignmentMode = .center
            initialsLabel.horizontalAlignmentMode = .center
            initialsLabel.zPosition = 2
            addChild(initialsLabel)
        }
    }

    private func setupNameLabel(name: String) {
        var displayName = name
        if displayName.count > Self.maxNameLength {
            displayName = String(displayName.prefix(Self.maxNameLength - 1)) + "…"
        }
        nameLabel.text = displayName
        nameLabel.fontName = "SFProText-Regular"
        nameLabel.fontSize = 11
        nameLabel.fontColor = SKColor.goldfishTextPrimary
        nameLabel.verticalAlignmentMode = .top
        nameLabel.horizontalAlignmentMode = .center
        nameLabel.position = CGPoint(x: 0, y: Self.nameOffset)
        nameLabel.zPosition = 3
        addChild(nameLabel)
    }

    private func setupSelectionGlow() {
        let r = Self.glowRadius
        selectionGlow.path = CGPath(ellipseIn: CGRect(
            x: -r, y: -r, width: r * 2, height: r * 2
        ), transform: nil)
        selectionGlow.fillColor = .clear
        selectionGlow.strokeColor = SKColor.goldfishSelectedGlow
        selectionGlow.lineWidth = 4
        selectionGlow.glowWidth = 8
        selectionGlow.zPosition = -1
        selectionGlow.isHidden = true
        addChild(selectionGlow)
    }

    private func setupNudgeGlow() {
        // Pseudo-randomly pick ~15% of contacts to demo the Smart Nudge (Interaction Decay)
        let hash = abs(personID.uuidString.hashValue) % 100
        let isNeglected = hash < 15
        
        let r = Self.nodeRadius + 4
        nudgeGlow.path = CGPath(ellipseIn: CGRect(
            x: -r, y: -r, width: r * 2, height: r * 2
        ), transform: nil)
        
        nudgeGlow.fillColor = .clear
        nudgeGlow.strokeColor = SKColor.orange
        nudgeGlow.lineWidth = 1.5
        nudgeGlow.glowWidth = 3.0
        nudgeGlow.zPosition = -2
        nudgeGlow.alpha = 0
        addChild(nudgeGlow)
        
        if isNeglected {
            let pulseIn = SKAction.fadeAlpha(to: 0.7, duration: 1.5)
            pulseIn.timingMode = .easeInEaseOut
            let pulseOut = SKAction.fadeAlpha(to: 0.1, duration: 1.5)
            pulseOut.timingMode = .easeInEaseOut
            let scaleUp = SKAction.scale(to: 1.15, duration: 1.5)
            scaleUp.timingMode = .easeInEaseOut
            let scaleDown = SKAction.scale(to: 1.0, duration: 1.5)
            scaleDown.timingMode = .easeInEaseOut
            
            let g1 = SKAction.group([pulseIn, scaleUp])
            let g2 = SKAction.group([pulseOut, scaleDown])
            
            nudgeGlow.run(SKAction.repeatForever(SKAction.sequence([g1, g2])))
        }
    }

    private func setupFavoriteBadge() {
        let badge = SKShapeNode(path: Self.starPath(size: Self.badgeSize))
        badge.fillColor = SKColor(red: 1.0, green: 0.84, blue: 0.0, alpha: 1.0) // gold
        badge.strokeColor = .white
        badge.lineWidth = 1
        badge.position = CGPoint(
            x: Self.nodeRadius * 0.7,
            y: Self.nodeRadius * 0.7
        )
        badge.zPosition = 4
        favoriteBadge = badge
        addChild(badge)
    }

    private func setupDotNode(colorHex: String?, name: String) {
        let color = Self.pastelColor(for: name, colorHex: colorHex)
        let dot = SKShapeNode(circleOfRadius: Self.dotRadius)
        dot.fillColor = color
        dot.strokeColor = .clear
        dot.zPosition = 1
        dot.isHidden = true
        dotNode = dot
        addChild(dot)
    }

    // MARK: - Selection

    func setSelected(_ selected: Bool) {
        selectionGlow.isHidden = !selected
    }

    // MARK: - LOD

    func updateLOD(zoom: CGFloat) {
        let newLOD: LODLevel
        if zoom < 0.35 {
            newLOD = .dot
        } else if zoom < 0.75 { // Aggressive semantic zooming
            newLOD = .compact
        } else {
            newLOD = .full
        }

        guard newLOD != currentLOD else { return }
        currentLOD = newLOD

        switch newLOD {
        case .full:
            photoSprite?.isHidden = false
            initialsCircle?.isHidden = false
            initialsLabel.isHidden = (photoSprite != nil) // hide if we have photo
            nameLabel.isHidden = false
            strokeRing.isHidden = false
            favoriteBadge?.isHidden = false
            selectionGlow.alpha = 1
            dotNode?.isHidden = true

        case .compact:
            photoSprite?.isHidden = false
            initialsCircle?.isHidden = false
            initialsLabel.isHidden = (photoSprite != nil)
            nameLabel.isHidden = true
            strokeRing.isHidden = false
            favoriteBadge?.isHidden = true
            selectionGlow.alpha = 1
            dotNode?.isHidden = true

        case .dot:
            photoSprite?.isHidden = true
            initialsCircle?.isHidden = true
            initialsLabel.isHidden = true
            nameLabel.isHidden = true
            strokeRing.isHidden = true
            favoriteBadge?.isHidden = true
            selectionGlow.alpha = 0.5
            dotNode?.isHidden = false
        }
    }

    // MARK: - Static Helpers

    /// Deterministic pastel color matching ContactPhotoView.swift
    static func pastelColor(for name: String, colorHex: String?) -> SKColor {
        if let hex: String = colorHex, !hex.isEmpty {
            return SKColor(hexString: hex)
        }
        var hash: Int = 0
        for char in name {
            hash = (hash &* 31) &+ Int(char.asciiValue ?? 0)
        }
        hash = abs(hash)
        let hue: CGFloat = CGFloat(hash % 360) / 360.0
        return SKColor(hue: hue, saturation: 0.4, brightness: 0.85, alpha: 1.0)
    }

    static func computeInitials(_ name: String) -> String {
        let components: [String.SubSequence] = name.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        guard !components.isEmpty else { return "?" }
        if components.count == 1 {
            return String(components[0].prefix(2)).uppercased()
        }
        let first: String.SubSequence = components.first?.prefix(1) ?? ""
        let last: String.SubSequence = components.last?.prefix(1) ?? ""
        return "\(first)\(last)".uppercased()
    }

    /// Crop a UIImage to a circle.
    static func circularCrop(_ image: UIImage, size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            UIBezierPath(ovalIn: rect).addClip()
            image.draw(in: rect)
        }
    }

    /// 5-pointed star CGPath centered at origin.
    static func starPath(size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let outerRadius = size / 2
        let innerRadius = outerRadius * 0.4
        let points = 5
        let angleStep = CGFloat.pi / CGFloat(points)
        let startAngle = -CGFloat.pi / 2

        for i in 0..<(points * 2) {
            let radius = i.isMultiple(of: 2) ? outerRadius : innerRadius
            let angle = startAngle + angleStep * CGFloat(i)
            let point = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - SKColor Helpers for GoldfishColors Compatibility

extension SKColor {

    /// Creates an SKColor from a hex string (e.g., "#FF6B6B" or "FF6B6B").
    convenience init(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b: CGFloat
        switch hex.count {
        case 3:
            r = CGFloat((int >> 8) * 17) / 255
            g = CGFloat((int >> 4 & 0xF) * 17) / 255
            b = CGFloat((int & 0xF) * 17) / 255
        case 6:
            r = CGFloat(int >> 16) / 255
            g = CGFloat(int >> 8 & 0xFF) / 255
            b = CGFloat(int & 0xFF) / 255
        default:
            r = 0.5; g = 0.5; b = 0.5
        }
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }

    /// GoldfishColors tokens as static SKColor properties (resolved for current trait collection).
    static var goldfishNodeStroke: SKColor {
        resolveAdaptive(light: 0xD1D5DB, dark: 0x4B5563)
    }

    static var goldfishEdgeLine: SKColor {
        resolveAdaptive(light: 0xD1D5DB, dark: 0x374151)
    }

    static var goldfishNodeFill: SKColor {
        resolveAdaptive(light: 0xFFFFFF, dark: 0x2C2C2E)
    }

    static var goldfishSelectedGlow: SKColor {
        let accent = resolveAdaptive(light: 0x7C3AED, dark: 0x8B5CF6)
        return accent.withAlphaComponent(0.25)
    }

    static var goldfishTextPrimary: SKColor {
        resolveAdaptive(light: 0x111827, dark: 0xF9FAFB)
    }

    static var goldfishBgPrimary: SKColor {
        resolveAdaptive(light: 0xFFFFFF, dark: 0x000000)
    }

    private static func resolveAdaptive(light: UInt32, dark: UInt32) -> SKColor {
        let style = UITraitCollection.current.userInterfaceStyle
        let hex = style == .dark ? dark : light
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        return SKColor(red: r, green: g, blue: b, alpha: 1.0)
    }
}
