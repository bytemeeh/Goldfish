import SwiftUI
import SwiftData

// MARK: - Unassigned Contacts Sheet
/// Shown when the user taps the "X contacts need a pond" banner.
/// Lists every non-Me contact without an active pond and lets the user
/// assign each one via a simple picker.
struct UnassignedContactsSheet: View {
    let circles: [GoldfishCircle]
    let dataManager: GoldfishDataManager
    @Environment(\.dismiss) private var dismiss

    // Fetch unassigned persons inline so the list updates after each assignment
    @State private var unassignedPersons: [Person] = []

    var body: some View {
        NavigationStack {
            Group {
                if unassignedPersons.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 52))
                            .foregroundColor(.green)
                        Text("All contacts are assigned")
                            .font(.title3.bold())
                        Text("Every contact belongs to a pond.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            ForEach(unassignedPersons) { person in
                                UnassignedContactRow(
                                    person: person,
                                    circles: circles,
                                    dataManager: dataManager,
                                    onAssigned: { reload() }
                                )
                            }
                        } header: {
                            Text("Tap a pond to assign each contact")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .textCase(nil)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("\(unassignedPersons.count) Without a Pond")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear { reload() }
    }

    private func reload() {
        guard let all = try? dataManager.fetchAllPersons() else { return }
        unassignedPersons = all.filter { person in
            !person.isMe && person.circleContacts.filter { !$0.manuallyExcluded }.isEmpty
        }.sorted { $0.name < $1.name }
    }
}

// MARK: - Row
private struct UnassignedContactRow: View {
    let person: Person
    let circles: [GoldfishCircle]
    let dataManager: GoldfishDataManager
    let onAssigned: () -> Void

    @State private var selectedCircleID: UUID? = nil
    @State private var isAssigning = false

    private var sortedCircles: [GoldfishCircle] {
        circles.sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        HStack(spacing: 12) {
            ContactPhotoView(
                photoData: person.photoData,
                name: person.name,
                colorHex: person.color,
                size: .small
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(person.name)
                    .font(.system(size: 14, weight: .semibold))
                Text("No pond assigned")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            Spacer()

            // Pond picker
            if sortedCircles.isEmpty {
                Text("No ponds yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Menu {
                    ForEach(sortedCircles) { circle in
                        Button(circle.name) {
                            assign(to: circle)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Assign")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.goldfishAccent.opacity(0.15))
                    .foregroundColor(.goldfishAccent)
                    .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 4)
        .opacity(isAssigning ? 0.5 : 1)
    }

    private func assign(to circle: GoldfishCircle) {
        isAssigning = true
        let _ = try? dataManager.addToCircle(person, circle: circle)
        ToastManager.shared.showToast(message: "Moved \(person.name) to \(circle.name)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onAssigned()
        }
    }
}
