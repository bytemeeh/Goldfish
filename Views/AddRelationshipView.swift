import SwiftUI
import SwiftData
import os

// MARK: - Add Relationship View
/// Sheet for creating a relationship between a source contact and a target contact.
/// Presented from ContactDetailView.
struct AddRelationshipView: View {
    let person: Person
    let dataManager: GoldfishDataManager
    @EnvironmentObject private var walkthroughManager: FeatureWalkthroughManager
    @AppStorage("isDemoModeActive") private var isDemoModeActive = false

    private let logger = Logger(subsystem: "com.goldfish.app", category: "AddRelationshipView")
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: RelationshipType = .friend
    @State private var selectedTarget: Person?
    @State private var searchText = ""
    @State private var isTargetSearchPresented = false
    @State private var allContacts: [Person] = []
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Connection Source
                Section {
                    HStack(alignment: .center, spacing: GoldfishDS.Space.md) {
                        ContactPhotoView(person: person, size: .extraSmall)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("From")
                                .font(.gfCaption)
                                .foregroundStyle(GoldfishDS.ink(.secondary))
                            Text(person.isMe ? "You" : person.name)
                                .font(.gfBody.weight(.medium))
                                .foregroundStyle(GoldfishDS.ink(.primary))
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 44)

                    Text("Choose a person below, then set the relationship.")
                        .font(.gfCaption)
                        .foregroundStyle(GoldfishDS.ink(.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("Connect From")
                        .gfSectionLabel()
                }
                .listRowBackground(GoldfishDS.surface)

                // MARK: - Contact Picker
                Section {
                    if filteredContacts.isEmpty {
                        Text(searchText.isEmpty ? "Everyone is already connected, or there are no other people yet." : "No contacts match your search.")
                            .font(.gfBody)
                            .foregroundStyle(GoldfishDS.ink(.tertiary))
                    } else {
                        ForEach(filteredContacts) { contact in
                            Button(action: {
                                selectedTarget = contact
                                isTargetSearchPresented = false
                            }) {
                                HStack {
                                    ContactPhotoView(person: contact, size: .extraSmall)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(contact.name)
                                            .font(.gfBody)
                                            .foregroundStyle(GoldfishDS.ink(.primary))
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text(contact.isMe ? "You" : contact.primaryCircle?.name ?? "Unassigned")
                                            .font(.gfCaption)
                                            .foregroundStyle(GoldfishDS.ink(.secondary))
                                    }
                                    if contact.isMe {
                                        Text("ME")
                                            .font(.gfCaption)
                                            .kerning(0.8)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(GoldfishDS.ink(.primary))
                                            .foregroundStyle(GoldfishDS.paper)
                                            .clipShape(RoundedRectangle(cornerRadius: GoldfishDS.Radius.chip))
                                    }
                                    Spacer()
                                    if selectedTarget?.id == contact.id {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(GoldfishDS.ink(.primary))
                                    }
                                }
                            }
                            .accessibilityAddTraits(selectedTarget?.id == contact.id ? .isSelected : [])
                            .walkthroughAnchor(step: .link, enabled: contact.id == suggestedRelationshipTarget?.id)
                        }
                    }
                } header: {
                    Text("Connect To")
                        .gfSectionLabel()
                }
                .listRowBackground(GoldfishDS.surface)
            }
            .scrollContentBackground(.hidden)
            .background(GoldfishDS.warmBlack)
            .searchable(text: $searchText, isPresented: $isTargetSearchPresented, prompt: "Search contacts")
            .navigationTitle("Add Relationship")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GoldfishDS.warmBlack, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("ADD RELATIONSHIP")
                        .font(.gfLabel)
                        .kerning(1.2)
                        .foregroundStyle(GoldfishDS.ink(.primary))
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.gfBody)
                        .foregroundStyle(GoldfishDS.ink(.secondary))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveRelationship() }
                        .font(.gfBody.weight(.medium))
                        .foregroundStyle(
                            (selectedTarget == nil || isSaving)
                                ? GoldfishDS.ink(.quaternary)
                                : GoldfishDS.terracotta
                        )
                        .disabled(selectedTarget == nil || isSaving)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .onAppear { loadContacts() }
            .onChange(of: walkthroughManager.currentStep) { _, step in
                if step != .link { dismiss() }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    selectedTargetSummary

                    // Once a target is chosen, the live direction/relationship
                    // summary becomes the guide. Stacking both panels can hide
                    // the form at larger text sizes.
                    if selectedTarget == nil && walkthroughManager.isActive && walkthroughManager.currentStep == .link {
                        WalkthroughInlineGuide(
                            maximumHeight: 260,
                            actionPromptOverride: relationshipTourPrompt
                        )
                            .padding(.horizontal, GoldfishDS.Space.pageMargin)
                            .safeAreaPadding(.bottom, 8)
                    }
                }
                .background(GoldfishDS.warmBlack)
            }
        }
    }

    // MARK: - Computed

    @ViewBuilder
    private var selectedTargetSummary: some View {
        if let target = selectedTarget {
            VStack(alignment: .leading, spacing: GoldfishDS.Space.sm) {
                HStack(alignment: .top, spacing: GoldfishDS.Space.md) {
                    ContactPhotoView(person: target, size: .extraSmall)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("To")
                            .font(.gfCaption)
                            .foregroundStyle(GoldfishDS.ink(.secondary))
                        Text(target.isMe ? "You" : target.name)
                            .font(.gfBody.weight(.medium))
                            .foregroundStyle(GoldfishDS.ink(.primary))
                        Text(directionLabel(target: target))
                            .font(.gfCaption)
                            .foregroundStyle(GoldfishDS.ink(.secondary))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                relationshipPicker
            }
            .padding(.horizontal, GoldfishDS.Space.lg)
            .padding(.vertical, GoldfishDS.Space.sm)
            .background(GoldfishDS.surface, in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
            .overlay(
                RoundedRectangle(cornerRadius: GoldfishDS.Radius.control)
                    .strokeBorder(GoldfishDS.ink(.hairline), lineWidth: GoldfishDS.Rule.hairline)
            )
            .padding(.horizontal, GoldfishDS.Space.pageMargin)
            .padding(.vertical, GoldfishDS.Space.sm)
            .accessibilityElement(children: .contain)
        }
    }

    private var relationshipPicker: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: GoldfishDS.Space.sm) {
                Text("Relationship")
                    .font(.gfBody)
                    .foregroundStyle(GoldfishDS.ink(.secondary))
                Spacer(minLength: GoldfishDS.Space.sm)
                relationshipMenu
            }

            VStack(alignment: .leading, spacing: GoldfishDS.Space.xs) {
                Text("Relationship")
                    .font(.gfCaption)
                    .foregroundStyle(GoldfishDS.ink(.secondary))
                relationshipMenu
            }
        }
    }

    private var relationshipMenu: some View {
        Picker("Relationship type", selection: $selectedType) {
            ForEach(RelationshipType.allCases) { type in
                Text(type.displayName).tag(type)
            }
        }
        .pickerStyle(.menu)
        .font(.gfBody)
        .foregroundStyle(GoldfishDS.ink(.primary))
        .tint(GoldfishDS.ink(.secondary))
    }

    private var suggestedRelationshipTarget: Person? {
        filteredContacts.first { $0.name == walkthroughManager.suggestedConnectionName }
            ?? filteredContacts.first
    }

    private var relationshipTourPrompt: String {
        guard let target = suggestedRelationshipTarget else { return "Everyone here is connected already. Tap Cancel to review the profile, or Skip to explore ponds." }
        return "Try choosing \(target.name), select Friend, then tap Save."
    }

    private var filteredContacts: [Person] {
        let existingRelatedIDs = Set(person.allRelationships.flatMap { [$0.fromContact.id, $0.toContact.id] })
        
        return allContacts.filter { contact in
            guard contact.id != person.id && !existingRelatedIDs.contains(contact.id) else {
                return false
            }
            if searchText.isEmpty { return true }
            return contact.name.localizedCaseInsensitiveContains(searchText)
        }.sorted { a, b in
            if a.isMe { return true }
            if b.isMe { return false }
            return a.name < b.name
        }
    }

    private func directionLabel(target: Person) -> String {
        if selectedType == .other { return "Record a connection from \(person.name) to \(target.name)." }
        return "\(person.name) is a \(selectedType.displayName.lowercased()) of \(target.name)."
    }

    // MARK: - Actions

    private func loadContacts() {
        do {
            let sourceMode = person.isMe ? (isDemoModeActive || walkthroughManager.isActive) : person.isDemo
            allContacts = try dataManager.fetchAllPersons().filter { $0.isMe || $0.isDemo == sourceMode }
        } catch {
            errorMessage = "Could not load contacts: \(error.localizedDescription)"
            showError = true
        }
    }

    private func saveRelationship() {
        guard let target = selectedTarget else { return }
        isSaving = true
        let relationshipIDsBeforeSave = Set(person.allRelationships.map(\.id))
        do {
            let relationship = try dataManager.createRelationship(from: person, to: target, type: selectedType)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if !relationshipIDsBeforeSave.contains(relationship.id) {
                let relationshipID = relationship.id
                ToastManager.shared.showToast(message: "Connected \(person.name) to \(target.name)", actionTitle: "Undo") { [dataManager] in
                    do {
                        if try dataManager.undoCreatedRelationship(id: relationshipID) {
                            ToastManager.shared.showToast(message: "Connection undone")
                        }
                    } catch {
                        ToastManager.shared.showToast(message: "Could not undo connection")
                    }
                }
            } else {
                ToastManager.shared.showToast(message: "Updated connection for \(person.name) and \(target.name)")
            }
            walkthroughManager.report(.createdLink)
            dismiss()
        } catch let error as GoldfishError {
            errorMessage = error.errorDescription ?? "An error occurred"
            showError = true
            isSaving = false
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            isSaving = false
        }
    }
}
