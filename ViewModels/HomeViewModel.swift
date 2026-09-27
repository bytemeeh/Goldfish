import SwiftUI
import SwiftData
import Combine

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
    /// Circle UUID strings are used for cross-view scope synchronization;
    /// `unassigned` is the explicit virtual scope.
    @Published var selectedScopeID: String?
    @Published var showFavoritesOnly: Bool = false
    
    // MARK: - Data
    struct ContactGroup: Identifiable {
        let id: String
        let name: String
        let contacts: [Person]
    }
    
    @Published var contacts: [Person] = []
    @Published var filteredContacts: [Person] = []
    @Published var groupedContacts: [ContactGroup] = []
    @Published var circles: [GoldfishCircle] = []
    @Published var listState: ListViewState = .loading
    @Published var errorMessage: String?
    @Published var relationshipSearch: RelationshipSearchResponse?

    var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var scopeName: String? {
        guard let selectedScopeID else { return nil }
        if selectedScopeID == "unassigned" { return "Unassigned" }
        return circles.first { $0.id.uuidString == selectedScopeID }?.name
    }

    var visibleScopeLabel: String {
        let base = isDemoMode ? "Sample pond" : "Your pond"
        let count = filteredContacts.count
        if isSearching {
            return "\(base) · \(count) \(count == 1 ? "match" : "matches")"
        }
        let noun = count == 1 ? "person" : "people"
        if let scopeName { return "\(base) · \(scopeName) · \(count) \(noun)" }
        return "\(base) · \(count) \(noun)"
    }
    
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
            if let selectedScopeID,
               selectedScopeID != "unassigned",
               !circles.contains(where: { $0.id.uuidString == selectedScopeID }) {
                self.selectedScopeID = nil
            }
            try fetchAllContacts()
            if !normalizedSearchText.isEmpty {
                performSearch(query: normalizedSearchText)
            } else {
                isSearching = false
                relationshipSearch = nil
            }
        } catch {
            errorMessage = "Could not load contacts: \(error.localizedDescription)"
            if contacts.isEmpty { listState = .emptyGlobal }
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
        
        if let selectedScopeID {
            if selectedScopeID == "unassigned" {
                all = all.filter { $0.primaryCircle == nil }
            } else if let circle = circles.first(where: { $0.id.uuidString == selectedScopeID }) {
                // Match the primary group used by the map and its counts.
                all = all.filter { $0.primaryCircle?.id == circle.id }
            }
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
    func performSearch(query: String) {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            self.isSearching = false
            relationshipSearch = nil
            // Reset to full list (respecting current filters)
            do { try fetchAllContacts() }
            catch { errorMessage = "Could not load contacts: \(error.localizedDescription)" }
            return
        }
        
        self.isSearching = true
        
        do {
                let chain = try dataManager.relationshipSearch(query: normalizedQuery, demoMode: isDemoMode)
                var uniqueIDs = Set<UUID>()
                let results = try chain.map { $0.paths.map(\.person).filter { uniqueIDs.insert($0.id).inserted } }
                    ?? dataManager.search(query: normalizedQuery, demoMode: isDemoMode)
                
                // Apply active filters on top of search results
                var finalResults = results
                
                if showFavoritesOnly {
                    finalResults = finalResults.filter { $0.isFavorite }
                }
                
                if let selectedScopeID {
                    if selectedScopeID == "unassigned" {
                        finalResults = finalResults.filter { $0.primaryCircle == nil }
                    } else if let circle = circles.first(where: { $0.id.uuidString == selectedScopeID }) {
                        finalResults = finalResults.filter { $0.primaryCircle?.id == circle.id }
                    }
                }
                
                if var chain {
                    let visibleIDs = Set(finalResults.map(\.id))
                    let total = chain.matchedContactCount
                    chain.paths = chain.paths.filter { visibleIDs.contains($0.person.id) }
                    let hidden = total - chain.matchedContactCount
                    if hidden > 0 {
                        let notice = "\(hidden) matching \(hidden == 1 ? "contact is" : "contacts are") outside the current filters. Clear filters to see all matches."
                        chain.message = [chain.message, notice].compactMap { $0 }.joined(separator: " ")
                    }
                    relationshipSearch = chain
                } else { relationshipSearch = nil }
                self.filteredContacts = finalResults
                self.updateGroupedContacts(from: finalResults)
        } catch {
            relationshipSearch = RelationshipSearchResponse(query: nil, paths: [], anchorMatches: [], message: "Search could not load your connections. Try again.", isTruncated: false)
            self.filteredContacts = []
            self.updateGroupedContacts(from: [])
            ToastManager.shared.showToast(message: "Search failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Actions
    func toggleViewMode() {
        viewMode = (viewMode == .graph) ? .list : .graph
    }
    
    func deleteContact(_ person: Person) {
        do {
            try dataManager.deletePerson(person)
            loadData() // Refresh list
        } catch {
            errorMessage = "Could not delete contact: \(error.localizedDescription)"
        }
    }
    
    func toggleFavoriteFilter() {
        showFavoritesOnly.toggle()
        loadData()
    }
    
    func selectCircleFilter(_ circle: GoldfishCircle?) {
        selectedScopeID = circle?.id.uuidString
        loadData()
    }

    func selectScope(_ scopeID: String?) {
        selectedScopeID = scopeID
        loadData()
    }

    /// Returns a truthful reason for a result that matched outside the name.
    func matchContext(for person: Person) -> String? {
        if let path = relationshipSearch?.paths.first(where: { $0.person.id == person.id }) { return path.summary }
        let query = normalizedSearchText
        guard !query.isEmpty else { return nil }
        if person.name.localizedCaseInsensitiveContains(query) { return nil }
        if (person.email ?? "").localizedCaseInsensitiveContains(query) { return "Email match" }
        if (person.phone ?? "").localizedCaseInsensitiveContains(query) { return "Phone match" }
        if (person.notes ?? "").localizedCaseInsensitiveContains(query) { return "Note match" }
        if person.tags.contains(where: { $0.localizedCaseInsensitiveContains(query) }) { return "Tag match" }
        if person.circleContacts.contains(where: { !$0.manuallyExcluded && $0.circle.name.localizedCaseInsensitiveContains(query) }) {
            return "Pond match"
        }
        let matchingTypes = RelationshipType.allCases.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
        if !matchingTypes.isEmpty,
           person.allRelationships.contains(where: { rel in
               let type = RelationshipType(rawValue: rel.typeRawValue) ?? .other
               return matchingTypes.contains(type)
           }) {
            return "Relationship match"
        }
        return "Contact detail match"
    }
    
    // MARK: - Grouping Helper
    private func updateGroupedContacts(from list: [Person]) {
        var groups: [String: [Person]] = [:]
        for person in list {
            let groupID = person.primaryCircle?.id.uuidString ?? "unassigned"
            groups[groupID, default: []].append(person)
        }
        
        let sortedKeys = groups.keys.sorted { a, b in
            if a == "unassigned" { return false }
            if b == "unassigned" { return true }
            let lhs = groups[a]?.first?.primaryCircle
            let rhs = groups[b]?.first?.primaryCircle
            if lhs?.sortOrder != rhs?.sortOrder { return (lhs?.sortOrder ?? 0) < (rhs?.sortOrder ?? 0) }
            let comparison = (lhs?.name ?? "").localizedStandardCompare(rhs?.name ?? "")
            return comparison == .orderedSame ? a < b : comparison == .orderedAscending
        }

        self.groupedContacts = sortedKeys.map { ContactGroup(id: $0, name: groups[$0]?.first?.primaryCircle?.name ?? "Unassigned", contacts: groups[$0] ?? []) }
        updateListState()
    }
    
    private func updateListState() {
        if !filteredContacts.isEmpty {
            listState = .populated
        } else if !normalizedSearchText.isEmpty {
            listState = .emptySearch
        } else if let selectedScopeID {
            listState = .emptyPond(scopeName ?? (selectedScopeID == "unassigned" ? "Unassigned" : "Selected pond"))
        } else {
            listState = .emptyGlobal
        }
    }
}
