import Foundation
import SwiftData

// MARK: - Location
/// A physical location associated with a contact.
///
/// One-to-many: a `Person` can have many locations (home, work, etc.).
/// The first location added (or the one marked `isPrimary`) is used as the
/// default in map views and address display.
///
/// Latitude and longitude are optional — a location can be address-only
/// until the user geocodes it or drops a pin.
@Model
final class Location {

    @Attribute(.unique)
    var id: UUID

    /// The contact this location belongs to.
    var contact: Person

    /// Raw storage for the location type enum.
    var typeRawValue: String

    /// User-facing label (e.g., "Home Office", "Grandma's House").
    var name: String?

    /// Full street address as a single string.
    var address: String?

    /// Geographic coordinates for MapKit display.
    var latitude: Double?
    var longitude: Double?

    /// Whether this is the primary/default location for the contact.
    var isPrimary: Bool

    // MARK: - Timestamps

    var createdAt: Date

    // MARK: - Init

    init(
        id: UUID = UUID(),
        contact: Person,
        type: LocationType = .home,
        name: String? = nil,
        address: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        isPrimary: Bool = false
    ) {
        self.id = id
        self.contact = contact
        self.typeRawValue = type.rawValue
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.isPrimary = isPrimary
        self.createdAt = Date()
    }

    // MARK: - Computed

    /// The typed location category, decoded from the stored raw value.
    var type: LocationType {
        get { LocationType(rawValue: typeRawValue) ?? .other }
        set { typeRawValue = newValue.rawValue }
    }

    /// Whether this location has valid coordinates for map display.
    var hasCoordinates: Bool {
        latitude != nil && longitude != nil
    }

    /// Display label: user-given name, or the type name as fallback.
    var displayName: String {
        name ?? type.displayName
    }
}
