import XCTest
import SwiftData
@testable import Goldfish

@MainActor
final class RelationshipSearchTests: XCTestCase {
    private func person(_ name: String, isMe: Bool = false, kind: ContactKind? = nil) -> Person {
        Person(name: name, isMe: isMe, petKindRaw: kind?.rawValue)
    }

    @discardableResult
    private func link(_ from: Person, _ to: Person, _ type: RelationshipType) -> Relationship {
        let relationship = Relationship(from: from, to: to, type: type)
        from.outgoingRelationships.append(relationship)
        to.incomingRelationships.append(relationship)
        return relationship
    }

    func testExactFullNameWinsAndPathMetadataPreservesRequestedRoleOrder() {
        let samLee = person("Sam Lee")
        let samJones = person("Sam Jones")
        let friend = person("Friend")
        let sibling = person("Sibling")
        link(samLee, friend, .friend)
        link(friend, sibling, .sibling)

        let query = RelationshipQuery(anchor: "Sam Lee", roles: [.friend, .sibling])
        let response = RelationshipSearchService().search(query, people: [samLee, samJones, friend, sibling])

        XCTAssertEqual(response.anchorMatches.map(\.id), [samLee.id])
        XCTAssertEqual(response.paths.count, 1)
        let path = try! XCTUnwrap(response.paths.first)
        XCTAssertEqual(path.people.map(\.id), [samLee.id, friend.id, sibling.id])
        XCTAssertEqual(path.roles, [.friend, .sibling])
        XCTAssertEqual(path.person.id, sibling.id)
        XCTAssertEqual(path.trailIDs, [samLee.id, friend.id, sibling.id])
        XCTAssertEqual(path.summary, "Sam Lee → friend Friend → sibling Sibling")
    }

    func testFirstNameFallbackMatchesEveryTokenBoundaryButNotSamantha() {
        let sam = person("Sam Lee")
        let samTaylor = person("Sam Taylor")
        let samantha = person("Samantha")
        let friendA = person("Friend A")
        let friendB = person("Friend B")
        link(sam, friendA, .friend)
        link(samTaylor, friendB, .friend)

        let response = RelationshipSearchService().search(
            RelationshipQuery(anchor: "Sam", roles: [.friend]),
            people: [sam, samTaylor, samantha, friendA, friendB]
        )

        XCTAssertEqual(response.anchorMatches.map(\.id), [sam.id, samTaylor.id])
        XCTAssertEqual(Set(response.paths.map { $0.people.first!.id }), Set([sam.id, samTaylor.id]))
        XCTAssertFalse(response.paths.contains { $0.people.first?.id == samantha.id })
    }

    func testDistinctRoutesToSamePersonAreRetainedWhileDuplicateFullIDPathsAreRemoved() {
        let anchor = person("Sam")
        let left = person("Left")
        let right = person("Right")
        let target = person("Target")
        link(anchor, left, .friend)
        link(anchor, right, .friend)
        link(left, target, .friend)
        link(right, target, .friend)

        let response = RelationshipSearchService().search(
            RelationshipQuery(anchor: "Sam", roles: [.friend, .friend]),
            people: [anchor, left, right, target]
        )
        let targetPaths = response.paths.filter { $0.person.id == target.id }
        XCTAssertEqual(targetPaths.count, 2)
        XCTAssertEqual(Set(targetPaths.map { $0.trailIDs }), Set([
            [anchor.id, left.id, target.id],
            [anchor.id, right.id, target.id]
        ]))
    }

    func testGenericSiblingChainAndReciprocalParentRoles() {
        let child = person("Child")
        let mother = person("Mother")
        let father = person("Father")
        let sibling = person("Sibling")
        link(mother, child, .mother)
        link(father, child, .father)
        link(child, sibling, .sibling)

        let parents = RelationshipSearchService().search(
            RelationshipQuery(anchor: "Child", roles: [.parent]),
            people: [child, mother, father, sibling]
        )
        XCTAssertEqual(Set(parents.paths.map { $0.person.id }), Set([mother.id, father.id]))

        let children = RelationshipSearchService().search(
            RelationshipQuery(anchor: "Mother", roles: [.child]),
            people: [child, mother, father, sibling]
        )
        XCTAssertEqual(children.paths.map { $0.person.id }, [child.id])

        let chained = RelationshipSearchService().search(
            RelationshipQuery(anchor: "Child", roles: [.sibling]),
            people: [child, mother, father, sibling]
        )
        XCTAssertEqual(chained.paths.map { $0.person.id }, [sibling.id])
    }

