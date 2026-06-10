import SwiftUI
import SwiftData
import PhotosUI
import os

struct ContactFormView: View {
    private let logger = Logger(subsystem: "com.goldfish.app", category: "ContactFormView")
    @Environment(\.dismiss) private var dismiss
    @StateObject var viewModel: ContactFormViewModel
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showDeleteConfirmation = false
    
    // Injected for circle picking
    @EnvironmentObject var dataManager: GoldfishDataManager

    
    var body: some View {
        Form {
                // MARK: - Basic Info
                Section("Basic Info") {
                    HStack {
                        Spacer()
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            ZStack {
                                Circle()
                                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                                    .foregroundColor(.secondary)
                                    .background(Circle().fill(Color.gray.opacity(0.1)))
                                    .frame(width: 80, height: 80)
                                
                                if !viewModel.emojiAvatar.isEmpty {
                                    Text(viewModel.emojiAvatar)
                                        .font(.system(size: 44))
                                } else if let data = viewModel.photoData, let image = UIImage(data: data) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipShape(Circle())
                                } else {
                                    VStack(spacing: 4) {
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 24))
                                            .foregroundColor(.secondary)
                                        Text("Add Photo")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .onChange(of: selectedPhotoItem) { _, newItem in
                            Task {
                                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                                    viewModel.photoData = data
                                    viewModel.emojiAvatar = ""  // Clear emoji when photo is set
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    
                    TextField("First Name", text: $viewModel.firstName)
                        .textContentType(.givenName)
                    
                    TextField("Last Name", text: $viewModel.lastName)
                        .textContentType(.familyName)
                }
                
                // MARK: - Connections
                if !viewModel.isMe, viewModel.existingPerson == nil {
                    Section("Connected To") {
                        Picker("Contact", selection: $viewModel.selectedConnectionID) {
                            Text("None").tag(UUID?(nil))
                            ForEach(viewModel.allPersons) { person in
                                Text(person.name).tag(UUID?(person.id))
                            }
                        }
                        
                        if viewModel.selectedConnectionID != nil {
                            Picker("Relationship", selection: $viewModel.selectedRelationshipType) {
                                ForEach(RelationshipType.allCases) { type in
                                    Text(type.displayName).tag(type)
                                }
                            }
                        }
                    }
                }
                
                if !viewModel.isMe {
                    // MARK: - Ponds
                    Section("Pond") {
                        if viewModel.allCircles.isEmpty {
                            Text("No ponds available")
                                .foregroundStyle(.secondary)
                        } else {
                            Picker("Select Pond", selection: Binding(
                                get: { viewModel.selectedCircleIDs.first },
                                set: { newID in
                                    viewModel.selectedCircleIDs.removeAll()
                                    if let id = newID { viewModel.selectedCircleIDs.insert(id) }
                                }
                            )) {
                                Text("None").tag(UUID?(nil))
                                ForEach(viewModel.allCircles) { circle in
                                    Text(circle.name).tag(UUID?(circle.id))
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    // MARK: - Additional Info
                    Section("Additional Info") {
                        Toggle("Favorite", isOn: $viewModel.isFavorite)
                    }
                    
                    Section("Notes") {
                        TextEditor(text: $viewModel.notes)
                            .frame(minHeight: 100)
                    }
                    
                    Section("Birthday") {
                        Toggle("Add Birthday", isOn: $viewModel.includeBirthday)
                        if viewModel.includeBirthday {
                            DatePicker("Birthday", selection: $viewModel.birthday, displayedComponents: .date)
                        }
                    }
                    
                    Section("Location") {
                        TextField("Street", text: $viewModel.street)
                        TextField("City", text: $viewModel.city)
                        TextField("State", text: $viewModel.state)
                        TextField("ZIP/Postal", text: $viewModel.postalCode)
                        TextField("Country", text: $viewModel.country)
                    }
                    
                    Section("Tags") {
                        TextField("Comma separated (e.g. gym, work)", text: $viewModel.tagsString)
                    }
                }
            
                Section("Appearance") {
                    ColorPicker("Node Color", selection: Binding(
                        get: { Color(hex: viewModel.colorHex) },
                        set: { viewModel.colorHex = $0.toHex() ?? "#808080" }
                    ))
                }
                
                // MARK: - Danger Zone
                if let existing = viewModel.existingPerson, !existing.isMe {
                    Section {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            HStack {
                                Spacer()
                                Text("Delete Contact")
                                Spacer()
                            }
                        }
                        .confirmationDialog(
                            "Delete Contact?",
                            isPresented: $showDeleteConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("Delete Contact", role: .destructive) {
                                if let person = viewModel.existingPerson {
                                    do {
                                        try dataManager.deletePerson(person)
                                        dismiss()
                                    } catch {
                                        logger.error("Failed to delete contact: \(error.localizedDescription)")
                                    }
                                }
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("This cannot be undone.")
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(viewModel.pageTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if viewModel.save() {
                            dismiss()
                        }
                    }
                    .disabled(!viewModel.isValid)
                }
                // Keyboard Done button
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
            }
        }
    }
}

