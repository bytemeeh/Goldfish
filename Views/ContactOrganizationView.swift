import SwiftData
import SwiftUI

/// A calm, explicit batch flow for placing contacts into one pond.
/// This screen deliberately creates no relationships between the selected people.
struct ContactOrganizationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let dataManager: GoldfishDataManager
    @State private var organizationService: ContactOrganizationService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Person.name) private var people: [Person]
    @Query(sort: \GoldfishCircle.sortOrder) private var ponds: [GoldfishCircle]

    let isDemoMode: Bool
    let initialContactIDs: Set<UUID>
    var onLater: (() -> Void)? = nil
    var onComplete: (() -> Void)? = nil

    @State private var selectedContactIDs: Set<UUID>
    @State private var selectedPondID: UUID?
    @State private var searchText = ""
    @State private var showUnassignedOnly = true
    @State private var undoReceipt: PondAssignmentUndoReceipt?
    @State private var savedSummary: String?
    @State private var rewardID = UUID()
    @State private var errorMessage: String?
    @State private var isUndoing = false

    init(
        dataManager: GoldfishDataManager,
        isDemoMode: Bool,
        initialContactIDs: Set<UUID> = [],
        onLater: (() -> Void)? = nil,
        onComplete: (() -> Void)? = nil
    ) {
        self.dataManager = dataManager
        _organizationService = State(initialValue: ContactOrganizationService(container: dataManager.context.container))
        self.isDemoMode = isDemoMode
        self.initialContactIDs = initialContactIDs
        self.onLater = onLater
        self.onComplete = onComplete
        _selectedContactIDs = State(initialValue: initialContactIDs)
    }

    private var scopedPeople: [Person] {
        people.filter { !$0.isMe && $0.isDemo == isDemoMode }
    }

    private var visiblePeople: [Person] {
        scopedPeople.filter { person in
            let matchesAssignment = !showUnassignedOnly || person.primaryCircle == nil
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty
                || person.name.localizedCaseInsensitiveContains(query)
                || (person.email?.localizedCaseInsensitiveContains(query) ?? false)
                || (person.phone?.localizedCaseInsensitiveContains(query) ?? false)
            return matchesAssignment && matchesSearch
        }
    }

    /// Empty custom ponds are neutral and remain available. A custom pond with
    /// active contacts from the other view scope is excluded to prevent mixing.
    /// System ponds are shared by design.
    private var availablePonds: [GoldfishCircle] {
        ponds.filter { pond in
            guard !pond.isSystem else { return true }
            let activePeople = pond.circleContacts.filter { !$0.manuallyExcluded && !$0.contact.isMe }.map(\.contact)
            let hasOtherScope = activePeople.contains { $0.isDemo != isDemoMode }
            return !hasOtherScope
        }.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            let order = $0.name.localizedCaseInsensitiveCompare($1.name)
            if order != .orderedSame { return order == .orderedAscending }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private var selectedPond: GoldfishCircle? {
        availablePonds.first { $0.id == selectedPondID }
    }

    private var selectedPeople: [Person] {
        scopedPeople.filter { selectedContactIDs.contains($0.id) }
    }

    private var unassignedCount: Int {
        scopedPeople.filter { $0.primaryCircle == nil }.count
    }

    private var allVisibleSelected: Bool {
        !visiblePeople.isEmpty && visiblePeople.allSatisfy { selectedContactIDs.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GoldfishDS.Space.md) {
                introduction
                organizationProgress
                if !selectedPeople.isEmpty {
                    selectedTray
                }
                if let savedSummary {
                    savedState(summary: savedSummary)
                }
                contactPicker
                if dynamicTypeSize.isAccessibilitySize { bottomActions }
                if let errorMessage {
                    errorBanner(errorMessage)
                }
            }
            .padding(.horizontal, GoldfishDS.Space.pageMargin)
            .padding(.top, GoldfishDS.Space.sm)
            .padding(.bottom, GoldfishDS.Space.xxl)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(GoldfishDS.warmBlack.ignoresSafeArea())
        .foregroundStyle(GoldfishDS.ink(.primary))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !dynamicTypeSize.isAccessibilitySize { bottomActions }
        }
        .navigationTitle("Organize people")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        .alert("Could not save this batch", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
    }

    private var introduction: some View {
        Text("Place people together without changing their relationships.")
            .font(.gfBody)
            .foregroundStyle(GoldfishDS.ink(.secondary))
            .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }

    private var organizationProgress: some View {
        HStack(spacing: GoldfishDS.Space.sm) {
            Image(systemName: scopedPeople.isEmpty ? "person.crop.circle" : unassignedCount == 0 ? "checkmark.circle" : "circle.dotted")
                .foregroundStyle(unassignedCount == 0 ? GoldfishDS.ink(.tertiary) : GoldfishDS.terracotta)
                .accessibilityHidden(true)
            Text(scopedPeople.isEmpty
                 ? "No contacts in this view yet."
                 : unassignedCount == 0
                    ? "Everyone in this view has a pond."
                    : "\(unassignedCount) \(unassignedCount == 1 ? "contact" : "contacts") still to organize")
                .font(.gfMeta)
                .foregroundStyle(GoldfishDS.ink(.secondary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var selectedTray: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: GoldfishDS.Space.sm) {
                ForEach(selectedPeople) { person in
                    Button {
                        toggle(person)
                    } label: {
                        ContactPhotoView(person: person, size: .small)
                            .frame(width: 48, height: 48)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(person.name) from selection")
                    .accessibilityHint("Removes this contact from the batch.")
                }
            }
        }
        .accessibilityLabel("Selected contacts")
        .frame(height: 52)
    }

    @ViewBuilder
    private var pondMenu: some View {
        if availablePonds.isEmpty {
            Text("No ponds are available in this contact view yet.")
                .font(.gfMeta)
                .foregroundStyle(GoldfishDS.ink(.secondary))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        } else {
            Menu {
                ForEach(availablePonds) { pond in
                    Button {
                        animateSelection { selectedPondID = pond.id }
                    } label: {
                        if selectedPondID == pond.id {
                            Label(pondMenuTitle(pond), systemImage: "checkmark")
                        } else {
                            Text(pondMenuTitle(pond))
                        }
                    }
                }
            } label: {
                HStack(spacing: GoldfishDS.Space.md) {
                    Circle()
                        .fill(GoldfishDS.pondTone(selectedPond?.name))
                        .frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                    Text(selectedPond.map { pondMenuTitle($0) } ?? "Choose destination pond")
                        .font(.gfBody.weight(.medium))
                        .foregroundStyle(GoldfishDS.ink(.primary))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: GoldfishDS.Space.sm)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.gfMeta.weight(.medium))
                        .foregroundStyle(GoldfishDS.ink(.tertiary))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, GoldfishDS.Space.md)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(GoldfishDS.surface, in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
                .overlay(RoundedRectangle(cornerRadius: GoldfishDS.Radius.control).strokeBorder(GoldfishDS.ink(.hairline), lineWidth: 0.5))
            }
            .accessibilityLabel("Destination pond")
            .accessibilityHint("Choose one pond for the selected contacts.")
        }
    }

    private func pondMenuTitle(_ pond: GoldfishCircle) -> String {
        let duplicateCount = availablePonds.filter {
            $0.name.localizedCaseInsensitiveCompare(pond.name) == .orderedSame
        }.count
        return duplicateCount > 1 ? "\(pond.name) · \(pondDescriptor(pond))" : pond.name
    }

    private var contactPicker: some View {
        VStack(alignment: .leading, spacing: GoldfishDS.Space.md) {
            HStack(spacing: GoldfishDS.Space.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(GoldfishDS.ink(.tertiary))
                    .accessibilityHidden(true)
                TextField("Search name, email or phone", text: $searchText)
                    .font(.gfBody)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .accessibilityLabel("Search contacts")
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(GoldfishDS.ink(.tertiary))
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.leading, GoldfishDS.Space.md)
            .padding(.trailing, GoldfishDS.Space.xs)
            .frame(minHeight: 52)
            .background(GoldfishDS.surface, in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
            .overlay(RoundedRectangle(cornerRadius: GoldfishDS.Radius.control).strokeBorder(GoldfishDS.ink(.hairline), lineWidth: 0.5))

            contactControls

            if visiblePeople.isEmpty {
                emptyContactState
            } else {
                LazyVStack(spacing: 1) {
                    ForEach(visiblePeople) { person in
                        contactRow(person)
                    }
                }
                .background(GoldfishDS.surface, in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.card))
                .clipShape(RoundedRectangle(cornerRadius: GoldfishDS.Radius.card))
                .overlay(RoundedRectangle(cornerRadius: GoldfishDS.Radius.card).strokeBorder(GoldfishDS.ink(.hairline), lineWidth: 0.5))
            }
        }
    }

    private var emptyContactState: some View {
        VStack(alignment: .leading, spacing: GoldfishDS.Space.xs) {
            Text(scopedPeople.isEmpty ? "No contacts here yet" : "No people match this view")
                .font(.gfBody.weight(.medium))
                .foregroundStyle(GoldfishDS.ink(.primary))
            Text(scopedPeople.isEmpty ? "Add contacts first, then you can place them together." : "Try another search or show all contacts.")
                .font(.gfMeta)
                .foregroundStyle(GoldfishDS.ink(.secondary))
        }
        .padding(GoldfishDS.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GoldfishDS.surface, in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.card))
    }

    private func contactRow(_ person: Person) -> some View {
        let isSelected = selectedContactIDs.contains(person.id)
        return Button {
            toggle(person)
        } label: {
            HStack(spacing: GoldfishDS.Space.md) {
                ContactPhotoView(person: person, size: .small)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(person.name)
                        .font(.gfBody.weight(.medium))
                        .foregroundStyle(GoldfishDS.ink(.primary))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(person.primaryCircle?.name ?? "Unassigned")
                        .font(.gfMeta)
                        .foregroundStyle(GoldfishDS.ink(.tertiary))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: GoldfishDS.Space.sm)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(isSelected ? GoldfishDS.terracotta : GoldfishDS.ink(.quaternary))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, GoldfishDS.Space.md)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
            .background(isSelected ? GoldfishDS.terracotta.opacity(0.08) : Color.clear)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(person.name), \(person.primaryCircle?.name ?? "unassigned")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isSelected ? "Removes this contact from the batch." : "Adds this contact to the batch.")
    }

    private func pondDescriptor(_ pond: GoldfishCircle) -> String {
        let memberCount = pond.circleContacts.filter {
            !$0.manuallyExcluded && !$0.contact.isMe && $0.contact.isDemo == isDemoMode
        }.count
        if let description = pond.desc?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
            return description
        }
        let sameNamePonds = availablePonds.filter {
            $0.name.localizedCaseInsensitiveCompare(pond.name) == .orderedSame
        }
        if sameNamePonds.count > 1, let index = sameNamePonds.firstIndex(where: { $0.id == pond.id }) {
            let kind = pond.isSystem ? "Built-in" : "Custom"
            return "\(kind) pond \(index + 1) · \(memberCount) here"
        }
        return pond.isSystem ? "Built-in pond" : "Custom pond · \(memberCount) here"
    }

    private var bottomActions: some View {
        VStack(spacing: GoldfishDS.Space.xs) {
            pondMenu
            if !selectedContactIDs.isEmpty {
                Button {
                    saveBatch()
                } label: {
                    Text("\(placeButtonTitle) · \(selectedContactIDs.count)")
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(PrimaryOrganizationButtonStyle())
                .disabled(selectedPond == nil || selectedContactIDs.isEmpty || availablePonds.isEmpty)
                .accessibilityHint(selectedPond == nil ? "Choose a pond first." : "Places the selected contacts in the selected pond.")
            }

            Button(savedSummary == nil ? "Do this later" : "Done") {
                if savedSummary != nil {
                    if let onComplete { onComplete() } else { dismiss() }
                } else {
                    if let onLater { onLater() } else { dismiss() }
                }
            }
            .font(.gfBody)
            .foregroundStyle(GoldfishDS.ink(.secondary))
            .frame(minHeight: 44)
        }
        .padding(.horizontal, GoldfishDS.Space.pageMargin)
        .padding(.top, GoldfishDS.Space.sm)
        .padding(.bottom, GoldfishDS.Space.xs)
        .frame(maxWidth: .infinity)
        .background {
            GoldfishDS.warmBlack
                .overlay(alignment: .top) { Rectangle().fill(GoldfishDS.ink(.hairline)).frame(height: 0.5) }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var placeButtonTitle: String {
        guard let selectedPond else { return "Choose a pond" }
        return "Place in \(selectedPond.name)"
    }

    private func savedState(summary: String) -> some View {
        HStack(alignment: .top, spacing: GoldfishDS.Space.md) {
            QuietPondReward(completed: false)
                .id(rewardID)
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: GoldfishDS.Space.xs) {
                Text(summary)
                    .font(.gfBody.weight(.medium))
                    .foregroundStyle(GoldfishDS.ink(.primary))
                Button {
                    undoBatch()
                } label: {
                    HStack(spacing: GoldfishDS.Space.xs) {
                        if isUndoing { ProgressView().tint(GoldfishDS.terracotta) }
                        Text("Undo")
                    }
                    .font(.gfBody.weight(.medium))
                    .foregroundStyle(GoldfishDS.terracotta)
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                }
                .disabled(isUndoing || undoReceipt == nil)
                .accessibilityHint("Restores how every selected contact was assigned before this batch.")
            }
            Spacer()
        }
        .padding(GoldfishDS.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GoldfishDS.surface, in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.card))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(GoldfishDS.terracotta.opacity(0.78))
                .frame(width: 3)
                .padding(.vertical, GoldfishDS.Space.sm)
        }
        .accessibilityElement(children: .contain)
    }

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle")
            .font(.gfMeta)
            .foregroundStyle(GoldfishDS.ink(.secondary))
            .padding(GoldfishDS.Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(GoldfishDS.surface, in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
    }

    private func filterButton(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.gfMeta.weight(isSelected ? .medium : .regular))
            .foregroundStyle(isSelected ? GoldfishDS.ink(.primary) : GoldfishDS.ink(.secondary))
            .padding(.horizontal, GoldfishDS.Space.md)
            .frame(minHeight: 44)
            .background(isSelected ? GoldfishDS.surfaceHi : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(isSelected ? GoldfishDS.ink(.hairline) : .clear, lineWidth: 0.5))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var contactControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: GoldfishDS.Space.sm) {
                filterButtons
                Spacer(minLength: 0)
                selectVisibleButton
            }
            VStack(alignment: .leading, spacing: GoldfishDS.Space.xs) {
                filterButtons
                selectVisibleButton
            }
        }
    }

    private var filterButtons: some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: GoldfishDS.Space.sm))
        return layout {
            filterButton("Unassigned", isSelected: showUnassignedOnly) {
                animateSelection { showUnassignedOnly = true }
            }
            filterButton("All contacts", isSelected: !showUnassignedOnly) {
                animateSelection { showUnassignedOnly = false }
            }
        }
    }

    private var selectVisibleButton: some View {
        Button(allVisibleSelected ? "Clear visible" : "Select visible") {
            animateSelection {
                if allVisibleSelected {
                    selectedContactIDs.subtract(visiblePeople.map(\.id))
                } else {
                    selectedContactIDs.formUnion(visiblePeople.map(\.id))
                }
            }
        }
        .font(.gfMeta.weight(.medium))
        .foregroundStyle(GoldfishDS.terracotta)
        .frame(minHeight: 44)
        .accessibilityHint(allVisibleSelected ? "Clears visible contact selections." : "Selects all visible contacts.")
    }

    private func toggle(_ person: Person) {
        animateSelection {
            if selectedContactIDs.contains(person.id) {
                selectedContactIDs.remove(person.id)
            } else {
                selectedContactIDs.insert(person.id)
            }
        }
    }

    private func animateSelection(_ update: () -> Void) {
        if reduceMotion {
            update()
        } else {
            withAnimation(GoldfishDS.Motion.snappy, update)
        }
    }

    private func saveBatch() {
        guard let pond = selectedPond else { return }
        let validIDs = Set(selectedPeople.map(\.id))
        guard !validIDs.isEmpty else { return }
        errorMessage = nil
        do {
            let receipt = try organizationService.assignPeople(ids: validIDs, to: pond.id)
            undoReceipt = receipt
            rewardID = UUID()
            selectedContactIDs.removeAll()
            let count = receipt.entries.count
            let noun = count == 1 ? "contact" : "contacts"
            let destination = pond.name
            if reduceMotion {
                savedSummary = "\(count) \(noun) placed in \(destination)."
            } else {
                withAnimation(GoldfishDS.Motion.settle) {
                    savedSummary = "\(count) \(noun) placed in \(destination)."
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func undoBatch() {
        guard let undoReceipt else { return }
        isUndoing = true
        defer { isUndoing = false }
        do {
            try organizationService.undoAssignment(undoReceipt)
            self.undoReceipt = nil
            savedSummary = nil
            selectedContactIDs.formUnion(undoReceipt.entries.map(\.personID))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct PrimaryOrganizationButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.gfBody.weight(.semibold))
            .foregroundStyle(GoldfishDS.paper)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(isEnabled ? GoldfishDS.terracotta : GoldfishDS.terracotta.opacity(0.38),
                        in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
            .opacity(configuration.isPressed ? 0.88 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.99 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
