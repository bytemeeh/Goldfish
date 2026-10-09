import SwiftUI
import SwiftData

// MARK: - App Entry Point
@main
struct GoldfishApp: App {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Tracks whether the user has completed the initial sign-in step.
    /// HomeView shows `OnboardingSignInOverlay` (over the ponds graph) until this is true.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    /// The SwiftData container.
    @State private var modelContainer: ModelContainer?
    
    /// Tracks initialization errors (e.g., corruption).
    @State private var databaseError: Error?
    @State private var incomingShare: IdentifiableWrapper<URL>?
    @State private var stagedShareURL: URL?
    @State private var shareOpenError: String?
    @State private var showPendingShareNotice = false
    
    /// The DataManager instance to inject into the environment.
    /// We keep it in @State so it survives view recycles, though in App it's stable.
    @State private var dataManager: GoldfishDataManager?
    

    
    /// The FeatureWalkthroughManager for the coach-mark tour.
    @StateObject private var walkthroughManager = FeatureWalkthroughManager()
    
    /// The DemoModeManager for the demo data toggle.
    @StateObject private var demoModeManager = DemoModeManager()
    
    @StateObject private var toastManager = ToastManager.shared
    
    init() {
        // We delay container creation to `body` or `.task` to handle errors properly,
        // but `@main` structs are initialized before `body`.
        // Common pattern: try create it here, catch error.
        do {
            #if DEBUG
            // A deterministic, non-destructive way to review the recovery screen.
            // The real store is left untouched and Retry uses the normal open path.
            if ProcessInfo.processInfo.arguments.contains("--ui-database-error") {
                throw CocoaError(.fileReadCorruptFile)
            }
            #endif
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            let isWelcomeMotionReview = arguments.contains("--welcome-motion-preview")
            let isPondReview = arguments.contains("--review-pond-disclosure") || isWelcomeMotionReview
            let isRippleReview = arguments.contains("--review-ripples")
            let isQualityReview = ProcessInfo.processInfo.arguments.contains("--review-network-50") || isRippleReview || isPondReview
            let isOnboardingReview = ProcessInfo.processInfo.arguments.contains("--review-onboarding")
            let container = try (isQualityReview || isOnboardingReview) ? GoldfishModelContainer.preview() : GoldfishModelContainer.production()
            #else
            let container = try GoldfishModelContainer.production()
            #endif
            let manager = GoldfishDataManager(context: container.mainContext)
            _modelContainer = State(initialValue: container)
            _dataManager = State(initialValue: manager)

            // DEBUG: deterministically seed demo data at launch (e.g. after a
            // "Logout and Reset" wipe left the graph on its empty state).
            // Toggle: `defaults write app.pond.goldfish gfDebugSeedDemo -int 1`.
            // Idempotent — guarded so repeated launches never duplicate data.
            #if DEBUG
            if isQualityReview {
                try manager.performOnboarding(name: "You")
                if isPondReview {
                    try DemoDataService(dataManager: manager).seedDemoData()
                } else if isRippleReview {
                    try DemoDataService(dataManager: manager).seedRippleReviewNetwork()
                } else {
                    try DemoDataService(dataManager: manager).seedQualityReviewNetwork()
                }
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                UserDefaults.standard.set(true, forKey: "hasSeenWalkthrough")
                UserDefaults.standard.set(true, forKey: "isDemoModeActive")
            }
            if UserDefaults.standard.integer(forKey: "gfDebugSeedDemo") == 1 {
                Self.seedDemoForDebug(manager: manager)
            }
            // Review only: reopen the real first-run flow without deleting contacts.
            // A dedicated flag keeps the preferences writable while testing the CTA.
            if ProcessInfo.processInfo.arguments.contains("--review-onboarding") {
                UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
                UserDefaults.standard.set(false, forKey: "hasSeenWalkthrough")
                UserDefaults.standard.set(false, forKey: "isDemoModeActive")
            }
            #endif
        } catch {
            _databaseError = State(initialValue: error)
        }
    }

