import XCTest
import SwiftData
@testable import Goldfish

@MainActor
final class RelationshipContextServiceTests: XCTestCase {
    @discardableResult
    private func connect(
        _ from: Person,
        _ to: Person,
        as type: RelationshipType,
        primary: Bool = false
    ) -> Relationship {
        let relationship = Relationship(from: from, to: to, type: type, isPrimary: primary)
        from.outgoingRelationships.append(relationship)
        to.incomingRelationships.append(relationship)
        return relationship
    }

    func testDirectSummaryUsesTrueDirectionAndGenericSiblingLabel() {
        let me = Person(name: "Me", isMe: true)
        let mother = Person(name: "Ada")
        let child = Person(name: "Leo")
        let sibling = Person(name: "Sam")
        connect(mother, me, as: .mother)
        connect(me, child, as: .parent)
        connect(sibling, me, as: .sibling)

        let service = RelationshipContextService(people: [me, mother, child, sibling])
        XCTAssertEqual(service.summary(for: mother), "Your mother")
        XCTAssertEqual(service.summary(for: child), "Your child")
        XCTAssertEqual(service.summary(for: sibling), "Your sibling")
    }

    func testPrimaryRoleLeadsAndEveryDistinctAdditionalRoleAppears() {
        let me = Person(name: "Me", isMe: true)
        let alex = Person(name: "Alex")
        connect(alex, me, as: .mother)
        connect(alex, me, as: .coworker)
        connect(alex, me, as: .friend, primary: true)
        connect(alex, me, as: .friend)

        let context = RelationshipContextService(people: [me, alex]).context(for: alex)
        XCTAssertEqual(context?.summary, "Your friend, mother, and coworker")
        guard case .direct(let primary, let additional)? = context?.connection else {
            return XCTFail("Expected a direct relationship context")
        }
        XCTAssertEqual(primary, .friend)
        XCTAssertEqual(additional, [.mother, .coworker])
    }

    func testIndirectSummaryUsesDeterministicFirstHopAndHonorsScope() {
        let me = Person(name: "Me", isMe: true)
        let david = Person(name: "David")
        let zara = Person(name: "Zara")
        connect(me, david, as: .friend)
        connect(zara, david, as: .sibling)

        let service = RelationshipContextService(people: [me, david, zara])
        XCTAssertEqual(service.summary(for: zara), "Connected through David")
        XCTAssertEqual(service.compactSummary(for: zara), "Through David")
        XCTAssertNil(RelationshipContextService(people: [me, zara]).summary(for: zara))
    }

    func testPetAndPondDescriptionsAreSafeAndIndependent() {
        let me = Person(name: "Me", isMe: true)
        let dog = Person(name: "Milo", petKindRaw: ContactKind.dog.rawValue)
        let unlinked = Person(name: "Robin")
        connect(dog, me, as: .pet)

        let pond = GoldfishCircle(name: "Book Club")
        let membership = CircleContact(circle: pond, contact: unlinked)
        pond.circleContacts.append(membership)
        unlinked.circleContacts.append(membership)

        let service = RelationshipContextService(people: [me, dog, unlinked])
        XCTAssertEqual(service.summary(for: dog), "Your dog")
        XCTAssertNil(service.summary(for: unlinked))
        XCTAssertEqual(service.pondSummary(for: unlinked), "Pond: Book Club")
    }
}

@MainActor
final class ContactMemoryTests: XCTestCase {
    func testAppendingMemoryPreservesExistingNoteVerbatim() {
        let existing = "  Likes quiet cafés.  \nSecond line with spacing. "
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let result = ContactDetailViewModel.notesByAppendingMemory(
            "  Asked about the new job.  ",
            to: existing,
            date: date
        )

        XCTAssertTrue(result?.hasPrefix(existing) == true)
        XCTAssertTrue(result?.hasSuffix(" — Asked about the new job.") == true)
    }

    func testAddingMemoryPersistsWithoutReplacingExistingNotes() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let person = try manager.createPerson(name: "Alex", notes: "Original note")
        let model = ContactDetailViewModel(person: person, dataManager: manager)

        XCTAssertTrue(model.addMemory("Follow up next week", date: Date(timeIntervalSince1970: 1_800_000_000)))
        XCTAssertTrue(person.notes?.hasPrefix("Original note\n\n") == true)
        XCTAssertTrue(person.notes?.hasSuffix(" — Follow up next week") == true)
    }
}

@MainActor
final class ContactQuickFormTests: XCTestCase {
    func testQuickFormSavesNameConnectionAndMemoryTogether() throws {
        let (manager, container) = try makeTestManager()
        defer { withExtendedLifetime(container) {} }
        let me = try manager.createPerson(name: "Me", isMe: true)
        let model = ContactFormViewModel(dataManager: manager, isDemoMode: false)
        model.firstName = "Taylor"
        model.lastName = "Reed"
        model.selectedConnectionID = me.id
        model.selectedRelationshipType = .sibling
        model.notes = "Met for lunch"

        XCTAssertEqual(model.relationshipPreview, "This saves: Taylor Reed is Me’s sibling.")
        XCTAssertTrue(model.save())

        let saved = try XCTUnwrap(try manager.fetchAllPersons().first { $0.name == "Taylor Reed" })
        XCTAssertEqual(saved.notes, "Met for lunch")
        let relationship = try XCTUnwrap(saved.allRelationships.first { $0.otherContact(from: saved).id == me.id })
        XCTAssertEqual(relationship.effectiveType(for: saved), .sibling)
    }
}
