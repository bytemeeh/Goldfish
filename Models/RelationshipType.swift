import Foundation

// MARK: - RelationshipType
/// Defines the kind of relationship between two contacts.
///
/// **Directionality contract:**
/// A `Relationship(from: A, to: B, type: .mother)` means "A is B's mother."
/// The `from` person IS the role described by the type, relative to `to`.
///
/// **Symmetric vs Directional:**
/// - Symmetric types (sibling, spouse, partner, friend, coworker) are stored as a single row.
///   Query helpers check both directions so one record covers both contacts.
/// - Directional types (mother, father, child, parent) are stored once with explicit direction.
///   The `inverse` property gives the reciprocal type (mother ↔ child, father ↔ child, parent ↔ child).
enum RelationshipType: String, Codable, CaseIterable, Identifiable {
    case mother
    case father
    case sibling
    case spouse
    case partner
    case friend
    case coworker
    case child
    case parent   // BUG 2 FIX: generic gender-neutral parent
    case other

    var id: String { rawValue }

    // MARK: - Symmetry

    /// Whether this relationship reads the same from both sides.
    /// For symmetric types, a single row represents the connection in both directions.
    var isSymmetric: Bool {
        switch self {
        case .sibling, .spouse, .partner, .friend, .coworker:  // BUG 1 FIX: .partner is symmetric
            return true
        case .mother, .father, .child, .parent, .other:
            return false
        }
    }

    /// Whether this relationship is directional (parent → child lineage).
    /// Used by cycle detection — only directional types can create ancestry cycles.
    var isDirectional: Bool { !isSymmetric }

    // MARK: - Inverse

    /// The reciprocal type when viewed from the other side.
    ///
    /// - mother ↔ child  (if A is B's mother, then B is A's child)
    /// - father ↔ child
    /// - parent ↔ child  (gender-neutral)
    /// - Symmetric types return themselves
    /// - other has no well-defined inverse → nil
    var inverse: RelationshipType? {
        switch self {
        case .mother:   return .child
        case .father:   return .child
        case .child:    return .parent  // BUG 2 FIX: inverse of child is parent
        case .parent:   return .child   // BUG 2 FIX: inverse of parent is child
        case .sibling:  return .sibling
        case .spouse:   return .spouse
        case .friend:   return .friend
        case .coworker: return .coworker
        case .partner:  return .partner // BUG 1 FIX: symmetric → returns self
        case .other:    return nil
        }
    }

    // MARK: - Circle Auto-Assignment

    /// The system circle name this relationship type maps to, if any.
    /// Used for automatic circle assignment when a relationship is created.
    ///
    /// - Family: mother, father, sibling, spouse, partner, child
    /// - Friends: friend
    /// - Professional: coworker
    /// - nil: other (no auto-assignment)
    var autoCircleName: String? {
        switch self {
        case .mother, .father, .sibling, .spouse, .partner, .child, .parent:
            return "Family"
        case .friend:
            return "Friends"
        case .coworker:
            return "Professional"
        case .other:
            return nil
        }
    }

    // MARK: - Display

    /// Human-readable label for UI display.
    var displayName: String {
        switch self {
        case .mother:   return "Mother"
        case .father:   return "Father"
        case .sibling:  return "Sibling"
        case .spouse:   return "Spouse"
        case .partner:  return "Partner"
        case .friend:   return "Friend"
        case .coworker: return "Coworker"
        case .child:    return "Child"
        case .parent:   return "Parent"  // BUG 2 FIX
        case .other:    return "Other"
        }
    }

    /// SF Symbol name for each type.
    var symbolName: String {
        switch self {
        case .mother:   return "figure.stand"
        case .father:   return "figure.stand"
        case .sibling:  return "figure.2"
        case .spouse:   return "heart.fill"
        case .partner:  return "heart"
        case .friend:   return "person.2.fill"
        case .coworker: return "briefcase.fill"
        case .child:    return "figure.child"
        case .parent:   return "figure.stand"     // BUG 2 FIX
        case .other:    return "person.crop.circle"
        }
    }
}
