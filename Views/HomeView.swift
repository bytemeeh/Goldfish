import SwiftUI

// MARK: - Home View
/// The main view after onboarding. Shows contacts list or graph,
/// with toolbar buttons for settings, view toggle, and add contact.
struct HomeView: View {
    @EnvironmentObject var dataManager: GoldfishDataManager

    var body: some View {
        HomeContent(dataManager: dataManager)
            .environmentObject(dataManager)
    }
}

// MARK: - Home Content
/// Separated so we can properly inject the real dataManager into ViewModels.
private struct HomeContent: View {
    @EnvironmentObject var dataManager: GoldfishDataManager

    @EnvironmentObject var walkthroughManager: FeatureWalkthroughManager
    @EnvironmentObject var demoModeManager: DemoModeManager
    @StateObject private var viewModel: HomeViewModel
    @StateObject private var graphViewModel: GraphViewModel

    /// Tracks whether the user has completed the initial sign-in onboarding.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var showSearchBar = false
    @State private var showingAddOptions = false
    @State private var activeSheet: ActiveSheet?
    @State private var searchSelectedPerson: Person?
    @State private var pendingDeletePerson: Person?
    @FocusState private var isSearchFocused: Bool

    private enum ActiveSheet: String, Identifiable, Equatable {
        case settings, addContact, phonebookPicker, addContactOptions, aiVoiceAdd
        var id: String { rawValue }
    }

    init(dataManager: GoldfishDataManager) {
        _viewModel = StateObject(wrappedValue: HomeViewModel(dataManager: dataManager))
        _graphViewModel = StateObject(wrappedValue: GraphViewModel(dataManager: dataManager))
    }

    var body: some View {
        ZStack {
            NavigationStack {
                VStack(spacing: 0) {
                    if showSearchBar { searchBar }
                    mainContent
                }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        viewModePicker
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        trailingToolbarButtons
                    }
                }
                .navigationDestination(item: $searchSelectedPerson) { person in
                    ContactDetailView(
                        viewModel: ContactDetailViewModel(
                            person: person,
                            dataManager: dataManager
                        )
                    )
                    .environmentObject(dataManager)
                }
                .tint(.goldfishAccent)
            }

