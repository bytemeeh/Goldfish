import XCTest
import SwiftData
@testable import Goldfish

// MARK: - Test Helpers
@MainActor
func makeTestContainerForVCard() throws -> ModelContainer {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let schema = Schema([
        Person.self,
        Relationship.self,
        Location.self,
        GoldfishCircle.self,
        CircleContact.self
    ])
    return try ModelContainer(for: schema, configurations: [config])
}

// MARK: - VCard Tests
final class VCardTests: XCTestCase {
    
    // MARK: - Exporter & Parser Tests
    
    func testRoundTrip() throws {
        // 1. Create Source Person
        let id = UUID()
        let source = Person(
            id: id,
            name: "Marcel Meeh",
            phone: "+49123456789",
            email: "marcel@example.com",
            birthday: Date(timeIntervalSince1970: 0), // 1970-01-01
            notes: "Likes coding;\nand \"swift\"",
            isFavorite: true,
            tags: ["dev", "ios, swift"], // Comma inside tag
            color: "#FF0000",
            street: "Musterstr. 1",
            city: "Berlin",
            country: "Germany"
        )
        
        // 2. Export
        let vCardData: Data = VCardExporter.export([source])
        let vCardString: String = String(data: vCardData, encoding: .utf8)!
        
        // Verify some raw string properties
        XCTAssertTrue(vCardString.contains("FN:Marcel Meeh"))
        XCTAssertTrue(vCardString.contains("X-GOLDFISH-TAGS:dev,ios\\, swift")) // Escaped comma
        XCTAssertTrue(vCardString.contains("NOTE:Likes coding\\;\\nand \"swift\"")) // Escaped chars
        
        // 3. Parse
        let parsed = VCardParser.parse(vCardData)
        XCTAssertEqual(parsed.count, 1)
        let result = parsed.first!
        
        // 4. Verify Fields
        XCTAssertEqual(result.uid, id)
        XCTAssertEqual(result.name, "Marcel Meeh")
        XCTAssertEqual(result.phone, "+49123456789")
        XCTAssertEqual(result.email, "marcel@example.com")
        XCTAssertEqual(result.isFavorite, true)
        XCTAssertEqual(result.color, "#FF0000")
        XCTAssertEqual(result.tags.count, 2)
        XCTAssertTrue(result.tags.contains("dev"))
        XCTAssertTrue(result.tags.contains("ios, swift")) // Unescaped
        XCTAssertEqual(result.notes, "Likes coding;\nand \"swift\"") // Unescaped
        
        // Check formatted address components
        XCTAssertEqual(result.street, "Musterstr. 1")
        XCTAssertEqual(result.city, "Berlin")
        XCTAssertEqual(result.country, "Germany")
        
        // Verify formatted birthday string (YYYY-MM-DD)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let expectedDate = formatter.string(from: Date(timeIntervalSince1970: 0))
        let actualDate = formatter.string(from: result.birthday!)
        XCTAssertEqual(actualDate, expectedDate)
    }
    
    func testLineFolding() throws {
        // Create a really long note
        let longNote = String(repeating: "A", count: 200)
        let person = Person(name: "Long Note", notes: longNote)
        
        let vCardData: Data = VCardExporter.export([person])
        let vCardString: String = String(data: vCardData, encoding: .utf8)!
        
        // Verify folding (CRLF space)
        XCTAssertTrue(vCardString.contains("\r\n "))
        
        // Verify parsing restores it
        let parsed = VCardParser.parse(vCardData)
        XCTAssertEqual(parsed.first?.notes, longNote)
    }
    
    func testMultiContactFile() throws {
        let p1 = Person(name: "Person One")
        let p2 = Person(name: "Person Two")
        
        // Manually concatenate
        let data1 = VCardExporter.export([p1])
        let data2 = VCardExporter.export([p2])
        var combinedData = data1
        combinedData.append(data2)
        
        let parsed = VCardParser.parse(combinedData)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertTrue(parsed.contains { $0.name == "Person One" })
        XCTAssertTrue(parsed.contains { $0.name == "Person Two" })
    }
    