    /// Ensures a Me person + demo data exist and demo mode is active, so the
    /// app behaves like a normal populated launch. Safe to call every launch:
    /// each step is a no-op when its target already exists.
    private static func seedDemoForDebug(manager: GoldfishDataManager) {
        do {
            // 1. Ensure Me exists — DemoDataService.seedDemoData() returns early
            //    without it (the root cause of the empty graph after a reset).
            if try manager.fetchMePerson() == nil {
                try manager.performOnboarding(name: "You")
            }
            // 2. Seed demo contacts/relationships/ponds (skips if already present).
            try DemoDataService(dataManager: manager).seedDemoData()
            // 3. Mark onboarding done + demo mode active so HomeView shows the graph
            //    instead of the sign-in overlay / empty state.
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            UserDefaults.standard.set(true, forKey: "isDemoModeActive")
        } catch {
            print("[gfDebugSeedDemo] Failed to seed: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            if let error = databaseError {
                DatabaseErrorView(error: error) {
                    retryDatabaseInit()
                }
            } else if let container = modelContainer, let manager = dataManager {
                Group {
                    // DEBUG: open a contact detail directly (for screenshotting directions
                    // without UI taps). Toggle: `defaults write app.pond.goldfish gfDebugDetail -int 1`.
                    if debugDetailEnabled,
                       let p = (try? manager.fetchAllPersons())?.first(where: { !$0.isMe }) {
                        NavigationStack {
                            ContactDetailView(viewModel: ContactDetailViewModel(person: p, dataManager: manager))
                                .environmentObject(manager)
                        }
                    } else if let debugScreen = debugScreenOverride {
                        // DEBUG: present a single screen directly for headless
                        // screenshot verification.
                        // Toggle: `defaults write app.pond.goldfish gfDebugScreen -string settings|form|lines|privacy`.
                        debugScreen
                            .environmentObject(manager)
                    } else {
                        HomeView()
#if DEBUG
                            .overlay {
                                if let preview = welcomeMotionPreview {
                                    WelcomeMotionPreview(variant: preview.variant, autoplay: preview.autoplay)
                                        .environmentObject(manager)
                                        .environmentObject(walkthroughManager)
                                        .environmentObject(demoModeManager)
                                }
                            }
#endif
                    }
                }
                    .transition(.opacity)
                    .animation(reduceMotion ? nil : .easeInOut, value: hasCompletedOnboarding)
                    .transaction { if reduceMotion { $0.disablesAnimations = true } }
                    .toastOverlay()
                    .environment(\.modelContext, container.mainContext)
                    .environmentObject(manager)
                    .environmentObject(walkthroughManager)
                    .environmentObject(demoModeManager)
                    .environmentObject(toastManager)
                    .tint(Color.goldfishAccent)
                    .onOpenURL { url in
                        do {
                            let staged = try GoldfishShareFile.stage(url)
                            if let previous = stagedShareURL { try? FileManager.default.removeItem(at: previous) }
                            stagedShareURL = staged
                            incomingShare = IdentifiableWrapper(staged)
                            showPendingShareNotice = !hasCompletedOnboarding
                        } catch { shareOpenError = error.localizedDescription }
                    }
                    .sheet(item: Binding(
                        get: { hasCompletedOnboarding ? incomingShare : nil },
                        set: { incomingShare = $0 }
                    ), onDismiss: {
                        if let staged = stagedShareURL { try? FileManager.default.removeItem(at: staged) }
                        stagedShareURL = nil
                    }) { wrapper in
                        GoldfishShareImportView(url: wrapper.value)
                            .environmentObject(manager)
                            .environmentObject(walkthroughManager)
                            .environmentObject(demoModeManager)
                    }
                    .alert("Your shared contacts are ready", isPresented: $showPendingShareNotice) {
                        Button("Continue") { }
                    } message: {
                        Text("Finish the welcome screen first. Then you can review and import the shared contacts and ponds.")
                    }
                    .alert("Could not open shared contacts", isPresented: Binding(
                        get: { shareOpenError != nil }, set: { if !$0 { shareOpenError = nil } }
                    )) {
                        Button("OK") { shareOpenError = nil }
                    } message: { Text(shareOpenError ?? "") }

            } else {
                ProgressView()
            }
        }
    }
    
