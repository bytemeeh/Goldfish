import Foundation

// MARK: - LocationType
/// The category of a physical location associated with a contact.
enum LocationType: String, Codable, CaseIterable, Identifiable {
    case home
    case work
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .home:  return "Home"
        case .work:  return "Work"
        case .other: return "Other"
        }
    }

}
