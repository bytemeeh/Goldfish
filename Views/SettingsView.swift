import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var dataManager: GoldfishDataManager

    @EnvironmentObject var walkthroughManager: FeatureWalkthroughManager
    @EnvironmentObject var demoModeManager: DemoModeManager
    @StateObject private var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingImporter = false
    @State private var showingOrganization = false
    @State private var incomingGoldfishURL: IdentifiableWrapper<URL>?
    @State private var showingImportOptions = false
    @State private var showingPhonebookPicker = false
    @State private var showingExportPrompt = false
    @State private var exportURL: IdentifiableWrapper<URL>?
    @State private var showingImportDetails = false
    @State private var didOfferInitialImport = false
    @State private var showingWelcomePreview = false
    @AppStorage("appearancePreference") private var appearancePreference = AppAppearance.system.rawValue
    @AppStorage("quietPondBackground") private var quietPondBackground = false
    private let startWithImport: Bool
    private let graphViewModel: GraphViewModel?

    init(startWithImport: Bool = false, graphViewModel: GraphViewModel? = nil) {
        self.graphViewModel = graphViewModel
        self.startWithImport = startWithImport
        // Placeholder — will be replaced in onAppear; needed because
        // @EnvironmentObject isn't available in init.
        _viewModel = StateObject(wrappedValue: SettingsViewModel())
    }

    var body: some View {
        List {

            // MARK: - Page title
            Section {
                Text("Settings")
                    .font(.largeTitle.weight(.light))
                    .foregroundStyle(GoldfishDS.ink(.primary))
                    .padding(.top, GoldfishDS.Space.lg)
                    .padding(.bottom, GoldfishDS.Space.sm)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0,
                                             leading: GoldfishDS.Space.pageMargin,
                                             bottom: 0,
                                             trailing: GoldfishDS.Space.pageMargin))
            }

            // MARK: - Profile hero row
            Section {
                if let me = viewModel.mePerson {
                    NavigationLink {
                        ContactFormView(viewModel: ContactFormViewModel(dataManager: dataManager, person: me))
                            .environmentObject(dataManager)
                    } label: {
                        HStack(spacing: GoldfishDS.Space.lg) {
                            ContactPhotoView(person: me, size: .medium)
                            VStack(alignment: .leading, spacing: GoldfishDS.Space.xs) {
                                Text(me.name).font(.gfName).foregroundStyle(GoldfishDS.ink(.primary))
                                Text("Edit your profile").font(.gfMeta).foregroundStyle(GoldfishDS.ink(.secondary))
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, GoldfishDS.Space.sm)
                    }
                    .accessibilityLabel("Edit your profile, \(me.name)")
                    .accessibilityIdentifier("editProfileButton")
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your profile is unavailable").font(.gfBody)
                        Button("Retry") { viewModel.loadMePerson() }
                            .frame(minHeight: 44)
                    }
                }
            } header: {
                SettingsSectionHeader("Profile")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0,
                                     leading: GoldfishDS.Space.pageMargin,
                                     bottom: 0,
                                     trailing: GoldfishDS.Space.pageMargin))
            .listRowSeparatorTint(GoldfishDS.ink(.hairline))

            // MARK: - Configuration
            Section {
                SettingsNavRow(
                    icon: "circle.grid.hex",
                    label: "Manage Ponds"
                ) {
                    CircleManagerView()
                        .environmentObject(dataManager)
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(GoldfishDS.ink(.hairline)).frame(height: 0.5).padding(.leading, 44)
                }

                if let graphViewModel {
                    SettingsActionRow(icon: "arrow.counterclockwise", label: "Restore automatic layout") {
                        graphViewModel.restoreAutomaticPondLayout()
                    }
                    SettingsActionRow(icon: "plus.magnifyingglass", label: "Zoom in") { graphViewModel.zoomIn() }
                    SettingsActionRow(icon: "minus.magnifyingglass", label: "Zoom out") { graphViewModel.zoomOut() }
                }
                SettingsNavRow(icon: "questionmark.circle", label: "Using the map") { MapHelpView() }

                SettingsActionRow(icon: "hand.point.up.left.fill", label: "Replay Feature Tour") {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        walkthroughManager.replayWalkthrough(dataManager: dataManager)
                    }
                }

                SettingsActionRow(icon: "sparkles.rectangle.stack", label: "Preview Welcome") {
                    showingWelcomePreview = true
                }
            } header: {
                SettingsSectionHeader("Configuration")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0,
                                     leading: GoldfishDS.Space.pageMargin,
                                     bottom: 0,
                                     trailing: GoldfishDS.Space.pageMargin))
            .listRowSeparator(.hidden)

            // MARK: - Appearance
            Section {
                Picker("Appearance", selection: $appearancePreference) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.title).tag(appearance.rawValue)
                    }
                }
                .font(.gfBody)
                .tint(GoldfishDS.terracotta)
                .accessibilityIdentifier("appearancePicker")

                Toggle("Quiet pond background", isOn: $quietPondBackground)
                    .font(.gfBody)
                    .tint(GoldfishDS.terracotta)
                    .accessibilityIdentifier("quietPondBackgroundToggle")
            } header: {
                SettingsSectionHeader("Appearance")
            } footer: {
                Text("Choose light or dark appearance, or follow your device setting. Quiet pond background removes the watercolor goldfish.")
                    .font(.gfMeta)
                    .foregroundStyle(GoldfishDS.ink(.tertiary))
                    .padding(.horizontal, GoldfishDS.Space.pageMargin)
                    .padding(.top, GoldfishDS.Space.sm)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0,
                                     leading: GoldfishDS.Space.pageMargin,
                                     bottom: 0,
                                     trailing: GoldfishDS.Space.pageMargin))
            .listRowSeparator(.hidden)

            // MARK: - Help & feedback
            Section {
                SettingsNavRow(
                    icon: "ladybug",
                    label: FeedbackKind.bug.title
                ) {
                    FeedbackView(initialKind: .bug)
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(GoldfishDS.ink(.hairline)).frame(height: 0.5).padding(.leading, 44)
                }

                SettingsNavRow(
                    icon: "lightbulb",
                    label: FeedbackKind.idea.title
                ) {
                    FeedbackView(initialKind: .idea)
                }

                if let supportURL = FeedbackConfiguration.supportURL {
                    Link(destination: supportURL) {
                        SettingsRowContent(icon: "lifepreserver", label: "Support website", showChevron: false)
                            .padding(.vertical, GoldfishDS.Space.sm)
                    }
                    .accessibilityLabel("Open Goldfish support website")
                }
            } header: {
                SettingsSectionHeader("Help & feedback")
            } footer: {
                Text("Tell us what went wrong or share an idea. You choose what to include and how to share it.")
                    .font(.gfMeta)
                    .foregroundStyle(GoldfishDS.ink(.tertiary))
                    .padding(.horizontal, GoldfishDS.Space.pageMargin)
                    .padding(.top, GoldfishDS.Space.sm)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0,
                                     leading: GoldfishDS.Space.pageMargin,
                                     bottom: 0,
                                     trailing: GoldfishDS.Space.pageMargin))
            .listRowSeparator(.hidden)

            // MARK: - Sample contacts
            Section {
                HStack(spacing: GoldfishDS.Space.lg) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15))
                        .frame(width: 20)
                        .foregroundStyle(GoldfishDS.ink(.tertiary))
                    Text("Show sample contacts")
                        .font(.gfBody)
                        .foregroundStyle(GoldfishDS.ink(.primary))
                    Spacer(minLength: 0)
                    Toggle("Show sample contacts", isOn: Binding(
                        get: { demoModeManager.isDemoModeActive },
                        set: { newValue in
                            if newValue {
                                demoModeManager.activateDemoMode(dataManager: dataManager)
                            } else {
                                demoModeManager.deactivateDemoMode()
                            }
                        }
                    ))
                    .labelsHidden()
                    .tint(GoldfishDS.terracotta)
                    .disabled(walkthroughManager.isActive)
                    .opacity(walkthroughManager.isActive ? 0.4 : 1)
                }
                .padding(.vertical, GoldfishDS.Space.sm)

                if walkthroughManager.isActive {
                    Text("Sample contacts are on during the feature tour.")
                        .font(.gfMeta)
                        .foregroundStyle(GoldfishDS.ink(.tertiary))
                        .padding(.leading, 36)
                        .padding(.bottom, GoldfishDS.Space.xs)
                }
            } header: {
                SettingsSectionHeader("Sample contacts")
            } footer: {
                Text("Sample mode shows sample contacts and connections to showcase all features. Your real data is safely hidden while sample mode is active.")
                    .font(.gfMeta)
                    .foregroundStyle(GoldfishDS.ink(.tertiary))
                    .padding(.horizontal, GoldfishDS.Space.pageMargin)
                    .padding(.top, GoldfishDS.Space.sm)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0,
                                     leading: GoldfishDS.Space.pageMargin,
                                     bottom: 0,
                                     trailing: GoldfishDS.Space.pageMargin))
            .listRowSeparatorTint(GoldfishDS.ink(.hairline))

            // MARK: - Data
            Section {
                SettingsNavRow(
                    icon: "square.and.arrow.up",
                    label: "Share Contacts"
                ) {
                    ContactExportSelectionView()
                        .environmentObject(dataManager)
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(GoldfishDS.ink(.hairline)).frame(height: 0.5).padding(.leading, 44)
                }

                NavigationLink {
                    ContactOrganizationView(dataManager: dataManager, isDemoMode: demoModeManager.isDemoModeActive)
                } label: { Label("Organize people", systemImage: "person.2.crop.square.stack") }
                SettingsActionRow(icon: "square.and.arrow.down", label: "Import Contacts") {
                    showingImportOptions = true
                }
                .disabled(viewModel.isImporting)

                if viewModel.isImporting {
                    HStack(spacing: GoldfishDS.Space.md) {
                        ProgressView()
                            .tint(GoldfishDS.ink(.secondary))
                        Text(viewModel.importProgress)
                            .font(.gfMeta)
                            .foregroundStyle(GoldfishDS.ink(.tertiary))
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, GoldfishDS.Space.sm)
                    .padding(.leading, 44)
                }
            } header: {
                SettingsSectionHeader("Data")
            } footer: {
                Text("Share selected people as a Goldfish bundle to preserve relationships and pond membership, or as a vCard for compatible contacts apps. Open a Goldfish bundle here to review it before importing.")
                    .font(.gfMeta)
                    .foregroundStyle(GoldfishDS.ink(.tertiary))
                    .padding(.horizontal, GoldfishDS.Space.pageMargin)
                    .padding(.top, GoldfishDS.Space.sm)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0,
                                     leading: GoldfishDS.Space.pageMargin,
                                     bottom: 0,
                                     trailing: GoldfishDS.Space.pageMargin))
            .listRowSeparator(.hidden)

            // MARK: - About
            Section {
                SettingsNavRow(
                    icon: "hand.raised.fill",
                    label: "Privacy Policy",
                    destination: { PrivacyPolicyView() }
                )
                .overlay(alignment: .bottom) {
                    Rectangle().fill(GoldfishDS.ink(.hairline)).frame(height: 0.5).padding(.leading, 44)
                }

                HStack(spacing: GoldfishDS.Space.lg) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15))
                        .frame(width: 20)
                        .foregroundStyle(GoldfishDS.ink(.tertiary))
                    Text("Version")
                        .font(.gfBody)
                        .foregroundStyle(GoldfishDS.ink(.primary))
                    Spacer(minLength: 0)
                    Text("\(viewModel.appVersion) (\(viewModel.buildNumber))")
                        .font(.gfBody)
                        .monospacedDigit()
                        .foregroundStyle(GoldfishDS.ink(.tertiary))
                }
                .padding(.vertical, GoldfishDS.Space.sm)

            } header: {
                SettingsSectionHeader("About")
            } footer: {
                VStack(spacing: GoldfishDS.Space.xs) {
                    Text("Goldfish © 2026")
                        .font(.gfCaption)
                        .monospacedDigit()
                        .kerning(1.1)
                        .foregroundStyle(GoldfishDS.ink(.quaternary))
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, GoldfishDS.Space.lg)
                .padding(.bottom, GoldfishDS.Space.xl)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0,
                                     leading: GoldfishDS.Space.pageMargin,
                                     bottom: 0,
                                     trailing: GoldfishDS.Space.pageMargin))
            .listRowSeparator(.hidden)

            // MARK: - Logout / Reset
            Section {
                Button {
                    showingExportPrompt = true
                } label: {
                    Text("Reset App")
                        .font(.gfLabel)
                        .textCase(.uppercase)
                        .kerning(1.2)
                        .foregroundStyle(GoldfishDS.terracotta)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .overlay(
                            RoundedRectangle(cornerRadius: GoldfishDS.Radius.control)
                                .strokeBorder(GoldfishDS.terracotta, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .padding(.vertical, GoldfishDS.Space.xs)
            } header: {
                // Marker-red rule above the section signals severity — end of service.
                Rectangle()
                    .fill(GoldfishDS.terracotta)
                    .frame(maxWidth: .infinity)
                    .frame(height: GoldfishDS.Rule.hairline)
                    .listRowInsets(EdgeInsets())
                    .textCase(nil)
            } footer: {
                Text("Reset deletes all local contacts, connections and ponds, including samples and your profile. Appearance preferences are kept.")
                    .font(.gfMeta)
                    .foregroundStyle(GoldfishDS.ink(.tertiary))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, GoldfishDS.Space.pageMargin)
                    .padding(.top, GoldfishDS.Space.sm)
                    .padding(.bottom, GoldfishDS.Space.xxl)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0,
                                     leading: GoldfishDS.Space.pageMargin,
                                     bottom: 0,
                                     trailing: GoldfishDS.Space.pageMargin))
            .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(GoldfishDS.warmBlack.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
                .font(.gfBody)
                .foregroundStyle(GoldfishDS.ink(.secondary))
            }
        }
        .onAppear {
            viewModel.configure(dataManager: dataManager)
            guard startWithImport,
                  !didOfferInitialImport,
                  !walkthroughManager.isActive,
                  !demoModeManager.isDemoModeActive else { return }
            didOfferInitialImport = true
            DispatchQueue.main.async { showingImportOptions = true }
        }
        .onChange(of: viewModel.showImportCompletionAlert) { _, completed in
            if completed && ((viewModel.lastImportResult?.importedCount ?? 0) + (viewModel.lastImportResult?.skippedCount ?? 0)) > 0 {
                if walkthroughManager.isActive { walkthroughManager.finishTour(keepDemoData: true) }
                demoModeManager.deactivateDemoMode()
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.goldfishContactBundle, .vCard],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    if url.pathExtension.lowercased() == "goldfish" {
                        incomingGoldfishURL = IdentifiableWrapper(url)
                    } else {
                        viewModel.importContacts(from: url)
                    }
                }
            case .failure(let error):
                viewModel.errorMessage = "Could not open file: " + error.localizedDescription
            }
        }
        .confirmationDialog("Import Contacts", isPresented: $showingImportOptions, titleVisibility: .visible) {
            Button("Import from File") {
                showingImporter = true
            }
            Button("Import from Phonebook") {
                showingPhonebookPicker = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Where would you like to import contacts from?")
        }
        .sheet(isPresented: $showingPhonebookPicker) {
            ContactPicker(isPresented: $showingPhonebookPicker) { selectedContacts in
                viewModel.importContacts(from: selectedContacts)
            }
            .presentationCornerRadius(GoldfishDS.Radius.sheet)
        }
        .alert("Action could not be completed", isPresented: Binding(
            get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } }
        )) { Button("OK") { viewModel.errorMessage = nil } } message: { Text(viewModel.errorMessage ?? "") }
        .alert(viewModel.importAlertTitle, isPresented: $viewModel.showImportCompletionAlert) {
            if (viewModel.lastImportResult?.importedCount ?? 0) > 0 {
                Button("Organize \(viewModel.lastImportResult?.importedCount ?? 0) people now") { showingOrganization = true }
            }
            if viewModel.hasImportDetails {
                Button("Details") { showingImportDetails = true }
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.importAlertMessage)
        }
        .sheet(isPresented: $showingOrganization) {
            NavigationStack {
                ContactOrganizationView(dataManager: dataManager, isDemoMode: false,
                                        initialContactIDs: viewModel.importedContactIDs)
            }
        }
        .sheet(isPresented: $showingImportDetails) {
            ImportDetailsView(
                lines: viewModel.importDetailLines,
                overflowCount: viewModel.importDetailOverflowCount
            )
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(GoldfishDS.Radius.sheet)
        }
        .alert("Reset app?", isPresented: $showingExportPrompt) {
            Button("Export contact copy") {
                if let url = viewModel.generateExportURL() {
                    self.exportURL = IdentifiableWrapper(url)
                }
            }
            Button("Delete All Local Data", role: .destructive) {
                if viewModel.performReset(
                    walkthroughManager: walkthroughManager,
                    demoModeManager: demoModeManager
                ) { dismiss() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Export a copy of your personal contacts before deleting your data. The vCard excludes sample contacts and is not a complete backup: empty ponds, saved layouts and some location data are omitted. Exporting or cancelling does not reset the app. Delete All Local Data removes personal and sample data, including your profile; appearance preferences are kept.")
        }
        .sheet(item: $exportURL) { wrapper in
            ShareSheet(activityItems: [wrapper.value])
                .presentationCornerRadius(GoldfishDS.Radius.sheet)
        }
        .sheet(item: $incomingGoldfishURL) { wrapper in
            GoldfishShareImportView(url: wrapper.value)
                .environmentObject(dataManager)
                .environmentObject(demoModeManager)
                .environmentObject(walkthroughManager)
                .presentationCornerRadius(GoldfishDS.Radius.sheet)
        }
        .sheet(isPresented: $showingWelcomePreview) {
            OnboardingSignInOverlay(previewOnly: true)
                .environmentObject(dataManager)
                .environmentObject(walkthroughManager)
                .environmentObject(demoModeManager)
                .environmentObject(ToastManager.shared)
                .ignoresSafeArea()
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

private struct ImportDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    let lines: [String]
    let overflowCount: Int

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.gfBody)
                            .foregroundStyle(GoldfishDS.ink(.primary))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: 44, alignment: .leading)
                    }
                    if overflowCount > 0 {
                        Text("\(overflowCount) more details are not shown here.")
                            .font(.gfMeta)
                            .foregroundStyle(GoldfishDS.ink(.secondary))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .listRowBackground(GoldfishDS.surface)
            }
            .scrollContentBackground(.hidden)
            .background(GoldfishDS.warmBlack.ignoresSafeArea())
            .navigationTitle("Import Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(GoldfishDS.terracotta)
                }
            }
        }
    }
}

