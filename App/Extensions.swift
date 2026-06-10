import SwiftUI
import SwiftData

// MARK: - Color Hex Initializer (String)
extension Color {
    /// Initialize Color from hex string (e.g. "#FF0000" or "FF0000").
    /// Canonical definition — used across the entire app.
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 128, 128, 128)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// Convert a Color back to its hex string representation.
    func toHex() -> String? {
        let uic = UIColor(self)
        guard let components = uic.cgColor.components, components.count >= 3 else {
            return nil
        }
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        var a = Float(1.0)

        if components.count >= 4 {
            a = Float(components[3])
        }

        if a != 1.0 {
            return String(format: "#%02lX%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255), lroundf(a * 255))
        } else {
            return String(format: "#%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
        }
    }
}

// MARK: - DataManager Preview Helper
extension GoldfishDataManager {
    /// Creates a preview instance with in-memory storage.
    /// Uses GoldfishModelContainer.preview() to avoid duplicating the schema list.
    @MainActor
    static func preview() -> GoldfishDataManager {
        do {
            let container = try GoldfishModelContainer.preview()
            return GoldfishDataManager(context: container.mainContext)
        } catch {
            fatalError("Failed to create preview container: \(error)")
        }
    }
}

// MARK: - Toast Manager
/// Singleton manager to trigger toast messages across the app acting like the web demo's showToast(msg).
@MainActor
class ToastManager: ObservableObject {
    static let shared = ToastManager()
    
    @Published var message: String?
    @Published var isShowing: Bool = false
    
    private var dismissTask: Task<Void, Never>?
    
    func showToast(message: String) {
        // Cancel any pending dismiss
        dismissTask?.cancel()
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            self.message = message
            self.isShowing = true
        }

        // Announce the toast so VoiceOver users hear the feedback
        UIAccessibility.post(notification: .announcement, argument: message)
        
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                self.isShowing = false
            }
        }
    }
}

// MARK: - Toast Modifier
struct ToastModifier: ViewModifier {
    @EnvironmentObject var manager: ToastManager
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if manager.isShowing, let message = manager.message {
                    Text(message)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
                        .padding(.bottom, 40)
                        // Transition
                        .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
                        .zIndex(9999)
                }
            }
    }
}

// MARK: - View Extension
public extension View {
    /// Applies the global toast overlay
    func toastOverlay() -> some View {
        self.modifier(ToastModifier())
    }
    
    /// Applies the feature walkthrough overlay
    func walkthroughOverlay() -> some View {
        self.modifier(WalkthroughOverlayModifier())
    }
    

}

// MARK: - Walkthrough Overlay Modifier
struct WalkthroughOverlayModifier: ViewModifier {
    @EnvironmentObject var walkthroughManager: FeatureWalkthroughManager
    
    func body(content: Content) -> some View {
        content
            .overlay {
                if walkthroughManager.isActive {
                    WalkthroughOverlayView()
                        .transition(AnyTransition.opacity.combined(with: AnyTransition.scale(scale: 0.95)))
                        .zIndex(10000)
                }
            }
    }
}

// MARK: - Walkthrough Overlay View
struct WalkthroughOverlayView: View {
    @EnvironmentObject var walkthroughManager: FeatureWalkthroughManager
    @EnvironmentObject var demoModeManager: DemoModeManager
    @EnvironmentObject var dataManager: GoldfishDataManager

    @State private var dragOffset: CGFloat = 0
    // P0-5 Fix: State to show post-onboarding prompt
    @State private var showDemoDataPrompt = false

    private var step: WalkthroughStep { walkthroughManager.currentStep }
    private var showingSuccess: Bool { walkthroughManager.showingStepSuccess }

