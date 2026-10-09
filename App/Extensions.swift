import SwiftUI
import SwiftData
import Darwin

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
    @Published var actionTitle: String?
    private var action: (() -> Void)?

    private var dismissTask: Task<Void, Never>?

    func showToast(message: String) {
        showToast(message: message, actionTitle: nil, action: nil)
    }

    func showToast(message: String, actionTitle: String?, action: (() -> Void)?) {
        // Cancel any pending dismiss
        dismissTask?.cancel()

        withAnimation(GoldfishDS.Motion.snappy) {
            self.message = message
            self.actionTitle = actionTitle
            self.action = action
            let announcement = actionTitle.map { "\(message). \($0) is available until dismissed." } ?? message
            UIAccessibility.post(notification: .announcement, argument: announcement)
            self.isShowing = true
        }

        dismissTask = Task {
            guard actionTitle == nil else { return }
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(GoldfishDS.Motion.snappy) {
                self.isShowing = false
                self.actionTitle = nil
                self.action = nil
            }
        }
    }

    /// Executes and clears the current toast action before invoking it. The
    /// callback may present a replacement toast (for example, "Connection
    /// undone"), so clearing first prevents the old toast from hiding it.
    func performAction() {
        let callback = action
        action = nil
        actionTitle = nil
        withAnimation(GoldfishDS.Motion.snappy) { isShowing = false }
        callback?()
    }

    func dismissToast() {
        dismissTask?.cancel()
        action = nil
        actionTitle = nil
        withAnimation(GoldfishDS.Motion.snappy) { isShowing = false }
    }
}

// MARK: - Toast Modifier
struct ToastModifier: ViewModifier {
    @EnvironmentObject var manager: ToastManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if manager.isShowing, let message = manager.message {
                    let layout = dynamicTypeSize >= .xxLarge
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                        : AnyLayout(HStackLayout(spacing: 12))
                    layout {
                        Text(message)
                            .fixedSize(horizontal: false, vertical: true)
                        if let actionTitle = manager.actionTitle {
                            Button(actionTitle) {
                                manager.performAction()
                            }
                            .font(.gfMeta.weight(.semibold))
                            .foregroundStyle(GoldfishDS.terracotta)
                            .frame(minWidth: 60, minHeight: 44)
                        }
                        Button {
                            manager.dismissToast()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.semibold))
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Dismiss")
                        .foregroundStyle(GoldfishDS.ink(.secondary))
                    }
                        .font(.gfMeta)
                        .foregroundStyle(GoldfishDS.ink(.primary))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: GoldfishDS.Radius.control)
                                .fill(GoldfishDS.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: GoldfishDS.Radius.control)
                                .stroke(GoldfishDS.ink(.hairline), lineWidth: GoldfishDS.Rule.hairline)
                        )
                        .padding(.bottom, 40)
                        .padding(.horizontal, 16)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
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
    func walkthroughOverlay(isPresented: Bool = true) -> some View {
        self.modifier(WalkthroughOverlayModifier(isPresented: isPresented))
    }
    

}

// MARK: - Walkthrough Overlay Modifier
struct WalkthroughOverlayModifier: ViewModifier {
    var isPresented: Bool
    @EnvironmentObject var walkthroughManager: FeatureWalkthroughManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var targetFrames: [WalkthroughStep: CGRect] = [:]

    func body(content: Content) -> some View {
        content
            .overlay {
                if walkthroughManager.isActive && isPresented {
                    WalkthroughOverlayView(targetFrames: targetFrames)
                        // Trains, not water: the card slides in along a straight
                        // track. Reduce Motion = fade only.
                        .transition(
                            reduceMotion
                                ? AnyTransition.opacity
                                : AnyTransition.move(edge: .bottom).combined(with: .opacity)
                        )
                        .zIndex(10000)
                }
            }
            .onPreferenceChange(WalkthroughAnchorKey.self) { frames in
                targetFrames = frames
            }
    }
}

// MARK: - Reusable inline walkthrough guide