// MARK: - Section header

private struct SettingsSectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .gfSectionLabel()
            .padding(.horizontal, GoldfishDS.Space.pageMargin)
            .padding(.top, GoldfishDS.Space.xl)
            .padding(.bottom, GoldfishDS.Space.xs)
            .textCase(nil)           // override List's default uppercase to use our own
    }
}

// MARK: - Reusable row: nav destination

private struct SettingsNavRow<Destination: View>: View {
    let icon: String
    let label: String
    let destination: () -> Destination

    var body: some View {
        NavigationLink(destination: destination()) {
            SettingsRowContent(icon: icon, label: label, showChevron: false)
                .padding(.vertical, GoldfishDS.Space.sm)
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Reusable row: action button (no trailing chevron — it's a tap action, not navigation)

private struct SettingsActionRow: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsRowContent(icon: icon, label: label, showChevron: false)
        }
        .buttonStyle(.plain)
        .padding(.vertical, GoldfishDS.Space.sm)
    }
}

// MARK: - Row content (icon + label + optional chevron)

private struct SettingsRowContent: View {
    let icon: String
    let label: String
    var showChevron: Bool = true

    var body: some View {
        HStack(spacing: GoldfishDS.Space.lg) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .frame(width: 20)
                .foregroundStyle(GoldfishDS.ink(.tertiary))
            Text(label)
                .font(.gfBody)
                .foregroundStyle(GoldfishDS.ink(.primary))
            Spacer(minLength: 0)
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(GoldfishDS.ink(.quaternary))
            }
        }
    }
}
