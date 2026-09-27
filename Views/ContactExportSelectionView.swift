import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum ExportInclusionReason: Equatable {
    case selected
    case directConnection

    var label: String {
        switch self {
        case .selected: return "Selected"
        case .directConnection: return "Direct connection"
        }
    }
}

struct ExportScopeEntry: Identifiable {
    let contact: Person
    let reason: ExportInclusionReason
    var id: UUID { contact.id }
}

enum ContactExportScope {
    static func entries(eligibleContacts: [Person], selectedIDs: Set<UUID>, includeConnections: Bool) -> [ExportScopeEntry] {
        let selected = eligibleContacts.filter { selectedIDs.contains($0.id) }
        guard includeConnections else {
            return selected.map { ExportScopeEntry(contact: $0, reason: .selected) }
        }
        let connectedIDs = Set(selected.flatMap { $0.connectedContacts.map(\.id) })
        return eligibleContacts.compactMap { contact in
            if selectedIDs.contains(contact.id) {
                return ExportScopeEntry(contact: contact, reason: .selected)
            }
            if !contact.isMe && connectedIDs.contains(contact.id) {
                return ExportScopeEntry(contact: contact, reason: .directConnection)
            }
            return nil
        }
    }
}

struct ContactExportSelectionView: View {
    @EnvironmentObject private var demoModeManager: DemoModeManager
    @EnvironmentObject private var walkthroughManager: FeatureWalkthroughManager
    @State private var searchText = ""
    @State private var selectedIDs: Set<UUID> = []
    @State private var includeConnections = false
    @State private var exportURL: IdentifiableWrapper<URL>?
    @State private var errorMessage: String?
    @State private var showingScopeReview = false
    @State private var exportAfterReview = false
    @Query(sort: \Person.name) private var allContacts: [Person]

