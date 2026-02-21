import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ContactExportSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: GoldfishDataManager
    
    @State private var searchText = ""
    @State private var selectedContacts: Set<Person> = []
    @State private var includeSubcontacts = false
    @State private var showingShareSheet = false
    @State private var exportURL: URL?
    
    @Query(sort: \Person.name) private var allContacts: [Person]
    
    var filteredContacts: [Person] {
        if searchText.isEmpty {
            return allContacts.filter { !$0.isMe } // Exclude "ME" card from manual selection if desired, or keep it. Let's keep it but maybe it's less relevant. Actually, it's better to allow exporting ME card if they want to. Let's not filter it.
        } else {
            return allContacts.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        List {
            Section {
                Toggle("Include Subcontacts", isOn: $includeSubcontacts)
                Text("When enabled, exports the selected contacts along with all of their direct connections.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Section {
                ForEach(searchText.isEmpty ? allContacts : filteredContacts) { contact in
                    HStack {
                        ContactPhotoView(
                            photoData: contact.photoData,
                            name: contact.name,
                            colorHex: contact.color,
                            size: 40
                        )
                        
                        VStack(alignment: .leading) {
                            Text(contact.name)
                                .font(.body)
                            if contact.isMe {
                                Text("This is you")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if let connectionCount = contact.connectedContacts.count as Int?, connectionCount > 0 {
                                Text("\(connectionCount) connection\(connectionCount == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        if selectedContacts.contains(contact) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.accentColor)
                        } else {
                            Image(systemName: "circle")
                                .foregroundColor(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedContacts.contains(contact) {
                            selectedContacts.remove(contact)
                        } else {
                            selectedContacts.insert(contact)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Select Contacts")
                    Spacer()
                    if !allContacts.isEmpty {
                        Button(selectedContacts.count == allContacts.count ? "Deselect All" : "Select All") {
                            if selectedContacts.count == allContacts.count {
                                selectedContacts.removeAll()
                            } else {
                                selectedContacts = Set(allContacts)
                            }
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search contacts")
        .navigationTitle("Export Contacts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Export (\(selectedContacts.count))") {
                    generateExport()
                }
                .disabled(selectedContacts.isEmpty)
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = exportURL {
                ShareSheet(activityItems: [url])
            }
        }
    }
    
    private func generateExport() {
        let depth = includeSubcontacts ? 1 : 0
        let data = VCardExportService.exportSelected(Array(selectedContacts), depth: depth)
        
        do {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("GoldfishExport.vcf")
            try data.write(to: url)
            self.exportURL = url
            self.showingShareSheet = true
        } catch {
            print("Failed to save export file: \(error)")
        }
    }
}
