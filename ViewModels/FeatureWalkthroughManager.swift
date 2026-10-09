import SwiftUI

// MARK: - Walkthrough Events
/// Real interactions the user performs during the guided tour. The view layer
/// reports these (see HomeView) and the manager advances the matching step.
enum WalkthroughEvent: Equatable {
    case openedSearchResult
    case openedProfile
    case createdLink
    case focusedPond
    case switchedToList
}

// MARK: - Hint Geometry
/// Where the instruction card sits, and where its pointer aims, so the card
/// never covers the control the user needs to reach.
enum HintPlacement { case top, bottom }
enum HintPointer { case none, topTrailing, topCenter, bottomCenter, center }

// MARK: - Walkthrough Steps
enum WalkthroughStep: Int, CaseIterable, Identifiable {
    case welcome = 0
    case search
    case profile
    case link
    case ponds
    case views
    case privacy
    case complete

    var id: Int { rawValue }

    /// The headline — the "tell".
    var title: String {
        switch self {
        case .welcome:  return "Welcome aboard"
        case .search:   return "Find any person"
        case .profile:  return "Read the whole story"
        case .link:     return "Make a connection"
        case .ponds:    return "Explore your ponds"
        case .views:    return "Pond or list"
        case .privacy:  return "A private network"
        case .complete: return "Ready to explore"
        }
    }

    /// One-line explanation of the feature — the "show".
    var description: String {
        switch self {
        case .welcome:
            return "Open a person’s story, connect two people, then explore a pond."
        case .search:
            return "Open a person to see the details that make them memorable."
        case .profile:
            return "Each person carries a full page — notes, birthday, address, and every connection in their branches."
        case .link:
            return "Connect two real sample people and see the relationship become part of the story."
        case .ponds:
            return "Use the pond switcher to focus a pond and see the people who belong there."
        case .views:
            return "Your pond is a living overview; the list remains available whenever you need every name."
        case .privacy:
            return "Contacts are stored locally. You choose when to share them; maps use Apple services."
        case .complete:
            return "That's the tour. Keep the sample people to explore, or return to your saved contacts."
        }
    }

    /// Plain-language confirmation shown after an action succeeds.
    var successDescription: String {
        switch self {
        case .welcome: return "The sample pond is ready."
        case .search: return "You found a sample person; search can reach every name."
        case .profile: return "You opened a person’s story, with their pond, notes, and connections together."
        case .link: return "You added a relationship, so the pond now shows a new branch."
        case .ponds: return "You focused a pond. Reveal more people as you explore its connections."
        case .views: return "You switched to the list, where every name appears in order."
        case .privacy: return "Your contacts stay local; sharing is your choice."
        case .complete: return "The feature tour is complete."
        }
    }

    /// The imperative ask — the "do". `nil` for passive steps (which show a Next button).
    var actionPrompt: String? {
        switch self {
        case .search:  return nil
        case .profile: return "Tap a person to open their story."
        case .link:    return "Connect the sample person to Me, choose Friend, then tap Save."
        case .ponds:   return "Use the pond switcher at the bottom to focus a pond."
        case .views:   return nil
        case .welcome, .privacy, .complete:
            return nil
        }
    }

    /// The interaction that satisfies this step; the user continues explicitly.
    var completionEvent: WalkthroughEvent? {
        switch self {
        case .search:  return nil
        case .profile: return .openedProfile
        case .link:    return .createdLink
        case .ponds:   return .focusedPond
        case .views:   return nil
        case .welcome, .privacy, .complete:
            return nil
        }
    }

    var isAction: Bool { completionEvent != nil }

    var icon: String {
        switch self {
        case .welcome:  return "circle.hexagongrid"
        case .search:   return "magnifyingglass"
        case .profile:  return "person.text.rectangle"
        case .link:     return "point.topleft.down.curvedto.point.bottomright.up"
        case .ponds:    return "arrow.triangle.swap"
        case .views:    return "list.bullet.rectangle"
        case .privacy:  return "lock.fill"
        case .complete: return "checkmark.circle.fill"
        }
    }

    /// Where the card sits so it doesn't cover the target control.
    var hintPlacement: HintPlacement {
        switch self {
        case .ponds: return .top      // target (carousel) lives at the bottom
        default:     return .bottom
        }
    }

