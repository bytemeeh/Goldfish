import Foundation
import SwiftData

// MARK: - GoldfishCircle
/// A named group for organizing contacts (e.g., Family, Friends, Professional).
///
/// **System circles** (`isSystem == true`) are created at first launch and
/// cannot be deleted. They have `autoRelationshipTypes` that drive automatic
/// circle assignment when relationships are created:
/// - Family: mother, father, sibling, spouse, partner, child
/// - Friends: friend
/// - Professional: coworker
///
/// **Custom circles** are user-created, freely editable, and deletable.
///
/// A contact belongs to **at most one** circle at a time. The
/// `CircleContact` junction table tracks the current membership.
@Model
final class GoldfishCircle {

    @Attribute(.unique)
    var id: UUID

    /// Display name (e.g., "Family", "Book Club").
    var name: String

    /// Hex color string for visual distinction in the graph and lists.
    var color: String

    /// Emoji icon shown alongside the circle name.
    var emoji: String

    /// Optional description of the circle's purpose.
    var desc: String?

    /// Whether this is a built-in system circle (Family, Friends, Professional).
    /// System circles cannot be deleted.
    var isSystem: Bool

    /// Relationship type raw values that trigger auto-assignment to this circle.
    /// e.g., ["mother", "father", "sibling", "spouse", "partner", "child"] for Family.
    /// Empty for custom circles.
    var autoRelationshipTypes: [String]

    /// Display order in the list/graph. Lower values appear first.
    var sortOrder: Int

    // MARK: - Relationships

    /// Junction records linking contacts to this circle.
    @Relationship(deleteRule: .cascade, inverse: \CircleContact.circle)
    var circleContacts: [CircleContact] = []

    // MARK: - Timestamps

    var createdAt: Date

    // MARK: - Init

    init(
        id: UUID = UUID(),
        name: String,
        color: String = "#808080",
        emoji: String = "⭐",
        desc: String? = nil,
        isSystem: Bool = false,
        autoRelationshipTypes: [String] = [],
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.emoji = emoji
        self.desc = desc
        self.isSystem = isSystem
        self.autoRelationshipTypes = autoRelationshipTypes
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }

    // MARK: - Computed

    /// All contacts currently in this circle (excluding manually excluded).
    var activeContacts: [Person] {
        circleContacts
            .filter { !$0.manuallyExcluded }
            .map(\.contact)
    }

    /// Whether a given relationship type triggers auto-assignment to this circle.
    func shouldAutoAssign(for type: RelationshipType) -> Bool {
        autoRelationshipTypes.contains(type.rawValue)
            || (type == .parent && (autoRelationshipTypes.contains(RelationshipType.mother.rawValue)
                                   || autoRelationshipTypes.contains(RelationshipType.father.rawValue)))
    }

    // MARK: - System Circle Factory

    /// Creates the three default system circles. Call once during onboarding.
    static func createSystemCircles() -> [GoldfishCircle] {
        [
            GoldfishCircle(
                name: "Family",
                color: "#FF6B6B",
                emoji: "",
                desc: "Your family members",
                isSystem: true,
                autoRelationshipTypes: [
                    RelationshipType.mother.rawValue,
                    RelationshipType.father.rawValue,
                    RelationshipType.sibling.rawValue,
                    RelationshipType.spouse.rawValue,
                    RelationshipType.partner.rawValue,
                    RelationshipType.child.rawValue,
                    RelationshipType.parent.rawValue
                ],
                sortOrder: 0
            ),
            GoldfishCircle(
                name: "Friends",
                color: "#4ECDC4",
                emoji: "",
                desc: "Your friends",
                isSystem: true,
                autoRelationshipTypes: [
                    RelationshipType.friend.rawValue
                ],
                sortOrder: 1
            ),
            GoldfishCircle(
                name: "Professional",
                color: "#45B7D1",
                emoji: "",
                desc: "Professional contacts and coworkers",
                isSystem: true,
                autoRelationshipTypes: [
                    RelationshipType.coworker.rawValue
                ],
                sortOrder: 2
            )
        ]
    }
}

/// A pond describes how someone belongs in your network, not just their role
/// relative to another contact. Shared by interactive creation and vCard import.
enum PondAssignmentPolicy {
    static func suggestedCircle(
        for person: Person,
        relatedTo other: Person,
        type: RelationshipType,
        systemCircles: [GoldfishCircle]
    ) -> GoldfishCircle? {
        guard !person.isMe, person.primaryCircle == nil,
              type.autoCircleName != nil else { return nil }

        let systemType: RelationshipType = (type == .pet || type == .guardian) ? .parent : type
        let defaultCircle = systemCircles.first { $0.shouldAutoAssign(for: systemType) }
        let candidate: GoldfishCircle?
        if other.isMe {
            candidate = defaultCircle
        } else if type.autoCircleName == "Family" {
            // Your friend's household belongs with that friend. Without an
            // existing context, a household is not assumed to be your family.
            candidate = other.primaryCircle
        } else if let context = other.primaryCircle, !context.isSystem {
            candidate = context
        } else {
            // A relative's friend or colleague does not become your family.
            candidate = defaultCircle
        }

        guard let candidate,
              !person.circleContacts.contains(where: { $0.circle.id == candidate.id }) else { return nil }
        return candidate
    }
}