    func testMalformedVCard() throws {
        // vCard without FN/Name should be skipped
        let malformed = """
        BEGIN:VCARD
        VERSION:3.0
        EMAIL:anon@example.com
        END:VCARD
        """
        
        let data = malformed.data(using: .utf8)!
        let parsed = VCardParser.parse(data)
        XCTAssertEqual(parsed.count, 0)
    }
    
    // MARK: - Goldfish Manifest Tests
    
    func testGoldfishManifestExport() throws {
        // Export with manifest enabled
        let p1 = Person(name: "Alice")
        let p2 = Person(name: "Bob")
        
        let data = VCardExporter.export([p1, p2], includeManifest: true)
        let vCardString = String(data: data, encoding: .utf8)!
        
        // Verify manifest is present
        XCTAssertTrue(vCardString.contains("FN:_GOLDFISH_MANIFEST"))
        XCTAssertTrue(vCardString.contains("X-GOLDFISH-EXPORT-VERSION:1.0"))
        XCTAssertTrue(vCardString.contains("X-GOLDFISH-EXPORT-DATE:"))
        XCTAssertTrue(vCardString.contains("X-GOLDFISH-EXPORT-COUNT:2"))
        XCTAssertTrue(vCardString.contains("X-GOLDFISH-EXPORT-CONNECTIONS:0")) // No relationships
    }
    
    func testGoldfishManifestDetection() throws {
        // Export with manifest, then parse
        let p1 = Person(name: "Alice")
        let data = VCardExporter.export([p1], includeManifest: true)
        
        let result = VCardParser.parseWithManifest(data)
        
        // Manifest should be detected
        XCTAssertTrue(result.isGoldfishFormat)
        XCTAssertNotNil(result.manifest)
        XCTAssertEqual(result.manifest?.version, "1.0")
        XCTAssertEqual(result.manifest?.contactCount, 1)
        XCTAssertEqual(result.manifest?.connectionCount, 0)
        XCTAssertNotNil(result.manifest?.exportDate)
        
        // Manifest should NOT appear in contacts list
        XCTAssertEqual(result.contacts.count, 1)
        XCTAssertEqual(result.contacts.first?.name, "Alice")
    }
    
    func testPlainVCardNoManifest() throws {
        // A plain vCard without Goldfish extensions
        let plain = """
        BEGIN:VCARD
        VERSION:3.0
        FN:John Doe
        TEL:+1234567890
        END:VCARD
        """
        
        let data = plain.data(using: .utf8)!
        let result = VCardParser.parseWithManifest(data)
        
        // No manifest
        XCTAssertFalse(result.isGoldfishFormat)
        XCTAssertNil(result.manifest)
        
        // Contact still parsed
        XCTAssertEqual(result.contacts.count, 1)
        XCTAssertEqual(result.contacts.first?.name, "John Doe")
    }
    
    func testExportWithoutManifest() throws {
        // Default export (no manifest) should not contain manifest
        let p1 = Person(name: "Alice")
        let data = VCardExporter.export([p1]) // includeManifest defaults to false
        let vCardString = String(data: data, encoding: .utf8)!
        
        XCTAssertFalse(vCardString.contains("_GOLDFISH_MANIFEST"))
    }
    
    // MARK: - Import Service Tests
    
