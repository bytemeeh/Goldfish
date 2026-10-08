import SwiftUI
import MapKit
import SwiftData

struct ContactDetailView: View {
    @StateObject var viewModel: ContactDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var dataManager: GoldfishDataManager
    @EnvironmentObject var walkthroughManager: FeatureWalkthroughManager
    @AppStorage("isDemoModeActive") private var isDemoModeActive = false
    @State private var showAddRelationship = false
    @State private var showAddMemory = false
    @State private var relationshipToDelete: Relationship?
    var showsCloseButton = false
    var allowsRippleExploration = true
    var onExploreRipples: ((UUID) -> Void)? = nil

    /// Optional hero transition (name-flight from the list row). iOS 18+.
    var heroNamespace: Namespace.ID? = nil
    var heroID: UUID? = nil

    private var pondName: String? {
        viewModel.person.circleContacts.first(where: { !$0.manuallyExcluded })?.circle.name
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
        List {
            // MARK: - Header
            Section {
                headerCell
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .id("walkthroughProfileHeader")

            // MARK: - Relationship story
            if viewModel.relationshipSummary != nil || viewModel.pondSummary != nil ||
                !(viewModel.person.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                Section {
                    relationshipStory
                }
                .listRowBackground(GoldfishDS.surface)
                .listRowSeparator(.hidden)
            }

            // MARK: - Contact Info
            let rows = infoRows
            if !rows.isEmpty {
                Section {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        contactInfoRow(row)
                    }
                } header: {
                    Text("Contact Info")
                        .gfSectionLabel()
                }
                .listRowBackground(GoldfishDS.surface)
            }

            // MARK: - Relationships
            Section {
                if allowsRippleExploration && (viewModel.connectedPeopleCount > 0 || viewModel.person.isMe) && !walkthroughManager.isActive,
                   let onExploreRipples {
                    Button {
                        onExploreRipples(viewModel.person.id)
                    } label: {
                        Label(viewModel.person.isMe ? "My ponds" : "Show in Pond", systemImage: "circle.dotted.circle")
                            .font(.gfBody)
                            .foregroundStyle(GoldfishDS.terracotta)
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("exploreRipplesButton")
                }
                if viewModel.groupedRelationships.isEmpty {
                    nativeEmptyRelationships
                } else {
                    ForEach(viewModel.groupedRelationships.keys.sorted(), id: \.self) { type in
                        let rels = viewModel.groupedRelationships[type] ?? []
                        ForEach(rels) { rel in
                            let other = rel.otherContact(from: viewModel.person)
                            NavigationLink(destination:
                                ContactDetailView(viewModel: ContactDetailViewModel(person: other, dataManager: dataManager),
                                                  allowsRippleExploration: allowsRippleExploration,
                                                  onExploreRipples: onExploreRipples)
                                    .environmentObject(dataManager)
                            ) {
                                relationshipRow(person: other, type: type)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { relationshipToDelete = rel } label: {
                                    Label("Remove connection", systemImage: "link.badge.minus")
                                }
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Connections")
                        .gfSectionLabel()
                    Spacer()
                    Button {
                        showAddRelationship = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(GoldfishDS.ink(.primary))
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Add relationship")
                    .accessibilityIdentifier("addRelationshipButton")
                    .walkthroughAnchor(step: .link)
                }
            }
            .listRowBackground(GoldfishDS.surface)
            .id("walkthroughProfileConnections")

            // MARK: - Map / Location
            if let lat = viewModel.person.primaryLocation?.latitude,
               let lon = viewModel.person.primaryLocation?.longitude {
                Section {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                    ))) {
                        Marker(viewModel.person.name, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                    }
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: GoldfishDS.Radius.card))
                    .overlay(
                        RoundedRectangle(cornerRadius: GoldfishDS.Radius.card)
                            .strokeBorder(GoldfishDS.ink(.hairline), lineWidth: GoldfishDS.Rule.hairline)
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                } header: {
                    Text("Location")
                        .gfSectionLabel()
                }
                .listRowBackground(GoldfishDS.surface)
            } else if let address = viewModel.person.fullAddress {
                Section {
                    Label {
                        Text(address)
                            .font(.gfBody)
                            .foregroundStyle(GoldfishDS.ink(.primary))
                    } icon: {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(GoldfishDS.ink(.secondary))
                    }
                } header: {
                    Text("Location")
                        .gfSectionLabel()
                }
                .listRowBackground(GoldfishDS.surface)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(GoldfishDS.warmBlack)
        .gfZoomDestination(id: heroID, in: heroNamespace)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(GoldfishDS.warmBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("closeContactButton")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if walkthroughManager.isActive,
               [.search, .profile, .link].contains(walkthroughManager.currentStep) {
                WalkthroughInlineGuide(
                    maximumHeight: 260,
                    actionPromptOverride: walkthroughManager.currentStep == .link && !walkthroughManager.exampleConnectionIsExisting
                        ? "Tap + beside Connections, then choose a person and a relationship type."
                        : nil
                )
                    .padding(.horizontal, GoldfishDS.Space.pageMargin)
                    .safeAreaPadding(.bottom, 8)
            }
        }
        .sheet(isPresented: $viewModel.isEditing, onDismiss: {
            viewModel.refreshData()
            NotificationCenter.default.post(name: .goldfishDataDidChange, object: nil)
        }) {
            NavigationStack {
                ContactFormView(viewModel: ContactFormViewModel(dataManager: dataManager, person: viewModel.person))
                    .environmentObject(dataManager)
            }
        }
        .sheet(isPresented: $showAddRelationship, onDismiss: { viewModel.refreshData() }) {
            AddRelationshipView(person: viewModel.person, dataManager: dataManager)
        }
        .sheet(isPresented: $showAddMemory) {
            AddMemorySheet(personName: viewModel.person.name) { memory in
                viewModel.addMemory(memory)
                    ? nil
                    : (viewModel.errorMessage ?? "The memory could not be saved. Try again.")
            }
        }
        .confirmationDialog("Remove connection?", isPresented: Binding(
            get: { relationshipToDelete != nil },
            set: { if !$0 { relationshipToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Remove Connection", role: .destructive) {
                if let relationship = relationshipToDelete { viewModel.removeRelationship(relationship) }
                relationshipToDelete = nil
            }
            Button("Cancel", role: .cancel) { relationshipToDelete = nil }
        } message: { Text("Both people are kept. Only their connection is removed.") }
        .alert("Could not complete action", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) { Button("OK") { viewModel.errorMessage = nil } } message: { Text(viewModel.errorMessage ?? "") }
        .onAppear {
            viewModel.isDemoMode = walkthroughManager.isActive || isDemoModeActive
            viewModel.refreshData()
            walkthroughManager.report(.openedProfile)
            scrollForWalkthrough(step: walkthroughManager.currentStep, proxy: scrollProxy)
        }
        .onChange(of: walkthroughManager.isActive) { _, isActive in
            viewModel.isDemoMode = isActive || isDemoModeActive
        }
        .onChange(of: isDemoModeActive) { _, isDemoActive in
            viewModel.isDemoMode = walkthroughManager.isActive || isDemoActive
        }
        .onChange(of: walkthroughManager.currentStep) { _, step in
            if step != .link { showAddRelationship = false }
            if step == .profile || (step == .link && walkthroughManager.exampleConnectionIsExisting) {
                walkthroughManager.report(.openedProfile)
            }
            scrollForWalkthrough(step: step, proxy: scrollProxy)
        }
        .onChange(of: viewModel.person.isDeleted) { _, deleted in if deleted { dismiss() } }
        .onReceive(NotificationCenter.default.publisher(for: .goldfishDataDidChange)) { _ in
            viewModel.refreshData()
        }
        .toastOverlay()
    }
    }

    private func scrollForWalkthrough(step: WalkthroughStep, proxy: ScrollViewProxy) {
        guard walkthroughManager.isActive, step == .profile || step == .link else { return }
        let target = step == .link ? "walkthroughProfileConnections" : "walkthroughProfileHeader"
        Task { @MainActor in
            await Task.yield()
            guard walkthroughManager.isActive, walkthroughManager.currentStep == step else { return }
            if reduceMotion {
                proxy.scrollTo(target, anchor: .top)
            } else {
                withAnimation(GoldfishDS.Motion.settle) {
                    proxy.scrollTo(target, anchor: .top)
                }
            }
        }
    }

    // MARK: - Header cell

    @ViewBuilder private var headerCell: some View {
        VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 16 : 10) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: GoldfishDS.Space.md) {
                    ContactPhotoView(person: viewModel.person, size: .extraLarge)
                    identityDetails
                }
            } else {
                HStack(alignment: .center, spacing: GoldfishDS.Space.lg) {
                    ContactPhotoView(person: viewModel.person, size: .large)
                    identityDetails
                }
            }
            contactActionShelf
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 16 : 8)
        .walkthroughAnchor(step: .profile)
    }

    @ViewBuilder private var identityDetails: some View {
        VStack(alignment: .leading, spacing: GoldfishDS.Space.sm) {
                Text(viewModel.person.name)
                    .font(.gfHero)
                    .foregroundStyle(GoldfishDS.ink(.primary))
                    .multilineTextAlignment(.leading)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)

                if viewModel.person.isMe {
                    Text("Your place in the pond".uppercased())
                        .font(.gfLabel)
                        .kerning(1.1)
                        .foregroundStyle(GoldfishDS.ink(.secondary))
                } else if let pondName {
                    // Signage chip: line-color bar + uppercase line name
                    HStack(spacing: GoldfishDS.Space.sm) {
                        Circle()
                            .fill(GoldfishDS.groupTone(viewModel.person.primaryCircle))
                            .frame(width: 6, height: 6)
                        Text(pondName.uppercased())
                            .font(.gfLabel)
                            .kerning(1.1)
                            .foregroundStyle(GoldfishDS.ink(.secondary))
                    }
                }
            }
    }

