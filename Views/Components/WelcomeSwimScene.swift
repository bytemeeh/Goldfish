import SpriteKit
import UIKit

enum WelcomeSwimVariant: Int, CaseIterable, Identifiable, Equatable {
    case swiftCurrent = 1
    case slowGlide
    case pigmentBloom
    case silkWake
    case quietDissolve

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .swiftCurrent: return "Swift Current · 1.8s"
        case .slowGlide: return "Slow Glide · 3.6s"
        case .pigmentBloom: return "Pigment Bloom · 3.8s"
        case .silkWake: return "Silk Wake · 3.2s"
        case .quietDissolve: return "Quiet Dissolve · 4.2s"
        }
    }

    var duration: TimeInterval {
        switch self {
        case .swiftCurrent: return 1.8
        case .slowGlide: return 3.6
        case .pigmentBloom: return 3.8
        case .silkWake: return 3.2
        case .quietDissolve: return 4.2
        }
    }

    fileprivate var bend: CGFloat {
        switch self {
        case .swiftCurrent, .slowGlide: return 0.035
        case .pigmentBloom: return 0.065
        case .silkWake: return -0.055
        case .quietDissolve: return 0.04
        }
    }

    fileprivate var dissolveStyle: Float {
        switch self {
        case .swiftCurrent, .slowGlide: return 0
        case .pigmentBloom: return 1 // tail to head, like wet color lifting from the paper
        case .silkWake: return 2 // outward edge bloom
        case .quietDissolve: return 3 // fragmented pigment clouds
        }
    }

    fileprivate var dissolveStart: Float {
        switch self {
        case .swiftCurrent, .slowGlide: return 1
        case .pigmentBloom: return 0.27
        case .silkWake: return 0.24
        case .quietDissolve: return 0.33
        }
    }

    fileprivate var dissolveEnd: Float {
        switch self {
        case .swiftCurrent, .slowGlide: return 1
        case .pigmentBloom: return 0.82
        case .silkWake: return 0.84
        case .quietDissolve: return 0.87
        }
    }

    fileprivate var travel: CGSize {
        switch self {
        case .swiftCurrent, .slowGlide: return CGSize(width: 0.30, height: 0.98)
        case .pigmentBloom: return CGSize(width: 0.14, height: 0.30)
        case .silkWake: return CGSize(width: 0.17, height: 0.34)
        case .quietDissolve: return CGSize(width: 0.12, height: 0.24)
        }
    }
}

/// Transparent SpriteKit layer that deforms the aligned cutout and leaves soft watercolor behind.
final class WelcomeSwimScene: SKScene {
    private let gridColumns = 4
    private let gridRows = 10
    private let variant: WelcomeSwimVariant
    private var sourcePositions: [SIMD2<Float>] = []
    private var warpableKoi: SKSpriteNode?
    private var canvasSize = CGSize.zero
    private var canvasCenter = CGPoint.zero
    private var wakeNodes: [SKSpriteNode] = []
    private var dissolveProgress: SKUniform?
    private var swimDuration: TimeInterval = 1

    /// Called on each scene update with normalized transition progress (0...1).
    /// The host uses this to reveal the live pond underneath the moving fish.
    var onProgress: ((Double) -> Void)?

    override init(size: CGSize) {
        variant = .swiftCurrent
        super.init(size: size)
        configureScene()
    }

    init(size: CGSize, variant: WelcomeSwimVariant) {
        self.variant = variant
        super.init(size: size)
        configureScene()
    }

    required init?(coder: NSCoder) {
        variant = .swiftCurrent
        super.init(coder: coder)
        configureScene()
    }

    func startSwimming(after delay: TimeInterval, duration: TimeInterval? = nil) {
        removeAction(forKey: "welcome-swim")
        stopWakeActions()
        swimDuration = max(0.1, duration ?? variant.duration)
        updateSwim(progress: 0)
        addWatercolorWake(after: delay, during: swimDuration)

        let wait = SKAction.wait(forDuration: max(0, delay))
        let swim = SKAction.customAction(withDuration: swimDuration) { [weak self] _, elapsed in
            guard let self else { return }
            self.updateSwim(progress: min(max(Double(elapsed) / self.swimDuration, 0), 1))
        }
        run(.sequence([wait, swim, .run { [weak self] in self?.updateSwim(progress: 1) }]), withKey: "welcome-swim")
    }

    func stopSwimming() {
        removeAction(forKey: "welcome-swim")
        removeAllActions()
        stopWakeActions()
        onProgress = nil
    }