    private var isDemoMode: Bool { demoModeManager.isDemoModeActive || walkthroughManager.isActive }
    private var eligibleContacts: [Person] { allContacts.filter { $0.isMe || $0.isDemo == isDemoMode } }
    private var filteredContacts: [Person] {
        eligibleContacts.filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    private var allResultsSelected: Bool { !filteredContacts.isEmpty && filteredContacts.allSatisfy { selectedIDs.contains($0.id) } }
    private var exportScope: [ExportScopeEntry] {
        ContactExportScope.entries(eligibleContacts: eligibleContacts, selectedIDs: selectedIDs, includeConnections: includeConnections)
    }

    private var exportContacts: [Person] {
        exportScope.map(\.contact)
    }

    var body: some View {
        List {
            Section {
                Toggle("Include direct connections", isOn: $includeConnections)
                    .font(.gfBody).tint(GoldfishDS.terracotta)
                Text("Also export each selected person's directly connected people. Your own card is included only if you select it. The export button shows the total.")
                    .font(.gfMeta).foregroundStyle(GoldfishDS.ink(.secondary))
                if isDemoMode {
                    Text("Showing demo contacts. Turn off Show Demo Data in Settings to export your own contacts.")
                        .font(.gfMeta).foregroundStyle(GoldfishDS.ink(.secondary))
                }
            }
            .listRowBackground(GoldfishDS.surface)

            Section {
                if filteredContacts.isEmpty {
                    ContentUnavailableView(searchText.isEmpty ? "No contacts to export" : "No matching contacts",
                                           systemImage: searchText.isEmpty ? "person.crop.circle" : "magnifyingglass",
                                           description: Text(searchText.isEmpty ? "Add or import a contact first." : "Try another name."))
                }
                ForEach(filteredContacts) { contact in
                    Button { toggle(contact) } label: {
                        HStack(spacing: GoldfishDS.Space.md) {
                            ContactPhotoView(person: contact, size: .small)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(contact.name).font(.gfName).foregroundStyle(GoldfishDS.ink(.primary))
                                if contact.isMe {
                                    Text("This is you").font(.gfMeta).foregroundStyle(GoldfishDS.ink(.secondary))
                                }
                            }
                            Spacer()
                            Image(systemName: selectedIDs.contains(contact.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selectedIDs.contains(contact.id) ? GoldfishDS.terracotta : GoldfishDS.ink(.secondary))
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(contact.name + (contact.isMe ? ", your card" : ""))
                    .accessibilityValue(selectedIDs.contains(contact.id) ? "Selected" : "Not selected")
                    .accessibilityAddTraits(selectedIDs.contains(contact.id) ? .isSelected : [])
                }
            } header: {
                HStack {
                    Text("Select Contacts").gfSectionLabel()
                    Spacer()
                    if !filteredContacts.isEmpty {
                        Button(allResultsSelected ? "Deselect Results" : "Select Results") {
                            let visible = Set(filteredContacts.map(\.id))
                            if allResultsSelected { selectedIDs.subtract(visible) } else { selectedIDs.formUnion(visible) }
                        }
                        .font(.gfMeta).foregroundStyle(GoldfishDS.terracotta)
                        .frame(minHeight: 44)
                    }
                }
            }
            .listRowBackground(GoldfishDS.surface)
        }
        .scrollContentBackground(.hidden)
        .background(GoldfishDS.warmBlack)
        .searchable(text: $searchText, prompt: "Search contacts")
        .navigationTitle("Export Contacts")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: GoldfishDS.Space.xs) {
                Button { generateExport() } label: {
                    Text("Export \(exportContacts.count) \(exportContacts.count == 1 ? "Person" : "People")")
                        .font(.gfBody.weight(.medium))
                        .foregroundStyle(GoldfishDS.paper)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background(GoldfishDS.ink(exportContacts.isEmpty ? .quaternary : .primary),
                                    in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
                }
                .buttonStyle(.plain)
                .disabled(exportContacts.isEmpty)
                .accessibilityIdentifier("exportContactsButton")

                Button("Review \(exportContacts.count) people") {
                    showingScopeReview = true
                }
                .font(.gfMeta)
                .foregroundStyle(GoldfishDS.terracotta)
                .frame(minHeight: 44)
                .disabled(exportContacts.isEmpty)
            }
            .padding(.horizontal, GoldfishDS.Space.pageMargin)
            .padding(.vertical, GoldfishDS.Space.sm)
            .background(GoldfishDS.warmBlack)
        }
        .sheet(item: $exportURL) { wrapper in ShareSheet(activityItems: [wrapper.value]) }
        .sheet(isPresented: $showingScopeReview, onDismiss: {
            guard exportAfterReview else { return }
            exportAfterReview = false
            generateExport()
        }) {
            ExportScopeReview(
                entries: exportScope,
                includeConnections: includeConnections,
                isDemoMode: isDemoMode,
                onCreate: {
                    exportAfterReview = true
                    showingScopeReview = false
                }
            )
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(GoldfishDS.Radius.sheet)
        }
        .alert("Could not export contacts", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "") }
    }

    private func toggle(_ contact: Person) {
        if selectedIDs.contains(contact.id) { selectedIDs.remove(contact.id) } else { selectedIDs.insert(contact.id) }
    }

    private func generateExport() {
        let data = VCardExportService.exportSelected(exportContacts, depth: 0)
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Goldfish-Contacts.vcf")
            try data.write(to: url, options: .atomic)
            exportURL = IdentifiableWrapper(url)
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct ExportScopeReview: View {
    @Environment(\.dismiss) private var dismiss
    let entries: [ExportScopeEntry]
    let includeConnections: Bool
    let isDemoMode: Bool
    let onCreate: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(isDemoMode ? "Demo contacts" : "Your contacts")
                        .font(.gfBody)
                    Text(includeConnections
                         ? "Review the people included by your selection and direct connections. Me is included only when selected."
                         : "Selected people only. Me is included only when selected.")
                        .font(.gfMeta)
                        .foregroundStyle(GoldfishDS.ink(.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(GoldfishDS.surface)

                Section("Included \(entries.count) \(entries.count == 1 ? "person" : "people")") {
                    ForEach(entries) { entry in
                        HStack(spacing: GoldfishDS.Space.md) {
                            ContactPhotoView(person: entry.contact, size: .small)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.contact.name)
                                    .font(.gfName)
                                    .foregroundStyle(GoldfishDS.ink(.primary))
                                if includeConnections {
                                    Text(entry.reason.label)
                                        .font(.gfMeta)
                                        .foregroundStyle(entry.reason == .directConnection ? GoldfishDS.ink(.secondary) : GoldfishDS.terracotta)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 44)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(entry.contact.name), \(includeConnections ? entry.reason.label : "Selected")")
                    }
                }
                .listRowBackground(GoldfishDS.surface)
            }
            .scrollContentBackground(.hidden)
            .background(GoldfishDS.warmBlack.ignoresSafeArea())
            .navigationTitle("Review Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(GoldfishDS.ink(.secondary))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create vCard", action: onCreate)
                        .foregroundStyle(GoldfishDS.terracotta)
                }
            }
        }
    }
}
