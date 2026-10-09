import SwiftUI
import SwiftData

/// Add several typed connections around one anchor contact in a single save.
/// The selected person is always the subject of the relationship: “Selma is
/// Adriana’s caregiver” is stored as Selma → Adriana, type caregiver.
struct BatchConnectionsView: View {
    let person: Person
    let dataManager: GoldfishDataManager
    var onSaved: ([UUID]) -> Void = { _ in }

    @State private var organizationService: ContactOrganizationService
    @ObservedObject private var session = ConnectionSession.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("isDemoModeActive") private var isDemoModeActive = false

    @State private var contacts: [Person] = []
    @State private var query = ""
    @State private var selectedIDs: Set<UUID> = []
    @State private var types: [UUID: RelationshipType] = [:]
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var showAllExistingPeople = false

    init(person: Person, dataManager: GoldfishDataManager, onSaved: @escaping ([UUID]) -> Void = { _ in }) {
        self.person = person
        self.dataManager = dataManager
        self.onSaved = onSaved
        _organizationService = State(initialValue: ContactOrganizationService(container: dataManager.context.container))
    }

    private var effectiveDemoScope: Bool { person.isMe ? isDemoModeActive : person.isDemo }
    private var sessionMatchesScope: Bool { session.isActive && session.isDemoMode == effectiveDemoScope }

