import SwiftUI
import SwiftData
import os

struct ContactFormView: View {
    private let logger = Logger(subsystem: "com.goldfish.app", category: "ContactFormView")
    @Environment(\.dismiss) private var dismiss
    @StateObject var viewModel: ContactFormViewModel
    @State private var showMoreDetails = false
    
    // Injected for circle picking
    @EnvironmentObject var dataManager: GoldfishDataManager

    
    var body: some View {
        Form {
                // MARK: - Basic Info
                Section("Basic Info") {
                    HStack {
                        Spacer()
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
                                Image(systemName: "face.smiling")
                                    .font(.system(size: 30))
                                    .foregroundColor(.secondary)
                                    .opacity(0.5)
                            }
                            
                            // Invisible TextField over it to pop keyboard
                            TextField("", text: $viewModel.emojiAvatar)
                                .font(.system(size: 80))
                                .opacity(0.01)
                                .frame(width: 80, height: 80)
                                .onChange(of: viewModel.emojiAvatar) { _, newValue in
                                    if newValue.count > 1 {
                                        viewModel.emojiAvatar = String(newValue.prefix(1))
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
                    
                    TextField("Phone", text: $viewModel.phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                }
                
                // MARK: - Connections
                if viewModel.existingPerson == nil {
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
                                Text("\(circle.emoji) \(circle.name)").tag(UUID?(circle.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                // MARK: - More Details Toggle
                    Section {
                        Button(action: {
                            withAnimation { showMoreDetails.toggle() }
                        }) {
                            HStack {
                                Text(showMoreDetails ? "Hide Details" : "Add More Details...")
                                Spacer()
                                Image(systemName: showMoreDetails ? "chevron.up" : "chevron.down")
                            }
                            .foregroundColor(.accentColor)
                        }
                    }
                    
                    if showMoreDetails {
                        Section("Additional Info") {
                            TextField("Email", text: $viewModel.email)
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                                .autocapitalization(.none)
                            
                            Toggle("Favorite", isOn: $viewModel.isFavorite)
                        }
                        
                        Section("Notes") {
                            TextEditor(text: $viewModel.notes)
                                .frame(minHeight: 100)
                        }
                    
                    Section("Appearance") {
                        ColorPicker("Node Color", selection: Binding(
                            get: { Color(hex: viewModel.colorHex) },
                            set: { viewModel.colorHex = $0.toHex() ?? "#808080" }
                        ))
                    }
                    
                    Section("Birthday") {
                        Toggle("Include Birthday", isOn: $viewModel.includeBirthday)
                        if viewModel.includeBirthday {
                            DatePicker("Date", selection: $viewModel.birthday, displayedComponents: .date)
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
                
                // MARK: - Danger Zone
                if viewModel.existingPerson != nil {
                    Section {
                        Button(role: .destructive) {
                            if let person = viewModel.existingPerson {
                                do {
                                    try dataManager.deletePerson(person)
                                    dismiss()
                                } catch {
                                    logger.error("Failed to delete contact: \(error.localizedDescription)")
                                }
                            }
                        } label: {
                            HStack {
                                Spacer()
                                Text("Delete Contact")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(viewModel.pageTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("← Back") {
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

