import Foundation
import SwiftData

// MARK: - Model Container Configuration
/// Centralized factory for creating the SwiftData `ModelContainer`.
///
/// Production uses local storage. No CloudKit capability is enabled in this build.
enum GoldfishModelContainer {

    /// All model types in the Goldfish schema.
    /// Register these in a single `Schema` to ensure SwiftData
    /// discovers all relationships correctly.
    static let schema = Schema([
        Person.self,
        Relationship.self,
        Location.self,
        GoldfishCircle.self,
        CircleContact.self
    ])

    /// Creates the production container with local-only storage.
    ///
    /// - Returns: A configured `ModelContainer`.
    static func production(
        cloudKitIdentifier: String = "iCloud.com.goldfish.app"
    ) throws -> ModelContainer {
        let config = ModelConfiguration(
            schema: schema,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    static var localStoreURL: URL {
        ModelConfiguration(schema: schema, cloudKitDatabase: .none).url
    }

    /// Creates an in-memory container for SwiftUI previews.
    /// No CloudKit, no disk writes.
    static func preview() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Creates an in-memory container for unit tests.
    /// Identical to preview but named separately for clarity.
    static func testing() throws -> ModelContainer {
        try preview()
    }
}
