import SwiftUI

struct CircleManagerView: View {
    @EnvironmentObject var dataManager: GoldfishDataManager

    var body: some View {
        CircleManagerContent(dataManager: dataManager)
    }
}

// MARK: - Circle Manager Content
private struct CircleManagerContent: View {
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
        .navigationTitle("Ponds")
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
                        ColorPicker("Color", selection: $newCircleColor)
                    }
                }
                .navigationTitle("New Pond")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showCreateSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            viewModel.createCircle(
                                name: newCircleName,
                                emoji: "",
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
