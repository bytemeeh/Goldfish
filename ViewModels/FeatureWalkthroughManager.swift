import SwiftUI
import Combine

// MARK: - Walkthrough Steps
enum WalkthroughStep: Int, CaseIterable, Identifiable {
    case welcome = 0
    case addContact
    case pondIt
    case complete

    var id: Int { rawValue }

    /// Interactive steps wait for the user to perform the real action
    /// in the app instead of advancing via the Next button.
    var isInteractive: Bool {
        switch self {
        case .addContact, .pondIt: return true
        case .welcome, .complete: return false
        }
    }

    var title: String {
        switch self {
        case .welcome: return "Welcome to the Pond"
        case .addContact: return "Add Your First Fish"
        case .pondIt: return "Pond It"
        case .complete: return "Into the Deep!"
        }
    }

    var description: String {
        switch self {
        case .welcome: return "A new kind of address book designed to cure that goldfish memory. We've stocked the pond with demo fish — now try the two moves that matter most."
        case .addContact: return "Tap the + button up top and add a contact yourself. Every fish you add is one face you'll never forget."
        case .pondIt: return "Drag any fish into a pond, or pick a pond in a contact's form. Ponds keep your people schooling together, like Family or Friends."
        case .complete: return "The water's fine! You know the moves — keep adding fish and watch your network ripple out."
        }
    }

    /// Brief acknowledgment shown when an interactive step's action completes.
    var successMessage: String {
        switch self {
        case .addContact: return "Splash! Your new fish just hit the water."
        case .pondIt: return "Nice — your fish found its school."
        case .welcome, .complete: return ""
        }
    }

    var icon: String {
        switch self {
        case .welcome: return "fish.fill"
        case .addContact: return "plus.circle.fill"
        case .pondIt: return "circle.grid.cross.fill"
        case .complete: return "checkmark.seal.fill"
        }
    }

    /// Total displayable steps (excluding .complete)
    static var displayableSteps: [WalkthroughStep] {
        allCases.filter { $0 != .complete }
    }

    var index: Int { rawValue }
    static var totalDisplayable: Int { displayableSteps.count }
}

// MARK: - Feature Walkthrough Manager
@MainActor
class FeatureWalkthroughManager: ObservableObject {
    @Published var isActive: Bool = false
    @Published var currentStep: WalkthroughStep = .welcome
    /// True while the brief success acknowledgment for a completed
    /// interactive step is showing (before auto-advancing).
    @Published var showingStepSuccess: Bool = false
    /// Global frames of views tagged with `.walkthroughAnchor(step:)`,
    /// used by the overlay to spotlight targets like the + button.
    @Published var anchorFrames: [WalkthroughStep: CGRect] = [:]

    @AppStorage("hasSeenWalkthrough") private var hasSeenWalkthrough = false

    /// Callback for when the walkthrough needs the graph view to be shown
    var onRequestGraphView: (() -> Void)?
    /// Callback for when the walkthrough needs the list view to be shown
    var onRequestListView: (() -> Void)?
    /// Callback for when the tour completes (with whether to keep demo data)
    var onTourCompleted: ((Bool) -> Void)?

    /// True while the tour seeds demo data, so seeding writes can never be
    /// mistaken for user actions. (Belt and braces: seeding also runs before
    /// `isActive` flips on, and the only other seeding path —
    /// `DemoModeManager.activateDemoMode` — runs after the tour ends.)
    private var isSeedingDemoData = false
    /// Set when the user assigns a pond while still on the add-contact step
    /// (e.g. picked a pond inside the contact form), so the pond step
    /// acknowledges immediately instead of asking them to do it twice.
    private var pondStepPreCompleted = false
    private var advanceTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init() {
        observeUserActions()
    }

    // MARK: - Lifecycle

    func startWalkthroughIfNeeded(dataManager: GoldfishDataManager) {
        guard !hasSeenWalkthrough else { return }
        startWalkthrough(dataManager: dataManager)
    }

    func replayWalkthrough(dataManager: GoldfishDataManager) {
        startWalkthrough(dataManager: dataManager)
    }

    func startWalkthrough(dataManager: GoldfishDataManager) {
        // Seed demo data BEFORE the tour begins so the graph step has a
        // populated network to show. seedDemoData() is idempotent, so the
        // keep path at tour end (activateDemoMode) won't double-seed, and
        // the discard path (removeDemoData) cleans up everything seeded here.
        isSeedingDemoData = true
        let service = DemoDataService(dataManager: dataManager)
        do {
            try service.seedDemoData()
        } catch {
            print("Failed to seed demo data for walkthrough: \(error)")
        }
        isSeedingDemoData = false

        advanceTask?.cancel()
        showingStepSuccess = false
        pondStepPreCompleted = false
        currentStep = .welcome
        withAnimation(.easeOut(duration: 0.4)) {
            isActive = true
        }
    }

