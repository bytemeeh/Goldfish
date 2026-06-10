import SwiftUI
import UniformTypeIdentifiers
import Contacts

// MARK: - SettingsViewModel
@MainActor
final class SettingsViewModel: ObservableObject {
    
    // MARK: - Dependencies
    private var dataManager: GoldfishDataManager?
    
    // MARK: - State
    @Published var appVersion: String = ""
    @Published var buildNumber: String = ""
    @Published var mePerson: Person?
    @Published var isExporting = false
    @Published var isImporting = false
    @Published var importProgress: String = ""
    @Published var showImportCompletionAlert = false
    @Published var lastImportResult: ImportResult?
    private var isConfigured = false
    
    var hasManualContacts: Bool {
        guard let dataManager else { return false }
        return (try? dataManager.fetchManualContactsCount()) ?? 0 > 0
    }
    
    // MARK: - Init
    init() {
        loadVersion()
    }
    
    /// Called from onAppear once the EnvironmentObject is available.
    func configure(dataManager: GoldfishDataManager) {
        guard !isConfigured else { return }
        self.dataManager = dataManager
        self.isConfigured = true
        loadMePerson()
    }
    
    func loadMePerson() {
        guard let dataManager else { return }
        do {
            self.mePerson = try dataManager.fetchMePerson()
        } catch {
            print("Error fetching ME person: \(error)")
        }
    }
    
    private func loadVersion() {
        let dictionary = Bundle.main.infoDictionary
        self.appVersion = dictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        self.buildNumber = dictionary?["CFBundleVersion"] as? String ?? "1"
    }

    // MARK: - Reset
    func performReset(
        walkthroughManager: FeatureWalkthroughManager,
        demoModeManager: DemoModeManager
    ) {
        guard let dataManager else { return }
        
        // 1. Reset managers (handles their specific UserDefaults and @Published flags)
        walkthroughManager.reset()
        demoModeManager.reset()

        // 2. Clear application-level flags
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: "hasCompletedOnboarding")
        defaults.set("graph", forKey: "homeViewMode")
        defaults.set("name", forKey: "contactSortOrder")

        // 3. Clear the database
        do {
            try dataManager.resetAllData()
        } catch {
            print("Error resetting data: \(error)")
        }
    }
    
    // MARK: - Export
    func generateExportURL() -> URL? {
        guard let dataManager else { return nil }
        do {
            let contacts = try dataManager.fetchAllPersons()
            let service = VCardExportService()
            let data = service.exportAll(contacts: contacts)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("GoldfishExport.vcf")
            try data.write(to: url)
            return url
        } catch {
            print("Export error: \(error)")
            return nil
        }
    }
    
    // MARK: - Import
    
    // Phonebook import
    func importContacts(from contacts: [CNContact]) {
        guard let dataManager else { return }
        isImporting = true
        importProgress = "Reading contacts..."
        
        Task {
            do {
                var importedCount = 0
                for cn in contacts {
                    let fullName = [cn.givenName, cn.familyName]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    guard !fullName.isEmpty else { continue }
                    
                    try dataManager.createPerson(
                        name: fullName,
                        birthday: cn.birthday.flatMap { Calendar.current.date(from: $0) },
                        photoData: cn.imageData
                    )
                    importedCount += 1
                }
                
                await MainActor.run {
                    self.lastImportResult = ImportResult(
                        importedCount: importedCount,
                        skippedCount: 0,
                        errors: [],
                        skippedDuplicates: [],
                        isGoldfishFormat: false,
                        goldfishVersion: nil,
                        connectionsRestored: 0,
                        connectionsSkipped: 0,
                        circlesCreated: 0,
                        circlesExisting: 0
                    )
                    self.isImporting = false
                    self.importProgress = ""
                    self.showImportCompletionAlert = true
                }
            } catch {
                await MainActor.run {
                    importProgress = "Failed: \(error.localizedDescription)"
                    isImporting = false
                }
            }
        }
    }
    
    // File import
    func importContacts(from url: URL) {
        guard let dataManager else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        
        isImporting = true
        importProgress = "Reading file..."
        
        Task {
            do {
                let data = try Data(contentsOf: url)
                let container = dataManager.context.container
                let service = VCardImportService(modelContainer: container)
                let result = try await service.importContacts(data) { progress in
                    Task { @MainActor in
                        self.importProgress = "Importing... \(Int(progress * 100))%"
                    }
                }
                await MainActor.run {
                    self.lastImportResult = result
                    self.isImporting = false
                    self.importProgress = ""
                    self.showImportCompletionAlert = true
                }
            } catch {
                await MainActor.run {
                    importProgress = "Failed: \(error.localizedDescription)"
                    isImporting = false
                }
            }
        }
    }
    
    // MARK: - Import Result Formatting
    
    /// Formatted title for the import completion alert.
    var importAlertTitle: String {
        guard let result = lastImportResult else { return "Import Complete" }
        if result.isGoldfishFormat {
            return "Goldfish File Detected ✓"
        } else {
            return "Import Complete"
        }
    }
    
    var importAlertMessage: String {
        guard let result = lastImportResult else { return "" }
        
        var lines: [String] = []
        
        if result.isGoldfishFormat {
            let contactStr = result.importedCount == 1 ? "contact" : "contacts"
            lines.append("\(result.importedCount) \(contactStr) imported")
            
            if result.skippedCount > 0 {
                let dupStr = result.skippedCount == 1 ? "duplicate" : "duplicates"
                lines.append("\(result.skippedCount) \(dupStr) skipped")
            }
            
            let connStr = result.connectionsRestored == 1 ? "connection" : "connections"
            lines.append("\(result.connectionsRestored) \(connStr) restored")
            
            if result.connectionsSkipped > 0 {
                let connSkipStr = result.connectionsSkipped == 1 ? "connection" : "connections"
                lines.append("\(result.connectionsSkipped) \(connSkipStr) already existed")
            }
            
            if result.circlesCreated > 0 {
                let pondStr = result.circlesCreated == 1 ? "pond" : "ponds"
                lines.append("\(result.circlesCreated) new \(pondStr) created")
            }
        } else {
            let contactStr = result.importedCount == 1 ? "contact" : "contacts"
            lines.append("\(result.importedCount) \(contactStr) added")
            
            if result.skippedCount > 0 {
                let dupStr = result.skippedCount == 1 ? "duplicate" : "duplicates"
                lines.append("\(result.skippedCount) \(dupStr) skipped")
            }
            
            lines.append("Imported without pond or connection data.")
        }
        
        if !result.errors.isEmpty {
            let errStr = result.errors.count == 1 ? "error" : "errors"
            lines.append("\n⚠️ \(result.errors.count) \(errStr) occurred")
        }
        
        return lines.joined(separator: "\n")
    }
}
