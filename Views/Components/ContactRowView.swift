import SwiftUI

// MARK: - Contact Row View
/// Standard list row for a contact.
/// See Spec §3 (views) and §8.1 (accessibility).
struct ContactRowView: View {
    let person: Person
    
    var subtitle: String {
        // Preference: Phone -> Email -> nil
        return person.phone ?? person.email ?? "No contact details"
    }
    
    var body: some View {
        HStack(spacing: 12) {
            ContactPhotoView(
                photoData: person.photoData,
                name: person.name,
                colorHex: person.color,
                size: 40
            )
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(person.name)
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    if person.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("Favorite")
                    }
                }
                
                if let sub = subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle()) // Make full row tappable
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(person.name). \(person.isFavorite ? "Favorite." : "")")
        .accessibilityHint("Double tap to view details")
    }
}