    private var existingPeople: [Person] {
        var seen: Set<UUID> = []
        return person.allRelationships
            .map { $0.otherContact(from: person) }
            .filter { $0.isMe || $0.isDemo == effectiveDemoScope }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var availablePeople: [Person] {
        let connected = Set(person.allRelationships.flatMap { [$0.fromContact.id, $0.toContact.id] })
        return contacts.filter { candidate in
            candidate.id != person.id && !connected.contains(candidate.id) &&
            (query.isEmpty || candidate.name.localizedCaseInsensitiveContains(query))
        }.sorted {
            if $0.isMe != $1.isMe { return $0.isMe }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var visibleExistingPeople: [Person] {
        guard existingPeople.count > 8, !showAllExistingPeople else { return existingPeople }
        return Array(existingPeople.prefix(8))
    }

    private var canSave: Bool {
        !selectedIDs.isEmpty && selectedIDs.allSatisfy { types[$0] != nil } && !saving
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: GoldfishDS.Space.md) {
                    connectionSessionControl
                    anchorHeader
                    existingTray
                    searchSection
                    if dynamicTypeSize.isAccessibilitySize { saveBar }
                }
                .padding(.horizontal, GoldfishDS.Space.pageMargin)
                .padding(.top, GoldfishDS.Space.sm)
                .padding(.bottom, GoldfishDS.Space.lg)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(GoldfishDS.warmBlack.ignoresSafeArea())
            .foregroundStyle(GoldfishDS.ink(.primary))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GoldfishDS.warmBlack, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("ADD CONNECTIONS")
                        .font(.gfLabel).kerning(1.2)
                        .foregroundStyle(GoldfishDS.ink(.primary))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.gfBody).foregroundStyle(GoldfishDS.ink(.secondary))
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !dynamicTypeSize.isAccessibilitySize { saveBar }
            }
            .alert("Couldn’t save connections", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "Please try again.") }
            .task { loadContacts() }
        }
        .tint(GoldfishDS.terracotta)
    }

    @ViewBuilder private var connectionSessionControl: some View {
        if sessionMatchesScope {
            ConnectionSessionCard()
        } else if session.isActive {
            VStack(alignment: .leading, spacing: GoldfishDS.Space.sm) {
                Text("A connection session for \(session.isDemoMode ? "sample" : "personal") contacts is active.")
                    .font(.gfBody).foregroundStyle(GoldfishDS.ink(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
                Button("End that session to start one here") { session.finish() }
                    .font(.gfBody.weight(.medium)).frame(minHeight: 44)
                    .accessibilityHint("Ends the active session. You can then start a session for this contact scope.")
            }
            .padding(GoldfishDS.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GoldfishDS.surface, in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
        } else {
            Button {
                session.start(isDemoMode: effectiveDemoScope)
            } label: {
                HStack(spacing: GoldfishDS.Space.sm) {
                    Image(systemName: "person.2.badge.plus")
                        .foregroundStyle(GoldfishDS.terracotta)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Connect five people")
                            .font(.gfBody.weight(.medium)).foregroundStyle(GoldfishDS.ink(.primary))
                        Text("Start a quiet session for this contact group")
                            .font(.gfCaption).foregroundStyle(GoldfishDS.ink(.secondary))
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(GoldfishDS.ink(.tertiary))
                }
                .padding(GoldfishDS.Space.md)
                .frame(minHeight: 56)
                .background(GoldfishDS.surface, in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
                .overlay(RoundedRectangle(cornerRadius: GoldfishDS.Radius.control)
                    .strokeBorder(GoldfishDS.ink(.hairline), lineWidth: GoldfishDS.Rule.hairline))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Starts an optional session to connect five people")
        }
    }

    private var anchorHeader: some View {
        HStack(alignment: .center, spacing: GoldfishDS.Space.md) {
            ContactPhotoView(person: person, size: .medium)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: GoldfishDS.Space.xs) {
                Text("Build around")
                    .font(.gfCaption).foregroundStyle(GoldfishDS.ink(.secondary))
                Text(person.isMe ? "You" : person.name)
                    .font(.gfName).foregroundStyle(GoldfishDS.ink(.primary))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Choose people, then say how each one connects to this person.")
                    .font(.gfCaption).foregroundStyle(GoldfishDS.ink(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(GoldfishDS.Space.lg)
        .background(GoldfishDS.surface, in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: GoldfishDS.Radius.card)
            .strokeBorder(GoldfishDS.ink(.hairline), lineWidth: GoldfishDS.Rule.hairline))
    }

    private var existingTray: some View {
        VStack(alignment: .leading, spacing: GoldfishDS.Space.sm) {
            Text("Already connected · \(existingPeople.count)")
                .font(.gfCaption).foregroundStyle(GoldfishDS.ink(.secondary))
            if existingPeople.isEmpty {
                Text("No connections yet")
                    .font(.gfCaption).foregroundStyle(GoldfishDS.ink(.tertiary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, GoldfishDS.Space.sm)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: GoldfishDS.Space.md) {
                        ForEach(visibleExistingPeople) { contact in
                            VStack(spacing: GoldfishDS.Space.xs) {
                                ContactPhotoView(person: contact, size: .medium)
                                Text(contact.isMe ? "You" : contact.name)
                                    .font(.gfCaption).foregroundStyle(GoldfishDS.ink(.secondary))
                                    .lineLimit(2).multilineTextAlignment(.center)
                                    .frame(width: 76)
                            }
                            .accessibilityElement(children: .combine)
                        }
                        if existingPeople.count > 8 {
                            Button {
                                showAllExistingPeople.toggle()
                            } label: {
                                VStack(spacing: GoldfishDS.Space.xs) {
                                    Image(systemName: showAllExistingPeople ? "minus" : "ellipsis")
                                        .font(.system(size: 15, weight: .medium))
                                        .frame(width: 50, height: 50)
                                        .background(GoldfishDS.ink(.hairline), in: Circle())
                                    Text(showAllExistingPeople ? "Show less" : "+\(existingPeople.count - 8) more")
                                        .font(.gfCaption).foregroundStyle(GoldfishDS.ink(.secondary))
                                }
                                .frame(minWidth: 76, minHeight: 76)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(showAllExistingPeople ? "Show fewer existing connections" : "Show all \(existingPeople.count) existing connections")
                        }
                    }
                    .padding(.vertical, 3)
                }
                .accessibilityLabel("Existing connections")
            }
        }
    }

    @ViewBuilder private var selectedSection: some View {
        let visibleIDs = Set(availablePeople.map(\.id))
        let hiddenSelected = selectedContacts.filter { !visibleIDs.contains($0.id) }
        if !hiddenSelected.isEmpty {
            DisclosureGroup("\(hiddenSelected.count) selected outside this search") {
                ForEach(hiddenSelected) { contact in selectedRow(contact) }
            }
            .font(.gfBody)
        }
    }

    private var searchSection: some View {
        VStack(alignment: .leading, spacing: GoldfishDS.Space.md) {
            Text("Choose people and set their relationship below.")
                .font(.gfCaption).foregroundStyle(GoldfishDS.ink(.secondary))
            HStack(spacing: GoldfishDS.Space.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(GoldfishDS.ink(.tertiary))
                TextField("Search contacts", text: $query)
                    .font(.gfBody)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Search contacts")
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(GoldfishDS.ink(.tertiary))
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, GoldfishDS.Space.md)
            .frame(minHeight: 48)
            .background(GoldfishDS.surface, in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: GoldfishDS.Radius.control)
                .strokeBorder(GoldfishDS.ink(.hairline), lineWidth: GoldfishDS.Rule.hairline))

            selectedSection

            if availablePeople.isEmpty {
                Text(query.isEmpty ? "Everyone is already connected, or there are no other people yet." : "No contacts match your search.")
                    .font(.gfBody).foregroundStyle(GoldfishDS.ink(.tertiary))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, GoldfishDS.Space.md)
            } else {
                VStack(spacing: 0) {
                    ForEach(availablePeople) { contact in
                        if selectedIDs.contains(contact.id) {
                            selectedRow(contact).padding(.vertical, 8)
                        } else {
                            contactChoice(contact)
                        }
                        if contact.id != availablePeople.last?.id {
                            Rectangle().fill(GoldfishDS.ink(.hairline)).frame(height: GoldfishDS.Rule.hairline)
                                .padding(.leading, 56)
                        }
                    }
                }
                .padding(.horizontal, GoldfishDS.Space.md)
                .background(GoldfishDS.surface, in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.card))
                .overlay(RoundedRectangle(cornerRadius: GoldfishDS.Radius.card)
                    .strokeBorder(GoldfishDS.ink(.hairline), lineWidth: GoldfishDS.Rule.hairline))
            }
        }
    }

    private func contactChoice(_ contact: Person) -> some View {
        let isSelected = selectedIDs.contains(contact.id)
        return Button {
            let change = { toggle(contact) }
            if reduceMotion { change() } else { withAnimation(GoldfishDS.Motion.snappy, change) }
        } label: {
            HStack(spacing: GoldfishDS.Space.md) {
                ContactPhotoView(person: contact, size: .extraSmall)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.isMe ? "You" : contact.name)
                        .font(.gfBody.weight(.medium)).foregroundStyle(GoldfishDS.ink(.primary))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(contact.primaryCircle?.name ?? "Unassigned")
                        .font(.gfCaption).foregroundStyle(GoldfishDS.ink(.secondary))
                }
                Spacer(minLength: GoldfishDS.Space.sm)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(isSelected ? GoldfishDS.terracotta : GoldfishDS.ink(.quaternary))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(contact.isMe ? "You" : contact.name), \(contact.primaryCircle?.name ?? "Unassigned")")
        .accessibilityHint(isSelected ? "Remove from connections to add" : "Add to connections")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectedRow(_ contact: Person) -> some View {
        VStack(alignment: .leading, spacing: GoldfishDS.Space.md) {
            HStack(alignment: .center, spacing: GoldfishDS.Space.md) {
                ContactPhotoView(person: contact, size: .extraSmall).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.isMe ? "You" : contact.name)
                        .font(.gfBody.weight(.medium)).foregroundStyle(GoldfishDS.ink(.primary))
                    Text(direction(for: contact))
                        .font(.gfCaption).foregroundStyle(GoldfishDS.ink(types[contact.id] == nil ? .tertiary : .secondary))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Relationship direction: \(direction(for: contact))")
                }
                Spacer(minLength: 0)
                Button {
                    selectedIDs.remove(contact.id)
                    types.removeValue(forKey: contact.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(GoldfishDS.ink(.secondary))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Remove \(contact.name)")
            }

            Menu {
                ForEach(RelationshipType.allCases) { type in
                    Button {
                        types[contact.id] = type
                    } label: {
                        if types[contact.id] == type {
                            Label(type.displayName, systemImage: "checkmark")
                        } else { Text(type.displayName) }
                    }
                }
            } label: {
                HStack(spacing: GoldfishDS.Space.sm) {
                    Image(systemName: types[contact.id]?.symbolName ?? "person.crop.circle.badge.questionmark")
                        .foregroundStyle(types[contact.id] == nil ? GoldfishDS.ink(.tertiary) : GoldfishDS.terracotta)
                    Text(types[contact.id]?.displayName ?? "Choose relationship")
                        .font(.gfBody.weight(.medium))
                        .foregroundStyle(types[contact.id] == nil ? GoldfishDS.ink(.secondary) : GoldfishDS.ink(.primary))
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(GoldfishDS.ink(.tertiary))
                }
                .padding(.horizontal, GoldfishDS.Space.md)
                .frame(minHeight: 48)
                .background(GoldfishDS.warmBlack, in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
                .overlay(RoundedRectangle(cornerRadius: GoldfishDS.Radius.control)
                    .strokeBorder(GoldfishDS.ink(.hairline), lineWidth: GoldfishDS.Rule.hairline))
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Relationship for \(contact.name)")
            .accessibilityValue(types[contact.id]?.displayName ?? "Not chosen")
            .frame(minHeight: 44)
        }
        .padding(GoldfishDS.Space.md)
        .background(GoldfishDS.surface, in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: GoldfishDS.Radius.card)
            .strokeBorder(types[contact.id] == nil ? GoldfishDS.ink(.hairline) : GoldfishDS.terracotta.opacity(0.35), lineWidth: GoldfishDS.Rule.hairline))
    }

    private var saveBar: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: GoldfishDS.Space.md))
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedIDs.isEmpty ? "Select people to continue" : "\(selectedIDs.count) \(selectedIDs.count == 1 ? "connection" : "connections")")
                    .font(.gfBody.weight(.medium)).foregroundStyle(GoldfishDS.ink(.primary))
                Text(selectedIDs.isEmpty ? "Add multiple people at once" : "Each relationship is saved together")
                    .font(.gfCaption).foregroundStyle(GoldfishDS.ink(.secondary))
            }
            Spacer(minLength: 0)
            Button(action: save) {
                HStack(spacing: GoldfishDS.Space.xs) {
                    if saving { ProgressView().tint(GoldfishDS.paper) }
                    Text(saving ? "Saving" : "Save all")
                }
                .font(.gfBody.weight(.semibold))
                .foregroundStyle(GoldfishDS.paper)
                .padding(.horizontal, GoldfishDS.Space.lg)
                .frame(minHeight: 48)
                .background(canSave ? GoldfishDS.terracotta : GoldfishDS.ink(.quaternary),
                            in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
            }
            .disabled(!canSave)
            .accessibilityHint("Save all selected connections together")
        }
        .padding(.horizontal, GoldfishDS.Space.pageMargin)
        .padding(.vertical, GoldfishDS.Space.sm)
        .background(GoldfishDS.warmBlack)
        .overlay(alignment: .top) { GoldfishDS.ink(.hairline).frame(height: GoldfishDS.Rule.hairline) }
    }

    private func sectionHeading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.gfLabel).kerning(0.9).foregroundStyle(GoldfishDS.ink(.secondary))
            Text(detail).font(.gfCaption).foregroundStyle(GoldfishDS.ink(.tertiary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var selectedContacts: [Person] {
        contacts.filter { selectedIDs.contains($0.id) }.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func direction(for contact: Person) -> String {
        guard let type = types[contact.id] else { return "Choose a relationship to see its direction." }
        let subject = contact.isMe ? "You" : contact.name
        let isYou = contact.isMe
        let verb = isYou ? "are" : "is"
        let anchorPossessive = person.isMe ? "your" : "\(person.name)’s"
        let anchorPlain = person.isMe ? "you" : person.name
        switch type {
        case .other: return "Record a connection from \(subject.lowercased()) to \(anchorPlain)."
        case .caregiver: return "\(subject) \(verb) \(anchorPossessive) caregiver."
        case .caredFor: return "\(subject) \(verb) cared for by \(anchorPlain)."
        case .child: return "\(subject) \(verb) \(anchorPossessive) child."
        case .pet: return "\(subject) \(verb) \(anchorPossessive) pet."
        case .guardian: return "\(subject) \(verb) \(anchorPossessive) guardian."
        default: return "\(subject) \(verb) \(anchorPossessive) \(type.displayName.lowercased())."
        }
    }

    private func toggle(_ contact: Person) {
        if selectedIDs.contains(contact.id) {
            selectedIDs.remove(contact.id)
            types.removeValue(forKey: contact.id)
        } else {
            selectedIDs.insert(contact.id)
        }
    }

    private func loadContacts() {
        do {
            let scopeIsDemo = person.isMe ? isDemoModeActive : person.isDemo
            contacts = try dataManager.fetchAllPersons().filter { $0.isMe || $0.isDemo == scopeIsDemo }
        } catch {
            errorMessage = "Could not load contacts: \(error.localizedDescription)"
        }
    }

    private func save() {
        guard canSave else { return }
        saving = true
        let drafts = selectedContacts.compactMap { contact -> RelationshipDraft? in
            guard let type = types[contact.id] else { return nil }
            return RelationshipDraft(sourceID: contact.id, targetID: person.id, type: type)
        }
        do {
            let ids = try organizationService.createRelationships(drafts)
            session.record(relationshipIDs: ids, anchorID: person.id, container: dataManager.context.container)
            ToastManager.shared.showToast(
                message: ids.isEmpty ? "These connections already exist" : "Added \(ids.count) \(ids.count == 1 ? "connection" : "connections")",
                actionTitle: ids.isEmpty ? nil : "Undo"
            ) { [organizationService, session] in
                do {
                    try organizationService.undoRelationships(ids: ids)
                    session.undo(relationshipIDs: ids)
                    ToastManager.shared.showToast(message: "Connections undone")
                } catch {
                    ToastManager.shared.showToast(message: "Could not undo connections")
                }
            }
            onSaved(ids)
            dismiss()
        } catch {
            saving = false
            errorMessage = error.localizedDescription
        }
    }
}
