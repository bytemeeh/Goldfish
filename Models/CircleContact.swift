import Foundation
import SwiftData

// MARK: - CircleContact
/// Junction table linking a `Person` to a `GoldfishCircle`.
///
/// **Single pond invariant:** Each contact may belong to at most one circle
/// at a time. Adding a contact to a new circle removes existing memberships.
///
/// **Manual exclusion guard:**
/// When `manuallyExcluded` is `true`, the auto-assignment logic will NOT
/// re-add this contact to the circle, even if a matching relationship exists.
/// This flag is set when a user explicitly removes a contact from a system circle.
///
/// For custom (non-system) circles, removal simply deletes the `CircleContact`
/// row — no exclusion tracking is needed.
@Model
final class CircleContact {

    @Attribute(.unique)
    var id: UUID

    /// The circle this membership belongs to.
    var circle: GoldfishCircle

    /// The contact who is a member of the circle.
    var contact: Person

    /// When `true`, prevents auto-re-addition after manual removal from a system circle.
    /// For custom circles this is always `false` (removal deletes the row entirely).
    var manuallyExcluded: Bool

    // MARK: - Timestamps

    var createdAt: Date

    // MARK: - Init

    init(
        id: UUID = UUID(),
        circle: GoldfishCircle,
        contact: Person,
        manuallyExcluded: Bool = false
    ) {
        self.id = id
        self.circle = circle
        self.contact = contact
        self.manuallyExcluded = manuallyExcluded
        self.createdAt = Date()
    }
}
