import SwiftUI

// MARK: - Walkthrough Steps
enum WalkthroughStep: Int, CaseIterable, Identifiable {
    case welcome = 0
    case contactList
    case graphView
    case relationships
    case ponds
    case privacy
    case complete
    
    var id: Int { rawValue }
    
    var title: String {
        switch self {
        case .welcome: return "Welcome to Goldfish"
        case .contactList: return "Your Roster"
        case .graphView: return "Visualize Connections"
        case .relationships: return "Connect the Dots"
        case .ponds: return "Organize into Ponds"
        case .privacy: return "Private by Design"
        case .complete: return "You're Ready!"
        }
    }
    
    var description: String {
        switch self {
        case .welcome: return "A new kind of address book designed to help you remember everyone and how they fit into your life."
        case .contactList: return "Keep track of all your people in one unified list. Add rich details like birthdays and custom notes so you never forget the important things."
        case .graphView: return "Toggle to the Graph View to see your entire network come alive. Watch relationships branch out from you as the center of your universe."
        case .relationships: return "Tap any two people in the graph to connect them, or add relationships on their profile. Map out families, coworkers, and friend groups."
        case .ponds: return "Group your contacts into Ponds like Family, Friends, or Work. Ponds cluster together in the graph so you can see different areas of your life at a glance."
        case .privacy: return "Your data is yours. Goldfish stores everything securely on your device and syncs via your personal iCloud. No external servers involved."
        case .complete: return "You've seen the highlights. Dive in, add your first contacts, and start building your network."
        }
    }
    
    var icon: String {
        switch self {
        case .welcome: return "fish.fill"
        case .contactList: return "person.text.rectangle.fill"
        case .graphView: return "network"
        case .relationships: return "link"
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
        // Now optional since the carousel is a full screen overlay
        // However, we still switch the background view so it looks nice
        // behind the translucent modal
        switch step {
        case .graphView, .relationships, .ponds:
            onRequestGraphView?()
        case .contactList:
            onRequestListView?()
        default:
            break
        }
    }
    
    // MARK: - Haptics
    
    private func triggerHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
}
