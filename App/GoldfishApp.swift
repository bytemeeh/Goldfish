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
                    // Retry logic: crash/restart or attempt re-init
                    // For simplicity, we just try to re-init
                    retryDatabaseInit()
                }
            } else if let container = modelContainer, let manager = dataManager {
                // Happy path
                // Note: We use a ZStack or Group to conditionalize Onboarding
                // But .fullScreenCover on Root is better for onboarding per spec
                HomeView()
                    .environment(\.modelContext, container.mainContext)
                    .environmentObject(manager)
                    .fullScreenCover(isPresented: Binding(
                        get: { !hasCompletedOnboarding },
                        set: { _ in } // logic handles dismissal via state change
                    )) {
                        OnboardingFlow()
                            .environment(\.modelContext, container.mainContext)
                            .environmentObject(manager)
                    }
            } else {
                // Loading state (should be sub-millisecond unless something weird happens)
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
