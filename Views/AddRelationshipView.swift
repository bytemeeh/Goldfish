import SwiftUI
import SwiftData
import os

// MARK: - Add Relationship View
/// Sheet for creating a relationship between a source contact and a target contact.
/// Presented from ContactDetailView.
struct AddRelationshipView: View {
    let person: Person
    let dataManager: GoldfishDataManager

    private let logger = Logger(subsystem: "com.goldfish.app", category: "AddRelationshipView")
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: RelationshipType = .friend
    @State private var selectedTarget: Person?
    @State private var searchText = ""
    @State private var allContacts: [Person] = []
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Relationship Type
                Section("Relationship Type") {
                    Picker("Type", selection: $selectedType) {
                        ForEach(RelationshipType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.menu)

                    if let target = selectedTarget {
                        Text(directionLabel(target: target))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // MARK: - Contact Picker
                Section("Connect To") {
                    if filteredContacts.isEmpty {
                        Text("No contacts available")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredContacts) { contact in
                            Button(action: { selectedTarget = contact }) {
                                HStack {
                                    ContactPhotoView(
                                        photoData: contact.photoData,
                                        name: contact.name,
                                        colorHex: contact.color,
                                        size: .extraSmall
                                    )
                                    Text(contact.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    if selectedTarget?.id == contact.id {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search contacts")
            .navigationTitle("Add Relationship")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveRelationship() }
                        .disabled(selectedTarget == nil || isSaving)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .onAppear { loadContacts() }
        }
    }

    // MARK: - Computed

    private var filteredContacts: [Person] {
        let existingRelatedIDs = Set(person.allRelationships.flatMap { [$0.fromContact.id, $0.toContact.id] })
        
        return allContacts.filter { contact in
            guard contact.id != person.id && !existingRelatedIDs.contains(contact.id) else {
                return false
            }
            if searchText.isEmpty { return true }
            return contact.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func directionLabel(target: Person) -> String {
        "\(person.name) is \(selectedType.displayName) of \(target.name)"
    }

    // MARK: - Actions

    private func loadContacts() {
        do {
            allContacts = try dataManager.fetchAllPersons()
        } catch {
            logger.error("Failed to load contacts: \(error.localizedDescription)")
        }
    }

    private func saveRelationship() {
        guard let target = selectedTarget else { return }
        isSaving = true
        do {
            try dataManager.createRelationship(from: person, to: target, type: selectedType)
            ToastManager.shared.showToast(message: "Connected \(person.name) to \(target.name) 🤝")
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