    var body: some View {
        ZStack {
            // Transparent background — there is intentionally NO dimming
            // layer, so the real UI stays fully usable during interactive
            // steps (tapping +, dragging fish into ponds, etc.)
            Color.clear
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Spotlight ring around the anchored target (e.g. the + button)
            if step.isInteractive && !showingSuccess,
               let frame = walkthroughManager.anchorFrames[step],
               frame != .zero {
                WalkthroughSpotlightRing(targetFrame: frame)
            }

            VStack {
                // Spacer fills the top area — passes touches through
                Spacer()
                    .allowsHitTesting(false)

                // The actual "Tile" card
                VStack(spacing: 20) {
                    // Header: Icon + Close Button
                    HStack {
                        Image(systemName: showingSuccess ? "checkmark.circle.fill" : step.icon)
                            .font(.title2)
                            .foregroundColor(showingSuccess ? .green : .goldfishAccent)

                        Spacer()

                        // P1-6 Fix: Use X icon instead of ambiguous Skip text
                        // Always reachable, even mid-interactive-step.
                        Button(action: { showDemoDataPrompt = true }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .accessibilityLabel("End tour")
                    }
                    .padding(.horizontal, 4)

                    // Title + Description (or success acknowledgment)
                    // P0-4 Fix: Uniform height for the text container
                    VStack(alignment: .leading, spacing: 8) {
                        Text(showingSuccess ? "Nailed it!" : step.title)
                            .font(.title3.bold())
                            .foregroundColor(.white)

                        // P1-3 Fix: Use ScrollView for fluid typography
                        ScrollView(.vertical, showsIndicators: false) {
                            Text(showingSuccess ? step.successMessage : step.description)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Lock the height so cards don't change size
                    .frame(height: 90, alignment: .top)

                    controls
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(Color(red: 0x2A/255, green: 0x24/255, blue: 0x20/255))
                        .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
                .offset(x: dragOffset)
                // Swipe navigation only applies to passive steps —
                // interactive steps advance when the real action completes.
                .gesture(dragGesture, including: step.isInteractive ? .subviews : .all)
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: walkthroughManager.currentStep)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: walkthroughManager.showingStepSuccess)
        .alert("Complete Setup", isPresented: $showDemoDataPrompt) {
            Button("Keep Demo Data") {
                walkthroughManager.finishTour(keepDemoData: true)
                walkthroughManager.currentStep = .complete
            }
            Button("Start Fresh (Empty)", role: .destructive) {
                // Remove demo data and transition out
                demoModeManager.removeDemoData(dataManager: dataManager)
                walkthroughManager.finishTour(keepDemoData: false)
                walkthroughManager.currentStep = .complete
            }
        } message: {
            Text("The tour pond uses sample contacts, relationships, and ponds. Keep them to explore, or start with a blank slate — contacts you added yourself are kept either way.")
        }
    }

    // MARK: Controls

    @ViewBuilder private var controls: some View {
        if step.isInteractive {
            // Interactive step: the real UI is the "Next button".
            // Offer only an escape hatch so the step can't soft-lock.
            HStack {
                dots

                Spacer(minLength: 8)

                Button(action: { walkthroughManager.skipCurrentStep() }) {
                    Text("Skip this step")
                        .font(.subheadline.bold())
                        .foregroundColor(.white.opacity(0.7))
                        .frame(height: 44)
                        .padding(.horizontal, 16)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .disabled(showingSuccess)
                .opacity(showingSuccess ? 0.4 : 1)
            }
        } else {
            // Passive step: classic Back / dots / Next navigation
            HStack(spacing: 0) {
                // Left Button Container (Back)
                if step != .welcome {
                    Button(action: { walkthroughManager.previousStep() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .frame(width: 110, height: 44)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    }
                } else {
                    // Invisible placeholder to maintain exact symmetry
                    Color.clear.frame(width: 110, height: 44)
                }

                Spacer(minLength: 8)

                dots

                Spacer(minLength: 8)

                // Right Button Container (Next / Get Started)
                Button(action: {
                    if step == .complete {
                        showDemoDataPrompt = true
                    } else {
                        walkthroughManager.nextStep()
                    }
                }) {
                    HStack(spacing: 4) {
                        if step == .complete {
                            Text("Get Started")
                        } else {
                            Text("Next")
                            Image(systemName: "chevron.right")
                        }
                    }
                    .font(.subheadline.bold())
                    .foregroundColor(.black)
                    .frame(width: 110, height: 44)
                    .background(Color.goldfishAccent)
                    .cornerRadius(12)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(WalkthroughStep.displayableSteps) { dotStep in
                Circle()
                    .fill(step == dotStep ? Color.goldfishAccent : Color.white.opacity(0.2))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { gesture in
                dragOffset = gesture.translation.width
            }
            .onEnded { gesture in
                if gesture.translation.width < -100 {
                    // Never swipe forward past an interactive step
                    if step != WalkthroughStep.displayableSteps.last && !step.isInteractive {
                        walkthroughManager.nextStep()
                    }
                } else if gesture.translation.width > 100 {
                    walkthroughManager.previousStep()
                }
                withAnimation(.spring()) {
                    dragOffset = 0
                }
            }
    }
}

// MARK: - Walkthrough Spotlight Ring
/// A pulsing ring drawn over the frame reported by `.walkthroughAnchor(step:)`
/// to point the user at the control an interactive step asks them to use.
/// Never intercepts touches.
private struct WalkthroughSpotlightRing: View {
    let targetFrame: CGRect
    @State private var pulse = false

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let diameter = max(targetFrame.width, targetFrame.height) + 16
            Circle()
                .stroke(Color.goldfishAccent, lineWidth: 3)
                .frame(width: diameter, height: diameter)
                .scaleEffect(pulse ? 1.2 : 0.95)
                .opacity(pulse ? 0.35 : 1.0)
                .position(
                    x: targetFrame.midX - origin.x,
                    y: targetFrame.midY - origin.y
                )
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

// MARK: - Identifiable Wrapper
public struct IdentifiableWrapper<T: Equatable>: Identifiable, Equatable {
    public let id: UUID
    public let value: T
    
    public init(_ value: T) {
        self.id = UUID()
        self.value = value
    }
}


// MARK: - UUID Identifiable