    /// Direction of the animated pointer toward the target control.
    var pointer: HintPointer {
        switch self {
        case .search:        return .topTrailing
        case .views:         return .none
        case .ponds:         return .bottomCenter
        case .profile, .link: return .none
        case .welcome, .privacy, .complete:
            return .none
        }
    }

    /// Total displayable steps (excluding the terminal `.complete`).
    static var displayableSteps: [WalkthroughStep] {
        [.welcome, .profile, .link, .ponds]
    }

    var index: Int { rawValue }
    static var totalDisplayable: Int { displayableSteps.count }
}

// MARK: - Feature Walkthrough Manager
@MainActor
class FeatureWalkthroughManager: ObservableObject {
    @Published var isActive: Bool = false
    @Published var currentStep: WalkthroughStep = .welcome
    @Published var isDemoDataSeeded: Bool = false
    @Published var demoErrorMessage: String?
    @Published var examplePersonID: UUID?
    @Published var examplePersonName: String = "Priya Patel"
    @Published var suggestedConnectionName: String = "Me"
    @Published var exampleConnectionIsExisting = false

    /// Global frames keep the Home-level card and the graph below its controls in
    /// the same coordinate space. A hidden card contributes no obstruction.
    @Published var overlayFrame: CGRect = .zero
    @Published var graphViewportFrame: CGRect = .zero
    @Published var graphFooterHeight: CGFloat = 0

    var overlayHeight: CGFloat { overlayFrame.height }

    var currentDescription: String {
        switch currentStep {
        case .search:
            return "Search the sample pond for \(examplePersonName), then open their result."
        case .link:
            return exampleConnectionIsExisting
                ? "Open the sample profile to inspect its existing connection, or add another relationship from that profile."
                : "Open a profile to add a relationship, or drag across the pond to grow a branch."
        default:
            return currentStep.description
        }
    }

    var currentActionPrompt: String? {
        switch currentStep {
        case .profile:
            return "Tap \(examplePersonName) on the pond to open their story."
        case .search:
            return "Tap Search, enter \(examplePersonName), then open that result."
        case .link:
            return exampleConnectionIsExisting
                ? "Open \(examplePersonName)’s profile and inspect its connection with \(suggestedConnectionName), or add another relationship and save it."
                : "Tap + beside Connections. Try linking \(examplePersonName) to \(suggestedConnectionName) as Friend."
        default:
            return currentStep.actionPrompt
        }
    }

    var successDescription: String {
        if currentStep == .link && exampleConnectionIsExisting {
            return "This profile shows an existing relationship."
        }
        return currentStep.successDescription
    }

    func maximumOverlayHeight(in containerFrame: CGRect) -> CGFloat {
        let preferredLimit = containerFrame.height * 0.55
        guard !graphViewportFrame.isEmpty else { return max(44, preferredLimit) }
        let visibleGraph = min(160, graphViewportFrame.height * 0.35)
        let availableHeight: CGFloat
        if currentStep.hintPlacement == .top {
            availableHeight = graphViewportFrame.maxY - containerFrame.minY
                - graphFooterHeight - visibleGraph - 12
        } else {
            availableHeight = containerFrame.maxY - graphViewportFrame.minY
                - visibleGraph - 30
        }
        return max(44, min(preferredLimit, availableHeight))
    }

    var graphObscuredInsets: (top: CGFloat, bottom: CGFloat) {
        let footer = max(0, graphFooterHeight)
        guard isActive, !overlayFrame.isEmpty, !graphViewportFrame.isEmpty,
              overlayFrame.intersects(graphViewportFrame) else { return (0, footer) }
        if currentStep.hintPlacement == .top {
            return (max(0, overlayFrame.maxY - graphViewportFrame.minY), footer)
        }
        return (0, max(footer, graphViewportFrame.maxY - overlayFrame.minY))
    }

    /// Brief "✓" celebration shown when an action step is satisfied, while the
    /// overlay waits for the user to continue.
    @Published var justCompletedStep: Bool = false

    @AppStorage("hasSeenWalkthrough") private var hasSeenWalkthrough = false

    /// Guards against double-advancing while the completion animation plays.
    private var isAdvancing = false

    /// Callback for when the walkthrough needs the graph view to be shown
    var onRequestGraphView: (() -> Void)?
    /// Callback for when the walkthrough needs the list view to be shown
    var onRequestListView: (() -> Void)?
    /// Callback for when the tour completes (with whether to keep demo data)
    var onTourCompleted: ((Bool) -> Void)?

    // MARK: - Lifecycle