            // ── Onboarding Sign-In Overlay ──
            // Sits directly inside this ZStack so the ponds graph remains
            // visible through the transparent top portion of the overlay.
            if !hasCompletedOnboarding {
                OnboardingSignInOverlay()
                    .environmentObject(dataManager)
                    .environmentObject(walkthroughManager)
                    .environmentObject(demoModeManager)
                    .environmentObject(ToastManager.shared)
                    .ignoresSafeArea()
                    .zIndex(5000)
            }
        }
        .sheet(item: $activeSheet, onDismiss: {
            viewModel.loadData()
            graphViewModel.refreshGraph()
        }) { sheet in
            switch sheet {
            case .settings:
                NavigationStack {
                    SettingsView()
                        .environmentObject(dataManager)
                }
            case .addContact:
                NavigationStack {
                    ContactFormView(viewModel: ContactFormViewModel(dataManager: dataManager))
                        .environmentObject(dataManager)
                }
            case .phonebookPicker:
                ContactPicker(isPresented: Binding(
                    get: { activeSheet == .phonebookPicker },
                    set: { if !$0 { activeSheet = nil } }
                )) { selectedContacts in
                    viewModel.importContacts(from: selectedContacts)
                }
            case .addContactOptions:
                AddContactSheet(
                    onVoiceEntry: {
                        activeSheet = .aiVoiceAdd
                    },
                    onPhonebook: {
                        activeSheet = .phonebookPicker
                    },
                    onManual: {
                        activeSheet = .addContact
                    }
                )
                .presentationDetents([.height(340)])
                .presentationDragIndicator(.hidden)
            case .aiVoiceAdd:
                AIVoiceAddView(dataManager: dataManager)
                    .environmentObject(dataManager)
            }
        }
        .sheet(isPresented: $viewModel.showImportCompletionAlert) {
            if let result = viewModel.lastImportResult {
                ImportSummarySheet(result: result) {
                    viewModel.showImportCompletionAlert = false
                    graphViewModel.refreshGraph()
                }
                .presentationDetents([.medium])
            }
        }
        .onAppear {
            setupWalkthroughCallbacks()
            let demoMode = demoModeManager.isDemoModeActive
            viewModel.isDemoMode = demoMode
            graphViewModel.isDemoMode = demoMode
            viewModel.loadData()
            if viewModel.viewMode == .graph {
                graphViewModel.loadGraph()
            }
            // Switch to graph view for onboarding so ponds are visible
            if !hasCompletedOnboarding {
                viewModel.viewMode = .graph
            }
            // Start the walkthrough if onboarding is already done (returning user)
            if hasCompletedOnboarding {
                walkthroughManager.startWalkthroughIfNeeded(dataManager: dataManager)
            }
            // Refresh to pick up any freshly seeded demo data
            graphViewModel.refreshGraph()
        }
        .onChange(of: demoModeManager.isDemoModeActive) { _, isDemoActive in
            let demoMode = walkthroughManager.isActive || isDemoActive
            viewModel.isDemoMode = demoMode
            graphViewModel.isDemoMode = demoMode
            viewModel.loadData()
            graphViewModel.refreshGraph()
        }
        .onChange(of: walkthroughManager.isActive) { _, isActive in
            let demoMode = isActive || demoModeManager.isDemoModeActive
            if viewModel.isDemoMode != demoMode {
                viewModel.isDemoMode = demoMode
                graphViewModel.isDemoMode = demoMode
                viewModel.loadData()
                graphViewModel.refreshGraph()
                if isActive {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        graphViewModel.resetCamera()
                    }
                }
            }
        }
        .walkthroughOverlay()
        .onChange(of: viewModel.viewMode) { _, newMode in
            if newMode == .graph {
                graphViewModel.refreshGraph()
            }
        }
        .onChange(of: hasCompletedOnboarding) { _, completed in
            if completed {
                let demoMode = demoModeManager.isDemoModeActive
                graphViewModel.isDemoMode = demoMode
                viewModel.isDemoMode = demoMode
                graphViewModel.refreshGraph()
                setupWalkthroughCallbacks()
                walkthroughManager.startWalkthroughIfNeeded(dataManager: dataManager)
            }
        }
    }

    // MARK: - Sub-views (extracted to help the Swift type-checker)

    private var viewModePicker: some View {
        Picker("View Mode", selection: Binding(
            get: { viewModel.viewMode },
            set: { viewModel.viewMode = $0 }
        )) {
            Text("Ponds").tag(HomeViewMode.graph)
            Text("Contacts").tag(HomeViewMode.list)
        }
        .pickerStyle(.segmented)
        .frame(width: 200)
    }

    @ViewBuilder private var trailingToolbarButtons: some View {
        Button {
            withAnimation {
                showSearchBar.toggle()
                isSearchFocused = showSearchBar
                if !showSearchBar { viewModel.searchText = "" }
            }
        } label: { Image(systemName: "magnifyingglass") }
        Button { activeSheet = .settings } label: { Image(systemName: "gear") }
        Button { activeSheet = .addContactOptions } label: { Image(systemName: "plus") }
            .walkthroughAnchor(step: .addContact)
    }

    @ViewBuilder private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundColor(.gray)
            TextField("Search contacts", text: $viewModel.searchText)
                .focused($isSearchFocused)
                .disableAutocorrection(true)
            if !viewModel.searchText.isEmpty {
                Button { viewModel.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                }
            }
            Button("Cancel") {
                withAnimation {
                    showSearchBar = false
                    viewModel.searchText = ""
                    isSearchFocused = false
                }
            }
            .foregroundColor(.goldfishAccent)
            .padding(.leading, 8)
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder private var mainContent: some View {
        ZStack(alignment: .top) {
            if viewModel.viewMode == .graph {
                GraphContainerView(viewModel: graphViewModel)
                    .onChange(of: viewModel.isSearching) { _, active in
                        if active && !viewModel.searchText.isEmpty {
                            graphViewModel.searchMatchedIDs = Set(viewModel.filteredContacts.map(\.id))
                        } else {
                            graphViewModel.searchMatchedIDs = nil
                        }
                    }
                    .onChange(of: viewModel.filteredContacts) { _, contacts in
                        if viewModel.isSearching && !viewModel.searchText.isEmpty {
                            graphViewModel.searchMatchedIDs = Set(contacts.map(\.id))
                        } else {
                            graphViewModel.searchMatchedIDs = nil
                        }
                    }
                    .onChange(of: demoModeManager.isDemoModeActive) { _, _ in }
                    .onAppear {
                        graphViewModel.isDemoMode = demoModeManager.isDemoModeActive
                        viewModel.isDemoMode = demoModeManager.isDemoModeActive
                    }
            } else {
                contactsList
            }
            if showSearchBar && !viewModel.searchText.isEmpty {
                SearchOverlayView(
                    viewModel: viewModel,
                    onSelect: { person in
                        isSearchFocused = false
                        if viewModel.viewMode == .graph {
                            graphViewModel.selectContact(person.id)
                        } else {
                            searchSelectedPerson = person
                        }
                    }
                )
                .padding(.horizontal)
            }
        }
    }

    private func setupWalkthroughCallbacks() {
        walkthroughManager.onRequestGraphView = {
            withAnimation { viewModel.viewMode = .graph }
        }
        walkthroughManager.onRequestListView = {
            withAnimation { viewModel.viewMode = .list }
        }
        walkthroughManager.onTourCompleted = { keepDemoData in
            if keepDemoData {
                demoModeManager.activateDemoMode(dataManager: dataManager)
            } else {
                demoModeManager.removeDemoData(dataManager: dataManager)
            }
            viewModel.loadData()
            graphViewModel.refreshGraph()
        }
    }

    // MARK: - Contacts List
    private var contactsList: some View {
        Group {
            switch viewModel.listState {
            case .loading:
                ProgressView()
            case .emptyGlobal:
                EmptyStateView(
                    systemImage: "person.3.sequence.fill",
                    headline: "Your pond is empty",
                    subtext: "Tap the + button to add your first contact."
                )
            case .emptyPond(let pondName):
                EmptyStateView(
                    systemImage: "circle.grid.cross.fill",
                    headline: "Empty pond",
                    subtext: "There are no contacts in the \(pondName) pond."
                )
            case .emptySearch:
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    headline: "No results",
                    subtext: "Try a different search term."
                )
            case .populated:
                List {
                    ForEach(viewModel.groupedContacts) { group in
                        Section(header: Text(group.name).font(.title3.bold()).foregroundColor(.white).textCase(nil).padding(.top, 4)) {
                            ForEach(group.contacts) { person in
                                NavigationLink {
                                    ContactDetailView(
                                        viewModel: ContactDetailViewModel(
                                            person: person,
                                            dataManager: dataManager
                                        )
                                    )
                                    .environmentObject(dataManager)
                                } label: {
                                    ContactRowView(person: person)
                                }
                            }
                            .onDelete { offsets in
                                if let offset = offsets.first {
                                    pendingDeletePerson = group.contacts[offset]
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .confirmationDialog(
                    "Delete \(pendingDeletePerson?.name ?? "Contact")?",
                    isPresented: Binding(
                        get: { pendingDeletePerson != nil },
                        set: { if !$0 { pendingDeletePerson = nil } }
                    ),
                    titleVisibility: .visible,
                    presenting: pendingDeletePerson
                ) { person in
                    Button("Delete Contact", role: .destructive) {
                        viewModel.deleteContact(person)
                        pendingDeletePerson = nil
                    }
                } message: { person in
                    Text("This permanently deletes \(person.name) and all of their connections everywhere — not just from this pond.")
                }
            }
        }
    }
}
