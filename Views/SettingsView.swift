import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var dataManager: GoldfishDataManager

    var body: some View {
        SettingsContent(dataManager: dataManager)
    }
}

// MARK: - Settings Content
private struct SettingsContent: View {
    @StateObject var viewModel: SettingsViewModel
    @EnvironmentObject var dataManager: GoldfishDataManager

    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var exportURL: URL?

    init(dataManager: GoldfishDataManager) {
        _viewModel = StateObject(wrappedValue: SettingsViewModel(dataManager: dataManager))
    }

    var body: some View {
        List {
            // MARK: - Profile
            Section {
                if let me = viewModel.mePerson {
                    NavigationLink(destination: ContactFormView(viewModel: ContactFormViewModel(dataManager: dataManager, person: me))) {
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
                NavigationLink(destination: CircleManagerView()) {
                    Label("Manage Circles", systemImage: "circle.grid.hex")
                }
            }

            // MARK: - Data
            Section("Data") {
                Button(action: {
                    exportURL = viewModel.generateExportURL()
                    if exportURL != nil {
                        showingExporter = true
                    }
                }) {
                    Label("Export Contacts", systemImage: "square.and.arrow.up")
                }

                Button(action: { showingImporter = true }) {
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
            }

            // MARK: - App Info
            Section {
                Link(destination: URL(string: "https://goldfish-app.com/privacy")!) {
                    Label("Privacy Policy", systemImage: "hand.raised.fill")
                }

                Link(destination: URL(string: "mailto:support@goldfish-app.com")!) {
                    Label("Contact Support", systemImage: "envelope.fill")
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
                Text("Goldfish © 2026")
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top)
            }
        }
        .navigationTitle("Settings")
        .sheet(isPresented: $showingExporter) {
            if let url = exportURL {
                ShareSheet(activityItems: [url])
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
                print("File picker error: \(error)")
            }
        }
    }
}

// MARK: - UIKit Share Sheet Wrapper
private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
