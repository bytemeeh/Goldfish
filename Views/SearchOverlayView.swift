import SwiftUI

struct SearchOverlayView: View {
    @ObservedObject var viewModel: HomeViewModel
    @EnvironmentObject var dataManager: GoldfishDataManager
    let onSelect: (Person) -> Void
    
    var body: some View {
        VStack {
            if viewModel.filteredContacts.isEmpty {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    headline: "No results for \"\(viewModel.searchText)\"",
                    subtext: "Try a different name, tag, or circle."
                )
                .frame(height: 300)
            } else {
                List {
                    ForEach(viewModel.filteredContacts) { person in
                        Button(action: {
                            onSelect(person)
                        }) {
                            ContactRowView(person: person)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 10)
        .padding()
        .transition(.move(edge: .bottom))
    }
}
