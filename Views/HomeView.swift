import SwiftUI
import UIKit

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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var isHomeRouteVisible = true
    @State private var showSettings = false
    @State private var startSettingsWithImport = false
    @State private var showAddContact = false
    @State private var showOrganization = false
    @State private var showConnectionPicker = false
    @State private var connectionAnchor: Person?
    @State private var pendingConnectionAnchor: Person?
    @ObservedObject private var connectionSession = ConnectionSession.shared
    @State private var showSearchBar = false
    @State private var selectedSearchPerson: Person?
    @State private var searchToRestoreAfterRipple: String?
    @State private var navigationRootID = UUID()
    @State private var contactToDelete: Person?
    @FocusState private var isSearchFocused: Bool

    /// Shared namespace for the "name-flight" hero transition (list row → detail).
    @Namespace private var heroNS

    init(dataManager: GoldfishDataManager) {
        _viewModel = StateObject(wrappedValue: HomeViewModel(dataManager: dataManager))
        _graphViewModel = StateObject(wrappedValue: GraphViewModel(dataManager: dataManager))
    }

    var body: some View {
        ZStack {
            mainNavigation
            .accessibilityHidden(!hasCompletedOnboarding)
            .allowsHitTesting(hasCompletedOnboarding)
            .sheet(item: $selectedSearchPerson) { person in
                NavigationStack {
                    ContactDetailView(viewModel: ContactDetailViewModel(person: person, dataManager: dataManager),
                                      showsCloseButton: true,
                                      onExploreRipples: { openPondRipple($0) })
                        .environmentObject(dataManager)
                }
            }
            .confirmationDialog("Delete contact?", isPresented: Binding(
                get: { contactToDelete != nil },
                set: { if !$0 { contactToDelete = nil } }
            ), titleVisibility: .visible) {
                if let person = contactToDelete {
                    Button("Delete \(person.name)", role: .destructive) {
                        viewModel.deleteContact(person)
                        contactToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) { contactToDelete = nil }
            } message: {
                Text("This permanently deletes the contact and their connections. Other contacts are kept.")
            }
            .alert("Could not complete action", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) { Button("OK") { viewModel.errorMessage = nil } } message: { Text(viewModel.errorMessage ?? "") }
            .alert("Could not load sample pond", isPresented: Binding(
                get: { walkthroughManager.demoErrorMessage != nil },
                set: { if !$0 { walkthroughManager.demoErrorMessage = nil } }
            )) {
                Button("Retry") {
                    walkthroughManager.demoErrorMessage = nil
                    walkthroughManager.seedDemoDataIfNeeded(dataManager: dataManager)
                    viewModel.loadData()
                    graphViewModel.refreshGraph()
                }
                Button("Replay tour") {
                    walkthroughManager.demoErrorMessage = nil
                    walkthroughManager.replayWalkthrough(dataManager: dataManager)
                }
                Button("Remove Sample Data", role: .destructive) {
                    walkthroughManager.demoErrorMessage = nil
                    demoModeManager.removeDemoData(dataManager: dataManager)
                    walkthroughManager.isDemoDataSeeded = false
                    viewModel.loadData()
                    graphViewModel.refreshGraph()
                }
                Button("Cancel", role: .cancel) { walkthroughManager.demoErrorMessage = nil }
            } message: {
                Text(walkthroughManager.demoErrorMessage ?? "Sample contacts could not be prepared.")
            }
            .sheet(isPresented: $showSettings, onDismiss: {
                startSettingsWithImport = false
                viewModel.loadData()
                graphViewModel.refreshGraph()
            }) {
                NavigationStack {
                    SettingsView(startWithImport: startSettingsWithImport)
                        .environmentObject(dataManager)
                        .environmentObject(walkthroughManager)
                        .environmentObject(demoModeManager)
                }
                .presentationCornerRadius(GoldfishDS.Radius.sheet)
            }
            .sheet(isPresented: $showOrganization) {
                NavigationStack {
                    ContactOrganizationView(dataManager: dataManager, isDemoMode: viewModel.isDemoMode)
                }
            }
            .sheet(isPresented: $showConnectionPicker, onDismiss: {
                if let person = pendingConnectionAnchor {
                    viewModel.viewMode = .graph
                    graphViewModel.activatePondContact(id: person.id)
                }
                connectionAnchor = pendingConnectionAnchor
                pendingConnectionAnchor = nil
            }) {
                NavigationStack {
                    ConnectionAnchorPicker(dataManager: dataManager, isDemoMode: viewModel.isDemoMode) { person in
                        pendingConnectionAnchor = person
                    }
                }
            }
            .sheet(item: $connectionAnchor) { person in
                BatchConnectionsView(person: person, dataManager: dataManager) { _ in
                    viewModel.loadData()
                    graphViewModel.refreshGraph()
                    viewModel.viewMode = .graph
                    graphViewModel.activatePondContact(id: person.id)
                }
            }
            .sheet(isPresented: $showAddContact, onDismiss: {
                viewModel.loadData()
                graphViewModel.refreshGraph()
            }) {
                NavigationStack {
                    ContactFormView(viewModel: ContactFormViewModel(
                        dataManager: dataManager,
                        isDemoMode: viewModel.isDemoMode,
                        initialCircleID: viewModel.selectedScopeID.flatMap(UUID.init(uuidString:))
                    ))
                        .environmentObject(dataManager)
                }
                .presentationCornerRadius(GoldfishDS.Radius.sheet)
            }
            .onAppear {
                setupWalkthroughCallbacks()
                surfaceDemoErrorIfNeeded()
                // Returning sample-mode users may have already finished the
                // tour, so its seeding path will not run on launch. Correct
                // known legacy sample contexts before loading the saved map.
                if demoModeManager.isDemoModeActive {
                    do {
                        try DemoDataService(dataManager: dataManager).updateExistingDemoContexts()
                    } catch {
                        walkthroughManager.demoErrorMessage = "Couldn’t update sample contacts. Try again."
                    }
                }
                let demoMode = walkthroughManager.isActive || demoModeManager.isDemoModeActive
                viewModel.isDemoMode = demoMode
                graphViewModel.isDemoMode = demoMode
                viewModel.loadData()
                // Keep the map behind onboarding without creating sample data.
                if !hasCompletedOnboarding {
                    viewModel.viewMode = .graph
                }
                // Only an explicit sample-mode choice starts the walkthrough.
                if hasCompletedOnboarding && demoModeManager.isDemoModeActive {
                    walkthroughManager.startWalkthroughIfNeeded(dataManager: dataManager)
                }
                // Load once after walkthrough/sample setup so the graph sees any
                // freshly seeded demo data without rebuilding the same map twice.
                graphViewModel.refreshGraph()
            }
            .onChange(of: demoModeManager.isDemoModeActive) { _, isDemoActive in
                searchToRestoreAfterRipple = nil
                let demoMode = walkthroughManager.isActive || isDemoActive
                viewModel.isDemoMode = demoMode
                graphViewModel.isDemoMode = demoMode
                viewModel.loadData()
                graphViewModel.refreshGraph()
            }
            .onChange(of: demoModeManager.demoErrorMessage) { _, _ in
                if hasCompletedOnboarding {
                    surfaceDemoErrorIfNeeded()
                }
            }
            .onChange(of: walkthroughManager.isActive) { _, isActive in
                if isActive {
                    searchToRestoreAfterRipple = nil
                    graphViewModel.closeRipple()
                }
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
            .walkthroughOverlay(isPresented: isWalkthroughOverlayPresented)
            // Any contact edit (e.g. ContactDetailView's Edit sheet) posts this so the
            // list and graph re-fetch and rebuild stale node visuals (name, line tone).
            .onReceive(NotificationCenter.default.publisher(for: .goldfishDataDidChange)) { notification in
                connectionSession.reconcile(container: dataManager.context.container)
                if notification.userInfo?["goldfishSharedImport"] as? Bool == true {
                    // Newly shared people may have no path to Me yet. Show them
                    // immediately rather than hiding them behind collapsed ponds.
                    viewModel.searchText = ""
                    viewModel.selectedScopeID = nil
                    viewModel.viewMode = .list
                }
                viewModel.loadData()
                graphViewModel.refreshGraph()
            }
            .onChange(of: viewModel.viewMode) { _, newMode in
                if newMode == .graph {
                    if graphViewModel.selectedPondFilter != viewModel.selectedScopeID {
                        graphViewModel.selectedPondFilter = viewModel.selectedScopeID
                    }
                    // loadGraph() is a no-op while the current map is still valid.
                    graphViewModel.loadGraph()
                    InteractionDiagnostics.record(.modeCommittedPond)
                }
                if newMode == .list {
                    InteractionDiagnostics.record(.modeCommittedList)
                    searchToRestoreAfterRipple = nil
                    graphViewModel.leavePondView()
                    walkthroughManager.report(.switchedToList)
                }
            }
            .onChange(of: graphViewModel.rippleFocus?.id) { oldID, newID in
                if oldID != nil, newID == nil, let query = searchToRestoreAfterRipple {
                    searchToRestoreAfterRipple = nil
                    viewModel.searchText = query
                    showSearchBar = true
                }
            }
            // ── Walkthrough action detection ──
            // The view layer reports real interactions; the manager advances the
            // matching action step (see FeatureWalkthroughManager.report).
            .onChange(of: graphViewModel.selectedPondFilter) { _, filter in
                if viewModel.selectedScopeID != filter {
                    viewModel.selectScope(filter)
                }
                if filter != nil { walkthroughManager.report(.focusedPond) }
            }
            .onChange(of: graphViewModel.linkCreatedTick) { _, _ in
                walkthroughManager.report(.createdLink)
            }
            // Start group exploration from the overview. Keep an opened profile
            // presented when the tour advances, so its actions remain usable.
            .onChange(of: walkthroughManager.currentStep) { _, step in
                switch step {
                case .welcome:
                    selectedSearchPerson = nil
                    graphViewModel.selectedContactID = nil
                    graphViewModel.searchMatchedIDs = nil
                case .profile:
                    if graphViewModel.selectedContactID == nil && selectedSearchPerson == nil,
                       let exampleID = walkthroughManager.examplePersonID {
                        graphViewModel.searchMatchedIDs = [exampleID]
                        graphViewModel.sceneDelegate?.centerOnContact(exampleID)
                    }
                case .search:
                    selectedSearchPerson = nil
                    graphViewModel.selectedContactID = nil
                    showSearchBar = false
                    isSearchFocused = false
                    viewModel.searchText = ""
                    graphViewModel.selectedPondFilter = nil
                    viewModel.selectScope(nil)
                case .link:
                    // Keep the connection lesson grounded in the seeded
                    // example after the user has opened a real profile.
                    if selectedSearchPerson == nil,
                       graphViewModel.selectedContactID == nil,
                       let exampleID = walkthroughManager.examplePersonID {
                        graphViewModel.selectContact(exampleID)
                    }
                case .ponds:
                    selectedSearchPerson = nil
                    graphViewModel.selectedContactID = nil
                    graphViewModel.searchMatchedIDs = nil
                    graphViewModel.selectedPondFilter = nil
                    viewModel.selectScope(nil)
                    graphViewModel.resetCamera()
                case .views:
                    graphViewModel.selectedPondFilter = nil
                    viewModel.selectScope(nil)
                    graphViewModel.resetCamera()
                default:
                    break
                }
            }
            // Resolve the explicit first-run choice without forcing sample data.
            .onChange(of: hasCompletedOnboarding) { _, completed in
                if completed {
                    let sampleWasChosen = demoModeManager.isDemoModeActive
                    graphViewModel.isDemoMode = sampleWasChosen
                    viewModel.isDemoMode = sampleWasChosen
                    viewModel.loadData()
                    graphViewModel.refreshGraph()
                    setupWalkthroughCallbacks()
                    if sampleWasChosen {
                        walkthroughManager.startWalkthroughIfNeeded(dataManager: dataManager)
                    }
                }
            }

            // ── Onboarding Sign-In Overlay ──
            // Sits directly inside this ZStack so the line map remains
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

    private var isSearchOverlayPresented: Bool {
        showSearchBar && (!viewModel.normalizedSearchText.isEmpty ||
            (walkthroughManager.isActive && walkthroughManager.currentStep == .search))
    }

    private var isWalkthroughOverlayPresented: Bool {
        hasCompletedOnboarding && isHomeRouteVisible && !showSearchBar && !showSettings && !showAddContact &&
            selectedSearchPerson == nil && graphViewModel.selectedContactID == nil && graphViewModel.rippleFocus == nil
    }

    private var mainNavigation: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showSearchBar && dynamicTypeSize.isAccessibilitySize {
                    Text(viewModel.isDemoMode ? "Sample contacts" : "Your contacts")
                        .font(.gfCaption)
                        .foregroundStyle(GoldfishDS.ink(.secondary))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, GoldfishDS.Space.pageMargin)
                        .padding(.top, 6)
                } else { homeControls }
                if demoModeManager.isDemoModeActive && !walkthroughManager.isActive {
                    sampleModeBar
                }
                if showSearchBar {
                    VStack(spacing: 0) {
                        adaptiveSearchEntry
                        .padding(.horizontal, GoldfishDS.Space.pageMargin)
                        .padding(.vertical, 10)
                        .background(GoldfishDS.surface)

                        if viewModel.normalizedSearchText.isEmpty && !walkthroughManager.isActive {
                            Text("Try “my sibling”")
                                .font(.gfCaption)
                                .foregroundStyle(GoldfishDS.ink(.secondary))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, GoldfishDS.Space.pageMargin)
                                .padding(.bottom, 8)
                        }

                        // 0.5pt bottom hairline
                        Rectangle()
                            .fill(GoldfishDS.ink(.hairline))
                            .frame(height: 0.5)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                if connectionSession.isActive && connectionSession.isDemoMode == viewModel.isDemoMode && !walkthroughManager.isActive {
                    ConnectionSessionCard {
                        if let id = connectionSession.anchorID {
                            viewModel.viewMode = .graph
                            graphViewModel.activatePondContact(id: id)
                        }
                    }
                    .padding(.horizontal, GoldfishDS.Space.pageMargin)
                    .background(GoldfishDS.warmBlack)
                }
                ZStack(alignment: .top) {
                    // Warm-black base behind graph / list / every empty state —
                    // never the system default pure black.
                    GoldfishDS.warmBlack.ignoresSafeArea()

                    if viewModel.viewMode == .graph {
                        GraphContainerView(viewModel: graphViewModel)
                            .onChange(of: viewModel.isSearching) { _, active in
                                if active && !viewModel.normalizedSearchText.isEmpty {
                                    graphViewModel.searchMatchedIDs = Set(viewModel.filteredContacts.map(\.id))
                                } else {
                                    graphViewModel.searchMatchedIDs = nil
                                }
                            }
                            .onChange(of: viewModel.filteredContacts) { _, contacts in
                                if viewModel.isSearching && !viewModel.normalizedSearchText.isEmpty {
                                    graphViewModel.searchMatchedIDs = Set(contacts.map(\.id))
                                } else {
                                    graphViewModel.searchMatchedIDs = nil
                                }
                            }
                            .onAppear {
                                InteractionDiagnostics.record(.pondDestinationAppeared)
                                let demoMode = walkthroughManager.isActive || demoModeManager.isDemoModeActive
                                graphViewModel.isDemoMode = demoMode
                                viewModel.isDemoMode = demoMode
                            }
                            .accessibilityHidden(isSearchOverlayPresented)
                            .allowsHitTesting(!isSearchOverlayPresented)
                    } else {
                        contactsList
                            .onAppear { InteractionDiagnostics.record(.listDestinationAppeared) }
                            .accessibilityHidden(isSearchOverlayPresented)
                            .allowsHitTesting(!isSearchOverlayPresented)
                    }

                    if isSearchOverlayPresented {
                        VStack(spacing: 0) {
                            if walkthroughManager.isActive && walkthroughManager.currentStep == .search {
                                WalkthroughInlineGuide(maximumHeight: 160)
                                    .safeAreaPadding(.top, 8)
                            }
                            if viewModel.selectedScopeID != nil || viewModel.showFavoritesOnly {
                                searchScopeNotice
                            }
                            if let response = viewModel.relationshipSearch {
                                relationshipResults(response)
                            } else {
                            SearchOverlayView(
                                viewModel: viewModel,
                                onSelect: { person in
                                    isSearchFocused = false
                                    showSearchBar = false
                                    viewModel.searchText = ""
                                    selectedSearchPerson = person
                                    walkthroughManager.report(.openedSearchResult)
                                }
                            )
                            }
                        }
                    }
                }
            }
            .onAppear { isHomeRouteVisible = true }
            .onDisappear { isHomeRouteVisible = false }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
        .id(navigationRootID)
    }

    @ViewBuilder
    private var adaptiveSearchEntry: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .trailing, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    searchInput
                    clearSearchButton
                }
                cancelSearchButton
            }
        } else {
            HStack(spacing: GoldfishDS.Space.sm) {
                Image(systemName: "magnifyingglass").foregroundStyle(GoldfishDS.ink(.tertiary))
                searchInput
                clearSearchButton
                cancelSearchButton
            }
        }
    }

    private var searchInput: some View {
        TextField("Name or relationship…", text: $viewModel.searchText, axis: .vertical)
            .focused($isSearchFocused)
            .disableAutocorrection(true)
            .lineLimit(1...3)
            .submitLabel(.search)
            .onSubmit { submitSearch() }
            .onChange(of: viewModel.searchText) { _, query in
                // A vertically growing TextField treats Return as a newline on
                // iOS. Keep natural wrapping, but make its Search key submit.
                if query.contains(where: \.isNewline) { submitSearch() }
            }
            .accessibilityLabel("Search names or relationships")
            .accessibilityIdentifier("relationshipSearchField")
            .font(.gfBody)
            .foregroundStyle(GoldfishDS.ink(.primary))
            .tint(GoldfishDS.terracotta)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func submitSearch() {
        let query = viewModel.searchText.split(whereSeparator: \.isNewline).joined(separator: " ")
        viewModel.searchText = query
        viewModel.performSearch(query: query)
        isSearchFocused = false
    }

    @ViewBuilder
    private var clearSearchButton: some View {
        if !viewModel.searchText.isEmpty {
            Button { viewModel.searchText = "" } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(GoldfishDS.ink(.tertiary))
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Clear search")
            .accessibilityIdentifier("clearSearchButton")
        }
    }

    private var cancelSearchButton: some View {
        Button {
            withAnimation(GoldfishDS.Motion.settle) {
                showSearchBar = false
                viewModel.searchText = ""
                isSearchFocused = false
            }
        } label: {
            Text("Cancel").fixedSize().frame(minHeight: 44)
        }
        .font(.gfBody)
        .foregroundStyle(GoldfishDS.ink(.secondary))
    }

    private func relationshipResults(_ response: RelationshipSearchResponse) -> some View {
        VStack(spacing: 0) {
            RelationshipSearchResultsView(response: response, onSelect: { person in
                isSearchFocused = false
                selectedSearchPerson = person
            }, onExplore: { path in
                openPondRipple(path.person.id, initialTrail: path.trailIDs, searchRouteSummary: path.summary)
            })
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GoldfishDS.warmBlack)
    }

    private var searchScopeNotice: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Searching \(viewModel.scopeName ?? "all ponds")\(viewModel.showFavoritesOnly ? " · Favorites only" : "")")
                .font(.gfMeta)
                .foregroundStyle(GoldfishDS.ink(.secondary))
                .fixedSize(horizontal: false, vertical: true)
            Button("Search all ponds") {
                viewModel.showFavoritesOnly = false
                viewModel.selectScope(nil)
                graphViewModel.selectedPondFilter = nil
            }
            .font(.gfMeta.weight(.medium))
            .frame(minHeight: 44)
            .accessibilityHint("Clears pond and favorite filters while keeping your search")
            .accessibilityIdentifier("clearSearchFiltersButton")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, GoldfishDS.Space.pageMargin)
        .padding(.top, GoldfishDS.Space.sm)
        .background(GoldfishDS.warmBlack)
    }

    /// Search and profile entry points reveal their route in the existing Pond.
    private func openPondRipple(_ id: UUID, initialTrail: [UUID]? = nil, searchRouteSummary: String? = nil) {
        graphViewModel.isDemoMode = viewModel.isDemoMode
        graphViewModel.selectedPondFilter = viewModel.selectedScopeID
        graphViewModel.loadGraph()
        graphViewModel.openRipple(id, initialTrail: initialTrail, searchRouteSummary: searchRouteSummary)
        if graphViewModel.graphLevels?.flatMap(\.allContacts).first(where: { $0.id == id })?.isMe == true {
            searchToRestoreAfterRipple = nil
            selectedSearchPerson = nil
            isSearchFocused = false
            showSearchBar = false
            viewModel.searchText = ""
            viewModel.showFavoritesOnly = false
            viewModel.selectScope(nil)
            viewModel.viewMode = .graph
            if !isHomeRouteVisible { navigationRootID = UUID() }
            return
        }
        guard graphViewModel.rippleFocus != nil else { return }

        searchToRestoreAfterRipple = showSearchBar && !viewModel.normalizedSearchText.isEmpty ? viewModel.searchText : nil
        selectedSearchPerson = nil
        isSearchFocused = false
        showSearchBar = false
        viewModel.searchText = ""
        graphViewModel.searchMatchedIDs = nil
        viewModel.viewMode = .graph
        // Return from any depth of profile navigation to the Pond surface.
        if !isHomeRouteVisible { navigationRootID = UUID() }
    }

    private var homeControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: GoldfishDS.Space.sm) {
                scopeLabel
                Spacer(minLength: GoldfishDS.Space.sm)
                modeControls.frame(width: 132)
                actionControls
            }
            VStack(alignment: .leading, spacing: GoldfishDS.Space.sm) {
                HStack(spacing: GoldfishDS.Space.sm) {
                    scopeLabel
                    Spacer(minLength: GoldfishDS.Space.sm)
                    actionControls
                }
                modeControls
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(GoldfishDS.warmBlack)
    }

    @ViewBuilder
    private var scopeLabel: some View {
        if viewModel.viewMode == .list && !showSearchBar {
            Menu {
                Picker("Pond", selection: Binding<String?>(
                    get: { viewModel.selectedScopeID },
                    set: { scope in
                        viewModel.selectScope(scope)
                        graphViewModel.selectedPondFilter = scope
                    }
                )) {
                    Text("All ponds").tag(String?.none)
                    ForEach(viewModel.circles) { circle in
                        Text(circle.name).tag(Optional(circle.id.uuidString))
                    }
                    Text("Unassigned").tag(Optional("unassigned"))
                }
            } label: {
                HStack(spacing: 6) {
                    scopeText
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.medium))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(GoldfishDS.ink(.secondary))
            .accessibilityLabel("Choose pond for the list")
            .accessibilityValue(viewModel.visibleScopeLabel)
            .accessibilityHint("Choose all ponds, one pond, or unassigned contacts")
            .accessibilityIdentifier("listPondPicker")
        } else {
            scopeText
        }
    }

    private var scopeText: some View {
        let label = viewModel.visibleScopeLabel
        return Text(label)
            .font(.gfMeta)
            .foregroundStyle(GoldfishDS.ink(.tertiary))
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
            .accessibilityLabel("Current scope: \(label)")
    }

    private var modeControls: some View {
        HStack(spacing: 0) {
            modeButton("Pond", mode: .graph)
            modeButton("List", mode: .list)
        }
        .background(GoldfishDS.surface, in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("homeViewMode")
        .walkthroughAnchor(step: .views)
    }

    private func modeButton(_ title: String, mode: HomeViewMode) -> some View {
        let isSelected = viewModel.viewMode == mode
        return Button {
            switch mode {
            case .graph:
                InteractionDiagnostics.record(.modeRequestedPond)
            case .list:
                InteractionDiagnostics.record(.modeRequestedList)
            }
            guard viewModel.viewMode != mode else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            viewModel.viewMode = mode
        } label: {
            Text(title)
                .font(.gfBody.weight(.medium))
                .foregroundStyle(isSelected ? GoldfishDS.terracotta : GoldfishDS.ink(.secondary))
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(isSelected ? GoldfishDS.terracotta.opacity(0.14) : Color.clear,
                            in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.control - 2))
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: GoldfishDS.Radius.control - 2)
                            .strokeBorder(GoldfishDS.terracotta.opacity(0.55), lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(mode == .graph ? "graphViewButton" : "listViewButton")
    }

    private var sampleModeBar: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // The heading already identifies sample mode. Keep its exit
                // action reachable without repeating a full screen of context.
                exitSampleButton
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: GoldfishDS.Space.sm) {
                        Label("Exploring sample contacts", systemImage: "sparkles")
                            .font(.gfMeta)
                            .foregroundStyle(GoldfishDS.ink(.secondary))
                        Spacer(minLength: GoldfishDS.Space.sm)
                        exitSampleButton
                    }
                    VStack(alignment: .leading, spacing: GoldfishDS.Space.xs) {
                        Label("Exploring sample contacts", systemImage: "sparkles")
                            .font(.gfMeta)
                            .foregroundStyle(GoldfishDS.ink(.secondary))
                        exitSampleButton
                    }
                }
            }
        }
        .padding(.horizontal, GoldfishDS.Space.pageMargin)
        .background(GoldfishDS.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(GoldfishDS.ink(.hairline)).frame(height: 0.5)
        }
    }

    private var exitSampleButton: some View {
        Button("Exit Sample") {
            demoModeManager.deactivateDemoMode()
        }
        .font(.gfLabel)
        .foregroundStyle(GoldfishDS.terracotta)
        .frame(minHeight: 44)
        .accessibilityHint("Shows your personal contacts and keeps the sample available for later.")
        .accessibilityIdentifier("exitSampleModeButton")
    }

    private var actionControls: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(GoldfishDS.Motion.settle) {
                    showSearchBar.toggle()
                    isSearchFocused = showSearchBar
                    if !showSearchBar { viewModel.searchText = "" }
                }
            } label: { Image(systemName: "magnifyingglass").frame(width: 44, height: 44) }
            .accessibilityLabel("Search contacts")
            .accessibilityIdentifier("searchContactsButton")
            .walkthroughAnchor(step: .search)
            Menu {
                Button("Add contact", systemImage: "person.badge.plus") { showAddContact = true }
                Button("Organize people", systemImage: "person.2.crop.square.stack") { showOrganization = true }
                Button("Add connections", systemImage: "point.3.connected.trianglepath.dotted") { showConnectionPicker = true }
                if !connectionSession.isActive {
                    Button("Connect five people", systemImage: "water.waves") {
                        connectionSession.start(isDemoMode: viewModel.isDemoMode)
                        showConnectionPicker = true
                    }
                } else {
                    Button("End connection session", systemImage: "checkmark") { connectionSession.finish() }
                }
            } label: {
                Image(systemName: "plus").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Add and organize contacts")
            .accessibilityIdentifier("addContactButton")
            Button {
                startSettingsWithImport = false
                showSettings = true
            } label: {
                Image(systemName: "gearshape").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("settingsButton")
        }
        .buttonStyle(.plain)
        .font(.system(size: 18, weight: .regular))
        .foregroundStyle(GoldfishDS.ink(.secondary))
    }

    private func openImportContacts() {
        startSettingsWithImport = true
        showSettings = true
    }

    private func setupWalkthroughCallbacks() {
        walkthroughManager.onRequestGraphView = {
            withAnimation { viewModel.viewMode = .graph }
        }
        walkthroughManager.onRequestListView = {
            withAnimation { viewModel.viewMode = .list }
        }
        walkthroughManager.onTourCompleted = { keepDemoData in
            resetWalkthroughPresentation()
            if keepDemoData {
                demoModeManager.activateDemoMode(dataManager: dataManager)
            } else {
                demoModeManager.deactivateDemoMode()
            }
            viewModel.loadData()
            graphViewModel.refreshGraph()
        }
    }

    private func resetWalkthroughPresentation() {
        selectedSearchPerson = nil
        graphViewModel.selectedContactID = nil
        showSearchBar = false
        isSearchFocused = false
        viewModel.searchText = ""
        graphViewModel.selectedPondFilter = nil
        viewModel.selectScope(nil)
    }

    private func surfaceDemoErrorIfNeeded() {
        guard let message = demoModeManager.demoErrorMessage else { return }
        if walkthroughManager.demoErrorMessage == nil {
            walkthroughManager.demoErrorMessage = message
        }
        demoModeManager.demoErrorMessage = nil
    }

    // MARK: - Contacts List
    private var contactsList: some View {
        Group {
            switch viewModel.listState {
            case .loading:
                ProgressView()
            case .emptyGlobal:
                EmptyStateView(
                    systemImage: "circle.hexagongrid",
                    headline: "Your pond starts here.",
                    subtext: "Tap + to add someone to your pond.",
                    actionLabel: "Add Contact",
                    editorial: true,
                    action: { showAddContact = true },
                    secondaryActionLabel: "Import Contacts",
                    secondaryAction: openImportContacts
                )
            case .emptyPond(let pondName):
                EmptyStateView(
                    systemImage: "circle.hexagongrid",
                    headline: "This pond is quiet.",
                    subtext: "No people in \(pondName) yet.",
                    actionLabel: "Add Contact",
                    editorial: true,
                    action: { showAddContact = true }
                )
            case .emptySearch:
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    headline: "No people match.",
                    subtext: "Try another name.",
                    editorial: true
                )
            case .populated:
                List {
                    ForEach(viewModel.groupedContacts) { group in
                        Section(header: sectionHeader(group.name)) {
                            ForEach(group.contacts) { person in
                                NavigationLink {
                                    ContactDetailView(
                                        viewModel: ContactDetailViewModel(
                                            person: person,
                                            dataManager: dataManager
                                        ),
                                        onExploreRipples: { openPondRipple($0) },
                                        heroNamespace: heroNS,
                                        heroID: person.id
                                    )
                                    .environmentObject(dataManager)
                                } label: {
                                    ContactRowView(person: person)
                                        .gfHeroSource(id: person.id, in: heroNS)
                                }
                                .listRowInsets(EdgeInsets(top: 2, leading: GoldfishDS.Space.pageMargin,
                                                          bottom: 2, trailing: GoldfishDS.Space.lg))
                                .listRowBackground(Color.clear)
                                .listRowSeparatorTint(GoldfishDS.ink(.hairline))
                                .alignmentGuide(.listRowSeparatorLeading) { _ in
                                    // avatar (44) + line bar (6) + two gaps → separator
                                    // starts where the station name starts.
                                    GoldfishDS.Space.pageMargin + 44 + 6 + GoldfishDS.Space.lg * 2
                                }
                                .accessibilityIdentifier("contactRow-\(person.id.uuidString)")
                            }
                            .onDelete { offsets in
                                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                                for offset in offsets {
                                    let person = group.contacts[offset]
                                    contactToDelete = person
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(GoldfishDS.warmBlack)

            }
        }
    }

    /// Editorial section header: uppercase tracked label + a hairline rule.
    private func sectionHeader(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: GoldfishDS.Space.sm) {
            Text(title)
                .gfSectionLabel()
            Rectangle()
                .fill(GoldfishDS.ink(.hairline))
                .frame(height: 0.5)
        }
        .padding(.leading, GoldfishDS.Space.pageMargin)
        .padding(.trailing, GoldfishDS.Space.lg)
        .padding(.top, GoldfishDS.Space.lg)
        .padding(.bottom, GoldfishDS.Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .listRowInsets(EdgeInsets())
        .background(GoldfishDS.warmBlack)
    }
}

// MARK: - Hero transition source (name-flight)
extension View {
    /// Marks a list row as the source of the zoom/hero transition into the detail.
    /// iOS 18+; a no-op (graceful default push) on iOS 17.
    @ViewBuilder
    func gfHeroSource(id: UUID, in ns: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.matchedTransitionSource(id: id, in: ns)
        } else {
            self
        }
    }
}
