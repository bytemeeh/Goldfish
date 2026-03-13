import SwiftUI

// MARK: - Walkthrough Steps
enum WalkthroughStep: Int, CaseIterable, Identifiable {
    case welcome = 0
    case search
    case contactList
    case graphView
    case relationships
    case shortcuts
    case ponds
    case privacy
    case complete
    
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .welcome: return "Welcome to the Pond"
        case .search: return "Cast a Net"
        case .contactList: return "Your Personal Pond"
        case .graphView: return "Survey the Waters"
        case .relationships: return "The Ripple Effect"
        case .shortcuts: return "Navigate the Current"
        case .ponds: return "School Your Fish"
        case .privacy: return "A Private Oasis"
        case .complete: return "Into the Deep!"
        }
    }
    
    var description: String {
        switch self {
        case .welcome: return "A new kind of address book designed to cure that goldfish memory. Keep track of everyone and how they fit into your life."
        case .search: return "Cast a net in the search bar to instantly find any person, organization, or pond."
        case .contactList: return "Keep all your contacts swimming in one unified list. Add rich details so you never forget a face (or a fin)."
        case .graphView: return "Toggle to the Graph View to watch your network swim to life. See relationships ripple out dynamically across the screen."
        case .relationships: return "Link people by dragging one onto another, or add relationships on their profile. Map out who swims with who seamlessly."
        case .shortcuts: return "Use the shortcut bar above the graph to quickly swim over to specific ponds or reset your view."
        case .ponds: return "Group your contacts into Ponds like Family or Work. Watch them cluster together like schools of fish in the graph."
        case .privacy: return "Your data is watertight. Goldfish stores everything securely on your device and syncs via encrypted iCloud."
        case .complete: return "The water's fine! Dive in, add your first contacts, and start growing your network."
        }
    }
    
    var icon: String {
        switch self {
        case .welcome: return "fish.fill"
        case .search: return "magnifyingglass"
        case .contactList: return "person.text.rectangle.fill"
        case .graphView: return "network"
        case .relationships: return "link"
        case .shortcuts: return "bolt.fill"
        case .ponds: return "circle.grid.cross.fill"
        case .privacy: return "lock.shield.fill"
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
    @Published var isDemoDataSeeded: Bool = false
    
    @AppStorage("hasSeenWalkthrough") private var hasSeenWalkthrough = false
    
    /// Callback for when the walkthrough needs the graph view to be shown
    var onRequestGraphView: (() -> Void)?
    /// Callback for when the walkthrough needs the list view to be shown
    var onRequestListView: (() -> Void)?
    /// Callback for when the tour completes (with whether to keep demo data)
    var onTourCompleted: ((Bool) -> Void)?
    
    // MARK: - Lifecycle
    
    func startWalkthroughIfNeeded(dataManager: GoldfishDataManager) {
        guard !hasSeenWalkthrough else { return }
        seedDemoDataIfNeeded(dataManager: dataManager)
        startWalkthrough()
    }
    
    func replayWalkthrough(dataManager: GoldfishDataManager) {
        seedDemoDataIfNeeded(dataManager: dataManager)
        startWalkthrough()
    }
    
    func startWalkthrough() {
        currentStep = .welcome
        withAnimation(.easeOut(duration: 0.4)) {
            isActive = true
        }
    }
    
    func seedDemoDataIfNeeded(dataManager: GoldfishDataManager) {
        guard !isDemoDataSeeded else { return }
        let service = DemoDataService(dataManager: dataManager)
        do {
            try service.seedDemoData()
            isDemoDataSeeded = true
        } catch {
            print("Failed to seed demo data: \(error)")
        }
    }
    
    // MARK: - Navigation
    
    func nextStep() {
        triggerHaptic()
        
        if currentStep == .complete {
            skip() // this accomplishes finishing the tour and keeping demo data
            return
        }
        
        if let next = WalkthroughStep(rawValue: currentStep.rawValue + 1) {
            // Pre-switch views for the upcoming step
            prepareView(for: next)
            
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                currentStep = next
            }
            
            if next == .complete {
                completeWalkthrough()
            }
        }
    }
    
    func previousStep() {
        guard currentStep.rawValue > 0 else { return }
        triggerHaptic()
        
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
        withAnimation(.easeOut(duration: 0.3)) {
            currentStep = .complete
        }
        // When skipping, keep demo data (user may want to explore)
        finishTour(keepDemoData: true)
    }
    
    // MARK: - Completion
    
    func finishTour(keepDemoData: Bool) {
        withAnimation(.easeOut(duration: 0.35)) {
            isActive = false
        }
        onTourCompleted?(keepDemoData)
        if !keepDemoData {
            isDemoDataSeeded = false
        }
    }
    
    private func completeWalkthrough() {
        hasSeenWalkthrough = true
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
        isDemoDataSeeded = false
    }
}
