import SwiftUI
import SwiftData

// MARK: - App Entry Point
@main
struct GoldfishApp: App {
    /// Tracks whether onboarding is complete.
    /// If false, we show the `OnboardingFlow`.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    /// The SwiftData container.
    @State private var modelContainer: ModelContainer?
    
    /// Tracks initialization errors (e.g., corruption).
    @State private var databaseError: Error?
    
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
            let container = try GoldfishModelContainer.production()
            _modelContainer = State(initialValue: container)
            _dataManager = State(initialValue: GoldfishDataManager(context: container.mainContext))
        } catch {
            _databaseError = State(initialValue: error)
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
                    if !hasCompletedOnboarding {
                        // Show ONLY onboarding — no HomeView underneath
                        OnboardingFlow()
                            .transition(.opacity)
                    } else {
                        HomeView()
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut, value: hasCompletedOnboarding)
                .toastOverlay()
                .environment(\.modelContext, container.mainContext)
                .environmentObject(manager)
                .environmentObject(walkthroughManager)
                .environmentObject(demoModeManager)
                .environmentObject(toastManager)
                .preferredColorScheme(.dark)
                .tint(Color.goldfishAccent)
            } else {
                ProgressView()
            }
        }
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
