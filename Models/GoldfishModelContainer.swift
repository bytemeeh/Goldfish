import SwiftData

// MARK: - Model Container Configuration
/// Centralized factory for creating the SwiftData `ModelContainer`.
///
/// **Production:** Uses CloudKit sync via `cloudKitContainerIdentifier`.
/// All models sync automatically — no custom sync logic required.
/// Merge conflicts use CloudKit's "latest wins" strategy.
///
/// **Previews / Tests:** Uses in-memory storage with no CloudKit.
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
    /// **CloudKit is currently disabled for local development.**
    /// To re-enable, uncomment the `cloudKitDatabase` line and restore
    /// the iCloud entitlements in `Goldfish.entitlements`.
    ///
    /// - Returns: A configured `ModelContainer`.
    static func production(
        cloudKitIdentifier: String = "iCloud.com.goldfish.app"
    ) throws -> ModelContainer {
        let config = ModelConfiguration(
            schema: schema
            // CloudKit sync (re-enable when signing is configured):
            // cloudKitDatabase: .private(cloudKitIdentifier)
        )
        return try ModelContainer(for: schema, configurations: [config])
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
