import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum ExportInclusionReason: Equatable {
    case selected
    case directConnection
    case connectedBranch

    var label: String {
        switch self {
        case .selected: return "Selected"
        case .directConnection: return "Direct connection"
        case .connectedBranch: return "Connected branch"
        }
    }
}

struct ExportScopeEntry: Identifiable {
    let contact: Person
    let reason: ExportInclusionReason
    var id: UUID { contact.id }
}

enum ContactExportScope {
    /// Kept for callers that use the original Boolean scope API.
    static func entries(eligibleContacts: [Person], selectedIDs: Set<UUID>, includeConnections: Bool) -> [ExportScopeEntry] {
        entries(eligibleContacts: eligibleContacts, selectedIDs: selectedIDs, depth: includeConnections ? 1 : 0)
    }

    /// A depth of 0 includes selected people, 1 adds direct connections, and
    /// nil includes every eligible person reachable through saved relationships.
    static func entries(eligibleContacts: [Person], selectedIDs: Set<UUID>, depth: Int?) -> [ExportScopeEntry] {
        let eligibleByID = Dictionary(eligibleContacts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let roots = selectedIDs.intersection(Set(eligibleByID.keys))
        guard depth != 0, !roots.isEmpty else {
            return eligibleContacts.compactMap { roots.contains($0.id) ? ExportScopeEntry(contact: $0, reason: .selected) : nil }
        }

        var distance = Dictionary(uniqueKeysWithValues: roots.map { ($0, 0) })
        var frontier = Array(roots)
        while !frontier.isEmpty {
            let id = frontier.removeFirst()
            let nextDistance = (distance[id] ?? 0) + 1
            if let depth, nextDistance > depth { continue }
            guard let person = eligibleByID[id] else { continue }
            if person.isMe && !roots.contains(id) { continue }
            for neighbor in person.connectedContacts where eligibleByID[neighbor.id] != nil && distance[neighbor.id] == nil {
                distance[neighbor.id] = nextDistance
                frontier.append(neighbor.id)
            }
        }
        return eligibleContacts.compactMap { contact in
            guard let d = distance[contact.id] else { return nil }
            if roots.contains(contact.id) { return ExportScopeEntry(contact: contact, reason: .selected) }
            // Me is deliberately excluded from expansion unless explicitly selected.
            guard !contact.isMe else { return nil }
            return ExportScopeEntry(contact: contact, reason: d == 1 ? .directConnection : .connectedBranch)
        }
    }
}

private enum ContactExportFormat: String, CaseIterable, Identifiable {
    case goldfish
    case vCard
    var id: String { rawValue }
    var title: String { self == .goldfish ? "Goldfish bundle" : "vCard" }
}

struct ContactExportSelectionView: View {
    @EnvironmentObject private var demoModeManager: DemoModeManager
    @EnvironmentObject private var walkthroughManager: FeatureWalkthroughManager
    @State private var searchText = ""
    @State private var selectedIDs: Set<UUID> = []
    @State private var scopeDepth: Int? = 0
    @State private var selectedPondID: UUID?
    @State private var includeNotes = true
    @State private var format: ContactExportFormat = .goldfish
    @State private var exportURL: IdentifiableWrapper<URL>?
    @State private var errorMessage: String?
    @State private var showingScopeReview = false
    @State private var exportAfterReview = false
    @Query(sort: \Person.name) private var allContacts: [Person]
    @Query(sort: \GoldfishCircle.sortOrder) private var allPonds: [GoldfishCircle]

    init(selectedContactIDs: Set<UUID> = []) {
        _selectedIDs = State(initialValue: selectedContactIDs)
    }

