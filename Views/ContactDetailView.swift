import SwiftUI
import MapKit
import SwiftData

struct ContactDetailView: View {
    @StateObject var viewModel: ContactDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: GoldfishDataManager
    @State private var showAddRelationship = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // MARK: - Header
                VStack(spacing: 16) {
                    ContactPhotoView(
                        photoData: viewModel.person.photoData,
                        name: viewModel.person.name,
                        colorHex: viewModel.person.color,
                        size: 100
                    )
                    
                    VStack(spacing: 4) {
                        Text(viewModel.person.name)
                            .font(.title)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        
                        if let circleName = viewModel.person.circleContacts.first?.circle.name {
                            Text(circleName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(12)
                        }
                    }
                }
                .padding(.top, 24)
                
                // MARK: - Quick Actions
                if hasContactMethods {
                    HStack(spacing: 24) {
                        ActionButton(icon: "phone.fill", label: "Call", action: viewModel.callContact)
                            .disabled(viewModel.person.phone == nil)
                        
                        ActionButton(icon: "message.fill", label: "Message", action: viewModel.messageContact)
                            .disabled(viewModel.person.phone == nil)
                        
                        ActionButton(icon: "envelope.fill", label: "Email", action: viewModel.emailContact)
                            .disabled(viewModel.person.email == nil)
                        
                        ActionButton(icon: "star.fill", label: "Favorite", isActive: viewModel.person.isFavorite, action: viewModel.toggleFavorite)
                    }
                    .padding(.horizontal)
                }
                
                // MARK: - Info Section
                VStack(alignment: .leading, spacing: 20) {
                    if let phone = viewModel.person.phone {
                        InfoRow(icon: "phone.fill", label: "Mobile", value: phone)
                    }
                    if let email = viewModel.person.email {
                        InfoRow(icon: "envelope.fill", label: "Email", value: email)
                    }
                    if let birthday = viewModel.person.birthday {
                        InfoRow(icon: "gift.fill", label: "Birthday", value: birthday.formatted(date: .long, time: .omitted))
                    }
                    if let notes = viewModel.person.notes, !notes.isEmpty {
                        InfoRow(icon: "note.text", label: "Notes", value: notes)
                    }
                    if !viewModel.person.tags.isEmpty {
                        InfoRow(icon: "tag.fill", label: "Tags", value: viewModel.person.tags.joined(separator: ", "))
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(16)
                .padding(.horizontal)
                
                // MARK: - Relationships
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Relationships")
                            .font(.headline)
                        Spacer()
                        Button {
                            showAddRelationship = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.accentColor)
                        }
                    }
                    .padding(.horizontal)
                    
                    if viewModel.groupedRelationships.isEmpty {
                        EmptyStateView(
                            systemImage: "person.line.dotted.person",
                            headline: "No connections yet",
                            subtext: "Add a relationship to see how you're connected.",
                            actionLabel: "Add Relationship",
                            action: {
                                showAddRelationship = true
                            }
                        )
                        .frame(height: 200)
                        .cornerRadius(16)
                        .padding(.horizontal)
                    } else {
                        ForEach(viewModel.groupedRelationships.keys.sorted(), id: \.self) { type in
                            VStack(alignment: .leading) {
                                Text(type.uppercased())
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading)
                                
                                ForEach(viewModel.groupedRelationships[type] ?? []) { rel in
                                    let other = rel.otherContact(from: viewModel.person)
                                    NavigationLink(destination: 
                                        ContactDetailView(viewModel: ContactDetailViewModel(person: other, dataManager: dataManager))
                                    ) {
                                        ContactRowView(person: other)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal)
                                }
                            }
                        }
                    }
                }
                
                // MARK: - Map
                if let lat = viewModel.person.primaryLocation?.latitude,
                   let lon = viewModel.person.primaryLocation?.longitude {
                    VStack(alignment: .leading) {
                        Text("Location")
                            .font(.headline)
                            .padding(.horizontal)
                        
                        Map(coordinateRegion: .constant(MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                        )))
                        .frame(height: 200)
                        .cornerRadius(16)
                        .padding(.horizontal)
                    }
                } else if let address = viewModel.person.fullAddress {
                     VStack(alignment: .leading) {
                        Text("Location")
                            .font(.headline)
                            .padding(.horizontal)
                        
                         HStack {
                             Image(systemName: "mappin.and.ellipse")
                             Text(address)
                         }
                         .padding()
                         .frame(maxWidth: .infinity, alignment: .leading)
                         .background(Color(.secondarySystemBackground))
                         .cornerRadius(16)
                         .padding(.horizontal)
                     }
                }
            }
            .padding(.bottom, 40)
        }
        .background(Color(.systemBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    viewModel.isEditing = true
                }
            }
        }
        .sheet(isPresented: $viewModel.isEditing) {
            ContactFormView(
                viewModel: ContactFormViewModel(
                    dataManager: dataManager,
                    person: viewModel.person
                )
            )
        }
        .sheet(isPresented: $showAddRelationship, onDismiss: {
            viewModel.refreshData()
        }) {
            AddRelationshipView(person: viewModel.person, dataManager: dataManager)
        }
        .onAppear {
            viewModel.refreshData()
        }
    }
    
    var hasContactMethods: Bool {
        viewModel.person.phone != nil || viewModel.person.email != nil
    }
}

// MARK: - Action Button
private struct ActionButton: View {
    let icon: String
    let label: String
    var isActive: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .frame(width: 44, height: 44)
                    .background(isActive ? Color.yellow : Color.accentColor)
                    .foregroundColor(isActive ? .white : .white)
                    .clipShape(Circle())
                
                Text(label)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - Info Row
private struct InfoRow: View {
    let icon: String
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.body)
            }
        }
    }
}
