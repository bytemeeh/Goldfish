import SwiftUI
import SwiftData

struct GoldfishShareImportView: View {
    @EnvironmentObject private var dataManager: GoldfishDataManager
    @EnvironmentObject private var walkthroughManager: FeatureWalkthroughManager
    @EnvironmentObject private var demoModeManager: DemoModeManager
    @Environment(\.dismiss) private var dismiss

    let url: URL
    @State private var preview: GoldfishContactBundle.GoldfishSharePreview?
    @State private var result: GoldfishContactBundle.GoldfishShareImportResult?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var isImporting = false
    @State private var reviewedData: Data?

    private let maximumFileSize = 50 * 1_024 * 1_024

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Reading Goldfish bundle…")
                        .font(.gfBody)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    ContentUnavailableView("Could not read bundle", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                        .padding()
                } else if let result {
                    completion(result)
                } else if let preview {
                    review(preview)
                }
            }
            .background(GoldfishDS.warmBlack.ignoresSafeArea())
            .navigationTitle(result == nil ? "Review Goldfish Bundle" : "Import Complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(result == nil ? "Cancel" : "Done") { dismiss() }
                        .frame(minHeight: 44)
                }
            }
            .task(id: url) { await loadPreview() }
        }
    }

    private func review(_ preview: GoldfishContactBundle.GoldfishSharePreview) -> some View {
        List {
            Section {
                Text("\(preview.people.count) people · \(preview.relationshipsCount) relationships · \(preview.ponds.count) ponds")
                    .font(.gfBody).foregroundStyle(GoldfishDS.ink(.primary))
                Text("Contact details, photos, and locations are copied when present. Notes are \(preview.includesNotes ? "included" : "omitted") in this bundle.")
                    .font(.gfMeta).foregroundStyle(GoldfishDS.ink(.secondary)).fixedSize(horizontal: false, vertical: true)
                Text("Previously shared contacts are recognized. Existing details and pond assignments are kept; missing details are added. Your own card stays yours.")
                    .font(.gfMeta).foregroundStyle(GoldfishDS.ink(.secondary)).fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(GoldfishDS.surface)

            Section("People in bundle") {
                ForEach(Array(preview.people.enumerated()), id: \.offset) { _, name in
                    Label(name, systemImage: "person.crop.circle")
                        .font(.gfBody).foregroundStyle(GoldfishDS.ink(.primary))
                        .frame(minHeight: 44)
                }
            }
            .listRowBackground(GoldfishDS.surface)

            Section("Ponds in bundle") {
                if preview.ponds.isEmpty {
                    Text("No pond information").font(.gfMeta).foregroundStyle(GoldfishDS.ink(.secondary)).frame(minHeight: 44)
                } else {
                    ForEach(Array(preview.ponds.enumerated()), id: \.offset) { _, name in
                        Label(name, systemImage: "circle.grid.hex")
                            .font(.gfBody).foregroundStyle(GoldfishDS.ink(.primary)).frame(minHeight: 44)
                    }
                }
            }
            .listRowBackground(GoldfishDS.surface)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) {
            Button { importBundle() } label: {
                Text(isImporting ? "Importing…" : "Import Reviewed Bundle")
                    .font(.gfBody.weight(.medium)).foregroundStyle(GoldfishDS.paper)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(GoldfishDS.ink(isImporting ? .quaternary : .primary), in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
            }
            .disabled(isImporting)
            .padding(.horizontal, GoldfishDS.Space.pageMargin).padding(.vertical, GoldfishDS.Space.sm)
            .background(GoldfishDS.warmBlack)
        }
    }

    private func completion(_ result: GoldfishContactBundle.GoldfishShareImportResult) -> some View {
        List {
            Section {
                NavigationLink("Organize people") {
                    ContactOrganizationView(dataManager: dataManager, isDemoMode: false)
                }
                Text("\(result.addedPeople) people added · \(result.reusedPeople) existing people recognized")
                Text("\(result.connectionsAdded) relationships added · \(result.pondsAdded) ponds added")
                if result.organizationConflicts > 0 {
                    Text("\(result.organizationConflicts) pond membership conflicts kept your existing organization.")
                }
                Text("Previously shared contacts were reused. Contacts saved separately may still appear twice, even if they have the same name. The sender’s connections stay intact; no connection to you is assumed. Your contacts will open in List view so you can find them immediately.")
                    .font(.gfMeta).foregroundStyle(GoldfishDS.ink(.secondary)).fixedSize(horizontal: false, vertical: true)
            }
            .font(.gfBody).foregroundStyle(GoldfishDS.ink(.primary)).listRowBackground(GoldfishDS.surface)
        }
        .listStyle(.insetGrouped).scrollContentBackground(.hidden)
    }

    @MainActor
    private func loadPreview() async {
        isLoading = true
        errorMessage = nil
        do {
            let fileURL = url
            let limit = maximumFileSize
            let data = try await Task.detached(priority: .userInitiated) { () throws -> Data in
                let hasAccess = fileURL.startAccessingSecurityScopedResource()
                defer { if hasAccess { fileURL.stopAccessingSecurityScopedResource() } }
                let values = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                guard let size = values.fileSize, size <= limit else {
                    throw GoldfishContactBundle.BundleError.tooLarge
                }
                return try Data(contentsOf: fileURL, options: .mappedIfSafe)
            }.value
            preview = try GoldfishContactBundle.preview(data: data)
            reviewedData = data
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func importBundle() {
        guard let data = reviewedData, !isImporting else { return }
        isImporting = true
        do {
            // A fresh context prevents unrelated unsaved edits in the live UI from
            // being included in the bundle import transaction.
            let importContext = ModelContext(dataManager.context.container)
            let imported = try GoldfishContactBundle.importData(data, into: importContext)
            result = imported
            if walkthroughManager.isActive { walkthroughManager.finishTour(keepDemoData: true) }
            demoModeManager.deactivateDemoMode()
            NotificationCenter.default.post(name: .goldfishDataDidChange, object: nil,
                                            userInfo: ["goldfishSharedImport": true])
        } catch {
            errorMessage = error.localizedDescription
        }
        isImporting = false
    }
}