    private func configureScene() {
        backgroundColor = .clear
        scaleMode = .resizeFill
        anchorPoint = .zero

        let scale = max(size.width / 1024, size.height / 1536)
        canvasSize = CGSize(width: 1024 * scale, height: 1536 * scale)
        let horizontalOverflow = max(0, canvasSize.width - size.width)
        canvasCenter = CGPoint(
            x: size.width / 2 - horizontalOverflow * 0.38,
            y: size.height / 2
        )

        // UIImage-backed textures retain the cutout's complete transparent canvas,
        // which keeps normalized mesh coordinates aligned with the hero artwork.
        guard let koiImage = UIImage(named: "WatercolorKoi") else { return }
        let koiTexture = SKTexture(image: koiImage)
        koiTexture.filteringMode = .linear
        let koi = SKSpriteNode(texture: koiTexture, size: canvasSize)
        koi.position = canvasCenter
        koi.zPosition = 1
        koi.subdivisionLevels = 1

        sourcePositions = makeGridPositions()
        koi.warpGeometry = SKWarpGeometryGrid(
            columns: gridColumns,
            rows: gridRows,
            sourcePositions: sourcePositions,
            destinationPositions: sourcePositions
        )
        if variant.dissolveStyle > 0 {
            let progressUniform = SKUniform(name: "u_progress", float: 0)
            let shader = SKShader(source: Self.dissolveShader, uniforms: [
                progressUniform,
                SKUniform(name: "u_style", float: variant.dissolveStyle),
                SKUniform(name: "u_start", float: variant.dissolveStart),
                SKUniform(name: "u_end", float: variant.dissolveEnd)
            ])
            koi.shader = shader
            dissolveProgress = progressUniform
        }

        warpableKoi = koi
        addChild(koi)
        createWakeNodes()
    }

    private func makeGridPositions() -> [SIMD2<Float>] {
        (0...gridRows).flatMap { row in
            (0...gridColumns).map { column in
                SIMD2<Float>(
                    Float(column) / Float(gridColumns),
                    Float(row) / Float(gridRows)
                )
            }
        }
    }

    private func updateSwim(progress: Double) {
        guard let warpableKoi else { return }
        let t = min(max(progress, 0), 1)
        let eased = t * t * (3 - 2 * t)
        let travelX = size.width * variant.travel.width
        let travelY = size.height * variant.travel.height
        let curve = sin(t * .pi) * size.width * variant.bend
        let recessionProgress = min(1, max(0, t / 0.40))
        let recessionEase = recessionProgress * recessionProgress * (3 - 2 * recessionProgress)
        let depthScale = variant.dissolveStyle > 0 ? 1 - 0.22 * CGFloat(recessionEase) : 1

        warpableKoi.position = CGPoint(
            x: canvasCenter.x + travelX * CGFloat(eased) + curve,
            y: canvasCenter.y + travelY * CGFloat(eased)
        )
        warpableKoi.setScale(depthScale)
        warpableKoi.zRotation = CGFloat(sin(t * .pi) * 0.055 - t * 0.08)
        warpableKoi.warpGeometry = SKWarpGeometryGrid(
            columns: gridColumns,
            rows: gridRows,
            sourcePositions: sourcePositions,
            destinationPositions: deformedPositions(progress: t)
        )
        dissolveProgress?.floatValue = Float(t)
        onProgress?(t)
    }

    private func deformedPositions(progress: Double) -> [SIMD2<Float>] {
        let ramp = min(1, progress * 3.8)
        return sourcePositions.map { point in
            let x = Double(point.x)
            let y = Double(point.y)
            let tailWeight = pow(1 - y, 1.3)
            let phase = progress * .pi * 7.2 - (1 - y) * .pi * 2.4
            let bodySweep = sin(phase) * 0.105 * tailWeight * ramp

            let finBand = exp(-pow((y - 0.70) / 0.17, 2))
            let finSide = x < 0.5 ? -1.0 : 1.0
            let finFlutter = sin(progress * .pi * 12 + x * 5)
                * 0.018 * finBand * abs(x - 0.5) * 2 * finSide * ramp

            let destinationX = x + bodySweep + finFlutter
            let destinationY = y + cos(phase) * tailWeight * 0.025 * ramp
            return SIMD2<Float>(Float(destinationX), Float(destinationY))
        }
    }

    private func createWakeNodes() {
        let texture = Self.makeWatercolorWashTexture(for: variant)
        let count: Int
        switch variant {
        case .swiftCurrent, .slowGlide: count = 8
        case .pigmentBloom, .silkWake, .quietDissolve: count = 6
        }

        for index in 0..<count {
            let wash = SKSpriteNode(texture: texture)
            let scale = CGFloat(index % 3)
            wash.size = CGSize(
                width: size.width * (0.24 + scale * 0.045),
                height: size.width * (0.15 + scale * 0.035)
            )
            wash.alpha = 0
            wash.zPosition = 0
            wakeNodes.append(wash)
            addChild(wash)
        }
    }

