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

    @State private var showSettings = false
    @State private var showAddContact = false
    @State private var isSearchActive = false

    init(dataManager: GoldfishDataManager) {
        _viewModel = StateObject(wrappedValue: HomeViewModel(dataManager: dataManager))
        _graphViewModel = StateObject(wrappedValue: GraphViewModel(dataManager: dataManager))
    }

    var body: some View {
        ZStack {
            NavigationStack {
                VStack(spacing: 0) {
                    if isSearchActive {
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField("Search...", text: $viewModel.searchText)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            if !viewModel.searchText.isEmpty {
                                Button(action: { viewModel.searchText = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                            }
                            Button("Cancel") {
                                withAnimation {
                                    isSearchActive = false
                                    viewModel.searchText = ""
                                }
                            }
                            .foregroundColor(.accentColor)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(Color(uiColor: .systemGroupedBackground))
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    
                    if viewModel.viewMode == .graph {
                        GraphContainerView(viewModel: graphViewModel)
                            .onTapGesture {
                                if isSearchActive {
                                    withAnimation {
                                        isSearchActive = false
                                        viewModel.searchText = ""
                                    }
                                }
                            }
                            .onChange(of: isSearchActive) { _, active in
                                if active && !viewModel.searchText.isEmpty {
                                    graphViewModel.searchMatchedIDs = Set(viewModel.filteredContacts.map(\.id))
                                } else {
                                    graphViewModel.searchMatchedIDs = nil
                                }
                            }
                            .onChange(of: viewModel.filteredContacts) { _, contacts in
                                if isSearchActive && !viewModel.searchText.isEmpty {
                                    graphViewModel.searchMatchedIDs = Set(contacts.map(\.id))
                                } else {
                                    graphViewModel.searchMatchedIDs = nil
                                }
                            }
                    } else {
                        contactsList
                    }
                }
                .navigationTitle(viewModel.viewMode == .graph ? "Ponds" : "Contacts")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItemGroup(placement: .topBarLeading) {
                        Button { showSettings = true } label: {
                            Image(systemName: "gear")
                        }
                        Button { 
                            withAnimation { isSearchActive.toggle() }
                            if !isSearchActive { viewModel.searchText = "" }
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button { viewModel.toggleViewMode() } label: {
                            Image(systemName: viewModel.viewMode == .graph ? "list.bullet" : "network")
                        }


                        Button { showAddContact = true } label: {
                            Image(systemName: "plus")
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
                    if viewModel.viewMode == .graph {
                        graphViewModel.refreshGraph()
                    }
                }) {
                    NavigationStack {
                        ContactFormView(viewModel: ContactFormViewModel(dataManager: dataManager))
                            .environmentObject(dataManager)
                    }
                }
                .onAppear {
                    viewModel.isDemoMode = demoModeManager.isDemoModeActive
                    graphViewModel.isDemoMode = demoModeManager.isDemoModeActive
                    viewModel.loadData()
                    if viewModel.viewMode == .graph {
                        graphViewModel.loadGraph()
                    }
                    

                }
                .onChange(of: demoModeManager.isDemoModeActive) { _, isDemoActive in
                    viewModel.isDemoMode = isDemoActive
                    graphViewModel.isDemoMode = isDemoActive
                    viewModel.loadData()
                    graphViewModel.refreshGraph()
                }

            }
            .walkthroughOverlay()
            .onAppear {
                setupWalkthroughCallbacks()
                walkthroughManager.startWalkthroughIfNeeded(dataManager: dataManager)
                // Refresh graph after demo data seeding so new contacts appear
                graphViewModel.refreshGraph()
            }
            .onChange(of: walkthroughManager.isActive) { wasActive, isActive in
                // When walkthrough completes (goes from active to inactive)
                if wasActive && !isActive {
                    // Turn on demo mode automatically at the end of the walkthrough
                    // This sets isDemoModeActive = true, which the Settings toggle reads
                    demoModeManager.activateDemoMode(dataManager: dataManager)
                }
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
    }

    // MARK: - Contacts List
    private var contactsList: some View {
        Group {
            if viewModel.filteredContacts.isEmpty && viewModel.searchText.isEmpty {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    headline: "No results",
                    subtext: "Try a different search term or add a contact."
                )
            } else if viewModel.filteredContacts.isEmpty {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    headline: "No results",
                    subtext: "Try a different search term."
                )
            } else {
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
                            .onDelete { _ in 
                                // Deletion from grouped lists requires mapping offsets back to the flat array.
                                // To keep it simple for now, we'll disable swipe-to-delete from the home view 
                                // since edit/delete is supported inside the detail view.
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}