    /// DEBUG-only direct screen presentation for headless verification.
    @ViewBuilder
    private var debugScreenView: some View {
        if let manager = dataManager {
            switch UserDefaults.standard.string(forKey: "gfDebugScreen") {
            case "settings":
                NavigationStack { SettingsView() }
            case "form":
                NavigationStack { ContactFormView(viewModel: ContactFormViewModel(dataManager: manager)) }
            case "lines":
                NavigationStack { CircleManagerView() }
            case "privacy":
                NavigationStack { PrivacyPolicyView() }
            case "export":
                NavigationStack { ContactExportSelectionView() }
            case "addrel":
                if let sourcePerson = (try? manager.fetchAllPersons())?.first(where: { !$0.isMe }) {
                    AddRelationshipView(person: sourcePerson, dataManager: manager)
                } else {
                    EmptyView()
                }
            case "connect", "connected", "move":
                // DEBUG screen fixtures use existing sample contacts and never edit them.
                let vm: GraphViewModel = {
                    let model = GraphViewModel(dataManager: manager)
                    model.isDemoMode = true
                    let people = (try? manager.fetchAllPersons()) ?? []
                    let mode = UserDefaults.standard.string(forKey: "gfDebugScreen")
                    if mode == "move" {
                        model.pendingPondMovePerson = people.first { $0.isDemo && $0.name == "Sarah Chen" }?.id
                        model.pendingPondMoveTarget = (try? manager.fetchAllCircles())?.first { $0.name == "Friends" }?.id.uuidString
                    } else {
                        model.pendingConnectionFrom = people.first { $0.isMe }?.id
                        let name = mode == "connected" ? "Sarah Chen" : "Priya Patel"
                        model.pendingConnectionTo = people.first { $0.isDemo && $0.name == name }?.id
                    }
                    return model
                }()
                GraphContainerView(viewModel: vm)
            case "search":
                let homeVM: HomeViewModel = {
                    let vm = HomeViewModel(dataManager: manager)
                    vm.isDemoMode = true
                    vm.loadData()
                    vm.searchText = "Sa"
                    return vm
                }()
                ZStack {
                    GoldfishDS.warmBlack.ignoresSafeArea()
                    SearchOverlayView(viewModel: homeVM, onSelect: { _ in })
                }
            default:
                EmptyView()
            }
        }
    }

    private var debugDetailEnabled: Bool {
        #if DEBUG
        return UserDefaults.standard.integer(forKey: "gfDebugDetail") == 1
        #else
        return false
        #endif
    }

#if DEBUG
    private var welcomeMotionPreview: (variant: WelcomeSwimVariant, autoplay: Bool)? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "--welcome-motion-preview"),
              arguments.indices.contains(flagIndex + 1),
              let index = Int(arguments[flagIndex + 1]),
              let variant = WelcomeSwimVariant(rawValue: index) else { return nil }
        return (variant, arguments.contains("--welcome-motion-autoplay"))
    }
#endif

    private var debugScreenOverride: AnyView? {
        #if DEBUG
        guard let name = UserDefaults.standard.string(forKey: "gfDebugScreen"),
              ["settings", "form", "lines", "privacy", "export", "addrel", "search", "connect", "connected", "move"].contains(name) else { return nil }
        // Toggle: `defaults write app.pond.goldfish gfDebugScreen -string settings|form|lines|privacy|export|addrel|search`
        return AnyView(debugScreenView)
        #else
        return nil
        #endif
    }

    private func retryDatabaseInit() {
        do {
            let container = try GoldfishModelContainer.production()
            self.modelContainer = container
            self.dataManager = GoldfishDataManager(context: container.mainContext)
            self.databaseError = nil
        } catch {
            self.databaseError = error
        }
    }
}
