import Foundation
import SwiftData

// MARK: - Relationship
/// Junction table connecting two `Person` records with a typed, optionally
/// directional relationship.
///
/// **Directionality contract:**
/// `Relationship(from: A, to: B, type: .mother)` means "A is B's mother."
/// The `fromContact` IS the role described by `type`, relative to `toContact`.
///
/// **Symmetric types (sibling, spouse, friend, coworker):**
/// Stored as a single row. Query helpers check both `fromContact` and `toContact`
/// so one record covers both sides. This avoids duplication and CloudKit sync conflicts.
///
/// **Directional types (mother, father, child):**
/// Stored with explicit direction. If you know A is B's mother, store
/// `(from: A, to: B, type: .mother)`. The inverse (B is A's child) is derived,
/// not stored as a separate row.
@Model
final class Relationship {

    @Attribute(.unique)
    var id: UUID

    /// Raw storage for the relationship type enum.
    /// Using a String raw value ensures CloudKit compatibility and migration safety.
    var typeRawValue: String

    /// Marks this as the primary relationship between two contacts.
    /// Used when a person has multiple relationship types with the same contact
    /// (e.g., both coworker and friend) to determine the display label.
    var isPrimary: Bool

    // MARK: - Linked Contacts

    /// The subject contact — this person IS the `type` relative to `toContact`.
    var fromContact: Person

    /// The object contact — the `type` describes `fromContact`'s role to this person.
    var toContact: Person

    // MARK: - Timestamps

    var createdAt: Date

    // MARK: - Init

    init(
        id: UUID = UUID(),
        from: Person,
        to: Person,
        type: RelationshipType,
        isPrimary: Bool = false
    ) {
        self.id = id
        self.fromContact = from
        self.toContact = to
        self.typeRawValue = type.rawValue
        self.isPrimary = isPrimary
        self.createdAt = Date()
    }

    // MARK: - Computed

    /// The typed relationship enum, decoded from the stored raw value.
    var type: RelationshipType {
        get { RelationshipType(rawValue: typeRawValue) ?? .other }
        set { typeRawValue = newValue.rawValue }
    }

    /// Whether this relationship is symmetric (both directions implied by one row).
    var isSymmetric: Bool { type.isSymmetric }

    /// Returns the "other" person in this relationship, given one of the two contacts.
    /// Useful when traversing the graph from a known contact.
    func otherContact(from person: Person) -> Person {
        if person.id == fromContact.id {
            return toContact
        } else {
            return fromContact
        }
    }

    /// Returns the effective relationship type as seen FROM the given person's perspective.
    ///
    /// Example: Relationship(from: Alice, to: Bob, type: .mother)
    /// - `effectiveType(for: Alice)` → .mother  ("Alice is a mother")
    /// - `effectiveType(for: Bob)` → .child     ("Bob's perspective: she's his mother, so he's her child" — but we return .mother here as the label, the inverse is computed separately)
    ///
    /// For symmetric types, always returns the stored type.
    func effectiveType(for person: Person) -> RelationshipType {
        if type.isSymmetric {
            return type
        }
        if person.id == fromContact.id {
            return type
        } else {
            return type.inverse ?? type
        }
    }
}
