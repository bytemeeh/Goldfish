import Foundation
import SwiftData

// MARK: - Person
/// The core contact model in Goldfish.
///
/// Each person represents a node in the relationship graph. Exactly one `Person`
/// must have `isMe == true` — this contact serves as the graph layout root and
/// cannot be deleted or reassigned.
///
/// **Photo storage:**
/// `photoData` uses `@Attribute(.externalStorage)` so SwiftData stores large blobs
/// as sidecar files and syncs them as CloudKit Assets. The repository layer enforces
/// compression to JPEG ≤500KB at ≤800×800px before persisting.
///
/// **Relationships are stored in a junction table** (`Relationship`), not as a
/// self-referencing `parent_id` tree. This supports multi-parent families, arbitrary
/// connections, and symmetric relationship types.
@Model
final class Person {

    // MARK: - Identifiers

    /// Stable unique identifier (auto-generated).
    @Attribute(.unique)
    var id: UUID

    // MARK: - Core Fields

    /// Full display name. Used for initials fallback and search.
    var name: String

    var phone: String?
    var email: String?

    /// Birthday for age display and reminder scheduling.
    var birthday: Date?

    /// Free-form notes about this contact.
    var notes: String?

    // MARK: - Flags

    /// Exactly one contact has `isMe == true`. This is the graph root.
    /// Created during onboarding; cannot be deleted or reassigned.
    var isMe: Bool

    /// User-toggled favorite for quick access filtering.
    var isFavorite: Bool

    // MARK: - Metadata

    /// Freeform tags for user-defined categorization (e.g., "gym", "book club").
    var tags: [String]

    /// Hex color string (e.g., "#FF6B6B") for graph node and initials circle.
    var color: String?

    // MARK: - Photo

    /// Profile photo stored as compressed JPEG data.
    /// The repository layer enforces max 800×800px and ≤500KB.
    /// `externalStorage` ensures large blobs are stored as sidecar files
    /// and sync via CloudKit Assets rather than inline in the database.
    @Attribute(.externalStorage)
    var photoData: Data?

    // MARK: - Address (Inline)
    /// Flat address fields for simple display. For geocoded / multi-location
    /// support, use the `Location` model via the `locations` relationship.
    var street: String?
    var city: String?
    var state: String?
    var country: String?
    var postalCode: String?

    /// Whether this contact was created as part of a demo or onboarding.
    var isDemo: Bool

    // MARK: - Timestamps

    var createdAt: Date
    var updatedAt: Date

    // MARK: - Relationships

    /// Relationships where this person is the "from" (subject) contact.
    /// e.g., if this person is someone's mother, that Relationship is in outgoing.
    @Relationship(deleteRule: .cascade, inverse: \Relationship.fromContact)
    var outgoingRelationships: [Relationship] = []

    /// Relationships where this person is the "to" (object) contact.
    /// e.g., if someone is this person's mother, that Relationship is in incoming.
    @Relationship(deleteRule: .cascade, inverse: \Relationship.toContact)
    var incomingRelationships: [Relationship] = []

    /// Physical locations associated with this contact.
    @Relationship(deleteRule: .cascade, inverse: \Location.contact)
    var locations: [Location] = []

    /// Circle memberships (via junction table).
    @Relationship(deleteRule: .cascade, inverse: \CircleContact.contact)
    var circleContacts: [CircleContact] = []

    // MARK: - Init

    init(
        id: UUID = UUID(),
        name: String,
        phone: String? = nil,
        email: String? = nil,
        birthday: Date? = nil,
        notes: String? = nil,
        isMe: Bool = false,
        isDemo: Bool = false,
        isFavorite: Bool = false,
        tags: [String] = [],
        color: String? = nil,
        photoData: Data? = nil,
        street: String? = nil,
        city: String? = nil,
        state: String? = nil,
        country: String? = nil,
        postalCode: String? = nil
    ) {
        self.id = id
        self.name = name
        self.phone = phone
        self.email = email
        self.birthday = birthday
        self.notes = notes
        self.isMe = isMe
        self.isDemo = isDemo
        self.isFavorite = isFavorite
        self.tags = tags
        self.color = color
        self.photoData = photoData
        self.street = street
        self.city = city
        self.state = state
        self.country = country
        self.postalCode = postalCode
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // MARK: - Computed Properties

    /// All relationships (both directions) for this contact.
    var allRelationships: [Relationship] {
        outgoingRelationships + incomingRelationships
    }

    /// Initials derived from the contact's name.
    /// - "Marcel Meeh" → "MM"
    /// - "Madonna" → "MA"
    /// - "" → "?"
    var initials: String {
        let components = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
        guard !components.isEmpty else { return "?" }
        if components.count == 1 {
            return String(components[0].prefix(2)).uppercased()
        }
        let first = components.first?.prefix(1) ?? ""
        let last = components.last?.prefix(1) ?? ""
        return "\(first)\(last)".uppercased()
    }

    /// Whether this contact has any relationship connections at all.
    /// Orphan contacts (no relationships) appear in the "Unlinked" section
    /// and float at the graph edge.
    var isOrphan: Bool {
        outgoingRelationships.isEmpty && incomingRelationships.isEmpty
    }

    /// Full formatted address string, or nil if no address fields are set.
    var fullAddress: String? {
        let parts = [street, city, state, postalCode, country].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// The primary location (first in the list), if any.
    var primaryLocation: Location? {
        locations.first { $0.isPrimary } ?? locations.first
    }

    /// Returns all contacts connected to this person (neighbors in the graph).
    /// For symmetric relationships, checks both directions.
    var connectedContacts: [Person] {
        var contacts: [Person] = []
        for rel in outgoingRelationships {
            contacts.append(rel.toContact)
        }
        for rel in incomingRelationships {
            contacts.append(rel.fromContact)
        }
        return contacts
    }
}
