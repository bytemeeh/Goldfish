import XCTest
import SwiftData
@testable import Goldfish

@MainActor
final class TransferIntegrityTests: XCTestCase {
    func testCircleNameFeedbackAllowsDuplicatesButRejectsInvalidInput() throws {
        let container = try makeTestContainerForVCard()
        let manager = GoldfishDataManager(context: container.mainContext)
        let existing = try manager.createCircle(name: "Family")
        let viewModel = CircleManagerViewModel(dataManager: manager)

        if case .invalid = viewModel.nameFeedback("   ") {} else { XCTFail("Whitespace-only names must be invalid") }
        if case .invalid = viewModel.nameFeedback("Line\nBreak") {} else { XCTFail("Control characters must be invalid") }
        if case .duplicate = viewModel.nameFeedback(" family ") {} else { XCTFail("Duplicate names should warn") }
        XCTAssertFalse(viewModel.nameFeedback(" family ", excluding: existing).preventsSave)
        let longName = String(repeating: "x", count: 61)
        if case .advisory = viewModel.nameFeedback(longName) {} else { XCTFail("Long names should be advisory") }
        let existingLong = try manager.createCircle(name: longName)
        viewModel.loadCircles()
        XCTAssertFalse(viewModel.nameFeedback(longName, excluding: existingLong).preventsSave)
    }

    func testExportScopeIncludesDirectPeopleButNeverExpandsToMe() throws {
        let container = try makeTestContainerForVCard()
        let manager = GoldfishDataManager(context: container.mainContext)
        let me = try manager.createPerson(name: "Me", isMe: true)
        let selected = try manager.createPerson(name: "Selected")
        let neighbor = try manager.createPerson(name: "Neighbor")
        try manager.createRelationship(from: selected, to: neighbor, type: .friend)

        let rootsOnly = ContactExportScope.entries(eligibleContacts: [me, selected, neighbor], selectedIDs: [selected.id], includeConnections: false)
        XCTAssertEqual(rootsOnly.map(\.contact.id), [selected.id])
        let expanded = ContactExportScope.entries(eligibleContacts: [me, selected, neighbor], selectedIDs: [selected.id], includeConnections: true)
        XCTAssertEqual(Set(expanded.map(\.contact.id)), [selected.id, neighbor.id])
        XCTAssertEqual(expanded.first { $0.contact.id == neighbor.id }?.reason, .directConnection)
    }

    func testSettingsImportOutcomeAndDetailsAreBounded() {
        let viewModel = SettingsViewModel()

        viewModel.lastImportResult = ImportResult(importedCount: 1, skippedCount: 1, errors: ["Malformed note"])
        XCTAssertEqual(viewModel.importOutcome, .partial)
        XCTAssertEqual(viewModel.importAlertTitle, "Import Partially Complete")

        var duplicateResult = ImportResult(skippedCount: 7)
        duplicateResult.skippedDuplicates = (1...7).map { "Person \($0)" }
        duplicateResult.errors = (1...6).map { "Issue \($0)" }
        viewModel.lastImportResult = duplicateResult
        XCTAssertEqual(viewModel.importOutcome, .partial)
        XCTAssertEqual(viewModel.importDetailLines.count, 10)
        XCTAssertEqual(viewModel.importDetailOverflowCount, 3)

        duplicateResult.errors = []
        viewModel.lastImportResult = duplicateResult
        XCTAssertEqual(viewModel.importOutcome, .alreadyHere)
        viewModel.lastImportResult = ImportResult()
        XCTAssertEqual(viewModel.importOutcome, .noContactsFound)
        viewModel.lastImportResult = ImportResult(errors: ["No valid contacts found"])
        XCTAssertEqual(viewModel.importOutcome, .couldNotRead)
    }