    // MARK: - User Action Observation

    /// Listens for real data writes (posted by GoldfishDataManager) so
    /// interactive steps advance when the user actually performs the action.
    private func observeUserActions() {
        NotificationCenter.default.publisher(for: .goldfishPersonCreated)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handlePersonCreated()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .goldfishMembershipChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                self?.handleMembershipChanged(notification)
            }
            .store(in: &cancellables)
    }

    private func handlePersonCreated() {
        guard isActive, !isSeedingDemoData else { return }
        guard currentStep == .addContact, !showingStepSuccess else { return }
        completeInteractiveStep()
    }

    private func handleMembershipChanged(_ notification: Notification) {
        guard isActive, !isSeedingDemoData else { return }
        // Only an assignment counts as "ponding" — ignore removals.
        guard (notification.userInfo?["action"] as? String) == "added" else { return }

        if currentStep == .pondIt && !showingStepSuccess {
            completeInteractiveStep()
        } else if currentStep == .addContact {
            // The user ponded the contact in the same action (e.g. via the
            // form's pond picker) — don't make them do it twice.
            pondStepPreCompleted = true
        }
    }

    /// Shows a brief success acknowledgment for the current interactive
    /// step, then auto-advances to the next step.
    private func completeInteractiveStep() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showingStepSuccess = true
        }

        advanceTask?.cancel()
        advanceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard let self, !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                self.showingStepSuccess = false
            }
            self.advanceStep()
        }
    }

    // MARK: - Navigation

    func nextStep() {
        triggerHaptic()
        advanceStep()
    }

    /// Skips just the current interactive step (the user opted out of
    /// performing the action) without ending the tour.
    func skipCurrentStep() {
        triggerHaptic()
        advanceTask?.cancel()
        showingStepSuccess = false
        advanceStep()
    }

    private func advanceStep() {
        if currentStep == .complete {
            skip() // this accomplishes finishing the tour and keeping demo data
            return
        }

        guard let next = WalkthroughStep(rawValue: currentStep.rawValue + 1) else { return }

        // Pre-switch views for the upcoming step
        prepareView(for: next)

        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            currentStep = next
        }

        if next == .complete {
            completeWalkthrough()
        }

        // If the user already ponded a contact during the add step,
        // acknowledge immediately instead of waiting for a second action.
        if next == .pondIt && pondStepPreCompleted {
            pondStepPreCompleted = false
            completeInteractiveStep()
        }
    }

    func previousStep() {
        guard currentStep.rawValue > 0 else { return }
        triggerHaptic()
        advanceTask?.cancel()
        showingStepSuccess = false

        if let prev = WalkthroughStep(rawValue: currentStep.rawValue - 1) {
            prepareView(for: prev)

            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                currentStep = prev
            }
        }
    }

    func skip() {
        triggerHaptic()
        completeWalkthrough()
        advanceTask?.cancel()
        showingStepSuccess = false
        pondStepPreCompleted = false
        withAnimation(.easeOut(duration: 0.3)) {
            currentStep = .complete
        }
        // When skipping, keep demo data (user may want to explore)
        finishTour(keepDemoData: true)
    }

    // MARK: - Completion

    func finishTour(keepDemoData: Bool) {
        advanceTask?.cancel()
        showingStepSuccess = false
        pondStepPreCompleted = false
        withAnimation(.easeOut(duration: 0.35)) {
            isActive = false
        }
        onTourCompleted?(keepDemoData)
    }

    private func completeWalkthrough() {
        hasSeenWalkthrough = true
    }

    // MARK: - Anchor Reporting

    /// Called by views tagged with `.walkthroughAnchor(step:)` to report
    /// their global frame for spotlighting.
    func reportAnchor(_ frame: CGRect, for step: WalkthroughStep) {
        guard anchorFrames[step] != frame else { return }
        anchorFrames[step] = frame
    }

    // MARK: - View Preparation

    private func prepareView(for step: WalkthroughStep) {
        // Option A implemented: Disabling automatic view switching
        // to stabilize the background view during the walkthrough.
        // We ensure HomeView is locked to the graph view.

        // Only trigger these if we actually want the background to bounce around,
        // but per P0.2 requirements we want to stabilize the background.
        // So we will trigger graph view once at the very beginning to lock it there.
        if step == .welcome {
            onRequestGraphView?()
        }
    }

    // MARK: - Haptics

    private func triggerHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    /// Resets the walkthrough state completely.
    func reset() {
        hasSeenWalkthrough = false
        isActive = false
        currentStep = .welcome
        advanceTask?.cancel()
        showingStepSuccess = false
        pondStepPreCompleted = false
    }
}
