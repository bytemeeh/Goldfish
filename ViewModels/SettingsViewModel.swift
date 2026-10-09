import SwiftUI
import UniformTypeIdentifiers
import Contacts

// MARK: - SettingsViewModel
@MainActor
final class SettingsViewModel: ObservableObject {

    enum ImportOutcome: Equatable {
        case imported
        case alreadyHere
        case partial
        case noContactsFound
        case couldNotRead
    }

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
    /// Newly created contacts selected when the user chooses “Organize people”.
    @Published var importedContactIDs: Set<UUID> = []
    @Published var errorMessage: String?
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
        if isConfigured { loadMePerson(); return }
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
    @discardableResult
    func performReset(
        walkthroughManager: FeatureWalkthroughManager,
        demoModeManager: DemoModeManager
    ) -> Bool {
        guard let dataManager, !isImporting else { return false }
        do {
            // Change launch flags only after the database deletion succeeds.
            try dataManager.resetAllData()
            ConnectionSession.shared.finish()
            walkthroughManager.reset()
            demoModeManager.reset()
            let defaults = UserDefaults.standard
            defaults.set(false, forKey: "hasCompletedOnboarding")
            defaults.set("graph", forKey: "homeViewMode")
            defaults.set("name", forKey: "contactSortOrder")
            return true
        } catch {
            errorMessage = "Could not reset: " + error.localizedDescription
            return false
        }
    }

    // MARK: - Export
    func generateExportURL() -> URL? {
        guard let dataManager else { return nil }
        do {
            let contacts = try dataManager.fetchAllPersons().filter { !$0.isDemo }
            let service = VCardExportService()
            let data = service.exportAll(contacts: contacts)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("GoldfishExport.vcf")
            try data.write(to: url)
            return url
        } catch {
            errorMessage = "Could not export: " + error.localizedDescription
            return nil
        }
    }

    // MARK: - Import

    // Both import entry points use the same duplicate and relationship rules.
    func importContacts(from contacts: [CNContact]) {
        guard dataManager != nil, !isImporting else { return }
        isImporting = true
        importProgress = "Reading contacts..."
        Task {
            do {
                let data = try CNContactVCardSerialization.data(with: contacts)
                try await importData(data)
            } catch { finishImportFailure(error) }
        }
    }

    func importContacts(from url: URL) {
        guard dataManager != nil, !isImporting else { return }
        isImporting = true
        importProgress = "Reading file..."
        Task {
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                try await importData(data)
            } catch { finishImportFailure(error) }
        }
    }

    private func importData(_ data: Data) async throws {
        guard let dataManager else { throw GoldfishError.contactNotFound }
        let service = VCardImportService(modelContainer: dataManager.context.container)
        let result = try await service.importContacts(data) { [weak self] progress in
            Task { @MainActor in
                guard let self, self.isImporting else { return }
                self.importProgress = "Importing... \(Int(progress * 100))%"
            }
        }
        lastImportResult = result
        importedContactIDs = result.importedContactIDs
        isImporting = false
        importProgress = ""
        showImportCompletionAlert = true
        NotificationCenter.default.post(name: .goldfishDataDidChange, object: nil)
    }

    private func finishImportFailure(_ error: Error) {
        isImporting = false
        importProgress = ""
        errorMessage = "Could not import: " + error.localizedDescription
    }

    // MARK: - Import Result Formatting

    var importOutcome: ImportOutcome? {
        guard let result = lastImportResult else { return nil }
        let usableCount = result.importedCount + result.skippedCount
        if usableCount == 0 {
            return result.errors.isEmpty ? .noContactsFound : .couldNotRead
        }
        if !result.errors.isEmpty { return .partial }
        return result.importedCount > 0 ? .imported : .alreadyHere
    }

    var hasImportDetails: Bool {
        guard let result = lastImportResult else { return false }
        return !result.skippedDuplicates.isEmpty || !result.errors.isEmpty
    }

    var importDetailLines: [String] {
        guard let result = lastImportResult else { return [] }
        let duplicates = result.skippedDuplicates.prefix(5).map { "Already here: \($0)" }
        let errors = result.errors.prefix(5).map { "Could not process: \($0)" }
        return Array(duplicates) + Array(errors)
    }

    var importDetailOverflowCount: Int {
        guard let result = lastImportResult else { return 0 }
        return max(0, result.skippedDuplicates.count - 5) + max(0, result.errors.count - 5)
    }

    var importAlertTitle: String {
        switch importOutcome {
        case .imported: return lastImportResult?.isGoldfishFormat == true ? "Goldfish Import Complete" : "Contacts Imported"
        case .alreadyHere: return "Already Here"
        case .partial: return "Import Partially Complete"
        case .noContactsFound: return "No Contacts Found"
        case .couldNotRead: return "Couldn’t Read Contacts"
        case nil: return "Import Complete"
        }
    }

    var importAlertMessage: String {
        guard let result = lastImportResult else { return "" }
        var lines: [String] = []

        switch importOutcome {
        case .noContactsFound:
            lines.append("No contacts were found in this selection.")
        case .couldNotRead:
            lines.append("The file did not contain readable contacts.")
        case .alreadyHere:
            lines.append("\(result.skippedCount) contacts were already here. No new contacts were added.")
        default:
            if result.importedCount > 0 { lines.append("\(result.importedCount) contacts imported") }
            if result.skippedCount > 0 { lines.append("\(result.skippedCount) duplicates skipped") }
        }

        if result.isGoldfishFormat {
            if result.connectionsRestored > 0 { lines.append("\(result.connectionsRestored) connections restored") }
            if result.connectionsSkipped > 0 { lines.append("\(result.connectionsSkipped) connections already existed or could not be restored") }
            if result.circlesCreated > 0 { lines.append("\(result.circlesCreated) new ponds created") }
        } else if result.importedCount + result.skippedCount > 0 {
            lines.append("This vCard does not include Goldfish connection or pond data.")
        }

        if !result.errors.isEmpty && importOutcome != .couldNotRead {
            lines.append("Some entries could not be processed. Open Details to review them.")
        }

        return lines.joined(separator: "\n")
    }
}
