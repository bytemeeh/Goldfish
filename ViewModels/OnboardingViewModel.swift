import SwiftUI
@preconcurrency import Contacts

// MARK: - OnboardingViewModel
@MainActor
final class OnboardingViewModel: ObservableObject {
    
    // MARK: - Dependencies
    private let dataManager: GoldfishDataManager
    
    // MARK: - State
    @Published var currentTab = 0
    @Published var name: String = ""
    @Published var phone: String = ""
    @Published var email: String = ""
    
    @Published var isImporting: Bool = false
    @Published var importStatus: String = "Importing..."
    
    // MARK: - Init
    init(dataManager: GoldfishDataManager) {
        self.dataManager = dataManager
    }
    
    // MARK: - Actions
}
