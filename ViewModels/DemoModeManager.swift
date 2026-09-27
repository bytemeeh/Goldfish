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
    @Published var demoErrorMessage: String?
    
    // MARK: - Actions
    
    /// Activates demo mode: seeds demo data if needed, then shows only demo data.
    @discardableResult
    func activateDemoMode(dataManager: GoldfishDataManager) -> Bool {
        demoErrorMessage = nil
        let service = DemoDataService(dataManager: dataManager)
        do {
            guard try service.seedDemoData() else {
                isDemoModeActive = false
                demoErrorMessage = "Sample contacts are incomplete. Remove Sample Data, then try again."
                return false
            }
            isDemoModeActive = true
            return true
        } catch {
            print("Failed to seed demo data: \(error)")
            isDemoModeActive = false
            demoErrorMessage = "Couldn’t load sample contacts. Try again."
            return false
        }
    }
    
    /// Deactivates demo mode: hides demo data and shows real user data.
    /// Demo data stays in the database for future re-activation.
    func deactivateDemoMode() {
        isDemoModeActive = false
        demoErrorMessage = nil
    }
    
    /// Permanently removes all demo data from the database and deactivates demo mode.
    /// Returns false when deletion fails so callers can keep the failure visible.
    @discardableResult
    func removeDemoData(dataManager: GoldfishDataManager) -> Bool {
        removeDemoData {
            try DemoDataService(dataManager: dataManager).removeDemoData()
        }
    }

    /// Separates the user-visible state transition from the storage operation.
    /// The injected operation also keeps failure behavior directly testable.
    @discardableResult
    func removeDemoData(operation: () throws -> Void) -> Bool {
        demoErrorMessage = nil
        do {
            try operation()
            isDemoModeActive = false
            return true
        } catch {
            print("Failed to remove demo data: \(error)")
            demoErrorMessage = "Couldn’t remove sample contacts. Try again."
            return false
        }
    }

    /// Resets the demo mode state.
    func reset() {
        isDemoModeActive = false
        demoErrorMessage = nil
    }
}