    func testPetSpeciesRequireConfirmedIdentityAndSavedGuardianLink() {
        let owner = person("Owner")
        let dog = person("Milo", kind: .dog)
        let cat = person("Nala", kind: .cat)
        let unconfirmed = person("Pond", kind: .pet)
        unconfirmed.notes = "dog seen near the pond"
        link(owner, dog, .guardian)
        link(owner, cat, .guardian)

        let dogs = RelationshipSearchService().search(RelationshipQuery(anchor: "Owner", roles: [.dog]), people: [owner, dog, cat, unconfirmed])
        XCTAssertEqual(dogs.paths.map { $0.person.id }, [dog.id])
        let cats = RelationshipSearchService().search(RelationshipQuery(anchor: "Owner", roles: [.cat]), people: [owner, dog, cat, unconfirmed])
        XCTAssertEqual(cats.paths.map { $0.person.id }, [cat.id])
    }

    func testMyAnchorUsesTheIsMeContact() {
        let me = person("Marcel", isMe: true)
        let friend = person("Friend")
        link(me, friend, .friend)

        let response = RelationshipSearchService().search(RelationshipQuery(anchor: "my", roles: [.friend]), people: [me, friend])
        XCTAssertEqual(response.anchorMatches.map(\.id), [me.id])
        XCTAssertEqual(response.paths.map { $0.person.id }, [friend.id])
        XCTAssertTrue(response.paths[0].summary.hasPrefix("You → friend"))
    }

    func testScopeExcludesContactsOutsideTheSuppliedGraph() {
        let anchor = person("Sam")
        let inside = person("Inside")
        let outside = person("Deleted")
        link(anchor, inside, .friend)
        link(inside, outside, .friend)

        let response = RelationshipSearchService().search(
            RelationshipQuery(anchor: "Sam", roles: [.friend, .friend]),
            people: [anchor, inside]
        )
        XCTAssertEqual(response.paths.map(\.trailIDs), [[anchor.id, inside.id, anchor.id]])
        XCTAssertFalse(response.paths.contains { $0.trailIDs.contains(outside.id) })
    }

    func testMissingAnchorAndMissingEdgeReturnHelpfulMessages() {
        let sam = person("Sam")
        let response = RelationshipSearchService().search(RelationshipQuery(anchor: "Unknown", roles: [.friend]), people: [sam])
        XCTAssertTrue(response.anchorMatches.isEmpty)
        XCTAssertTrue(response.paths.isEmpty)
        XCTAssertFalse(response.message?.isEmpty ?? true)

        let noFriend = RelationshipSearchService().search(RelationshipQuery(anchor: "Sam", roles: [.friend]), people: [sam])
        XCTAssertTrue(noFriend.paths.isEmpty)
        XCTAssertTrue(noFriend.message?.localizedCaseInsensitiveContains("friend") == true || noFriend.message?.localizedCaseInsensitiveContains("connect") == true)
    }

    func testCyclesAllowExactlyRequestedNumberOfStepsAndRemainFinite() {
        let a = person("A")
        let b = person("B")
        let c = person("C")
        link(a, b, .friend)
        link(b, c, .friend)
        link(c, a, .friend)

        let response = RelationshipSearchService().search(
            RelationshipQuery(anchor: "A", roles: [.friend, .friend, .friend]),
            people: [a, b, c]
        )
        XCTAssertEqual(response.paths.count, 8)
        XCTAssertTrue(response.paths.allSatisfy { $0.roles.count == 3 && $0.people.count == 4 })
        XCTAssertTrue(response.paths.allSatisfy { path in
            zip(path.people, path.people.dropFirst()).allSatisfy { from, to in
                from.connectedContacts.contains { $0.id == to.id }
            }
        })
    }

    func testLargeResultSetIsDeterministicBoundedAndMarkedTruncated() {
        let anchor = person("Sam")
        var people = [anchor]
        let sharedHub = person("Shared Hub")
        people.append(sharedHub)
        for index in 0..<60 {
            let friend = person(String(format: "Friend %02d", index))
            link(anchor, friend, .friend)
            people.append(friend)
            link(friend, sharedHub, .friend)
        }

        let query = RelationshipQuery(anchor: "Sam", roles: [.friend, .friend, .friend])
        let first = RelationshipSearchService().search(query, people: people)
        let second = RelationshipSearchService().search(query, people: people)
        XCTAssertLessThanOrEqual(first.paths.count, 128)
        XCTAssertTrue(first.isTruncated)
        XCTAssertEqual(first.paths.map(\.trailIDs), second.paths.map(\.trailIDs))
        XCTAssertFalse(first.paths.isEmpty)
    }

