import SwiftUI
import UniformTypeIdentifiers

// MARK: - SettingsViewModel
@MainActor
final class SettingsViewModel: ObservableObject {
    
    // MARK: - Dependencies
    let dataManager: GoldfishDataManager
    
    // MARK: - State
    @Published var appVersion: String = ""
    @Published var buildNumber: String = ""
    @Published var mePerson: Person?
    @Published var isExporting = false
    @Published var isImporting = false
    @Published var importProgress: String = ""
    
    // MARK: - Init
    init(dataManager: GoldfishDataManager) {
        self.dataManager = dataManager
        loadMePerson()
        loadVersion()
    }
    
    func loadMePerson() {
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
    
    // MARK: - Export
    func generateExportURL() -> URL? {
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
    func importContacts(from url: URL) {
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
                        self.importProgress = progress
                    }
                }
                await MainActor.run {
                    importProgress = "Done: \(result.importedCount) imported, \(result.skippedCount) skipped"
                    isImporting = false
                }
            } catch {
                await MainActor.run {
                    importProgress = "Failed: \(error.localizedDescription)"
                    isImporting = false
                }
            }
        }
    }
}
