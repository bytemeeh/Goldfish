import SwiftUI

// MARK: - Contact Row View
/// Editorial row: pigment coin, serif name and quiet connection metadata.
/// Relationship and pond context are independent: sharing a pond never implies
/// a graph connection.
/// Terracotta marks favorite people.
struct ContactRowView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let person: Person
    let relationshipSummary: String?
    let pondSummary: String?

    init(person: Person, relationshipSummary: String? = nil, pondSummary: String? = nil) {
        self.person = person
        self.relationshipSummary = relationshipSummary
        self.pondSummary = pondSummary
    }

    private var inferredContexts: RelationshipContextService {
        var peopleByID: [UUID: Person] = [person.id: person]
        var queue = [person]
        var index = 0
        while index < queue.count {
            let current = queue[index]
            index += 1
            for connected in current.connectedContacts
            where connected.isMe || connected.isDemo == person.isDemo {
                if peopleByID[connected.id] == nil {
                    peopleByID[connected.id] = connected
                    queue.append(connected)
                }
            }
        }
        return RelationshipContextService(people: Array(peopleByID.values))
    }

    private var displayedRelationshipSummary: String? {
        relationshipSummary ?? inferredContexts.compactSummary(for: person)
    }

    private var displayedPondSummary: String? {
        pondSummary ?? inferredContexts.pondSummary(for: person)
    }

    var body: some View {
        HStack(spacing: GoldfishDS.Space.lg) {
            ContactPhotoView(person: person, size: .small)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: GoldfishDS.Space.sm) {
                    Text(person.name)
                        .font(.gfName)
                        .foregroundStyle(GoldfishDS.ink(.primary))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)

                    if person.isFavorite {
                        Circle()
                            .fill(GoldfishDS.terracotta)
                            .frame(width: 5, height: 5)
                            .accessibilityLabel("Favourite")
                    }
                }

                if let displayedRelationshipSummary {
                    Text(displayedRelationshipSummary)
                        .font(.gfMeta)
                        .foregroundStyle(GoldfishDS.ink(.tertiary))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let displayedPondSummary {
                    Text(displayedPondSummary)
                        .font(.gfCaption)
                        .foregroundStyle(GoldfishDS.ink(.quaternary))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, GoldfishDS.Space.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            [person.name,
             person.isFavorite ? "Favourite" : nil,
             displayedRelationshipSummary ?? "No saved connection",
             displayedPondSummary]
                .compactMap { $0 }
                .joined(separator: ". ")
        )
        .accessibilityHint("Opens contact")
    }
}