    private var isDemoMode: Bool { demoModeManager.isDemoModeActive || walkthroughManager.isActive }
    private var eligibleContacts: [Person] { allContacts.filter { $0.isMe || $0.isDemo == isDemoMode } }
    private var eligibleIDs: Set<UUID> { Set(eligibleContacts.map(\.id)) }
    private var pondFilteredContacts: [Person] {
        guard let selectedPondID else { return eligibleContacts }
        return eligibleContacts.filter { person in
            person.circleContacts.contains { $0.circle.id == selectedPondID && !$0.manuallyExcluded }
        }
    }
    private var filteredContacts: [Person] {
        pondFilteredContacts.filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    private var allResultsSelected: Bool { !filteredContacts.isEmpty && filteredContacts.allSatisfy { selectedIDs.contains($0.id) } }
    private var exportScope: [ExportScopeEntry] {
        ContactExportScope.entries(eligibleContacts: eligibleContacts, selectedIDs: selectedIDs, depth: scopeDepth)
    }
    private var exportContacts: [Person] { exportScope.map(\.contact) }
    private var exportIDs: Set<UUID> { Set(exportContacts.map(\.id)) }
    private var relationshipCount: Int {
        var seen = Set<UUID>()
        for person in exportContacts {
            for relationship in person.allRelationships where exportIDs.contains(relationship.fromContact.id) && exportIDs.contains(relationship.toContact.id) {
                seen.insert(relationship.id)
            }
        }
        return seen.count
    }
    private var includedPonds: [GoldfishCircle] {
        allPonds.filter { pond in pond.circleContacts.contains { exportIDs.contains($0.contact.id) } }
    }

    var body: some View {
        List {
            Section {
                Picker("Include connections", selection: $scopeDepth) {
                    Text("Selected people only").tag(Optional<Int>.some(0))
                    Text("Direct connections").tag(Optional<Int>.some(1))
                    Text("Whole connected branch").tag(Optional<Int>.none)
                }
                .font(.gfBody)
                .accessibilityHint("Choose how far to follow saved relationships from selected people")

                Picker("Pond", selection: $selectedPondID) {
                    Text("All ponds").tag(UUID?.none)
                    ForEach(allPonds.filter { pond in pond.circleContacts.contains { eligibleIDs.contains($0.contact.id) } }) { pond in
                        Text(pond.name).tag(Optional(pond.id))
                    }
                }
                .font(.gfBody)

                Picker("File format", selection: $format) {
                    ForEach(ContactExportFormat.allCases) { value in Text(value.title).tag(value) }
                }
                .font(.gfBody)
                if format == .goldfish {
                    Toggle("Include notes", isOn: $includeNotes).tint(GoldfishDS.terracotta)
                } else {
                    Text("vCards include notes when present.").font(.gfMeta).foregroundStyle(GoldfishDS.ink(.secondary))
                }
                Text("Goldfish bundles preserve relationships, ponds, contact details, and photos. Recipients must open the file in Goldfish to restore its structure. vCards work with common contacts apps, but cannot preserve the full structure.")
                    .font(.gfMeta).foregroundStyle(GoldfishDS.ink(.secondary)).fixedSize(horizontal: false, vertical: true)
                if isDemoMode {
                    Text("Showing demo contacts. Turn off Show Demo Data in Settings to share your own contacts.")
                        .font(.gfMeta).foregroundStyle(GoldfishDS.ink(.secondary))
                }
            }
            .listRowBackground(GoldfishDS.surface)

            Section {
                if filteredContacts.isEmpty {
                    ContentUnavailableView(searchText.isEmpty ? "No contacts to share" : "No matching contacts",
                                           systemImage: searchText.isEmpty ? "person.crop.circle" : "magnifyingglass",
                                           description: Text(searchText.isEmpty ? "Add or import a contact first." : "Try another name or pond."))
                }
                ForEach(filteredContacts) { contact in
                    Button { toggle(contact) } label: {
                        HStack(spacing: GoldfishDS.Space.md) {
                            ContactPhotoView(person: contact, size: .small)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(contact.name).font(.gfName).foregroundStyle(GoldfishDS.ink(.primary))
                                if contact.isMe { Text("This is you").font(.gfMeta).foregroundStyle(GoldfishDS.ink(.secondary)) }
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
                    Text("Select People").gfSectionLabel()
                    Spacer()
                    if !filteredContacts.isEmpty {
                        Button(allResultsSelected ? "Deselect Results" : "Select Results") {
                            let visible = Set(filteredContacts.map(\.id))
                            if allResultsSelected { selectedIDs.subtract(visible) } else { selectedIDs.formUnion(visible) }
                        }
                        .font(.gfMeta).foregroundStyle(GoldfishDS.terracotta).frame(minHeight: 44)
                    }
                }
            }
            .listRowBackground(GoldfishDS.surface)
        }
        .scrollContentBackground(.hidden)
        .background(GoldfishDS.warmBlack)
        .searchable(text: $searchText, prompt: "Search people")
        .navigationTitle("Share Contacts")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button { showingScopeReview = true } label: {
                Text("Review \(exportContacts.count) \(exportContacts.count == 1 ? "Person" : "People")")
                    .font(.gfBody.weight(.medium)).foregroundStyle(GoldfishDS.paper)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(GoldfishDS.ink(exportContacts.isEmpty ? .quaternary : .primary), in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
            }
            .buttonStyle(.plain).disabled(exportContacts.isEmpty)
            .padding(.horizontal, GoldfishDS.Space.pageMargin).padding(.vertical, GoldfishDS.Space.sm)
            .background(GoldfishDS.warmBlack)
        }
        .sheet(item: $exportURL) { wrapper in
            ShareSheet(activityItems: [wrapper.value])

        }
        .sheet(isPresented: $showingScopeReview, onDismiss: {
            guard exportAfterReview else { return }
            exportAfterReview = false
            generateExport()
        }) {
            ExportScopeReview(entries: exportScope, relationshipCount: relationshipCount,
                             ponds: includedPonds.map(\.name), includeNotes: includeNotes, format: format,
                             isDemoMode: isDemoMode, onCreate: {
                exportAfterReview = true
                showingScopeReview = false
            })
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(GoldfishDS.Radius.sheet)
        }
        .alert("Could not share contacts", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("OK") { errorMessage = nil } } message: { Text(errorMessage ?? "") }
    }

    private func toggle(_ contact: Person) {
        if selectedIDs.contains(contact.id) { selectedIDs.remove(contact.id) } else { selectedIDs.insert(contact.id) }
    }

    @MainActor private func generateExport() {
        do {
            let data: Data
            let ext: String
            switch format {
            case .goldfish:
                data = try GoldfishContactBundle.export(contacts: exportContacts, includeNotes: includeNotes)
                ext = "goldfish"
            case .vCard:
                data = VCardExportService.exportSelected(exportContacts, depth: 0)
                ext = "vcf"
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("Goldfish-Contacts-\(UUID().uuidString).\(ext)")
            try data.write(to: url, options: .atomic)
            exportURL = IdentifiableWrapper(url)
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct ExportScopeReview: View {
    @Environment(\.dismiss) private var dismiss
    let entries: [ExportScopeEntry]
    let relationshipCount: Int
    let ponds: [String]
    let includeNotes: Bool
    let format: ContactExportFormat
    let isDemoMode: Bool
    let onCreate: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(isDemoMode ? "Demo contacts" : "Your contacts").font(.gfBody)
                    Text("\(entries.count) people · \(relationshipCount) internal relationships · \(ponds.count) ponds")
                        .font(.gfMeta).foregroundStyle(GoldfishDS.ink(.secondary))
                    Text("Names, contact details, and photos are included. \(format == .goldfish ? (includeNotes ? "Notes are included." : "Notes are omitted.") : "Notes are included when present.") \(format == .goldfish ? "The recipient needs Goldfish to open this bundle and preserve its structure." : "A vCard cannot preserve full relationships and pond structure.")")
                        .font(.gfMeta).foregroundStyle(GoldfishDS.ink(.secondary)).fixedSize(horizontal: false, vertical: true)
                    Text("Your card is included only if you selected it. Demo contacts and real contacts are kept in separate sharing scopes.")
                        .font(.gfMeta).foregroundStyle(GoldfishDS.ink(.secondary)).fixedSize(horizontal: false, vertical: true)
                }
                .listRowBackground(GoldfishDS.surface)

                Section("Included people") {
                    ForEach(entries) { entry in
                        HStack(spacing: GoldfishDS.Space.md) {
                            ContactPhotoView(person: entry.contact, size: .small)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.contact.name).font(.gfName).foregroundStyle(GoldfishDS.ink(.primary))
                                if entry.reason != .selected {
                                    Text(entry.reason.label).font(.gfMeta).foregroundStyle(GoldfishDS.ink(.secondary))
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 44)
                        .accessibilityElement(children: .combine)
                    }
                }
                .listRowBackground(GoldfishDS.surface)
            }
            .scrollContentBackground(.hidden)
            .background(GoldfishDS.warmBlack.ignoresSafeArea())
            .navigationTitle("Review Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(GoldfishDS.ink(.secondary))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Share \(format == .goldfish ? "Bundle" : "vCard")", action: onCreate).foregroundStyle(GoldfishDS.terracotta)
                }
            }
        }
    }
}
