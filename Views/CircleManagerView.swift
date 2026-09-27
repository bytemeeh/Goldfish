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
    @EnvironmentObject private var demoModeManager: DemoModeManager
    @EnvironmentObject private var walkthroughManager: FeatureWalkthroughManager
    @State private var circleToDelete: GoldfishCircle?
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
        Group {
            List {
                ForEach(viewModel.circles) { circle in
                    CircleRow(circle: circle, isDemoMode: demoModeManager.isDemoModeActive || walkthroughManager.isActive) {
                        viewModel.errorMessage = nil
                        editName = circle.name
                        editColor = Color(hex: circle.color)
                        editingCircle = circle
                    } onDelete: {
                        circleToDelete = circle
                    }
                    .listRowBackground(GoldfishDS.surface)
                    .listRowSeparatorTint(GoldfishDS.ink(.hairline))
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(GoldfishDS.warmBlack.ignoresSafeArea())
            .navigationTitle("Ponds")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.errorMessage = nil
                        showCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(GoldfishDS.ink(.primary))
                    }
                    .accessibilityLabel("Create pond")
                    .accessibilityIdentifier("createGroupButton")
                }
            }
        }
        .confirmationDialog("Delete pond?", isPresented: Binding(
            get: { circleToDelete != nil },
            set: { if !$0 { circleToDelete = nil } }
        ), titleVisibility: .visible) {
            if let circle = circleToDelete {
                Button("Delete \(circle.name)", role: .destructive) {
                    viewModel.deleteCircle(circle)
                    circleToDelete = nil
                }
            }
            Button("Cancel", role: .cancel) { circleToDelete = nil }
        } message: { Text("People and connections are kept. Members become unassigned.") }
        .alert("Could not update pond", isPresented: Binding(
            get: { viewModel.errorMessage != nil && editingCircle == nil && !showCreateSheet },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) { Button("OK") { viewModel.errorMessage = nil } } message: { Text(viewModel.errorMessage ?? "") }
        // MARK: - Create Sheet
        .sheet(isPresented: $showCreateSheet) {
            LineEditSheet(
                title: "New Pond",
                errorMessage: $viewModel.errorMessage,
                lineName: $newCircleName,
                lineColor: $newCircleColor,
                nameFeedback: { viewModel.nameFeedback($0) },
                previewMemberCount: 0,
                isSystem: false,
                onCancel: {
                    showCreateSheet = false
                    newCircleName = ""
                },
                onConfirm: {
                    guard viewModel.createCircle(
                        name: newCircleName,
                        emoji: "",
                        color: newCircleColor.toHex() ?? "#808080"
                    ) else { return }
                    showCreateSheet = false
                    newCircleName = ""
                },
                confirmLabel: "Create",
                onDelete: nil
            )
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(GoldfishDS.Radius.sheet)
        }
        // MARK: - Edit Sheet
        .sheet(item: $editingCircle) { circle in
            LineEditSheet(
                title: "Edit Pond",
                errorMessage: $viewModel.errorMessage,
                lineName: $editName,
                lineColor: $editColor,
                nameFeedback: { viewModel.nameFeedback($0, excluding: circle) },
                previewMemberCount: circle.activeContacts.filter { !$0.isMe && $0.isDemo == (demoModeManager.isDemoModeActive || walkthroughManager.isActive) }.count,
                isSystem: circle.isSystem,
                onCancel: { editingCircle = nil },
                onConfirm: {
                    guard viewModel.updateCircle(
                        circle,
                        name: editName,
                        emoji: circle.emoji,
                        color: editColor.toHex() ?? circle.color
                    ) else { return }
                    editingCircle = nil
                },
                confirmLabel: "Save",
                onDelete: circle.isSystem ? nil : {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    guard viewModel.deleteCircle(circle) else { return }
                    editingCircle = nil
                }
            )
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(GoldfishDS.Radius.sheet)
        }
    }
}

// MARK: - Circle Row