    @ViewBuilder private var relationshipStory: some View {
        VStack(alignment: .leading, spacing: GoldfishDS.Space.md) {
            if let relationship = viewModel.relationshipSummary {
                storyLine(icon: "person.2", title: "Connection", value: relationship)
            }
            if let pond = viewModel.pondSummary {
                storyLine(icon: "circle.hexagongrid", title: "Membership", value: pond)
            }
            if let notes = viewModel.person.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: GoldfishDS.Space.xs) {
                    Text("REMEMBER" ).gfSectionLabel()
                    Text(notes)
                        .font(.gfProse)
                        .foregroundStyle(GoldfishDS.ink(.primary))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, GoldfishDS.Space.xs)
    }

    @ViewBuilder private func storyLine(icon: String, title: String, value: String) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: GoldfishDS.Space.xs) {
                Label(title.uppercased(), systemImage: icon)
                    .font(.gfCaption)
                    .tracking(0.8)
                    .foregroundStyle(GoldfishDS.ink(.secondary))
                Text(value)
                    .font(.gfBody.weight(.medium))
                    .foregroundStyle(GoldfishDS.ink(.primary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, GoldfishDS.Space.xs)
        } else {
        HStack(alignment: .firstTextBaseline, spacing: GoldfishDS.Space.sm) {
            Image(systemName: icon)
                .foregroundStyle(GoldfishDS.terracotta)
                .frame(width: 22)
            Text(title.uppercased())
                .font(.gfCaption)
                .tracking(0.8)
                .foregroundStyle(GoldfishDS.ink(.secondary))
            Spacer(minLength: GoldfishDS.Space.sm)
            Text(value)
                .font(.gfBody.weight(.medium))
                .foregroundStyle(GoldfishDS.ink(.primary))
                .multilineTextAlignment(.trailing)
        }
        .frame(minHeight: 44)
        }
    }

    @ViewBuilder private var contactActionShelf: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 140 : 60), spacing: GoldfishDS.Space.sm)], spacing: GoldfishDS.Space.sm) {
                profileAction("Edit", systemImage: "pencil") { viewModel.isEditing = true }
                profileAction("Memory", systemImage: "square.and.pencil") { showAddMemory = true }
                if hasUsablePhone {
                    profileAction("Call", systemImage: "phone") { viewModel.callContact() }
                    profileAction("Text", systemImage: "message") { viewModel.messageContact() }
                }
                if hasUsableEmail {
                    profileAction("Email", systemImage: "envelope") { viewModel.emailContact() }
                }
                copyAction
        }
        .accessibilityIdentifier("contactActions")
    }

    private func profileAction(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .medium))
                Text(title)
                    .font(.gfCaption.weight(.medium))
                    .lineLimit(1)
            }
                .foregroundStyle(GoldfishDS.ink(.primary))
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.vertical, 4)
                .background(GoldfishDS.surface, in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    @ViewBuilder private var copyAction: some View {
        if let phone = viewModel.person.phone,
           !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let email = viewModel.person.email,
           !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Menu {
                Button("Copy phone") { copyValue(phone, label: "phone") }
                Button("Copy email") { copyValue(email, label: "email") }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 15, weight: .medium))
                    Text("Copy")
                        .font(.gfCaption.weight(.medium))
                }
                    .foregroundStyle(GoldfishDS.ink(.primary))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.vertical, 4)
                    .background(GoldfishDS.surface, in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
            }
            .accessibilityLabel("Copy contact detail")
        } else if let phone = viewModel.person.phone, !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            profileAction("Copy", systemImage: "doc.on.doc") { copyValue(phone, label: "phone") }
        } else if let email = viewModel.person.email, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            profileAction("Copy", systemImage: "doc.on.doc") { copyValue(email, label: "email") }
        }
    }

    private func copyValue(_ value: String, label: String) {
        UIPasteboard.general.string = value
        ToastManager.shared.showToast(message: "Copied \(label)")
    }

    private var hasUsablePhone: Bool {
        viewModel.person.phone?.contains(where: { $0.isNumber }) == true
    }

    private var hasUsableEmail: Bool {
        guard let email = viewModel.person.email,
              !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return components.url != nil
    }

    // MARK: - Contact info row

    @ViewBuilder private func contactInfoRow(_ row: InfoItem) -> some View {
        if let url = row.actionURL {
            Link(destination: url) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.label.uppercased()).font(.gfCaption).foregroundStyle(GoldfishDS.ink(.secondary))
                        Text(row.value).font(.gfBody).foregroundStyle(GoldfishDS.terracotta)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } icon: { Image(systemName: row.icon).foregroundStyle(GoldfishDS.ink(.secondary)) }
            }
            .accessibilityLabel("\(row.label == "Mobile" ? "Call" : "Email") \(row.value)")
        } else if row.isProse {
            VStack(alignment: .leading, spacing: 4) {
                Label(row.label.uppercased(), systemImage: row.icon)
                    .font(.gfCaption)
                    .kerning(0.8)
                    .foregroundStyle(GoldfishDS.ink(.secondary))
                Text(row.value)
                    .textSelection(.enabled)
                    .font(.gfProse)
                    .foregroundStyle(GoldfishDS.ink(.primary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
        } else {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label.uppercased())
                        .font(.gfCaption)
                        .kerning(0.8)
                        .foregroundStyle(GoldfishDS.ink(.secondary))
                    Text(row.value)
                        .font(.gfBody)
                        .monospacedDigit()
                        .foregroundStyle(GoldfishDS.ink(.primary))
                }
            } icon: {
                Image(systemName: row.icon)
                    .foregroundStyle(GoldfishDS.ink(.secondary))
            }
        }
    }

    // MARK: - Relationship row

    @ViewBuilder private func relationshipRow(person: Person, type: String) -> some View {
        HStack(spacing: 12) {
            ContactPhotoView(person: person, size: .small)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.name)
                    .font(.gfName)
                    .foregroundStyle(GoldfishDS.ink(.primary))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(type.uppercased())
                    .font(.gfCaption)
                    .kerning(0.8)
                    .foregroundStyle(GoldfishDS.ink(.secondary))
            }
        }
    }

    // MARK: - Empty relationships

    @ViewBuilder private var nativeEmptyRelationships: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No connections yet")
                .font(.gfBody)
                .foregroundStyle(GoldfishDS.ink(.secondary))
            Text("Tap + above to add a connection, or drag two people together in the pond.")
                .font(.gfCaption)
                .foregroundStyle(GoldfishDS.ink(.tertiary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .listRowSeparator(.hidden)
    }

    // MARK: - Info rows model

    struct InfoItem {
        let icon: String; let label: String; let value: String; let isProse: Bool
        var actionURL: URL? {
            if label == "Mobile" {
                let clean = value.filter { $0.isNumber || $0 == "+" }
                return clean.isEmpty ? nil : URL(string: "tel:\(clean)")
            }
            if label == "Email" {
                var components = URLComponents()
                components.scheme = "mailto"
                components.path = value
                return components.url
            }
            return nil
        }
    }

    private var infoRows: [InfoItem] {
        var rows: [InfoItem] = []
        let p = viewModel.person
        if let phone = p.phone { rows.append(.init(icon: "phone", label: "Mobile", value: phone, isProse: false)) }
        if let email = p.email { rows.append(.init(icon: "envelope", label: "Email", value: email, isProse: false)) }
        if let birthday = p.birthday {
            rows.append(.init(icon: "gift", label: "Birthday",
                              value: birthday.formatted(date: .long, time: .omitted), isProse: false))
        }
        if !p.tags.isEmpty {
            rows.append(.init(icon: "tag", label: "Tags", value: p.tags.joined(separator: ", "), isProse: false))
        }
        return rows
    }
}