/// The same compact guide used by the home overlay and by modal/search
/// surfaces. Only the explanatory body scrolls; the end, back, skip, and
/// continue controls stay visible at every text size.
struct WalkthroughInlineGuide: View {
    @EnvironmentObject private var walkthroughManager: FeatureWalkthroughManager
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var maximumHeight: CGFloat = 360
    var actionPromptOverride: String? = nil

    @State private var measuredBodyHeight: CGFloat = 0
    @State private var showEndChoice = false

    private var boundedMaximumHeight: CGFloat {
        guard maximumHeight.isFinite else { return 360 }
        return max(112, min(520, maximumHeight))
    }

    private var isCompact: Bool {
        boundedMaximumHeight < 200
    }

    private var bodyViewportHeight: CGFloat {
        let controlsAllowance: CGFloat = dynamicTypeSize.isAccessibilitySize ? 184 : (isCompact ? 109 : 132)
        let cap = max(40, boundedMaximumHeight - controlsAllowance)
        guard measuredBodyHeight > 0 else { return min(cap, isCompact ? 56 : 160) }
        return min(cap, max(40, measuredBodyHeight))
    }

    var body: some View {
        let step = walkthroughManager.currentStep

        VStack(spacing: 0) {
            Rectangle()
                .fill(barTone(for: step))
                .frame(height: GoldfishDS.Rule.bar)

            HStack(spacing: 8) {
                if !isCompact && !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: walkthroughManager.justCompletedStep ? "checkmark.circle.fill" : step.icon)
                        .font(.title3)
                        .foregroundStyle(walkthroughManager.justCompletedStep ? Color.goldfishSuccess : GoldfishDS.ink(.primary))

                    if step.isAction {
                        Text(walkthroughManager.justCompletedStep ? "DONE" : "TRY IT")
                            .font(.gfCaption)
                            .kerning(1)
                            .foregroundStyle(GoldfishDS.warmBlack)
                            .padding(.vertical, 3)
                            .padding(.horizontal, 7)
                            .background(GoldfishDS.ink(.primary), in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.chip))
                    }
                }

