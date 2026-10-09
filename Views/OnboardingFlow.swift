import SwiftUI
import SpriteKit
import Contacts
import ContactsUI

// MARK: - First-Run Introduction
/// Introduces the product and makes the interactive sample-tour choice explicit.
struct OnboardingSignInOverlay: View {
    @EnvironmentObject var dataManager: GoldfishDataManager
    @EnvironmentObject var walkthroughManager: FeatureWalkthroughManager
    @EnvironmentObject var demoModeManager: DemoModeManager

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showPrivacy = false
    @State private var onboardingError: String?
    @Environment(\.colorSchemeContrast) private var accessibilityContrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var wordmarkFontSize: CGFloat = 56
    @State private var heroArtworkOpacity = 1.0
    @State private var welcomeContentOpacity = 1.0
    @State private var swimSceneOpacity = 0.0
    @State private var scrimOpacity = 1.0
    @State private var swimScene: WelcomeSwimScene?
    @State private var isTransitioning = false
    @State private var transitionTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.98, green: 0.965, blue: 0.935)
                let artLayout = artworkLayout(for: geometry.size)
                artworkBackdrop(size: geometry.size, artLayout: artLayout)

                ScrollView {
                    welcomeContent(for: geometry.size)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: max(0, geometry.size.height - welcomeTopClearance - welcomeBottomClearance),
                            alignment: .bottom
                        )
                        .padding(.top, welcomeTopClearance)
                        .padding(.bottom, welcomeBottomClearance)
                }
                .scrollIndicators(.hidden)
                .opacity(welcomeContentOpacity)
                .allowsHitTesting(!isTransitioning)
                .accessibilityHidden(isTransitioning)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .onDisappear {
                transitionTask?.cancel()
                transitionTask = nil
                swimScene?.stopSwimming()
            }
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showPrivacy) {
            NavigationStack {
                PrivacyPolicyView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showPrivacy = false } } }
            }
        }
        .alert("Could not get started", isPresented: Binding(
            get: { onboardingError != nil }, set: { if !$0 { onboardingError = nil } }
        )) {
            Button("Remove Sample Data", role: .destructive) {
                if demoModeManager.removeDemoData(dataManager: dataManager) {
                    walkthroughManager.isDemoDataSeeded = false
                    onboardingError = nil
                } else {
                    let message = demoModeManager.demoErrorMessage
                        ?? "Couldn’t remove sample contacts. Try again."
                    onboardingError = nil
                    Task { @MainActor in
                        await Task.yield()
                        onboardingError = message
                    }
                }
            }
            Button("OK", role: .cancel) { onboardingError = nil }
        } message: { Text(onboardingError ?? "") }
        #if DEBUG
        // Headless-verification hook: `SIMCTL_CHILD_GF_AUTO_ONBOARD=1 simctl launch …`
        // completes the sign-in step without a tap so CI/agents can reach the app.
        .onAppear {
            if ProcessInfo.processInfo.environment["GF_AUTO_ONBOARD"] == "1" {
                startPersonalPond()
            }
        }
        #endif
    }

    private var welcomeTopClearance: CGFloat { 64 }
    private var welcomeBottomClearance: CGFloat { 52 }

    private struct ArtworkLayout {
        let size: CGSize
        let center: CGPoint
    }

    private func artworkLayout(for viewport: CGSize) -> ArtworkLayout {
        let scale = max(viewport.width / 1024, viewport.height / 1536)
        let artworkSize = CGSize(width: 1024 * scale, height: 1536 * scale)
        let horizontalOverflow = max(0, artworkSize.width - viewport.width)
        return ArtworkLayout(
            size: artworkSize,
            center: CGPoint(
                x: viewport.width / 2 - horizontalOverflow * 0.38,
                y: viewport.height / 2
            )
        )
    }

    private func artworkBackdrop(size: CGSize, artLayout: ArtworkLayout) -> some View {
        ZStack {
            Image("WatercolorHero")
                .resizable()
                .interpolation(.high)
                .frame(width: artLayout.size.width, height: artLayout.size.height)
                .position(artLayout.center)
                .opacity(heroArtworkOpacity)

            if let swimScene {
                SpriteView(scene: swimScene, options: [.allowsTransparency])
                    .frame(width: size.width, height: size.height)
                    .opacity(swimSceneOpacity)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(dynamicTypeSize.isAccessibilitySize ? 0.70 : 0), location: 0),
                    .init(color: .black.opacity(dynamicTypeSize.isAccessibilitySize ? 0.72 : 0.08), location: 0.28),
                    .init(color: .black.opacity(0.65), location: 0.55),
                    .init(color: .black.opacity(0.78), location: 0.70),
                    .init(color: .black.opacity(0.85), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(scrimOpacity)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private func welcomeContent(for size: CGSize) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: dynamicTypeSize.isAccessibilitySize ? 80 : 110)

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
                .foregroundStyle(GoldfishDS.cream.opacity(0.88))
                .padding(.top, 4)

            Button {
                beginWelcomeTransition(for: size, action: exploreSample)
            } label: {
                Text("EXPLORE A SAMPLE")
                    .font(.gfLabel)
                    .kerning(1.6)
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 12)
                    .frame(minHeight: 52)
                    .background(
                        RoundedRectangle(cornerRadius: GoldfishDS.Radius.control)
                            .fill(GoldfishDS.cream)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 24)
            .accessibilityIdentifier("startSampleTourButton")
            .accessibilityHint("Opens real sample contacts and a guided tour. You can end the tour at any time.")
            .disabled(isTransitioning)

            Button {
                beginWelcomeTransition(for: size, action: startPersonalPond)
            } label: {
                Text("START MY POND")
                    .font(.gfLabel)
                    .kerning(1.4)
                    .foregroundStyle(GoldfishDS.cream)
                    .frame(maxWidth: .infinity)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 12)
                    .frame(minHeight: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: GoldfishDS.Radius.control)
                            .strokeBorder(
                                GoldfishDS.cream.opacity(accessibilityContrast == .increased ? 1 : 0.82),
                                lineWidth: accessibilityContrast == .increased ? 1.5 : 1
                            )
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
            .accessibilityIdentifier("startPersonalPondButton")
            .accessibilityHint("Starts with an empty personal pond and does not create sample contacts.")
            .disabled(isTransitioning)

            Text("Your contacts stay stored on this device.")
                .font(.gfMeta)
                .foregroundStyle(GoldfishDS.cream.opacity(0.82))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 18)

            Button("Privacy & Your Data") { showPrivacy = true }
                .font(.gfMeta)
                .foregroundStyle(GoldfishDS.cream.opacity(0.92))
                .frame(minHeight: 44)
                .padding(.top, 4)
                .disabled(isTransitioning)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
    }

    private func beginWelcomeTransition(for size: CGSize, action: @escaping () -> Void) {
        guard !isTransitioning else { return }
        isTransitioning = true

        let duration = reduceMotion ? 0.24 : welcomeSwimDuration
        let crossfadeDuration = reduceMotion ? duration : 0.20
        withAnimation(.easeInOut(duration: reduceMotion ? duration : duration * 0.4)) {
            scrimOpacity = 0
        }

        if reduceMotion {
            withAnimation(.easeOut(duration: duration)) {
                welcomeContentOpacity = 0
                heroArtworkOpacity = 0
            }
        } else {
            let scene = WelcomeSwimScene(size: size)
            scene.startSwimming(after: crossfadeDuration, duration: duration - crossfadeDuration)
            swimScene = scene
            withAnimation(.easeInOut(duration: crossfadeDuration)) {
                welcomeContentOpacity = 0
                heroArtworkOpacity = 0
                swimSceneOpacity = 1
            }
        }

        transitionTask?.cancel()
        transitionTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            action()
            guard onboardingError != nil else { return }

            swimScene?.stopSwimming()
            transitionTask = nil
            withAnimation(.easeInOut(duration: 0.24)) {
                isTransitioning = false
                welcomeContentOpacity = 1
                heroArtworkOpacity = 1
                scrimOpacity = 1
                swimSceneOpacity = 0
                swimScene = nil
            }
        }
    }

    private var welcomeSwimDuration: TimeInterval {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--welcome-swim-slow") ? 3.2 : 1.8
        #else
        return 1.8
        #endif
    }

    private func exploreSample() {
        completeProfileIfNeeded()
        guard onboardingError == nil else { return }
        walkthroughManager.isDemoDataSeeded = false
        guard demoModeManager.activateDemoMode(dataManager: dataManager) else {
            onboardingError = demoModeManager.demoErrorMessage ?? "Couldn’t load sample contacts. Try again."
            return
        }
        hasCompletedOnboarding = true
    }

    private func startPersonalPond() {
        completeProfileIfNeeded()
        guard onboardingError == nil else { return }
        demoModeManager.deactivateDemoMode()
        walkthroughManager.completeOnboardingWithoutWalkthrough()
        hasCompletedOnboarding = true
    }

    private func completeProfileIfNeeded() {
        onboardingError = nil
        do {
            if try dataManager.fetchMePerson() == nil {
                try dataManager.performOnboarding(name: "Me")
            }
        } catch {
            print("Onboarding setup error: \(error)")
            onboardingError = error.localizedDescription
        }
    }
}

// MARK: - Contact Picker Wrapper
struct ContactPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onContactsSelected: ([CNContact]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    class Coordinator: NSObject, CNContactPickerDelegate {
        var parent: ContactPicker

        init(_ parent: ContactPicker) {
            self.parent = parent
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            parent.onContactsSelected(contacts)
            parent.isPresented = false
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            parent.isPresented = false
        }
    }
}
