import SwiftUI
import SwiftData

// MARK: - AI Bulk Approval View
/// Presents the extracted draft contacts as an editable list before committing to the database.
struct AIBulkApprovalView: View {
    @ObservedObject var viewModel: AIVoiceAddViewModel
    let dataManager: GoldfishDataManager
    @Environment(\.dismiss) private var dismiss

    // Shown before "Discard All" wipes the dictation session
    @State private var showDiscardConfirmation = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0x1E/255, green: 0x18/255, blue: 0x15/255)
                    .ignoresSafeArea()

                if viewModel.draftContacts.isEmpty {
                    VStack {
                        Text("No contacts extracted.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    List {
                        ForEach($viewModel.draftContacts) { $draft in
                            Section {
                                DraftContactCard(draft: $draft)
                                    .listRowBackground(Color(red: 0x2A/255, green: 0x24/255, blue: 0x20/255))
                                    .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Review Contacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard All") {
                        if viewModel.draftContacts.isEmpty {
                            viewModel.discardAll()
                            dismiss()
                        } else {
                            showDiscardConfirmation = true
                        }
                    }
                    .foregroundColor(.red)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save All (\(viewModel.approvedCount))") {
                        saveAllToDatabase()
                    }
                    .bold()
                    .disabled(viewModel.approvedCount == 0)
                }
            }
            .confirmationDialog(
                "Discard \(viewModel.draftContacts.count) contact\(viewModel.draftContacts.count == 1 ? "" : "s")?",
                isPresented: $showDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard All", role: .destructive) {
                    viewModel.discardAll()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This can't be undone.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func saveAllToDatabase() {
        // Resolve relationship target models and save everyone globally.
        do {
            let allPersons = try dataManager.fetchAllPersons()

            for draft in viewModel.draftContacts where draft.isApproved {
                // 1. Create the new Person
                let nameParts = draft.name.split(separator: " ").map(String.init)
                let first = nameParts.first ?? "Unknown"
                let last = nameParts.dropFirst().joined(separator: " ")
                
                let newPerson = try dataManager.createPerson(
                    name: draft.name,
                    phone: draft.phone,
                    email: draft.email,
                    birthday: DateFormatter.yyyyMMdd.date(from: draft.birthday ?? ""),
                    notes: draft.notes,
                    tags: draft.tags,
                    color: Color.goldfishAccent.toHex() ?? "#FF6B6B"
                )

                // 2. Resolve relationships
                // EITHER LLM specified a target contact...
                var targetPerson: Person? = nil
                if let targetName = draft.linkedExistingContactName?.lowercased() {
                    targetPerson = allPersons.first(where: { $0.name.lowercased().contains(targetName) })
                }
                
                // OR fallback to the ME contact if none specified but relationship exists
                if targetPerson == nil && draft.relationshipToMe != nil {
                    targetPerson = try dataManager.fetchMePerson()
                }

                if let targetPerson, let relTypeRaw = draft.relationshipToMe {
                    if let relType = RelationshipType(rawValue: relTypeRaw) {
                        try dataManager.createRelationship(from: newPerson, to: targetPerson, type: relType)
                    }
                }
            }

            viewModel.saveApproved()
            dismiss()
        } catch {
            print("Failed to bulk save draft contacts: \(error)")
            ToastManager.shared.showToast(message: "Error saving contacts.")
        }
    }
}

// MARK: - Draft Contact Card
fileprivate struct DraftContactCard: View {
    @Binding var draft: AIDraftContact

    var body: some View {
        VStack(spacing: 12) {
            // Header: Name + Approve Toggle
            HStack {
                TextField("Name", text: $draft.name)
                    .font(.headline)
                    .foregroundColor(.white)
                    .textFieldStyle(.plain)

                Spacer()

                Toggle("", isOn: $draft.isApproved)
                    .labelsHidden()
                    .tint(Color.goldfishAccent)
            }

            Divider().background(Color.white.opacity(0.1))

            // Fields
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Image(systemName: "envelope.fill").foregroundStyle(.secondary).frame(width: 20)
                    TextField("Email", text: Binding(
                        get: { draft.email ?? "" },
                        set: { draft.email = $0.isEmpty ? nil : $0 }
                    ))
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                }
                
                if let rel = draft.relationshipToMe {
                    HStack(alignment: .top) {
                        Image(systemName: "person.2.fill").foregroundColor(Color.goldfishAccent).frame(width: 20)
                        Text("\(rel.capitalized) of \(draft.linkedExistingContactName ?? "Me")")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                    }
                }

                if let notes = draft.notes, !notes.isEmpty {
                    HStack(alignment: .top) {
                        Image(systemName: "note.text").foregroundStyle(.secondary).frame(width: 20)
                        TextField("Notes", text: Binding(
                            get: { draft.notes ?? "" },
                            set: { draft.notes = $0.isEmpty ? nil : $0 }
                        ))
                        .font(.subheadline)
                    }
                }
                
                if !draft.tags.isEmpty {
                    HStack(alignment: .top) {
                        Image(systemName: "tag.fill").foregroundStyle(.secondary).frame(width: 20)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(draft.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.white.opacity(0.1))
                                        .cornerRadius(6)
                                }
                            }
                        }
                    }
                }
            }
            .font(.subheadline)
            .foregroundColor(.white.opacity(0.9))
        }
        .opacity(draft.isApproved ? 1.0 : 0.5)
    }
}

// MARK: - DateFormatter Helper
extension DateFormatter {
    static let yyyyMMdd: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt
    }()
}