                Text(progressLabel(for: step))
                    .font(.gfMeta)
                    .foregroundStyle(GoldfishDS.ink(.tertiary))
                    .accessibilityLabel(step == .welcome ? "Tour introduction" : "Action \(WalkthroughStep.displayableSteps.firstIndex(of: step) ?? 1) of 3")
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 8)

                Button("End") { showEndChoice = true }
                    .font(.gfMeta)
                    .foregroundStyle(GoldfishDS.ink(.secondary))
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("End feature tour")
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 20)
            .padding(.top, isCompact ? 0 : 8)
            .frame(minHeight: isCompact ? 44 : 52)

            ScrollView(.vertical) {
                Group {
                if isCompact && step == .search {
                    Text(walkthroughManager.justCompletedStep
                         ? walkthroughManager.successDescription
                         : "Find \(walkthroughManager.examplePersonName), then open the result.")
                        .font(.gfBody)
                        .foregroundStyle(GoldfishDS.ink(.primary))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        if let prompt = actionPromptOverride ?? walkthroughManager.currentActionPrompt,
                           !walkthroughManager.justCompletedStep {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "hand.tap.fill")
                                    .foregroundStyle(GoldfishDS.ink(.secondary))
                                Text(prompt)
                                    .font(.gfBody)
                                    .foregroundStyle(GoldfishDS.ink(.primary))
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 14)
                            .background(GoldfishDS.ink(.faint), in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
                        }

                        if !isCompact && !(boundedMaximumHeight < 300 && step.isAction && !walkthroughManager.justCompletedStep) {
                            Text(step.title)
                                .font(.gfBody.weight(.medium))
                                .foregroundStyle(GoldfishDS.ink(.primary))
                        }

                        if !(boundedMaximumHeight < 300 && step.isAction && !walkthroughManager.justCompletedStep) {
                        Text(walkthroughManager.justCompletedStep
                             ? walkthroughManager.successDescription
                             : walkthroughManager.currentDescription)
                            .font(.gfBody)
                            .foregroundStyle(GoldfishDS.ink(.secondary))
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, isCompact ? 0 : 20)
                .padding(.vertical, isCompact ? 0 : 20)
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { contentGeometry in
                        Color.clear.preference(
                            key: WalkthroughCardContentHeightKey.self,
                            value: contentGeometry.size.height
                        )
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: bodyViewportHeight)

            Divider()
                .overlay(GoldfishDS.ink(.hairline))

            guideControls(for: step)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity)
        .background(GoldfishDS.surface)
        .clipShape(RoundedRectangle(cornerRadius: GoldfishDS.Radius.card))
        .overlay(
            RoundedRectangle(cornerRadius: GoldfishDS.Radius.card)
                .stroke(GoldfishDS.ink(.hairline), lineWidth: GoldfishDS.Rule.hairline)
        )
        .onPreferenceChange(WalkthroughCardContentHeightKey.self) { height in
            guard height.isFinite, height > 0 else { return }
            if abs(measuredBodyHeight - height) > 0.5 { measuredBodyHeight = height }
        }
        .onChange(of: walkthroughManager.currentStep) { _, _ in measuredBodyHeight = 0 }
        .alert("End feature tour?", isPresented: $showEndChoice) {
            Button("Keep exploring samples") { walkthroughManager.finishTour(keepDemoData: true) }
            Button("Use my contacts") { walkthroughManager.finishTour(keepDemoData: false) }
            Button("Continue tour", role: .cancel) { }
        } message: {
            Text("Your saved contacts stay on this device. Keep the sample mode available to explore, or switch back to your contacts.")
        }
    }

    private func progressLabel(for step: WalkthroughStep) -> String {
        guard let index = WalkthroughStep.displayableSteps.firstIndex(of: step) else { return "Done" }
        return index == 0 ? "Start" : "\(index) of 3"
    }

    private func guideControls(for step: WalkthroughStep) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 0))
        return layout {
            if step != .welcome {
                Button {
                    walkthroughManager.previousStep()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.gfMeta)
                        .foregroundStyle(GoldfishDS.ink(.secondary))
                }
                .frame(minWidth: 88, minHeight: 44, alignment: .leading)
            } else if !dynamicTypeSize.isAccessibilitySize {
                Color.clear.frame(width: 88, height: 44)
            }

            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }

            if step.isAction && !walkthroughManager.justCompletedStep {
                Button("Skip") { walkthroughManager.nextStep() }
                    .font(.gfMeta)
                    .foregroundStyle(GoldfishDS.ink(.secondary))
                    .frame(minWidth: 88, minHeight: 44, alignment: .trailing)
            } else {
                Button(step == .complete ? "Finish" : "Continue") {
                    if step == .complete {
                        showEndChoice = true
                    } else {
                        walkthroughManager.nextStep()
                    }
                }
                .font(.gfLabel)
                .kerning(1)
                .foregroundStyle(GoldfishDS.warmBlack)
                .padding(.horizontal, 16)
                .frame(minWidth: 100, minHeight: 44)
                .background(GoldfishDS.ink(.primary), in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
            }
        }
    }

    private func barTone(for step: WalkthroughStep) -> Color {
        switch step {
        case .welcome, .complete: return GoldfishDS.terracotta
        default:
            let tones = [GoldfishDS.pondTone("family"), GoldfishDS.pondTone("friends"), GoldfishDS.pondTone("professional")]
            return tones[(step.rawValue - 1) % tones.count]
        }
    }
}