private struct AddMemorySheet: View {
    let personName: String
    let onSave: (String) -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var memory = ""
    @State private var saveError: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: GoldfishDS.Space.lg) {
                Text("Add something you want to remember about \(personName). It will be dated and added to the existing notes.")
                    .font(.gfBody)
                    .foregroundStyle(GoldfishDS.ink(.secondary))
                    .fixedSize(horizontal: false, vertical: true)

                ZStack(alignment: .topLeading) {
                    if memory.isEmpty {
                        Text("A conversation, preference, or moment…")
                            .font(.gfProse)
                            .foregroundStyle(GoldfishDS.ink(.quaternary))
                            .padding(.top, GoldfishDS.Space.md)
                            .padding(.leading, GoldfishDS.Space.sm)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $memory)
                        .focused($isFocused)
                        .font(.gfProse)
                        .foregroundStyle(GoldfishDS.ink(.primary))
                        .scrollContentBackground(.hidden)
                        .padding(GoldfishDS.Space.xs)
                        .frame(minHeight: 150)
                }
                .background(GoldfishDS.surface, in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
                .overlay(
                    RoundedRectangle(cornerRadius: GoldfishDS.Radius.control)
                        .strokeBorder(GoldfishDS.ink(.hairline), lineWidth: GoldfishDS.Rule.hairline)
                )

                if let saveError {
                    Label(saveError, systemImage: "exclamationmark.circle")
                        .font(.gfMeta)
                        .foregroundStyle(GoldfishDS.terracotta)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Save failed. \(saveError)")
                }

                Spacer(minLength: 0)
            }
            .padding(GoldfishDS.Space.pageMargin)
            .background(GoldfishDS.warmBlack)
            .navigationTitle("Add a Memory")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GoldfishDS.warmBlack, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        if let error = onSave(memory) {
                            saveError = error
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(memory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Zoom destination (name-flight target)
private extension View {
    @ViewBuilder
    func gfZoomDestination(id: UUID?, in ns: Namespace.ID?) -> some View {
        if #available(iOS 18.0, *), !UIAccessibility.isReduceMotionEnabled, let id, let ns {
            self.navigationTransition(.zoom(sourceID: id, in: ns))
        } else {
            self
        }
    }
}
