import SwiftUI
import SwiftData
import Combine
import Contacts
import UniformTypeIdentifiers

// MARK: - View Mode
enum HomeViewMode: String, CaseIterable, Identifiable {
    case graph
    case list
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .graph: return "network"
        case .list: return "list.bullet"
        }
    }
}

// MARK: - List State
enum ListViewState: Equatable {
    case loading
    case populated
    case emptySearch
    case emptyPond(String)
    case emptyGlobal
}

// MARK: - HomeViewModel
@MainActor
final class HomeViewModel: ObservableObject {
    
    // MARK: - Dependencies
    private let dataManager: GoldfishDataManager
    
    /// When `true`, only show demo contacts; when `false`, only show real contacts.
    var isDemoMode: Bool = false
    
    // MARK: - Persistent State
    @AppStorage("homeViewMode") var viewMode: HomeViewMode = .graph
    @AppStorage("contactSortOrder") var sortOrder: String = "name"
    
    // MARK: - Ephemeral State
    @Published var searchText: String = ""
    @Published var isSearching: Bool = false
    @Published var selectedCircleID: UUID?
    @Published var showFavoritesOnly: Bool = false
    
    // MARK: - Import State
    @Published var isImporting = false
    @Published var importProgress: String = ""
    @Published var showImportCompletionAlert = false
    @Published var lastImportResult: ImportResult?
    
    // MARK: - Data
    struct ContactGroup: Identifiable {
        let id = UUID()
        let name: String
        let contacts: [Person]
    }
    
    @Published var contacts: [Person] = []
    @Published var filteredContacts: [Person] = []
    @Published var groupedContacts: [ContactGroup] = []
    @Published var circles: [GoldfishCircle] = []
    @Published var listState: ListViewState = .loading
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Init
    init(dataManager: GoldfishDataManager) {
        self.dataManager = dataManager
        
        setupSearchSubscription()
    }
    
    // MARK: - Setup
    private func setupSearchSubscription() {
        $searchText
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] query in
                self?.performSearch(query: query)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Data Loading
    func loadData() {
        do {
            // Load circles for filter
            self.circles = try dataManager.fetchAllCircles()
            
            // Initial load of all contacts
            // If in search mode, we don't reload all contacts to avoid nuking results
            if searchText.isEmpty {
                try fetchAllContacts()
            }
        } catch {
            print("Failed to load data: \(error)")
        }
    }
    
    private func fetchAllContacts() throws {
        // Apply basic filters (favorites, circle)
        // If sorting implementation is needed, we'd do it here. 
        // For now, simpler to fetch all and filter in memory since dataset is <1000.
        
        var all = try dataManager.fetchAllPersons()
        
        // Never show the "Me" contact in the contacts list
        // Filter by demo mode: show only demo or only real contacts
        all = all.filter { !$0.isMe && $0.isDemo == isDemoMode }
        
        if showFavoritesOnly {
            all = all.filter { $0.isFavorite }
        }
        
        if let circleID = selectedCircleID,
           let circle = circles.first(where: { $0.id == circleID }) {
            // This is O(N*M) effectively, but N is small.
            // Better: circle.activeContacts, but that requires circle object.
            // We have the circle object from the ID lookup.
            let memberIDs = Set(circle.activeContacts.map(\.id))
            all = all.filter { memberIDs.contains($0.id) }
        }
        
        // Sort
        if sortOrder == "dateAdded" {
            all.sort { $0.createdAt > $1.createdAt }
        } else {
            all.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        
        self.contacts = all
        self.filteredContacts = all // When not searching, filtered = all (or subset based on filters)
        self.updateGroupedContacts(from: all)
    }
    
    // MARK: - Search
    private func performSearch(query: String) {
        guard !query.isEmpty else {
            self.isSearching = false
            // Reset to full list (respecting current filters)
            loadData()
            return
        }
        
        self.isSearching = true
        
        Task {
            do {
                let results = try dataManager.search(query: query, demoMode: isDemoMode)
                
                // Apply active filters on top of search results
                var finalResults = results
                
                if showFavoritesOnly {
                    finalResults = finalResults.filter { $0.isFavorite }
                }
                
                if let circleID = selectedCircleID,
                   let circle = circles.first(where: { $0.id == circleID }) {
                    let memberIDs = Set(circle.activeContacts.map(\.id))
                    finalResults = finalResults.filter { memberIDs.contains($0.id) }
                }
                
                await MainActor.run {
                    self.filteredContacts = finalResults
                    self.updateGroupedContacts(from: finalResults)
                }
            } catch {
                print("Search failed: \(error)")
            }
        }
    }
    
    // MARK: - Actions
    
    func deleteContact(_ person: Person) {
        do {
            try dataManager.deletePerson(person)
            loadData() // Refresh list
        } catch {
            print("Failed to delete contact: \(error)")
        }
    }
    
    // MARK: - Grouping Helper
    private func updateGroupedContacts(from list: [Person]) {
        var groups: [String: [Person]] = [:]
        for person in list {
            let activeCircles = person.circleContacts.filter { !$0.manuallyExcluded }
            let circleName = activeCircles.first?.circle.name ?? "Unassigned"
            groups[circleName, default: []].append(person)
        }
        
        let sortedKeys = groups.keys.sorted { a, b in
            if a == "Unassigned" { return false }
            if b == "Unassigned" { return true }
            return a < b
        }
        
        self.groupedContacts = sortedKeys.map { ContactGroup(name: $0, contacts: groups[$0]!) }
        updateListState()
    }
    
    private func updateListState() {
        if !filteredContacts.isEmpty {
            listState = .populated
        } else if !searchText.isEmpty {
            listState = .emptySearch
        } else if let circleID = selectedCircleID, let circle = circles.first(where: { $0.id == circleID }) {
            listState = .emptyPond(circle.name)
        } else {
            listState = .emptyGlobal
        }
    }
    
    // MARK: - Import
    
    func importContacts(from contacts: [CNContact]) {
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
                        isDemo: self.isDemoMode,
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
                    self.loadData() // Refresh list after import!
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
