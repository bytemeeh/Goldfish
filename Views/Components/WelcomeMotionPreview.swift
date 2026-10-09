#if DEBUG
import SwiftUI
import SpriteKit

/// A temporary first-run surface over the in-memory sample pond. It lets the
/// welcome transition be reviewed from the real Home screen without changing
/// the normal onboarding route or any saved data.
struct WelcomeMotionPreview: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let variant: WelcomeSwimVariant
    let autoplay: Bool

    @ScaledMetric(relativeTo: .largeTitle) private var wordmarkFontSize: CGFloat = 56
    @State private var progress: CGFloat = 0
    @State private var isTransitioning = false
    @State private var isFinishing = false
    @State private var isVisible = true
    @State private var swimScene: WelcomeSwimScene?
    @State private var autoplayTask: Task<Void, Never>?
    @State private var completionTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.98, green: 0.965, blue: 0.935)
                    .opacity(backgroundOpacity)

                heroArtwork(in: geometry.size)
                    .opacity(heroOpacity)

                if let swimScene {
                    SpriteView(scene: swimScene, options: [.allowsTransparency])
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .opacity(fishOpacity)
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }

                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.02), location: 0),
                        .init(color: .black.opacity(0.12), location: 0.30),
                        .init(color: .black.opacity(0.62), location: 0.58),
                        .init(color: .black.opacity(0.84), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .opacity(scrimOpacity)
                .accessibilityHidden(true)

                welcomeContent(size: geometry.size, safeAreaInsets: geometry.safeAreaInsets)
                    .opacity(contentOpacity)
                    .allowsHitTesting(!isTransitioning)
                    .accessibilityHidden(isTransitioning)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .accessibilityAddTraits(.isModal)
            .onAppear { scheduleAutoplay(size: geometry.size) }
            .onDisappear(perform: cancelTasksAndScene)
        }
        .ignoresSafeArea()
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .accessibilityHidden(!isVisible)
        .animation(.easeOut(duration: 0.16), value: isVisible)
    }

    private var heroOpacity: Double {
        Double(1 - min(progress / 0.20, 1))
    }

    private var fishOpacity: Double {
        max(0.001, Double(min(progress / 0.20, 1)))
    }

    private var backgroundOpacity: Double {
        let fade = min(max((progress - 0.18) / 0.62, 0), 1)
        return Double(1 - fade)
    }

    private var scrimOpacity: Double {
        let fade = min(max((progress - 0.08) / 0.42, 0), 1)
        return Double(1 - fade)
    }

    private var contentOpacity: Double {
        guard isTransitioning else { return 1 }
        return Double(1 - min(progress / 0.12, 1))
    }

    private func heroArtwork(in viewport: CGSize) -> some View {
        let scale = max(viewport.width / 1024, viewport.height / 1536)
        let artworkSize = CGSize(width: 1024 * scale, height: 1536 * scale)
        let horizontalOverflow = max(0, artworkSize.width - viewport.width)
        let center = CGPoint(
            x: viewport.width / 2 - horizontalOverflow * 0.38,
            y: viewport.height / 2
        )

        return Image("WatercolorHero")
            .resizable()
            .interpolation(.high)
            .frame(width: artworkSize.width, height: artworkSize.height)
            .position(center)
            .frame(width: viewport.width, height: viewport.height)
            .clipped()
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    private func welcomeContent(size: CGSize, safeAreaInsets: EdgeInsets) -> some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                Text("PREVIEW \(variant.rawValue) · \(variant.title.uppercased())")
                    .font(.gfCaption.weight(.medium))
                    .kerning(0.7)
                    .foregroundStyle(GoldfishDS.cream)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.black.opacity(0.40), in: Capsule())
                    .accessibilityLabel("Motion preview \(variant.rawValue): \(variant.title)")
            }
            .padding(.top, max(64, safeAreaInsets.top + 8))

            Spacer(minLength: 64)

            (
                Text("Gold")
                    .foregroundColor(GoldfishDS.cream)
                + Text("fish")
                    .italic()
                    .foregroundColor(GoldfishDS.cream)
            )
            .font(.system(size: wordmarkFontSize, weight: .thin, design: .default))
            .accessibilityLabel("Goldfish")

            Text("Remember everyone")
                .font(.system(.title3, design: .default).weight(.light))
                .foregroundStyle(GoldfishDS.cream.opacity(0.90))
                .padding(.top, 4)

            VStack(spacing: 10) {
                Button { beginTransition(size: size) } label: {
                    Text("EXPLORE A SAMPLE")
                        .font(.gfLabel)
                        .kerning(1.6)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .frame(minHeight: 52)
                        .background(GoldfishDS.cream, in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("previewSampleTransitionButton")

                Button { beginTransition(size: size) } label: {
                    Text("START MY POND")
                        .font(.gfLabel)
                        .kerning(1.4)
                        .foregroundStyle(GoldfishDS.cream)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .frame(minHeight: 52)
                        .overlay(
                            RoundedRectangle(cornerRadius: GoldfishDS.Radius.control)
                                .strokeBorder(GoldfishDS.cream.opacity(0.84), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("previewPersonalPondTransitionButton")
            }
            .padding(.top, 24)

            Text("Your contacts stay stored on this device.")
                .font(.gfMeta)
                .foregroundStyle(GoldfishDS.cream.opacity(0.82))
                .multilineTextAlignment(.center)
                .padding(.top, 18)

            Spacer(minLength: max(52, safeAreaInsets.bottom + 16))
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func scheduleAutoplay(size: CGSize) {
        if !reduceMotion, swimScene == nil {
            swimScene = WelcomeSwimScene(size: size, variant: variant)
        }
        guard autoplay else { return }
        autoplayTask?.cancel()
        autoplayTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 2_500_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            beginTransition(size: size)
        }
    }

    private func beginTransition(size: CGSize) {
        guard !isTransitioning, isVisible else { return }
        isTransitioning = true
        autoplayTask?.cancel()
        autoplayTask = nil

        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.42)) {
                progress = 1
            }
            completionTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 460_000_000)
                finishPreview()
            }
            return
        }

        let scene = swimScene ?? WelcomeSwimScene(size: size, variant: variant)
        scene.onProgress = { value in
            DispatchQueue.main.async {
                guard isTransitioning, isVisible else { return }
                progress = min(max(value, 0), 1)
                if progress >= 1 {
                    finishPreview()
                }
            }
        }
        swimScene = scene
        scene.startSwimming(after: 0.20, duration: variant.duration)

        // Keep removal bounded if SpriteKit stops sending progress while the
        // app is backgrounded or its view is replaced.
        completionTask?.cancel()
        completionTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: UInt64((variant.duration + 1.0) * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            finishPreview()
        }
    }

    private func finishPreview() {
        guard isTransitioning, isVisible, !isFinishing else { return }
        isFinishing = true
        swimScene?.stopSwimming()
        completionTask?.cancel()
        completionTask = nil
        withAnimation(.easeOut(duration: 0.16)) {
            isVisible = false
        }
    }

    private func cancelTasksAndScene() {
        autoplayTask?.cancel()
        autoplayTask = nil
        completionTask?.cancel()
        completionTask = nil
        swimScene?.stopSwimming()
        swimScene = nil
    }
}
#endif