    private func addWatercolorWake(after delay: TimeInterval, during duration: TimeInterval) {
        guard !wakeNodes.isEmpty else { return }
        for (index, wash) in wakeNodes.enumerated() {
            wash.removeAllActions()
            wash.alpha = 0
            wash.setScale(0.62)

            let fraction = 0.08 + Double(index) / Double(wakeNodes.count) * 0.80
            let spawnDelay = max(0, delay + duration * fraction)
            let growth: CGFloat
            switch variant {
            case .quietDissolve: growth = 1.9
            case .pigmentBloom: growth = 1.65
            default: growth = 1.35
            }
            let placeWash = SKAction.run { [weak self, weak wash] in
                guard let self, let wash else { return }
                let point = self.pathPosition(progress: fraction)
                wash.position = CGPoint(
                    x: point.x - self.size.width * 0.07,
                    y: point.y - self.size.height * 0.18
                )
            }
            let hold = duration * (variant == .quietDissolve ? 0.26 : 0.18)
            let wakeOpacity: CGFloat = variant.dissolveStyle > 0
                ? 0.15
                : 0.48
            let fade = SKAction.sequence([
                .fadeAlpha(to: wakeOpacity, duration: 0.42),
                .wait(forDuration: hold),
                .fadeOut(withDuration: duration * 0.38)
            ])
            let spread = SKAction.scale(to: growth, duration: duration * 0.74)
            wash.run(
                .sequence([
                    .wait(forDuration: spawnDelay),
                    placeWash,
                    .group([fade, spread])
                ]),
                withKey: "watercolor-wake"
            )
        }
    }

    private func stopWakeActions() {
        wakeNodes.forEach { $0.removeAllActions() }
    }

    private func pathPosition(progress: Double) -> CGPoint {
        let t = min(max(progress, 0), 1)
        let eased = t * t * (3 - 2 * t)
        return CGPoint(
            x: canvasCenter.x + size.width * variant.travel.width * CGFloat(eased)
                + sin(t * .pi) * size.width * variant.bend,
            y: canvasCenter.y + size.height * variant.travel.height * CGFloat(eased)
        )
    }

    private static func makeWatercolorWashTexture(for variant: WelcomeSwimVariant) -> SKTexture {
        let canvas = CGSize(width: 320, height: 320)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: canvas, format: format).image { renderer in
            let context = renderer.cgContext
            let colorSpace = CGColorSpaceCreateDeviceRGB()

            let coral = UIColor(red: 0.89, green: 0.38, blue: 0.31, alpha: 0.19)
            let gold = UIColor(red: 0.80, green: 0.62, blue: 0.28, alpha: 0.15)
            let blue = UIColor(red: 0.32, green: 0.60, blue: 0.75, alpha: 0.06)
            let clear = UIColor(red: 0.56, green: 0.74, blue: 0.79, alpha: 0)

            func bloom(center: CGPoint, radius: CGFloat, color: UIColor) {
                let colors = [color.cgColor, color.withAlphaComponent(color.cgColor.alpha * 0.45).cgColor, clear.cgColor] as CFArray
                let locations: [CGFloat] = [0, 0.42, 1]
                guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) else {
                    return
                }
                context.drawRadialGradient(
                    gradient,
                    startCenter: center,
                    startRadius: radius * 0.06,
                    endCenter: center,
                    endRadius: radius,
                    options: []
                )
            }

