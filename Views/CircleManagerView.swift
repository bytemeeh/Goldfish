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

    // Edit state
    @State private var editingCircle: GoldfishCircle?
    @State private var editName = ""
    @State private var editColor = Color.gray

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
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(4)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    editName = circle.name
                    editColor = Color(hex: circle.color) ?? .gray
                    editingCircle = circle
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
        // MARK: - Create Sheet
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
        // MARK: - Edit Sheet
        .sheet(item: $editingCircle) { circle in
            NavigationStack {
                Form {
                    Section("Details") {
                        TextField("Name", text: $editName)
                        ColorPicker("Color", selection: $editColor)
                    }
                    if !circle.isSystem {
                        Section {
                            Button(role: .destructive) {
                                viewModel.deleteCircle(circle)
                                editingCircle = nil
                            } label: {
                                HStack {
                                    Spacer()
                                    Text("Delete Pond")
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Edit Pond")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { editingCircle = nil }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            viewModel.updateCircle(
                                circle,
                                name: editName,
                                emoji: circle.emoji,
                                color: editColor.toHex() ?? circle.color
                            )
                            editingCircle = nil
                        }
                        .disabled(editName.isEmpty)
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
}