// MARK: - Walkthrough Overlay View
/// Guided, do-it-yourself tour. Each action step dims the app, points at the
/// real control, and waits for the user to perform the gesture — the manager
/// marks the step complete when the matching interaction is reported, then waits
/// for the user to continue (see HomeView).
struct WalkthroughOverlayView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var walkthroughManager: FeatureWalkthroughManager
    let targetFrames: [WalkthroughStep: CGRect]

    @State private var pulse = false

    var body: some View {
        let step = walkthroughManager.currentStep

        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.06)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                if step.isAction && !walkthroughManager.justCompletedStep {
                    targetPointer(for: step, in: geometry)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                        .transition(.opacity)
                }

                VStack(spacing: 0) {
                    if step.hintPlacement == .bottom {
                        Spacer(minLength: 0).allowsHitTesting(false)
                    }

                    WalkthroughInlineGuide(
                        maximumHeight: walkthroughManager.maximumOverlayHeight(in: geometry.frame(in: .global))
                    )
                        .background {
                            GeometryReader { cardGeometry in
                                let frame = cardGeometry.frame(in: .global).integral
                                Color.clear
                                    .onAppear { publishOverlayFrame(frame) }
                                    .onChange(of: frame) { _, newFrame in
                                        publishOverlayFrame(newFrame)
                                    }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, step.hintPlacement == .top ? 12 : 0)
                        .padding(.bottom, step.hintPlacement == .bottom ? 30 : 0)

                    if step.hintPlacement == .top {
                        Spacer(minLength: 0).allowsHitTesting(false)
                    }
                }
            }
        }
        .onDisappear {
            DispatchQueue.main.async {
                walkthroughManager.overlayFrame = .zero
            }
        }
        .animation(GoldfishDS.Motion.settle, value: walkthroughManager.currentStep)
        .animation(GoldfishDS.Motion.snappy, value: walkthroughManager.justCompletedStep)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private func publishOverlayFrame(_ frame: CGRect) {
        guard !frame.isEmpty,
              frame.minX.isFinite, frame.minY.isFinite,
              frame.width.isFinite, frame.height.isFinite else { return }
        let measured = frame.integral
        DispatchQueue.main.async {
            guard walkthroughManager.overlayFrame != measured else { return }
            walkthroughManager.overlayFrame = measured
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-layout-trace") {
                let viewport = walkthroughManager.graphViewportFrame
                let insets = walkthroughManager.graphObscuredInsets
                let line = "[WalkthroughLayout] global overlay=\(measured) viewport=\(viewport) insets=(\(insets.top),\(insets.bottom))\n"
                line.withCString { fputs($0, stdout) }
                fflush(stdout)
            }
#endif
        }
    }

    @ViewBuilder
    private func targetPointer(for step: WalkthroughStep, in geometry: GeometryProxy) -> some View {
        if step.isAction,
           let globalFrame = targetFrames[step],
           globalFrame.width > 0, globalFrame.height > 0,
           globalFrame.minX.isFinite, globalFrame.minY.isFinite,
           globalFrame.maxX.isFinite, globalFrame.maxY.isFinite {
            let container = geometry.frame(in: .global)
            let frame = globalFrame.offsetBy(dx: -container.minX, dy: -container.minY)
            let bounds = CGRect(origin: .zero, size: geometry.size)

            if frame.intersects(bounds), bounds.contains(CGPoint(x: frame.midX, y: frame.midY)) {
                let cardFrame = walkthroughManager.overlayFrame
                let cardIsBelow = !cardFrame.isEmpty && cardFrame.minY >= globalFrame.maxY
                let arrowName = cardIsBelow ? "arrow.up" : "arrow.down"
                let arrowY = cardIsBelow ? frame.maxY + 20 : frame.minY - 20

                ZStack {
                    RoundedRectangle(cornerRadius: GoldfishDS.Radius.control)
                        .stroke(GoldfishDS.terracotta, lineWidth: 2)
                        .frame(width: frame.width + 12, height: frame.height + 12)
                        .position(x: frame.midX, y: frame.midY)

                    Image(systemName: arrowName)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(GoldfishDS.terracotta)
                        .padding(7)
                        .background(GoldfishDS.surface, in: Circle())
                        .position(x: frame.midX, y: arrowY)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .opacity(pulse ? 1 : 0.72)
                .allowsHitTesting(false)
            }
        }
    }
}


// MARK: - Identifiable Wrapper
public struct IdentifiableWrapper<T: Equatable>: Identifiable, Equatable {
    public let id: UUID
    public let value: T
    
    public init(_ value: T, id: UUID = UUID()) {
        self.id = id
        self.value = value
    }
}


// MARK: - Helper: Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - UUID Identifiable

private struct WalkthroughCardContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
