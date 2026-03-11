import SwiftUI
import UniformTypeIdentifiers
import Contacts

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

    init() {
        // Placeholder — will be replaced in onAppear; needed because
        // @EnvironmentObject isn't available in init.
        _viewModel = StateObject(wrappedValue: SettingsViewModel())
    }

    var body: some View {
        List {
            // MARK: - Profile
            Section {
                if let me = viewModel.mePerson {
                    NavigationLink {
                        ContactFormView(viewModel: ContactFormViewModel(dataManager: dataManager, person: me))
                            .environmentObject(dataManager)
                    } label: {
                        HStack(spacing: 12) {
                            ContactPhotoView(
                                photoData: me.photoData,
                                name: me.name,
                                colorHex: me.color,
                                size: 50
                            )
                            VStack(alignment: .leading) {
                                Text(me.name)
                                    .font(.headline)
                                Text("This is you")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } else {
                    Text("My Card not found")
                        .foregroundStyle(.secondary)
                }
            }

            // MARK: - Configuration
            Section("Configuration") {
                NavigationLink {
                    CircleManagerView()
                        .environmentObject(dataManager)
                } label: {
                    Label("Manage Ponds", systemImage: "circle.grid.hex")
                }
                

                
                Button(action: {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        walkthroughManager.replayWalkthrough(dataManager: dataManager)
                    }
                }) {
                    Label("Replay Feature Tour", systemImage: "hand.point.up.left.fill")
                        .foregroundColor(.primary)
                }
            }

            // MARK: - Demo Mode
            Section {
                Toggle(isOn: Binding(
                    get: { demoModeManager.isDemoModeActive },
                    set: { newValue in
                        if newValue {
                            demoModeManager.activateDemoMode(dataManager: dataManager)
                        } else {
                            demoModeManager.deactivateDemoMode()
                        }
                    }
                )) {
                    Label("Show Demo Data", systemImage: "sparkles")
                }
            } header: {
                Text("Demo Mode")
            } footer: {
                Text("Demo mode shows sample contacts and connections to showcase all features. Your real data is safely hidden while demo mode is active.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // MARK: - Data
            Section {
                NavigationLink {
                    ContactExportSelectionView()
                        .environmentObject(dataManager)
                } label: {
                    Label("Export Contacts", systemImage: "square.and.arrow.up")
                }

                Button {
                    showingImportOptions = true
                } label: {
                    Label("Import Contacts", systemImage: "square.and.arrow.down")
                }

                if viewModel.isImporting {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text(viewModel.importProgress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Data")
            } footer: {
                Text("Exports include connections, ponds, and relationship types. Another Goldfish user can import this file to restore the full network.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // MARK: - App Info
            Section {
                NavigationLink(destination: PrivacyPolicyView()) {
                    Label("Privacy Policy", systemImage: "hand.raised.fill")
                }
                
                HStack {
                    Text("Version")
                    Spacer()
                    Text("\(viewModel.appVersion) (\(viewModel.buildNumber))")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("About")
            } footer: {
                VStack(spacing: 8) {
                    Text("Goldfish © 2026")
                        .padding(.top)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }

            // MARK: - Logout
            Section {
                Button(role: .destructive) {
                    if viewModel.hasManualContacts {
                        showingExportPrompt = true
                    } else {
                        showingLogoutAlert = true
                    }
                } label: {
                    HStack {
                        Spacer()
                        Text("Logout and Reset Experience")
                        Spacer()
                    }
                }
            } footer: {
                Text("Logout will permanently delete all your local data and reset the app to its initial state.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("← Back") {
                    dismiss()
                }
            }
        }
        .onAppear {
            viewModel.configure(dataManager: dataManager)
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
                print("File picker error: \(error)")
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
        }
        .alert(viewModel.importAlertTitle, isPresented: $viewModel.showImportCompletionAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.importAlertMessage)
        }
        .alert("Reset Experience", isPresented: $showingLogoutAlert) {
            Button("Reset Anyway", role: .destructive) {
                viewModel.performReset(
                    walkthroughManager: walkthroughManager,
                    demoModeManager: demoModeManager
                )
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete ALL your contacts and connections. This action cannot be undone.")
        }
        .alert("Export Contacts?", isPresented: $showingExportPrompt) {
            Button("Export and Save") {
                if let url = viewModel.generateExportURL() {
                    self.exportURL = IdentifiableWrapper(url)
                    // We can't easily trigger ShareSheet from here without a bit more boilerplate,
                    // but we can provide the URL and then reset.
                    // For now, let's just trigger the system share sheet if possible or reset.
                    // A better way is to use a ShareLink in SwiftUI or a custom UIActivityViewController wrapper.
                }
            }
            Button("Reset Anyway", role: .destructive) {
                viewModel.performReset(
                    walkthroughManager: walkthroughManager,
                    demoModeManager: demoModeManager
                )
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You have manually created contacts. Would you like to export them before resetting everything?")
        }
        .sheet(item: $exportURL) { wrapper in
            ShareSheet(activityItems: [wrapper.value])
        }
    }
}


