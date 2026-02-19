import SwiftUI

struct CircleManagerView: View {
    @EnvironmentObject var dataManager: GoldfishDataManager
    @StateObject private var viewModel: CircleManagerViewModel
    
    @State private var showCreateSheet = false
    @State private var newCircleName = ""
    @State private var newCircleEmoji = "⭕️"
    
    init() {
        _viewModel = StateObject(wrappedValue: CircleManagerViewModel(dataManager: .preview()))
    }
    
    var body: some View {
        DataManagerInjector()
    }
    
    struct DataManagerInjector: View {
        @EnvironmentObject var dataManager: GoldfishDataManager
        var body: some View {
            Content(dataManager: dataManager)
        }
    }
    
    struct Content: View {
        @StateObject var viewModel: CircleManagerViewModel
        @State private var showCreateSheet = false
        @State private var newCircleName = ""
        @State private var newCircleEmoji = "⭕️"
        @State private var newCircleColor = Color.gray
        
        init(dataManager: GoldfishDataManager) {
            _viewModel = StateObject(wrappedValue: CircleManagerViewModel(dataManager: dataManager))
        }
        
        var body: some View {
            List {
                ForEach(viewModel.circles) { circle in
                    HStack {
                        Text(circle.emoji)
                        Text(circle.name)
                            .font(.headline)
                        Spacer()
                        if circle.isSystem {
                            Text("System")
                                .font(.caption)
                                .padding(4)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(4)
                        }
                    }
                    .swipeActions {
                        if !circle.isSystem {
                            Button(role: .destructive) {
                                viewModel.deleteCircle(circle)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Circles")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showCreateSheet = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                NavigationStack {
                    Form {
                        Section("Details") {
                            TextField("Name", text: $newCircleName)
                            TextField("Emoji", text: $newCircleEmoji)
                            ColorPicker("Color", selection: $newCircleColor)
                        }
                    }
                    .navigationTitle("New Circle")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { showCreateSheet = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Create") {
                                viewModel.createCircle(
                                    name: newCircleName,
                                    emoji: newCircleEmoji,
                                    color: newCircleColor.toHex() ?? "#808080"
                                )
                                showCreateSheet = false
                                newCircleName = ""
                            }
                            .disabled(newCircleName.isEmpty)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }
}