    func startWalkthroughIfNeeded(dataManager: GoldfishDataManager) {
        guard !hasSeenWalkthrough else { return }
        guard (try? dataManager.fetchMePerson()) != nil,
              seedDemoDataIfNeeded(dataManager: dataManager) else { return }
        startWalkthrough()
    }

    func replayWalkthrough(dataManager: GoldfishDataManager) {
        guard (try? dataManager.fetchMePerson()) != nil else {
            demoErrorMessage = "Create your profile before replaying the sample tour."
            return
        }
        guard seedDemoDataIfNeeded(dataManager: dataManager) else { return }
        startWalkthrough()
    }

    func startWalkthrough() {
        var initialStep: WalkthroughStep = .welcome
        #if DEBUG
        // DEBUG: jump to a specific tour step for headless screenshot verification.
        // Toggle: `defaults write app.pond.goldfish gfDebugTourStep -string welcome|search|profile|link|ponds|views|privacy|complete`.
        if let stepName = UserDefaults.standard.string(forKey: "gfDebugTourStep"),
           let matched = WalkthroughStep.allCases.first(where: { String(describing: $0) == stepName }) {
            initialStep = matched
        }
        #endif
        overlayFrame = .zero
        currentStep = initialStep
        isAdvancing = false
        justCompletedStep = false
        prepareView(for: initialStep)
        withAnimation(.easeOut(duration: 0.4)) {
            isActive = true
        }
    }

    @discardableResult
    func seedDemoDataIfNeeded(dataManager: GoldfishDataManager) -> Bool {
        let service = DemoDataService(dataManager: dataManager)
        do {
            guard try service.seedDemoData() else {
                demoErrorMessage = (try? dataManager.fetchMePerson()) == nil
                    ? nil
                    : "Sample contacts are incomplete. Remove Sample Data, then try again."
                return false
            }
            demoErrorMessage = nil
            deriveExamplePeople(dataManager: dataManager)
            isDemoDataSeeded = true
            return true
        } catch {
            demoErrorMessage = "Couldn’t load sample contacts. Try again."
            print("Failed to seed demo data: \(error)")
            return false
        }
    }

    private func deriveExamplePeople(dataManager: GoldfishDataManager) {
        guard let me = try? dataManager.fetchMePerson() else {
            examplePersonID = nil
            exampleConnectionIsExisting = false
            return
        }
        let demos = (try? dataManager.fetchAllPersons())?.filter { $0.isDemo } ?? []
        let directlyConnectedIDs = Set(me.connectedContacts.map(\.id))
        // A useful replay target may have other relationships; it only needs to
        // be unlinked from the suggested contact so the lesson can create a real
        // new connection without resetting retained demo edits.
        let unlinkedFromMe = demos.filter { !directlyConnectedIDs.contains($0.id) }
        if let target = unlinkedFromMe.first(where: { $0.name == "Priya Patel" }) ?? unlinkedFromMe.first {
            examplePersonID = target.id
            examplePersonName = target.name
            suggestedConnectionName = me.name
            exampleConnectionIsExisting = false
            return
        }

        let priya = demos.first(where: { $0.name == "Priya Patel" })
        let samplePair: (Person, Person)? = {
            if let priya, let partner = demos.first(where: { $0.id != priya.id && !areConnected(priya, $0) }) {
                return (priya, partner)
            }
            for target in demos {
                if let partner = demos.first(where: { $0.id != target.id && !areConnected(target, $0) }) {
                    return (target, partner)
                }
            }
            return nil
        }()
        if let (target, partner) = samplePair {
            examplePersonID = target.id
            examplePersonName = target.name
            suggestedConnectionName = partner.name
            exampleConnectionIsExisting = false
            return
        }

        let target = priya ?? demos.first
        examplePersonID = target?.id
        suggestedConnectionName = me.name
        exampleConnectionIsExisting = target.map { directlyConnectedIDs.contains($0.id) } ?? false
        if let target { examplePersonName = target.name }
    }

    private func areConnected(_ lhs: Person, _ rhs: Person) -> Bool {
        lhs.allRelationships.contains {
            ($0.fromContact.id == lhs.id && $0.toContact.id == rhs.id)
                || ($0.fromContact.id == rhs.id && $0.toContact.id == lhs.id)
        }
    }

    // MARK: - Action Reporting