    func testHomeViewModelResolvesBrotherAliasThroughSavedSampleRelationship() throws {
        let (manager, container) = try makeTestManager()
        _ = container
        let me = try manager.createPerson(name: "Me", isMe: true)
        let sampleBrother = try manager.createPerson(name: "Sample Brother", isDemo: true)
        try manager.createRelationship(from: me, to: sampleBrother, type: .sibling)

        let viewModel = HomeViewModel(dataManager: manager)
        viewModel.isDemoMode = true
        viewModel.loadData()
        viewModel.searchText = "my brother"
        viewModel.performSearch(query: viewModel.searchText)

        XCTAssertEqual(viewModel.relationshipSearch?.query, RelationshipQuery(anchor: "me", roles: [.sibling]))
        XCTAssertEqual(viewModel.relationshipSearch?.paths.map { $0.person.id }, [sampleBrother.id])
    }

    func testHomeViewModelKeepsOrdinaryLiteralNameSearchAndClearsZeroQuery() throws {
        let (manager, container) = try makeTestManager()
        _ = container
        _ = try manager.createPerson(name: "Me", isMe: true)
        let alice = try manager.createPerson(name: "Alice")

        let viewModel = HomeViewModel(dataManager: manager)
        viewModel.loadData()
        viewModel.searchText = "Alice"
        viewModel.performSearch(query: viewModel.searchText)
        XCTAssertNil(viewModel.relationshipSearch)
        XCTAssertEqual(viewModel.filteredContacts.map(\.id), [alice.id])

        viewModel.searchText = ""
        viewModel.performSearch(query: "")
        XCTAssertNil(viewModel.relationshipSearch)
        XCTAssertFalse(viewModel.isSearching)
    }

    func testHomeViewModelFiltersOnlyResultEndpointsAndClearingScopeRestoresThem() throws {
        let (manager, container) = try makeTestManager()
        _ = container
        let me = try manager.createPerson(name: "Me", isMe: true)
        let throughOtherPond = try manager.createPerson(name: "Through Other Pond")
        let selectedResult = try manager.createPerson(name: "Selected Result")
        let outsideResult = try manager.createPerson(name: "Outside Result")
        try manager.createRelationship(from: me, to: throughOtherPond, type: .friend)
        try manager.createRelationship(from: throughOtherPond, to: selectedResult, type: .friend)
        try manager.createRelationship(from: me, to: outsideResult, type: .friend)
        try manager.createRelationship(from: throughOtherPond, to: outsideResult, type: .friend)

        let selectedPond = try manager.createCircle(name: "Selected Pond")
        let otherPond = try manager.createCircle(name: "Other Pond")
        try manager.addToCircle(selectedResult, circle: selectedPond)
        try manager.addToCircle(throughOtherPond, circle: otherPond)

        let viewModel = HomeViewModel(dataManager: manager)
        viewModel.loadData()
        viewModel.selectScope(selectedPond.id.uuidString)
        viewModel.searchText = "my friend's friend"
        viewModel.performSearch(query: viewModel.searchText)

        XCTAssertEqual(viewModel.filteredContacts.map(\.id), [selectedResult.id])
        XCTAssertTrue(viewModel.relationshipSearch?.paths.contains { $0.person.id == selectedResult.id } == true)
        XCTAssertTrue(viewModel.relationshipSearch?.paths.contains { $0.people.dropFirst().contains { $0.id == throughOtherPond.id } } == true)

        viewModel.selectScope(nil)
        XCTAssertEqual(Set(viewModel.filteredContacts.map(\.id)), Set([selectedResult.id, outsideResult.id, throughOtherPond.id, me.id]))
    }

    func testRefreshingAfterDeletingRelationshipRemovesStaleSearchResult() throws {
        let (manager, container) = try makeTestManager()
        _ = container
        let me = try manager.createPerson(name: "Me", isMe: true)
        let friend = try manager.createPerson(name: "Friend")
        let relationship = try manager.createRelationship(from: me, to: friend, type: .friend)

        let viewModel = HomeViewModel(dataManager: manager)
        viewModel.loadData()
        viewModel.searchText = "my friend"
        viewModel.performSearch(query: viewModel.searchText)
        XCTAssertEqual(viewModel.relationshipSearch?.paths.map { $0.person.id }, [friend.id])

        try manager.deleteRelationship(relationship)
        viewModel.loadData()
        XCTAssertTrue(viewModel.relationshipSearch?.paths.isEmpty == true)
        XCTAssertTrue(viewModel.filteredContacts.isEmpty)
    }
}