    @MainActor
    func testDuplicateDetection() async throws {
        let container = try makeTestContainerForVCard()
        let context = container.mainContext
        let service = VCardImportService(modelContainer: container)
        
        // 1. Existing person in DB
        let existing = Person(name: "Alice", email: "alice@example.com")
        context.insert(existing)
        try context.save()
        let originalID = existing.id
        
        // 2. Import same person (same Name + Email) with a different UUID
        let vCard = """
        BEGIN:VCARD
        VERSION:3.0
        UID:\(UUID().uuidString)
        FN:Alice
        N:;Alice;;;
        EMAIL;TYPE=INTERNET:alice@example.com
        END:VCARD
        """
        
        let result = try await service.importContacts(vCard.data(using: .utf8)!) { _ in }
        
        // 3. Verify Skipped
        XCTAssertEqual(result.importedCount, 0)
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertEqual(result.skippedDuplicates, ["Alice"])
        
        // Verify DB still has only 1 Alice
        let cnt = try context.fetchCount(FetchDescriptor<Person>())
        XCTAssertEqual(cnt, 1)
        
        let remaining = try context.fetch(FetchDescriptor<Person>()).first!
        XCTAssertEqual(remaining.id, originalID)
    }
    
    @MainActor
    func testRelationshipResolution() async throws {
        let container = try makeTestContainerForVCard()
        let service = VCardImportService(modelContainer: container)
        
        // Create 2 people: Mom and Son
        let momID = UUID()
        let sonID = UUID()
        
        let momCard = """
        BEGIN:VCARD
        VERSION:3.0
        UID:\(momID.uuidString)
        FN:Mom
        N:;Mom;;;
        X-GOLDFISH-RELATED-TO:\(sonID.uuidString);mother
        END:VCARD
        """
        
        let sonCard = """
        BEGIN:VCARD
        VERSION:3.0
        UID:\(sonID.uuidString)
        FN:Son
        N:;Son;;;
        X-GOLDFISH-RELATED-TO:\(momID.uuidString);child
        END:VCARD
        """
        
        let combined = momCard + "\n" + sonCard
        
        // Import
        let result = try await service.importContacts(combined.data(using: .utf8)!) { _ in }
        
        XCTAssertEqual(result.importedCount, 2)
        
        // Verify Relationship — inverse deduplication should produce exactly 1 row
        let context = container.mainContext
        let relationships = try context.fetch(FetchDescriptor<Relationship>())
        
        // With the inverse dedup fix:
        // Mom says: I am mother of Son -> Creates Relationship(Mom, Son, mother)
        // Son says: I am child of Mom -> Detects inverse (mother<->child) already exists, skips
        XCTAssertEqual(relationships.count, 1, "Inverse relationships should be deduplicated to a single row")
        
        // Verify the connection stats
        XCTAssertEqual(result.connectionsRestored, 1)
        XCTAssertEqual(result.connectionsSkipped, 1) // The inverse was skipped
    }
    
    @MainActor
    func testGoldfishFormatImportResult() async throws {
        let container = try makeTestContainerForVCard()
        let service = VCardImportService(modelContainer: container)
        
        // Create a Goldfish-format file with manifest
        let p1 = Person(name: "Test Person")
        let data = VCardExporter.export([p1], includeManifest: true)
        
        let result = try await service.importContacts(data) { _ in }
        
        // Should detect Goldfish format
        XCTAssertTrue(result.isGoldfishFormat)
        XCTAssertEqual(result.goldfishVersion, "1.0")
        XCTAssertEqual(result.importedCount, 1)
    }
    
    @MainActor
    func testPlainVCardImportResult() async throws {
        let container = try makeTestContainerForVCard()
        let service = VCardImportService(modelContainer: container)
        
        // A plain vCard without Goldfish extensions
        let plain = """
        BEGIN:VCARD
        VERSION:3.0
        FN:Jane Plain
        TEL:+9876543210
        END:VCARD
        """
        
        let result = try await service.importContacts(plain.data(using: .utf8)!) { _ in }
        
        // Should NOT detect Goldfish format
        XCTAssertFalse(result.isGoldfishFormat)
        XCTAssertNil(result.goldfishVersion)
        XCTAssertEqual(result.importedCount, 1)
        XCTAssertEqual(result.connectionsRestored, 0)
    }
}