            // Off-center blooms overlap into a single soft, irregular wash rather
            // than reading as separate bubbles or particles.
            bloom(center: CGPoint(x: 130, y: 154), radius: 150, color: blue)
            bloom(center: CGPoint(x: 202, y: 122), radius: 118, color: coral)
            bloom(center: CGPoint(x: 104, y: 218), radius: 104, color: gold)
            bloom(center: CGPoint(x: 228, y: 218), radius: 92, color: variant.rawValue == WelcomeSwimVariant.silkWake.rawValue ? blue : coral)
            bloom(center: CGPoint(x: 164, y: 176), radius: 76, color: blue)
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }

    private static let dissolveShader = """
    float hash21(vec2 p) {
        p = fract(p * vec2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }

    float noise21(vec2 p) {
        vec2 i = floor(p);
        vec2 f = fract(p);
        f = f * f * (3.0 - 2.0 * f);
        float a = hash21(i);
        float b = hash21(i + vec2(1.0, 0.0));
        float c = hash21(i + vec2(0.0, 1.0));
        float d = hash21(i + vec2(1.0, 1.0));
        return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
    }

    void main() {
        vec4 color = texture2D(u_texture, v_tex_coord);
        float phase = clamp((u_progress - u_start) / max(0.001, u_end - u_start), 0.0, 1.0);
        vec2 uv = v_tex_coord;
        float grain = noise21(uv * vec2(42.0, 34.0) + u_progress * 3.1);
        float cloud = noise21(uv * vec2(13.0, 18.0) - u_progress * 1.7);
        float field;

        if (u_style < 1.5) {
            // The painted tail is at the lower-left; lift pigment toward the head.
            field = uv.x * 0.54 + uv.y * 0.46 + (grain - 0.5) * 0.16;
        } else if (u_style < 2.5) {
            // Narrow, gently wavering fronts let the tail shed painted ribbons.
            field = uv.x * 0.48 + uv.y * 0.52 + (cloud - 0.5) * 0.12;
        } else {
            // A broken pigment front forms soft islands that merge as it spreads.
            float direction = uv.x * 0.36 + uv.y * 0.34;
            field = direction + cloud * 0.25 + grain * 0.17;
        }

        float threshold = phase * 1.45 - 0.14;
        float softEdge = u_style > 2.5 ? 0.16 : 0.105;
        float pigment = smoothstep(threshold - softEdge, threshold + softEdge, field);
        float lifting = smoothstep(0.015, 0.30, phase);
        float tail = 1.0 - smoothstep(0.08, 0.82, uv.y);

        // Bleed is sampled from the cutout and advected into nearby paper. The
        // taps carry the original coral/gold pigment and premultiplied alpha;
        // each style moves them along a different, noise-broken current.
        float spread = mix(0.004, 0.052, lifting);
        vec2 turbulence = vec2(
            noise21(uv * 17.0 + u_progress * 1.9),
            noise21(uv * 21.0 - u_progress * 1.4)
        ) - 0.5;
        vec2 flow = normalize(vec2(-0.70, -0.72) + turbulence * 0.42);
        vec4 bleed = vec4(0.0);
        float bleedStrength = 0.0;

        if (u_style < 1.5) {
            vec2 bloomOffset = flow * spread * (0.55 + cloud * 0.9);
            bleed += texture2D(u_texture, clamp(uv - bloomOffset * 0.7, vec2(0.0), vec2(1.0)));
            bleed += texture2D(u_texture, clamp(uv - bloomOffset * 1.4, vec2(0.0), vec2(1.0)));
            bleed += texture2D(u_texture, clamp(uv - bloomOffset * 2.2, vec2(0.0), vec2(1.0)));
            bleed /= 3.0;
            bleedStrength = lifting * (0.10 + tail * 0.30) * (0.55 + cloud * 0.45);
        } else if (u_style < 2.5) {
            vec2 ribbon = normalize(vec2(-0.82, -0.57) + turbulence * 0.18);
            vec2 crossFlow = vec2(-ribbon.y, ribbon.x);
            vec2 bend = crossFlow * sin(uv.y * 19.0 + u_progress * 8.0) * spread * 0.42;
            bleed += texture2D(u_texture, clamp(uv - ribbon * spread * 1.0 + bend, vec2(0.0), vec2(1.0)));
            bleed += texture2D(u_texture, clamp(uv - ribbon * spread * 2.2 - bend * 0.6, vec2(0.0), vec2(1.0)));
            bleed += texture2D(u_texture, clamp(uv - ribbon * spread * 3.6 + bend * 0.45, vec2(0.0), vec2(1.0)));
            bleed /= 3.0;
            bleedStrength = lifting * (0.08 + tail * 0.34) * (0.60 + cloud * 0.30);
        } else {
            vec2 islandA = (vec2(grain, cloud) - 0.5) * spread * 3.5;
            vec2 islandB = (vec2(cloud, 1.0 - grain) - 0.5) * spread * 5.2;
            bleed += texture2D(u_texture, clamp(uv - flow * spread + islandA, vec2(0.0), vec2(1.0)));
            bleed += texture2D(u_texture, clamp(uv - flow * spread * 2.0 + islandB, vec2(0.0), vec2(1.0)));
            bleed += texture2D(u_texture, clamp(uv - flow * spread * 3.2 - islandA * 0.7, vec2(0.0), vec2(1.0)));
            bleed /= 3.0;
            float islands = smoothstep(0.30, 0.78, grain * 0.58 + cloud * 0.42);
            bleedStrength = lifting * (0.06 + islands * 0.22) * (0.65 + tail * 0.20);
        }

        color *= pigment;
        bleed *= bleedStrength;
        color.rgb += bleed.rgb;
        color.a += bleed.a;
        color.rgb = min(color.rgb, vec3(color.a));
        gl_FragColor = color * (1.0 - smoothstep(0.72, 1.0, phase));
    }
    """
}