    /// Called by the view layer when the user performs a real interaction.
    /// If it satisfies the current step, flash a ✓ and wait for Continue.
    func report(_ event: WalkthroughEvent) {
        guard isActive, !isAdvancing, !justCompletedStep else { return }
        let isInspectingExistingLink = currentStep == .link
            && exampleConnectionIsExisting
            && event == .openedProfile
        guard currentStep.completionEvent == event || isInspectingExistingLink else { return }

        isAdvancing = true
        triggerSuccessHaptic()
        withAnimation(GoldfishDS.Motion.snappy) {
            justCompletedStep = true
        }

    }

    // MARK: - Navigation

    func nextStep() {
        justCompletedStep = false
        isAdvancing = false
        triggerHaptic()

        if currentStep == .complete {
            skip() // finish the tour and keep demo data
            return
        }

        let steps = WalkthroughStep.displayableSteps + [.complete]
        if let index = steps.firstIndex(of: currentStep), index + 1 < steps.count {
            let next = steps[index + 1]
            // Put the app in the right view for the upcoming step
            prepareView(for: next)

            withAnimation(GoldfishDS.Motion.settle) {
                currentStep = next
            }

            // hasSeenWalkthrough is committed only when the user answers
            // the Keep/Fresh alert (finishTour) or exits early (earlyExit/skip),
            // not merely on reaching the .complete card.
        }
    }

    func previousStep() {
        let steps = WalkthroughStep.displayableSteps + [.complete]
        guard let index = steps.firstIndex(of: currentStep), index > 0 else { return }
        justCompletedStep = false
        isAdvancing = false
        triggerHaptic()

        if index - 1 >= 0 {
            let prev = steps[index - 1]
            prepareView(for: prev)

            withAnimation(GoldfishDS.Motion.settle) {
                currentStep = prev
            }
        }
    }

    func skip() {
        triggerHaptic()
        withAnimation(.easeOut(duration: 0.3)) {
            currentStep = .complete
        }
        // When skipping, keep demo data (user may want to explore).
        // finishTour commits hasSeenWalkthrough.
        finishTour(keepDemoData: true)
    }

    /// Early exit via the X button: ends the tour and asks the owner to show the
    /// user's contacts. The owner decides whether retained samples are cleaned
    /// up; this manager only reports the keep-data choice.
    func earlyExit() {
        triggerHaptic()
        finishTour(keepDemoData: false)
    }

    // MARK: - Completion

    func finishTour(keepDemoData: Bool) {
        // Commit the seen flag here — the one and only resolution point,
        // so an unresolved state (app killed at .complete card) re-shows
        // the tour on next launch while isDemoModeActive reflects reality.
        completeWalkthrough()
        justCompletedStep = false
        isAdvancing = false
        withAnimation(.easeOut(duration: 0.35)) {
            isActive = false
            overlayFrame = .zero
        }
        onTourCompleted?(keepDemoData)
        if !keepDemoData {
            isDemoDataSeeded = false
        }
    }

    private func completeWalkthrough() {
        hasSeenWalkthrough = true
    }

    /// Records the explicit first-run choice to begin with a personal pond.
    /// This prevents a later appearance from silently starting the sample tour.
    func completeOnboardingWithoutWalkthrough() {
        hasSeenWalkthrough = true
        isActive = false
        currentStep = .welcome
        isDemoDataSeeded = false
        demoErrorMessage = nil
        justCompletedStep = false
        isAdvancing = false
    }

    // MARK: - View Preparation

    /// Most steps demonstrate the graph, so we keep it stable behind the card.
    /// The `.views` step starts on the graph (so switching to the list is a real
    /// change), then we leave the user wherever they land for the trailing
    /// passive steps rather than snapping back.
    private func prepareView(for step: WalkthroughStep) {
        switch step {
        case .welcome, .search, .profile, .link, .ponds, .views:
            onRequestGraphView?()
        case .privacy, .complete:
            break
        }
    }

    // MARK: - Haptics

    private func triggerHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }

    private func triggerSuccessHaptic() {
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    /// Resets the walkthrough state completely.
    func reset() {
        hasSeenWalkthrough = false
        isActive = false
        overlayFrame = .zero
        currentStep = .welcome
        isDemoDataSeeded = false
        demoErrorMessage = nil
        examplePersonID = nil
        examplePersonName = "Priya Patel"
        suggestedConnectionName = "Me"
        exampleConnectionIsExisting = false
        isAdvancing = false
        justCompletedStep = false
    }
}
