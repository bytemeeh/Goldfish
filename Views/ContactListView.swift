import SwiftUI

struct ContactListView: View {
    @ObservedObject var viewModel: HomeViewModel
    @EnvironmentObject var dataManager: GoldfishDataManager
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if viewModel.contacts.isEmpty {
                    EmptyStateView(
                        systemImage: "person.3.fill",
                        headline: "No contacts yet",
                        subtext: "People you add will appear here.",
                        actionLabel: "Add Contact",
                        action: {
                            // Trigger add sheet via parent or overlay
                        }
                    )
                    .frame(height: 400)
                } else {
                    // Grouped Logic
                    // For MVP simplicity we just dump properties, 
                    // ideally we group by circle or first letter here.
                    // We'll group by Circle if that's the sort, or just list.
                    
                    if viewModel.sortOrder == "circle" {
                        ForEach(viewModel.circles) { circle in
                            let members = viewModel.contacts.filter { 
                                $0.circleContacts.contains(where: { $0.circle.id == circle.id }) 
                            }
                            if !members.isEmpty {
                                Section(header: SectionHeader(title: circle.name)) {
                                    ForEach(members) { person in
                                        NavigationLink {
                                            ContactDetailView(viewModel: ContactDetailViewModel(person: person, dataManager: dataManager))
                                        } label: {
                                            ContactRowView(person: person)
                                                .padding(.horizontal)
                                        }
                                        Divider().padding(.leading, 68)
                                    }
                                }
                            }
                        }
                    } else {
                        // Flat list (or alphabetical sections)
                        ForEach(viewModel.contacts) { person in
                            NavigationLink {
                                ContactDetailView(viewModel: ContactDetailViewModel(person: person, dataManager: dataManager))
                            } label: {
                                ContactRowView(person: person)
                                    .padding(.horizontal)
                            }
                            Divider().padding(.leading, 68)
                        }
                    }
                    
                    // Footer padding
                    Color.clear.frame(height: 100)
                }
            }
            .padding(.top, 8)
        }
        .refreshable {
            viewModel.loadData()
        }
    }
}

private struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(.systemGroupedBackground))
    }
}
