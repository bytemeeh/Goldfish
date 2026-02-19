import SwiftUI

struct HomeView: View {
    @EnvironmentObject var dataManager: GoldfishDataManager
    @StateObject private var viewModel: HomeViewModel
    @StateObject private var graphViewModel: GraphViewModel
    
    @State private var showSettings = false
    @State private var showAddContact = false
    
    init() {
        // We defer initialization to onAppear/init block pattern or use StateObject with auto-init
        // But we need DataManager.
        // Since we can't access EnvironmentObject in init, we rely on dependency injection via .environmentObject
        // and init the ViewModels in a slightly different way or assuming DataManager is passed?
        //
        // Workaround: We use a wrapper or initialize them with a placeholder, then configure.
        // Better: Use a loader view.
        
        // For this purpose, we'll initialize with placeholder and configure in onAppear/task
        _viewModel = StateObject(wrappedValue: HomeViewModel(dataManager: .preview())) 
        _graphViewModel = StateObject(wrappedValue: GraphViewModel(dataManager: .preview()))
        // The above is slightly hacky because we want the REAL data manager.
    }
    
    // Better pattern for SwiftUI DI:
    struct Content: View {
        @EnvironmentObject var dataManager: GoldfishDataManager
        @StateObject var viewModel: HomeViewModel
        @StateObject var graphViewModel: GraphViewModel
        
        init(dataManager: GoldfishDataManager) {
            _viewModel = StateObject(wrappedValue: HomeViewModel(dataManager: dataManager))
            _graphViewModel = StateObject(wrappedValue: GraphViewModel(dataManager: dataManager))
        }
        
        @State private var showSettings = false
        @State private var showAddContact = false
        
        var body: some View {
             NavigationStack {
                ZStack {
                    // MARK: - Main Content
                    if viewModel.viewMode == .graph {
                        GraphContainerView(viewModel: graphViewModel)
                            .id("graph") // Force recreate on switch if needed, but keeping state is better
                    } else {
                        ContactListView(viewModel: viewModel)
                            .id("list")
                    }
                    
                    // MARK: - Search Overlay (Graph Mode)
                    if viewModel.viewMode == .graph && viewModel.isSearching {
                        VStack {
                            Spacer()
                            SearchOverlayView(viewModel: viewModel) { person in
                                viewModel.isSearching = false
                                viewModel.searchText = "" // Clear search logic
                                graphViewModel.selectContact(person.id)
                            }
                            .frame(maxHeight: 400)
                        }
                        .zIndex(2)
                    }
                }
                .navigationTitle(viewModel.viewMode == .graph ? "Graph" : "Contacts")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $viewModel.searchText, placement: .navigationBarDrawer(displayMode: .always))
                .toolbar {
                    // Leading: Settings
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: { showSettings = true }) {
                            Image(systemName: "gear")
                        }
                    }
                    
                    // Trailing: View Toggle + Add
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack {
                            Button(action: viewModel.toggleViewMode) {
                                Image(systemName: viewModel.viewMode == .graph ? "list.bullet" : "network")
                            }
                            
                            Button(action: { showAddContact = true }) {
                                Image(systemName: "plus")
                            }
                        }
                    }
                }
                .navigationDestination(isPresented: $showSettings) {
                    SettingsView()
                }
                .sheet(isPresented: $showAddContact) {
                    ContactFormView(viewModel: ContactFormViewModel(dataManager: dataManager))
                }
                .onAppear {
                    viewModel.loadData()
                    graphViewModel.loadGraph()
                }
            }
        }
    }
    
    var body: some View {
        // We need a way to pass the EnvironmentObject dataManager to the init of the StateObjects.
        // Since we can't do that at the root of HomeView directly if HomeView is created without args.
        // We use a middleware View.
        DataManagerInjector()
    }
    
    struct DataManagerInjector: View {
        @EnvironmentObject var dataManager: GoldfishDataManager
        var body: some View {
            Content(dataManager: dataManager)
        }
    }
}