    func testCustomGroupsRestoreBeforeAutoAssignmentAndRetainDuplicateNames() async throws {
        let source = try makeTestContainerForVCard()
        let manager = GoldfishDataManager(context: source.mainContext)
        try manager.createSystemCircles()
        let a = try manager.createPerson(name: "A"), b = try manager.createPerson(name: "B")
        let first = try manager.createCircle(name: "Same", color: "#123456")
        let second = try manager.createCircle(name: "Same", color: "#ABCDEF")
        try manager.addToCircle(a, circle: first)
        try manager.addToCircle(b, circle: second)
        try manager.createRelationship(from: a, to: b, type: .friend)
        let data = VCardExporter.export([a,b], includeManifest: true)

        let destination = try makeTestContainerForVCard()
        try GoldfishDataManager(context: destination.mainContext).createSystemCircles()
        let importer = VCardImportService(modelContainer: destination)
        _ = try await importer.importContacts(data, progressHandler: { _ in })
        let context = ModelContext(destination)
        let people = try context.fetch(FetchDescriptor<Person>())
        XCTAssertEqual(people.first { $0.id == a.id }?.primaryCircle?.id, first.id)
        XCTAssertEqual(people.first { $0.id == b.id }?.primaryCircle?.id, second.id)
        XCTAssertEqual(people.first { $0.id == b.id }?.primaryCircle?.color, second.color)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Relationship>()).count, 1)
    }

    func testChildFirstImportRetainsSpecificParentRoleAndOtherRelationship() async throws {
        let source = try makeTestContainerForVCard()
        let manager = GoldfishDataManager(context: source.mainContext)
        let parent = try manager.createPerson(name: "Mother"), child = try manager.createPerson(name: "Child")
        try manager.createRelationship(from: parent, to: child, type: .mother)
        try manager.createRelationship(from: parent, to: child, type: .other)
        let data = VCardExporter.export([child,parent])
        let destination = try makeTestContainerForVCard()
        _ = try await VCardImportService(modelContainer: destination).importContacts(data, progressHandler: { _ in })
        let relationships = try ModelContext(destination).fetch(FetchDescriptor<Relationship>())
        XCTAssertEqual(relationships.count, 2)
        let mother = try XCTUnwrap(relationships.first { $0.type == .mother })
        XCTAssertEqual(mother.fromContact.id, parent.id)
        XCTAssertEqual(mother.toContact.id, child.id)
        XCTAssertEqual(relationships.filter { $0.type == .other }.count, 1)
    }

    func testChildFirstImportUsesFriendHouseholdContext() async throws {
        let source = try makeTestContainerForVCard()
        let manager = GoldfishDataManager(context: source.mainContext)
        let me = try manager.createPerson(name: "Me", isMe: true)
        let jake = try manager.createPerson(name: "Jake")
        let nicole = try manager.createPerson(name: "Nicole")
        let child = try manager.createPerson(name: "Child")
        try manager.createRelationship(from: me, to: jake, type: .friend, skipAutoAssign: true)
        try manager.createRelationship(from: jake, to: nicole, type: .spouse, skipAutoAssign: true)
        try manager.createRelationship(from: nicole, to: child, type: .parent, skipAutoAssign: true)
        let data = VCardExporter.export([child, nicole, jake, me])

        let destination = try makeTestContainerForVCard()
        try GoldfishDataManager(context: destination.mainContext).createSystemCircles()
        _ = try await VCardImportService(modelContainer: destination).importContacts(data, progressHandler: { _ in })
        let people = try ModelContext(destination).fetch(FetchDescriptor<Person>())
        XCTAssertEqual(people.count, 4)
        XCTAssertTrue(people.filter { !$0.isMe }.allSatisfy { $0.primaryCircle?.name == "Friends" })
        XCTAssertNil(people.first { $0.isMe }?.primaryCircle)
    }

    func testCancelledImportDoesNotPersistContacts() async throws {
        let destination = try makeTestContainerForVCard()
        let data = VCardExporter.export([Person(name: "Must not persist")])
        let importer = VCardImportService(modelContainer: destination)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await importer.importContacts(data, progressHandler: { _ in })
        }
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
        XCTAssertTrue(try ModelContext(destination).fetch(FetchDescriptor<Person>()).isEmpty)
    }
}
