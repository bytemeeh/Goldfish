import SwiftUI

// MARK: - Demo Mode Manager
/// **Single source of truth** for demo data seeding and visibility.
///
/// When demo mode is active, the app shows only demo contacts/connections
/// and hides real user data. When inactive, demo data is hidden and real
/// user data is shown. No data is ever deleted by toggling — only the
/// permanent "Remove Demo Data" action deletes demo contacts.
///
/// All seeding flows (onboarding, settings toggle, walkthrough replay)
/// go through `activateDemoMode(dataManager:)` to guarantee consistency.
@MainActor
final class DemoModeManager: ObservableObject {
    
    /// Persisted demo mode state. When `true`, views show only demo data.
    @AppStorage("isDemoModeActive") var isDemoModeActive: Bool = false
    
    /// Persisted flag tracking whether demo data has been successfully seeded.
    /// Survives relaunches so we don't attempt redundant seeding.
    @AppStorage("isDemoDataSeeded") var isDemoDataSeeded: Bool = false
    
    // MARK: - Actions
    
    /// Activates demo mode: seeds demo data if needed (and repairs any
    /// missing circle assignments), then shows only demo data.
    func activateDemoMode(dataManager: GoldfishDataManager) {
        let service = DemoDataService(dataManager: dataManager)
        do {
            // Always call seedDemoData — it's idempotent and will repair
            // missing circle assignments even if contacts already exist.
            let didSeed = try service.seedDemoData()
            if didSeed {
                isDemoDataSeeded = true
            }
        } catch {
            print("Failed to seed demo data: \(error)")
        }
        isDemoModeActive = true
    }
    
    /// Deactivates demo mode: hides demo data and shows real user data.
    /// Demo data stays in the database for future re-activation.
    func deactivateDemoMode() {
        isDemoModeActive = false
    }
    
    /// Permanently removes all demo data from the database and deactivates demo mode.
    func removeDemoData(dataManager: GoldfishDataManager) {
        let service = DemoDataService(dataManager: dataManager)
        do {
            try service.removeDemoData()
        } catch {
            print("Failed to remove demo data: \(error)")
        }
        isDemoModeActive = false
        isDemoDataSeeded = false
    }

    /// Resets the demo mode state.
    func reset() {
        isDemoModeActive = false
        isDemoDataSeeded = false
    }
}
