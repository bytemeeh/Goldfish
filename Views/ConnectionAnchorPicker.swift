import SwiftUI
import SwiftData

struct ConnectionAnchorPicker: View {
    let dataManager: GoldfishDataManager
    let isDemoMode: Bool
    let onSelect: (Person) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Person.name) private var people: [Person]
    @State private var search = ""
    private var contacts: [Person] {
        people.filter { ($0.isMe || $0.isDemo == isDemoMode) &&
            (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        List {
            Section {
                Text("Who would you like to build around? Choose someone, then add several of their connections together.")
                    .font(.gfBody).foregroundStyle(GoldfishDS.ink(.secondary))
            }.listRowBackground(GoldfishDS.surface)
            ForEach(contacts) { person in
                Button {
                    onSelect(person)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        ContactPhotoView(person: person, size: .extraSmall).accessibilityHidden(true)
                        Text(person.isMe ? "You" : person.name).font(.gfBody)
                        Spacer()
                        Image(systemName: "chevron.right").accessibilityHidden(true)
                    }
                    .foregroundStyle(GoldfishDS.ink(.primary)).frame(minHeight: 44)
                }.listRowBackground(GoldfishDS.surface)
            }
            if contacts.isEmpty { Text("No matching contacts").font(.gfBody) }
        }
        .scrollContentBackground(.hidden).background(GoldfishDS.warmBlack)
        .navigationTitle("Build around someone").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Find a person")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done for now") { dismiss() } } }
    }
}
