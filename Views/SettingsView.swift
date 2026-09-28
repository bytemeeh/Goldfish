import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var dataManager: GoldfishDataManager

    @EnvironmentObject var walkthroughManager: FeatureWalkthroughManager
    @EnvironmentObject var demoModeManager: DemoModeManager
    @StateObject private var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingImporter = false
    @State private var showingImportOptions = false
    @State private var showingPhonebookPicker = false
    @State private var showingLogoutAlert = false
    @State private var showingExportPrompt = false
    @State private var exportURL: IdentifiableWrapper<URL>?
    @State private var showingImportDetails = false
    @State private var didOfferInitialImport = false
    private let startWithImport: Bool

    init(startWithImport: Bool = false) {
        self.startWithImport = startWithImport
        // Placeholder — will be replaced in onAppear; needed because
        // @EnvironmentObject isn't available in init.
        _viewModel = StateObject(wrappedValue: SettingsViewModel())
    }

    var body: some View {
        List {

            // MARK: - Large title (signage board: marker-red bar + uppercase)
            Section {
                VStack(alignment: .leading, spacing: GoldfishDS.Space.sm) {
                    Rectangle()
                        .fill(GoldfishDS.terracotta)
                        .frame(width: 56, height: GoldfishDS.Rule.bar)
                    Text("Settings")
                        .font(.gfDisplay)
                        .textCase(.uppercase)
                        .kerning(1.5)
                        .foregroundStyle(GoldfishDS.ink(.primary))
                }
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
                    Text("My Card not found")
                        .font(.gfBody)
                        .foregroundStyle(GoldfishDS.ink(.tertiary))
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

                SettingsActionRow(icon: "hand.point.up.left.fill", label: "Replay Feature Tour") {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        walkthroughManager.replayWalkthrough(dataManager: dataManager)
                    }
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

            // MARK: - Demo Mode
            Section {
                HStack(spacing: GoldfishDS.Space.lg) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 15))
                        .frame(width: 20)
                        .foregroundStyle(GoldfishDS.ink(.tertiary))
                    Text("Show Demo Data")
                        .font(.gfBody)
                        .foregroundStyle(GoldfishDS.ink(.primary))
                    Spacer(minLength: 0)
                    Toggle("Show Demo Data", isOn: Binding(
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
                    Text("Demo data is on during the feature tour.")
                        .font(.gfMeta)
                        .foregroundStyle(GoldfishDS.ink(.tertiary))
                        .padding(.leading, 36)
                        .padding(.bottom, GoldfishDS.Space.xs)
                }
            } header: {
                SettingsSectionHeader("Demo Mode")
            } footer: {
                Text("Demo mode shows sample contacts and connections to showcase all features. Your real data is safely hidden while demo mode is active.")
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
                    label: "Export Contacts"
                ) {
                    ContactExportSelectionView()
                        .environmentObject(dataManager)
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(GoldfishDS.ink(.hairline)).frame(height: 0.5).padding(.leading, 44)
                }

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
                Text("Export selected people as a vCard. Goldfish can also restore included connections and pond membership. See Privacy for transfer limits.")
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
                    if viewModel.hasManualContacts {
                        showingExportPrompt = true
                    } else {
                        showingLogoutAlert = true
                    }
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
                Text("Resetting permanently deletes all your local data and returns the app to its initial state.")
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
            allowedContentTypes: [.vCard],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    viewModel.importContacts(from: url)
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
            if viewModel.hasImportDetails {
                Button("Details") { showingImportDetails = true }
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.importAlertMessage)
        }
        .sheet(isPresented: $showingImportDetails) {
            ImportDetailsView(
                lines: viewModel.importDetailLines,
                overflowCount: viewModel.importDetailOverflowCount
            )
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(GoldfishDS.Radius.sheet)
        }
        .alert("Reset Experience", isPresented: $showingLogoutAlert) {
            Button("Delete All Local Data", role: .destructive) {
                if viewModel.performReset(
                    walkthroughManager: walkthroughManager,
                    demoModeManager: demoModeManager
                ) { dismiss() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete ALL your contacts and connections. This action cannot be undone.")
        }
        .alert("Export Contacts?", isPresented: $showingExportPrompt) {
            Button("Export First") {
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
            Text("You have saved contacts. Export a copy first, then return here to reset. Delete All Local Data permanently deletes your contacts and connections.")
        }
        .sheet(item: $exportURL) { wrapper in
            ShareSheet(activityItems: [wrapper.value])
                .presentationCornerRadius(GoldfishDS.Radius.sheet)
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