private struct CircleRow: View {
    let circle: GoldfishCircle
    let isDemoMode: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    private var memberCount: Int { circle.activeContacts.filter { !$0.isMe && $0.isDemo == isDemoMode }.count }
    private var groupColor: Color { GoldfishDS.groupTone(circle) }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: GoldfishDS.Space.md) {
                // Short thick line segment — the line's color on the map.
                Circle()
                    .fill(groupColor)
                    .frame(width: 8, height: 8)

                Text(circle.name)
                    .font(.gfName)
                    .foregroundStyle(GoldfishDS.ink(.primary))

                if circle.isSystem {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(GoldfishDS.ink(.tertiary))
                }

                Spacer()

                Text(memberCountLabel)
                    .font(.gfMeta)
                    .monospacedDigit()
                    .foregroundStyle(GoldfishDS.ink(.secondary))
            }
            .padding(.vertical, GoldfishDS.Space.xs)
        }
        .foregroundStyle(GoldfishDS.ink(.primary))
        .accessibilityLabel("\(circle.name), \(memberCountLabel)\(circle.isSystem ? ", built-in pond" : "")")
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !circle.isSystem {
                Button(role: .destructive) {
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private var memberCountLabel: String {
        switch memberCount {
        case 0: return "0 people"
        case 1: return "1 person"
        default: return "\(memberCount) people"
        }
    }
}

// MARK: - Line Edit Sheet (Create & Edit)

private struct LineEditSheet: View {
    let title: String
    @Binding var errorMessage: String?
    @Binding var lineName: String
    @Binding var lineColor: Color
    let nameFeedback: (String) -> CircleManagerViewModel.NameFeedback
    let previewMemberCount: Int
    let isSystem: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void
    let confirmLabel: String
    let onDelete: (() -> Void)?

    @FocusState private var nameFocused: Bool
    @State private var showDeleteConfirmation = false

    private var currentNameFeedback: CircleManagerViewModel.NameFeedback {
        nameFeedback(lineName)
    }

    var body: some View {
        NavigationStack {
            Form {
                if isSystem {
                    Text("This built-in pond has a fixed name and color. Create a custom pond for your own grouping.")
                        .font(.gfMeta)
                        .foregroundStyle(GoldfishDS.ink(.secondary))
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Color.goldfishError)
                }
                Section {
                    TextField("Pond name", text: $lineName)
                        .font(.gfBody)
                        .foregroundStyle(GoldfishDS.ink(.primary))
                        .disabled(isSystem)
                        .focused($nameFocused)
                        .accessibilityLabel("Pond name")
                        .accessibilityHint(currentNameFeedback.message ?? "")
                    if !isSystem, let message = currentNameFeedback.message {
                        Text(message)
                            .font(.gfMeta)
                            .foregroundStyle(currentNameFeedback.preventsSave ? Color.goldfishError : GoldfishDS.ink(.secondary))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("Name")
                        .gfSectionLabel()
                        .textCase(nil)
                }
                .listRowBackground(GoldfishDS.surface)

                Section {
                    ColorPicker("Pond color", selection: $lineColor).disabled(isSystem)
                        .font(.gfBody)
                        .foregroundStyle(GoldfishDS.ink(.primary))
                    PondColorPreview(
                        name: lineName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Pond name" : lineName,
                        memberCount: previewMemberCount,
                        color: lineColor
                    )
                } header: {
                    Text("Color")
                        .gfSectionLabel()
                        .textCase(nil)
                }
                .listRowBackground(GoldfishDS.surface)

                if onDelete != nil {
                    Section {
                        Button(role: .destructive, action: { showDeleteConfirmation = true }) {
                            Text("Delete Pond")
                                .font(.gfLabel)
                                .textCase(.uppercase)
                                .kerning(1.2)
                                .foregroundStyle(GoldfishDS.terracotta)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .listRowBackground(GoldfishDS.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(GoldfishDS.warmBlack.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .font(.gfBody)
                        .foregroundStyle(GoldfishDS.ink(.secondary))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmLabel, action: onConfirm)
                        .font(.gfBody)
                        .foregroundStyle(GoldfishDS.ink(.primary))
                        .disabled(currentNameFeedback.preventsSave)
                }
            }
        }
        .confirmationDialog("Delete pond?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Pond", role: .destructive) { onDelete?() }
            Button("Cancel", role: .cancel) { }
        } message: { Text("People and connections are kept. Members become unassigned.") }
        .onAppear { nameFocused = !isSystem }
    }
}

private struct PondColorPreview: View {
    let name: String
    let memberCount: Int
    let color: Color

    private var countLabel: String {
        memberCount == 1 ? "1 person" : "\(memberCount) people"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GoldfishDS.Space.xs) {
            Text("Pond mark preview")
                .font(.gfMeta)
                .foregroundStyle(GoldfishDS.ink(.secondary))
            HStack(spacing: GoldfishDS.Space.sm) {
                previewSurface(background: Color(hex: "#F5F0EB"), ink: Color(hex: "#1A1614"))
                previewSurface(background: Color(hex: "#1A1614"), ink: Color(hex: "#F5F0EB"))
            }
            Text("The saved color appears with the pond name and border on both surfaces.")
                .font(.gfMeta)
                .foregroundStyle(GoldfishDS.ink(.tertiary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(countLabel), pond mark preview")
        .accessibilityHint("Decorative preview of the saved color on light and dark surfaces.")
    }

    private func previewSurface(background: Color, ink: Color) -> some View {
        HStack(spacing: GoldfishDS.Space.xs) {
            RoundedRectangle(cornerRadius: GoldfishDS.Radius.chip)
                .fill(color)
                .frame(width: 26, height: 16)
                .overlay {
                    RoundedRectangle(cornerRadius: GoldfishDS.Radius.chip)
                        .stroke(ink.opacity(0.55), lineWidth: 1)
                }
            Text(name)
                .font(.gfMeta)
                .foregroundStyle(ink)
                .lineLimit(1)
        }
        .padding(.horizontal, GoldfishDS.Space.sm)
        .padding(.vertical, GoldfishDS.Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
        .overlay {
            RoundedRectangle(cornerRadius: GoldfishDS.Radius.control)
                .stroke(ink.opacity(0.22), lineWidth: GoldfishDS.Rule.hairline)
        }
    }
}
