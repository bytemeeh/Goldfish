import XCTest
import SwiftData
@testable import Goldfish

@MainActor
final class ResetTests: XCTestCase {

    var manager: GoldfishDataManager!

    override func setUp() async throws {
        manager = try makeTestManager()
    }

    func testResetAllData() throws {
        // Given
        try manager.createPerson(name: "Me", isMe: true)
        try manager.createPerson(name: "Friend", isDemo: true)
        try manager.createPerson(name: "Manual")
        
        let countBefore = try manager.fetchPersonCount()
        XCTAssertEqual(countBefore, 3)

        // When
        try manager.resetAllData()

        // Then
        let countAfter = try manager.fetchPersonCount()
        XCTAssertEqual(countAfter, 0)
    }

    func testManualContactDetection() throws {
        // Given
        try manager.createPerson(name: "Me", isMe: true)
        try manager.createPerson(name: "Demo 1", isDemo: true)
        try manager.createPerson(name: "Demo 2", isDemo: true)
        
        // When
        let manualCountBase = try manager.fetchManualContactsCount()
        
        // Then
        XCTAssertEqual(manualCountBase, 0, "Only Me and Demo contacts should not count as manual")
        
        // Given
        try manager.createPerson(name: "Manual 1")
        try manager.createPerson(name: "Manual 2")
        
        // When
        let manualCountExtra = try manager.fetchManualContactsCount()
        
        // Then
        XCTAssertEqual(manualCountExtra, 2, "Should detect 2 manual contacts")
    }
}
