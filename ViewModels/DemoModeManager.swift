import SwiftUI

// MARK: - Demo Mode Manager
/// Centralized manager for the demo mode toggle.
///
/// When demo mode is active, the app shows only demo contacts/connections
/// and hides real user data. When inactive, demo data is hidden and real
/// user data is shown. No data is ever deleted by toggling — only the
/// permanent "Remove Demo Data" action deletes demo contacts.
@MainActor
final class DemoModeManager: ObservableObject {
    
    /// Persisted demo mode state. When `true`, views show only demo data.
    @AppStorage("isDemoModeActive") var isDemoModeActive: Bool = false
    
    // MARK: - Actions
    
    /// Activates demo mode: seeds demo data if needed, then shows only demo data.
    func activateDemoMode(dataManager: GoldfishDataManager) {
        let service = DemoDataService(dataManager: dataManager)
        do {
            try service.seedDemoData()
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
    }
}
