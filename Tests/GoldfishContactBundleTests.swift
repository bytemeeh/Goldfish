import XCTest
import SwiftData
@testable import Goldfish

@MainActor
final class GoldfishContactBundleTests: XCTestCase {
    func testReceivingAnExistingSampleContactMakesItVisibleOutsideSampleMode() throws {
        let source = try makeTestContainerForVCard()
        let person = Person(name: "Shared sample", isDemo: true)
        source.mainContext.insert(person); try source.mainContext.save()
        let data = try GoldfishContactBundle.export(contacts: [person])
        let destination = try makeTestContainerForVCard()
        let existing = Person(id: person.id, name: "Shared sample", isDemo: true)
        destination.mainContext.insert(existing); try destination.mainContext.save()
        _ = try GoldfishContactBundle.importData(data, into: destination.mainContext)
        XCTAssertFalse(existing.isDemo)
    }

    func testOwnShareReusesMeAndSystemPondWithoutChangingIdentity() throws {
        let container = try makeTestContainerForVCard()
        let manager = GoldfishDataManager(context: container.mainContext)
        let me = try manager.createPerson(name: "Recipient", isMe: true)
        let friend = try manager.createPerson(name: "Friend")
        let pond = GoldfishCircle(name: "Friends", isSystem: true)
        container.mainContext.insert(pond)
        try manager.addToCircle(friend, circle: pond)
        try manager.createRelationship(from: me, to: friend, type: .friend, skipAutoAssign: true)
        let data = try GoldfishContactBundle.export(contacts: [me, friend])
        let result = try GoldfishContactBundle.importData(data, into: container.mainContext)
        XCTAssertEqual(result.addedPeople, 0)
        XCTAssertEqual(result.reusedPeople, 2)
        XCTAssertEqual(result.pondsAdded, 0)
        XCTAssertEqual(result.connectionsAdded, 0)
        XCTAssertTrue(me.isMe)
        XCTAssertEqual(friend.primaryCircle?.id, pond.id)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Person>()).filter(\.isMe).count, 1)
    }

    func testImportRefinesAnExistingGenericParentRole() throws {
        let source = try makeTestContainerForVCard()
        let parent = Person(name: "Parent")
        let child = Person(name: "Child")
        source.mainContext.insert(parent); source.mainContext.insert(child)
        let sharedFather = Relationship(from: parent, to: child, type: .father)
        source.mainContext.insert(sharedFather)
        parent.outgoingRelationships.append(sharedFather); child.incomingRelationships.append(sharedFather)
        try source.mainContext.save()
        let data = try GoldfishContactBundle.export(contacts: [parent, child])

        let destination = try makeTestContainerForVCard()
        let existingParent = Person(id: parent.id, name: "Parent")
        let existingChild = Person(id: child.id, name: "Child")
        destination.mainContext.insert(existingParent); destination.mainContext.insert(existingChild)
        let genericChild = Relationship(from: existingChild, to: existingParent, type: .child)
        destination.mainContext.insert(genericChild)
        existingChild.outgoingRelationships.append(genericChild); existingParent.incomingRelationships.append(genericChild)
        try destination.mainContext.save()

        let result = try GoldfishContactBundle.importData(data, into: destination.mainContext)

        XCTAssertEqual(result.connectionsAdded, 0)
        XCTAssertEqual(try destination.mainContext.fetch(FetchDescriptor<Relationship>()).count, 1)
        XCTAssertEqual(genericChild.type, .father)
        XCTAssertEqual(genericChild.fromContact.id, parent.id)
        XCTAssertEqual(genericChild.toContact.id, child.id)
    }

    func testAncestryLoopRollsBackWholeImport() throws {
        let source = try makeTestContainerForVCard()
        let a = Person(name: "A"), b = Person(name: "B")
        source.mainContext.insert(a); source.mainContext.insert(b)
        for (from, to) in [(a, b), (b, a)] {
            let relationship = Relationship(from: from, to: to, type: .parent)
            source.mainContext.insert(relationship)
            from.outgoingRelationships.append(relationship)
            to.incomingRelationships.append(relationship)
        }
        try source.mainContext.save()
        let data = try GoldfishContactBundle.export(contacts: [a, b])
        let destination = try makeTestContainerForVCard()
        XCTAssertThrowsError(try GoldfishContactBundle.importData(data, into: destination.mainContext))
        XCTAssertTrue(try ModelContext(destination).fetch(FetchDescriptor<Person>()).isEmpty)
        XCTAssertTrue(try ModelContext(destination).fetch(FetchDescriptor<Relationship>()).isEmpty)
    }

    func testTransferKeepsSelectedGraphFieldsPondsAndRecipientMeSeparate() throws {
        let source = try makeTestContainerForVCard()
        let sourceManager = GoldfishDataManager(context: source.mainContext)
        try sourceManager.createSystemCircles()
        let adriana = Person(name: "Adriana", phone: "+1 555 0100", email: "adriana@example.com",
                             birthday: Date(timeIntervalSince1970: 1_000_000), notes: "Likes jasmine tea",
                             isFavorite: true, tags: ["school", "neighbor"], color: "#123456",
                             photoData: Data([1, 2, 3]), street: "10 Lake Rd", city: "Zurich",
                             state: "ZH", country: "Switzerland", postalCode: "8000")
        let riley = Person(name: "Riley", isMe: true)
        let zach = Person(name: "Zach")
        let aaron = Person(name: "Aaron")
        let selma = Person(name: "Selma")
        let outsider = Person(name: "Outsider")
        let meNeighbor = Person(name: "Riley's other contact")
        for person in [adriana, riley, zach, aaron, selma, outsider, meNeighbor] { source.mainContext.insert(person) }
        let home = Location(contact: adriana, type: .home, name: "Lake house", address: "10 Lake Rd",
                            latitude: 47.3769, longitude: 8.5417, isPrimary: true)
        source.mainContext.insert(home); adriana.locations.append(home)
        let friend = Relationship(from: adriana, to: riley, type: .friend, isPrimary: true)
        let father = Relationship(from: zach, to: riley, type: .parent, isPrimary: true)
        let mother = Relationship(from: aaron, to: riley, type: .parent)
        let care = Relationship(from: selma, to: adriana, type: .caregiver)
        let outsideLink = Relationship(from: adriana, to: outsider, type: .friend)
        let meSideLink = Relationship(from: riley, to: meNeighbor, type: .friend)
        for relationship in [friend, father, mother, care, outsideLink, meSideLink] {
            source.mainContext.insert(relationship)
            relationship.fromContact.outgoingRelationships.append(relationship)
            relationship.toContact.incomingRelationships.append(relationship)
        }
        let family = GoldfishCircle(name: "Family", color: "#aa0000", emoji: "🏠", desc: "Adriana's family",
                                    isSystem: true, autoRelationshipTypes: [RelationshipType.parent.rawValue])
        source.mainContext.insert(family)
        let daycare = try sourceManager.createCircle(name: "Daycare", color: "#00aa00", emoji: "🧸", desc: "School parents")
        let familyMembership = CircleContact(circle: family, contact: zach, manuallyExcluded: true)
        let daycareMembership = CircleContact(circle: daycare, contact: selma)
        for membership in [familyMembership, daycareMembership] {
            source.mainContext.insert(membership)
            membership.circle.circleContacts.append(membership)
            membership.contact.circleContacts.append(membership)
        }
        try source.mainContext.save()

        let data = try GoldfishContactBundle.export(contacts: [adriana, riley, zach, aaron, selma])
        let preview = try GoldfishContactBundle.preview(data: data)
        XCTAssertEqual(Set(preview.people), ["Adriana", "Riley", "Zach", "Aaron", "Selma"])
        XCTAssertEqual(preview.relationshipsCount, 4, "Links to unselected people must not escape the bundle")
        XCTAssertEqual(Set(preview.ponds), ["Family", "Daycare"])
        XCTAssertTrue(preview.includesNotes)

        let destination = try makeTestContainerForVCard()
        let recipientMe = Person(name: "Recipient Me", isMe: true)
        destination.mainContext.insert(recipientMe)
        let recipientFamily = GoldfishCircle(name: "Family", isSystem: true)
        let recipientDaycare = GoldfishCircle(name: "Daycare", color: "#abcdef", emoji: "🧩", desc: "Recipient's daycare")
        destination.mainContext.insert(recipientFamily)
        destination.mainContext.insert(recipientDaycare)
        try destination.mainContext.save()
        let result = try GoldfishContactBundle.importData(data, into: destination.mainContext)
        XCTAssertEqual(result.addedPeople, 5)
        XCTAssertEqual(result.connectionsAdded, 4)
        XCTAssertEqual(result.pondsAdded, 2)

        let context = ModelContext(destination)
        let imported = try context.fetch(FetchDescriptor<Person>())
        XCTAssertEqual(imported.filter(\.isMe).map(\.id), [recipientMe.id])
        let receivedAdriana = try XCTUnwrap(imported.first { $0.name == "Adriana" })
        XCTAssertEqual(receivedAdriana.phone, adriana.phone)
        XCTAssertEqual(receivedAdriana.email, adriana.email)
        XCTAssertEqual(receivedAdriana.birthday, adriana.birthday)
        XCTAssertEqual(receivedAdriana.notes, adriana.notes)
        XCTAssertEqual(receivedAdriana.tags, ["school", "neighbor"])
        XCTAssertEqual(receivedAdriana.color, "#123456")
        XCTAssertTrue(receivedAdriana.isFavorite)
        XCTAssertEqual(receivedAdriana.photoData, Data([1, 2, 3]))
        XCTAssertEqual(receivedAdriana.street, "10 Lake Rd")
        XCTAssertEqual(receivedAdriana.city, "Zurich")
        XCTAssertEqual(receivedAdriana.state, "ZH")
        XCTAssertEqual(receivedAdriana.country, "Switzerland")
        XCTAssertEqual(receivedAdriana.postalCode, "8000")
        XCTAssertEqual(receivedAdriana.primaryLocation?.id, home.id)
        XCTAssertEqual(receivedAdriana.primaryLocation?.latitude, 47.3769)
        let importedRiley = try XCTUnwrap(imported.first { $0.name == "Riley" })
        XCTAssertFalse(importedRiley.isMe)
        let relationships = try context.fetch(FetchDescriptor<Relationship>())
        XCTAssertEqual(Set(relationships.map(\.type)), [.friend, .parent, .caregiver])
        XCTAssertTrue(relationships.first { $0.type == .friend }!.isPrimary)
        let parentLinks = relationships.filter { $0.type == .parent }
        XCTAssertEqual(Set(parentLinks.map { "\($0.fromContact.name)->\($0.toContact.name)" }),
                       ["Zach->Riley", "Aaron->Riley"])
        XCTAssertTrue(parentLinks.first { $0.fromContact.name == "Zach" }!.isPrimary)
        XCTAssertEqual(relationships.first { $0.type == .caregiver }?.fromContact.name, "Selma")
        XCTAssertEqual(relationships.first { $0.type == .caregiver }?.toContact.name, "Adriana")
        let importedPonds = try context.fetch(FetchDescriptor<GoldfishCircle>())
        let sourceFamily = try XCTUnwrap(importedPonds.first { !$0.isSystem && $0.name == "Family" })
        XCTAssertNotEqual(sourceFamily.id, recipientFamily.id)
        XCTAssertEqual(importedPonds.first { $0.id == recipientFamily.id }?.name, "Family")
        XCTAssertEqual(importedPonds.first { $0.id == recipientDaycare.id }?.desc, "Recipient's daycare")
        let zachCopy = try XCTUnwrap(imported.first { $0.name == "Zach" })
        XCTAssertTrue(zachCopy.circleContacts.first?.manuallyExcluded == true)
        XCTAssertEqual(zachCopy.circleContacts.first?.circle.id, sourceFamily.id)
        let selmaCopy = try XCTUnwrap(imported.first { $0.name == "Selma" })
        XCTAssertEqual(selmaCopy.circleContacts.first?.circle.name, "Daycare")
        XCTAssertFalse(selmaCopy.circleContacts.first?.manuallyExcluded ?? true)
        XCTAssertEqual(imported.first { $0.isMe }?.circleContacts.count, 0)
    }

    func testNotesCanBeOmittedAndRepeatedImportDoesNotDuplicateGraph() throws {
        let source = try makeTestContainerForVCard()
        let first = Person(name: "Adriana", notes: "private note")
        let second = Person(name: "Riley")
        source.mainContext.insert(first); source.mainContext.insert(second)
        let relationship = Relationship(from: first, to: second, type: .friend)
        source.mainContext.insert(relationship)
        first.outgoingRelationships.append(relationship); second.incomingRelationships.append(relationship)
        try source.mainContext.save()
        let data = try GoldfishContactBundle.export(contacts: [first, second], includeNotes: false)
        XCTAssertFalse(try GoldfishContactBundle.preview(data: data).includesNotes)
        let destination = try makeTestContainerForVCard()
        _ = try GoldfishContactBundle.importData(data, into: destination.mainContext)
        let repeated = try GoldfishContactBundle.importData(data, into: destination.mainContext)
        XCTAssertEqual(repeated.addedPeople, 0)
        XCTAssertEqual(repeated.reusedPeople, 2)
        XCTAssertEqual(repeated.connectionsAdded, 0)
        let imported = try ModelContext(destination).fetch(FetchDescriptor<Person>())
        XCTAssertNil(imported.first { $0.name == "Adriana" }?.notes)
        XCTAssertEqual(try ModelContext(destination).fetch(FetchDescriptor<Relationship>()).count, 1)
    }

    func testImportFillsMissingDetailsWithoutReplacingRecipientValues() throws {
        let source = try makeTestContainerForVCard()
        let shared = Person(name: "Adriana", phone: "+1 555 0100", email: "source@example.com", notes: "source note")
        source.mainContext.insert(shared); try source.mainContext.save()
        let data = try GoldfishContactBundle.export(contacts: [shared])
        let destination = try makeTestContainerForVCard()
        let existing = Person(id: shared.id, name: "My Adriana", phone: "my phone", email: nil, notes: "my note")
        destination.mainContext.insert(existing); try destination.mainContext.save()
        let result = try GoldfishContactBundle.importData(data, into: destination.mainContext)
        XCTAssertEqual(result.reusedPeople, 1)
        XCTAssertEqual(existing.name, "My Adriana")
        XCTAssertEqual(existing.phone, "my phone")
        XCTAssertEqual(existing.email, "source@example.com")
        XCTAssertEqual(existing.notes, "my note")
    }

    func testReversedExistingFriendPreventsDuplicateConnection() throws {
        let source = try makeTestContainerForVCard()
        let adriana = Person(name: "Adriana")
        let riley = Person(name: "Riley")
        source.mainContext.insert(adriana); source.mainContext.insert(riley)
        let sentFriend = Relationship(from: adriana, to: riley, type: .friend)
        source.mainContext.insert(sentFriend)
        adriana.outgoingRelationships.append(sentFriend); riley.incomingRelationships.append(sentFriend)
        try source.mainContext.save()
        let data = try GoldfishContactBundle.export(contacts: [adriana, riley])

        let destination = try makeTestContainerForVCard()
        let receivedAdriana = Person(id: adriana.id, name: "Adriana")
        let receivedRiley = Person(id: riley.id, name: "Riley")
        destination.mainContext.insert(receivedAdriana); destination.mainContext.insert(receivedRiley)
        let existingFriend = Relationship(from: receivedRiley, to: receivedAdriana, type: .friend)
        destination.mainContext.insert(existingFriend)
        receivedRiley.outgoingRelationships.append(existingFriend)
        receivedAdriana.incomingRelationships.append(existingFriend)
        try destination.mainContext.save()

        let result = try GoldfishContactBundle.importData(data, into: destination.mainContext)
        XCTAssertEqual(result.connectionsAdded, 0)
        XCTAssertEqual(try ModelContext(destination).fetch(FetchDescriptor<Relationship>()).count, 1)
    }

    func testExistingActivePondWinsWhenIncomingPondSharesSameContactID() throws {
        let source = try makeTestContainerForVCard()
        let shared = Person(name: "Adriana")
        source.mainContext.insert(shared)
        let incomingPond = GoldfishCircle(name: "School")
        source.mainContext.insert(incomingPond)
        let incomingMembership = CircleContact(circle: incomingPond, contact: shared)
        source.mainContext.insert(incomingMembership)
        incomingPond.circleContacts.append(incomingMembership); shared.circleContacts.append(incomingMembership)
        try source.mainContext.save()
        let data = try GoldfishContactBundle.export(contacts: [shared])

        let destination = try makeTestContainerForVCard()
        let existing = Person(id: shared.id, name: "Adriana")
        let recipientPond = GoldfishCircle(name: "Work")
        destination.mainContext.insert(existing); destination.mainContext.insert(recipientPond)
        let recipientMembership = CircleContact(circle: recipientPond, contact: existing)
        destination.mainContext.insert(recipientMembership)
        recipientPond.circleContacts.append(recipientMembership); existing.circleContacts.append(recipientMembership)
        try destination.mainContext.save()

        let result = try GoldfishContactBundle.importData(data, into: destination.mainContext)
        XCTAssertEqual(result.organizationConflicts, 1)
        XCTAssertEqual(existing.primaryCircle?.id, recipientPond.id)
        XCTAssertEqual(existing.circleContacts.count, 1)
        XCTAssertEqual(existing.circleContacts.first?.id, recipientMembership.id)
    }

    func testAllSelectedPeopleRestoreMembershipsInOneSharedPond() throws {
        let source = try makeTestContainerForVCard()
        let people = [Person(name: "Adriana"), Person(name: "Riley"), Person(name: "Zach")]
        people.forEach { source.mainContext.insert($0) }
        let daycare = GoldfishCircle(name: "Daycare")
        source.mainContext.insert(daycare)
        for person in people {
            let row = CircleContact(circle: daycare, contact: person)
            source.mainContext.insert(row); daycare.circleContacts.append(row); person.circleContacts.append(row)
        }
        try source.mainContext.save()
        let data = try GoldfishContactBundle.export(contacts: people)

        let destination = try makeTestContainerForVCard()
        _ = try GoldfishContactBundle.importData(data, into: destination.mainContext)
        let imported = try ModelContext(destination).fetch(FetchDescriptor<Person>())
        let importedPond = try XCTUnwrap(try ModelContext(destination).fetch(FetchDescriptor<GoldfishCircle>()).first)
        XCTAssertEqual(importedPond.name, "Daycare")
        XCTAssertEqual(Set(importedPond.circleContacts.map { $0.contact.name }), Set(["Adriana", "Riley", "Zach"]))
        XCTAssertTrue(imported.allSatisfy { $0.primaryCircle?.id == importedPond.id })
    }

    func testActiveAndExcludedMembershipsForOnePersonBothRestore() throws {
        let source = try makeTestContainerForVCard()
        let person = Person(name: "Selma")
        source.mainContext.insert(person)
        let daycare = GoldfishCircle(name: "Daycare")
        let family = GoldfishCircle(name: "Family")
        source.mainContext.insert(daycare); source.mainContext.insert(family)
        let active = CircleContact(circle: daycare, contact: person)
        let excluded = CircleContact(circle: family, contact: person, manuallyExcluded: true)
        for row in [active, excluded] {
            source.mainContext.insert(row); row.circle.circleContacts.append(row); person.circleContacts.append(row)
        }
        try source.mainContext.save()
        let data = try GoldfishContactBundle.export(contacts: [person])

        let destination = try makeTestContainerForVCard()
        _ = try GoldfishContactBundle.importData(data, into: destination.mainContext)
        let received = try XCTUnwrap(try ModelContext(destination).fetch(FetchDescriptor<Person>()).first)
        XCTAssertEqual(received.circleContacts.count, 2)
        XCTAssertEqual(received.primaryCircle?.name, "Daycare")
        XCTAssertTrue(received.circleContacts.first { $0.circle.name == "Family" }?.manuallyExcluded == true)
        XCTAssertFalse(received.circleContacts.first { $0.circle.name == "Daycare" }?.manuallyExcluded ?? true)
    }

    func testImportedDemoContactIsOrdinaryContact() throws {
        let source = try makeTestContainerForVCard()
        let demo = Person(name: "Demo Sam", isDemo: true)
        source.mainContext.insert(demo); try source.mainContext.save()
        let data = try GoldfishContactBundle.export(contacts: [demo])
        let destination = try makeTestContainerForVCard()
        _ = try GoldfishContactBundle.importData(data, into: destination.mainContext)
        let received = try XCTUnwrap(try ModelContext(destination).fetch(FetchDescriptor<Person>()).first)
        XCTAssertFalse(received.isDemo)
    }

    func testSelectedFamilyBranchIncludesGrandparentsAndChildButExcludesMeSideContacts() throws {
        let source = try makeTestContainerForVCard()
        let adriana = Person(name: "Adriana")
        let senderMe = Person(name: "Adriana's Me", isMe: true)
        let riley = Person(name: "Riley")
        let zach = Person(name: "Zach")
        let aaron = Person(name: "Aaron")
        let grandparent = Person(name: "Grandparent")
        let child = Person(name: "Riley's child")
        let behindMe = Person(name: "Unselected Me-side contact")
        let selected = [adriana, riley, zach, aaron, grandparent, child]
        for person in selected + [senderMe, behindMe] { source.mainContext.insert(person) }
        let links = [
            Relationship(from: adriana, to: riley, type: .friend),
            Relationship(from: zach, to: riley, type: .parent),
            Relationship(from: aaron, to: riley, type: .parent),
            Relationship(from: grandparent, to: zach, type: .parent),
            Relationship(from: riley, to: child, type: .parent),
            Relationship(from: senderMe, to: adriana, type: .friend),
            Relationship(from: riley, to: behindMe, type: .friend)
        ]
        for link in links {
            source.mainContext.insert(link)
            link.fromContact.outgoingRelationships.append(link); link.toContact.incomingRelationships.append(link)
        }
        try source.mainContext.save()
        let data = try GoldfishContactBundle.export(contacts: selected)
        let preview = try GoldfishContactBundle.preview(data: data)
        XCTAssertEqual(Set(preview.people), Set(selected.map(\.name)))
        XCTAssertEqual(preview.relationshipsCount, 5)
        XCTAssertFalse(preview.people.contains(senderMe.name))
        XCTAssertFalse(preview.people.contains(behindMe.name))
        let destination = try makeTestContainerForVCard()
        _ = try GoldfishContactBundle.importData(data, into: destination.mainContext)
        XCTAssertEqual(Set(try ModelContext(destination).fetch(FetchDescriptor<Person>()).map(\.name)), Set(selected.map(\.name)))
    }

    func testFiftyContactRoundTripPreservesPeopleAndRelationshipCounts() throws {
        let source = try makeTestContainerForVCard()
        let people = (0..<50).map { Person(name: "Contact \($0)") }
        people.forEach { source.mainContext.insert($0) }
        for index in 0..<(people.count - 1) {
            let relationship = Relationship(from: people[index], to: people[index + 1], type: .friend)
            source.mainContext.insert(relationship)
            people[index].outgoingRelationships.append(relationship)
            people[index + 1].incomingRelationships.append(relationship)
        }
        try source.mainContext.save()
        let data = try GoldfishContactBundle.export(contacts: people)
        let destination = try makeTestContainerForVCard()
        let result = try GoldfishContactBundle.importData(data, into: destination.mainContext)
        XCTAssertEqual(result.addedPeople, 50)
        XCTAssertEqual(result.connectionsAdded, 49)
        XCTAssertEqual(try ModelContext(destination).fetch(FetchDescriptor<Person>()).count, 50)
        XCTAssertEqual(try ModelContext(destination).fetch(FetchDescriptor<Relationship>()).count, 49)
    }

    func testMalformedUnsupportedAndDanglingBundlesFailBeforeAnyImport() throws {
        let source = try makeTestContainerForVCard()
        let person = Person(name: "Adriana")
        source.mainContext.insert(person); try source.mainContext.save()
        let valid = try GoldfishContactBundle.export(contacts: [person])
        let unsupported = try replacingJSONValue(in: valid, key: "version", with: 99)
        let dangling = try replacingJSONValue(in: valid, key: "relationships", with: [[
            "id": UUID().uuidString, "fromID": person.id.uuidString,
            "toID": UUID().uuidString, "type": "friend", "isPrimary": false
        ]])
        let sourceManager = GoldfishDataManager(context: source.mainContext)
        let pond = try sourceManager.createCircle(name: "School")
        let member = CircleContact(circle: pond, contact: person)
        source.mainContext.insert(member); pond.circleContacts.append(member); person.circleContacts.append(member)
        try source.mainContext.save()
        let withPond = try GoldfishContactBundle.export(contacts: [person])
        var pondObject = try XCTUnwrap(JSONSerialization.jsonObject(with: withPond) as? [String: Any])
        var ponds = try XCTUnwrap(pondObject["ponds"] as? [[String: Any]])
        var exportedPond = try XCTUnwrap(ponds.first)
        var memberships = try XCTUnwrap(exportedPond["memberships"] as? [[String: Any]])
        memberships[0]["personID"] = UUID().uuidString
        exportedPond["memberships"] = memberships
        ponds[0] = exportedPond
        pondObject["ponds"] = ponds
        let danglingMembership = try JSONSerialization.data(withJSONObject: pondObject, options: [.sortedKeys])
        let destination = try makeTestContainerForVCard()
        for invalid in [Data("not-json".utf8), unsupported, dangling, danglingMembership] {
            XCTAssertThrowsError(try GoldfishContactBundle.importData(invalid, into: destination.mainContext))
            XCTAssertTrue(try ModelContext(destination).fetch(FetchDescriptor<Person>()).isEmpty)
            XCTAssertTrue(try ModelContext(destination).fetch(FetchDescriptor<Relationship>()).isEmpty)
        }
    }

    private func replacingJSONValue(in data: Data, key: String, with value: Any) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object[key] = value
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
