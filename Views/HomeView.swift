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

    @State private var showSettings = false
    @State private var showAddContact = false
    @State private var showSearchBar = false
    @FocusState private var isSearchFocused: Bool

    init(dataManager: GoldfishDataManager) {
        _viewModel = StateObject(wrappedValue: HomeViewModel(dataManager: dataManager))
        _graphViewModel = StateObject(wrappedValue: GraphViewModel(dataManager: dataManager))
    }

    var body: some View {
        ZStack {
            NavigationStack {
                VStack(spacing: 0) {
                    if showSearchBar {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.gray)
                            TextField("Search contacts...", text: $viewModel.searchText)
                                .focused($isSearchFocused)
                                .disableAutocorrection(true)
                            
                            if !viewModel.searchText.isEmpty {
                                Button(action: {
                                    viewModel.searchText = ""
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
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
                                .onChange(of: demoModeManager.isDemoModeActive) { _, isActive in
                                    graphViewModel.isDemoMode = isActive
                                    graphViewModel.refreshGraph()
                                    viewModel.isDemoMode = isActive
                                    viewModel.loadData()
                                }
                                .onAppear {
                                    graphViewModel.isDemoMode = demoModeManager.isDemoModeActive
                                    viewModel.isDemoMode = demoModeManager.isDemoModeActive
                                }
                        } else {
                            contactsList
                        }

                        if showSearchBar && isSearchFocused && !viewModel.searchText.isEmpty {
                            SearchOverlayView(
                                viewModel: viewModel,
                                onSelect: { person in
                                    // Complete search with the selected person's name
                                    viewModel.searchText = person.name
                                    isSearchFocused = false
                                }
                            )
                            .padding(.horizontal)
                        }
                    }
                }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
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
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { 
                            withAnimation {
                                showSearchBar.toggle()
                                if showSearchBar {
                                    isSearchFocused = true
                                } else {
                                    viewModel.searchText = ""
                                    isSearchFocused = false
                                }
                            }
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        Button { showSettings = true } label: {
                            Image(systemName: "gear")
                        }
                        Button { showAddContact = true } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    SettingsView()
                        .environmentObject(dataManager)
                }
            }
            .sheet(isPresented: $showAddContact, onDismiss: {
                viewModel.loadData()
                graphViewModel.refreshGraph()
            }) {
                NavigationStack {
                    ContactFormView(viewModel: ContactFormViewModel(dataManager: dataManager))
                        .environmentObject(dataManager)
                }
            }
            .onAppear {
                setupWalkthroughCallbacks()
                // If onboarding isn't done yet, seed demo data immediately
                // so the ponds graph is populated behind the sign-in overlay.
                if !hasCompletedOnboarding {
                    walkthroughManager.seedDemoDataIfNeeded(dataManager: dataManager)
                }
                let demoMode = walkthroughManager.isActive || demoModeManager.isDemoModeActive || !hasCompletedOnboarding
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
            // When sign-in completes, start the feature walkthrough tour
            .onChange(of: hasCompletedOnboarding) { _, completed in
                if completed {
                    // Reload graph in demo mode (demo data already seeded before sign-in)
                    graphViewModel.isDemoMode = true
                    viewModel.isDemoMode = true
                    graphViewModel.refreshGraph()
                    setupWalkthroughCallbacks()
                    walkthroughManager.startWalkthroughIfNeeded(dataManager: dataManager)
                }
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
                    headline: "Empty Pond",
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
                        Section(header: Text(group.name).font(.headline).foregroundColor(.white).textCase(nil)) {
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
                                for offset in offsets {
                                    let person = group.contacts[offset]
                                    viewModel.deleteContact(person)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}
