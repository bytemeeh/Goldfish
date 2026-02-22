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
    func performReset() {
        guard let dataManager else { return }
        do {
            try dataManager.resetAllData()
            // Reset onboarding state in UserDefaults
            UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
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
                        phone: cn.phoneNumbers.first?.value.stringValue,
                        email: cn.emailAddresses.first?.value as String?,
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
    
    /// Formatted message for the import completion alert.
    var importAlertMessage: String {
        guard let result = lastImportResult else { return "" }
        
        var lines: [String] = []
        
        if result.isGoldfishFormat {
            lines.append("\(result.importedCount) contacts imported")
            if result.skippedCount > 0 {
                lines.append("\(result.skippedCount) duplicates skipped")
            }
            lines.append("\(result.connectionsRestored) connections restored")
            if result.connectionsSkipped > 0 {
                lines.append("\(result.connectionsSkipped) connections already existed")
            }
            if result.circlesCreated > 0 {
                lines.append("\(result.circlesCreated) new ponds created")
            }
        } else {
            lines.append("\(result.importedCount) contacts added")
            if result.skippedCount > 0 {
                lines.append("\(result.skippedCount) duplicates skipped")
            }
            lines.append("No Goldfish connection data found — contacts imported as standalone entries.")
        }
        
        if !result.errors.isEmpty {
            lines.append("\n⚠️ \(result.errors.count) error(s) occurred")
        }
        
        return lines.joined(separator: "\n")
    }
}
