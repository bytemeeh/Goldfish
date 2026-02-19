import SwiftUI
import PhotosUI
import SwiftData

struct ContactFormView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject var viewModel: ContactFormViewModel
    
    // Injected for circle picking
    @EnvironmentObject var dataManager: GoldfishDataManager 
    
    // We init with the VM already created, or create it?
    // Usually convenient to pass VM
    
    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Basic Info
                Section("Basic Info") {
                    TextField("Name", text: $viewModel.name)
                        .textContentType(.name)
                    
                    TextField("Phone", text: $viewModel.phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    
                    TextField("Email", text: $viewModel.email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .autocapitalization(.none)
                    
                    Toggle("Favorite", isOn: $viewModel.isFavorite)
                }
                
                // MARK: - Notes
                Section("Notes") {
                    TextEditor(text: $viewModel.notes)
                        .frame(minHeight: 100)
                }
                
                // MARK: - Appearance
                Section("Appearance") {
                    HStack {
                        Text("Photo")
                        Spacer()
                        PhotosPicker(selection: $viewModel.selectedPhotoItem, matching: .images) {
                            if let data = viewModel.photoData, let uiImage = UIImage(data: data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 60, height: 60)
                                    .clipShape(Circle())
                            } else {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .font(.system(size: 40))
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                    
                    ColorPicker("Graph Color", selection: Binding(
                        get: { Color(hex: viewModel.colorHex) },
                        set: { viewModel.colorHex = $0.toHex() ?? "#808080" }
                    ))
                }
                
                // MARK: - Birthday
                Section("Birthday") {
                    Toggle("Include Birthday", isOn: $viewModel.includeBirthday)
                    if viewModel.includeBirthday {
                        DatePicker("Date", selection: $viewModel.birthday, displayedComponents: .date)
                    }
                }
                
                // MARK: - Location
                Section("Location") {
                    TextField("Street", text: $viewModel.street)
                    TextField("City", text: $viewModel.city)
                    TextField("State", text: $viewModel.state)
                    TextField("ZIP/Postal", text: $viewModel.postalCode)
                    TextField("Country", text: $viewModel.country)
                }
                
                // MARK: - Circles
                Section("Circles") {
                    if viewModel.allCircles.isEmpty {
                        Text("No circles available")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.allCircles) { circle in
                            Button(action: {
                                viewModel.toggleCircle(circle)
                            }) {
                                HStack {
                                    Text("\(circle.emoji) \(circle.name)")
                                    Spacer()
                                    if viewModel.selectedCircleIDs.contains(circle.id) {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.accentColor)
                                    }
                                }
                            }
                            .foregroundColor(.primary)
                        }
                    }
                }
                
                // MARK: - Metadata
                Section("Tags") {
                    TextField("Comma separated (e.g. gym, work)", text: $viewModel.tagsString)
                }
            }
            .navigationTitle(viewModel.pageTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if viewModel.save() {
                            dismiss()
                        }
                    }
                    .disabled(!viewModel.isValid)
                }
            }
        }
    }
}

// MARK: - Color Hex Helpers
extension Color {
    func toHex() -> String? {
        let uic = UIColor(self)
        guard let components = uic.cgColor.components, components.count >= 3 else {
            return nil
        }
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        var a = Float(1.0)
        
        if components.count >= 4 {
            a = Float(components[3])
        }
        
        if a != 1.0 {
            return String(format: "%02lX%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255), lroundf(a * 255))
        } else {
            return String(format: "%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
        }
    }
}
