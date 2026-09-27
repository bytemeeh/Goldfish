import XCTest
import SwiftData
import SpriteKit
@testable import Goldfish

@MainActor
final class QualityScaleTests: XCTestCase {
    func testFiftyContactReviewIncludesEveryPersonAndKeepsPersonalScopeEmpty() throws {
        let container = try GoldfishModelContainer.testing()
        let manager = GoldfishDataManager(context: container.mainContext)
        try manager.performOnboarding(name: "You")
        try DemoDataService(dataManager: manager).seedQualityReviewNetwork()
        let people = try manager.fetchAllPersons()
        let demos = people.filter { !$0.isMe }
        XCTAssertEqual(demos.count, 50)
        XCTAssertTrue(demos.allSatisfy(\.isDemo))
        XCTAssertEqual(Set(demos.map(\.name)).count, 50)
        XCTAssertEqual(demos.filter { $0.name == "Alex Jordan" }.count, 1)
        XCTAssertFalse(demos.contains { $0.name.localizedCaseInsensitiveContains("review contact") })
        XCTAssertTrue(demos.contains { $0.name == "Alexandra Montgomery-Wellington" })
        XCTAssertTrue(demos.contains { $0.name == "田中 花子" })
        XCTAssertTrue(demos.contains { ($0.notes?.count ?? 0) > 500 })
        XCTAssertFalse(demos.flatMap(\.allRelationships).contains { $0.type == .other })
        let qualityAdditions = demos.filter { $0.email?.hasPrefix("sample") == true }
        XCTAssertEqual(qualityAdditions.count, 32)
        XCTAssertTrue(qualityAdditions.allSatisfy { !$0.tags.isEmpty })
        XCTAssertTrue(qualityAdditions.allSatisfy { $0.primaryCircle?.name != "Family" })
        XCTAssertEqual(Set(demos.filter { $0.primaryCircle?.name == "Family" }.map(\.name)),
                       ["Sarah Chen", "Linda Miller", "Robert Miller", "Tom Miller"])

        let peopleByName = Dictionary(uniqueKeysWithValues: demos.map { ($0.name, $0) })
        let david = try XCTUnwrap(peopleByName["David Park"])
        let emma = try XCTUnwrap(peopleByName["Emma Wilson"])
        let alex = try XCTUnwrap(peopleByName["Alex Jordan"])
        let professionalCohort = qualityAdditions.filter { $0.tags.contains("Professional network") }
        let bookClubCohort = qualityAdditions.filter { $0.tags.contains("Book club") }
        let designCohort = qualityAdditions.filter { $0.tags.contains("Design research") }
        let independentCohort = qualityAdditions.filter { $0.tags.contains("Independent contact") }
        XCTAssertEqual(professionalCohort.count, 10)
        XCTAssertEqual(bookClubCohort.count, 8)
        XCTAssertEqual(designCohort.count, 12)
        XCTAssertEqual(independentCohort.count, 2)
        XCTAssertTrue(professionalCohort.allSatisfy {
            $0.primaryCircle?.id == david.primaryCircle?.id && hasRelationship(between: david, and: $0, type: .coworker)
        })
        XCTAssertTrue(bookClubCohort.allSatisfy {
            $0.primaryCircle?.id == emma.primaryCircle?.id && hasRelationship(between: emma, and: $0, type: .friend)
        })
        XCTAssertTrue(designCohort.allSatisfy {
            $0.primaryCircle?.name == "Design & Research Collective" && hasRelationship(between: alex, and: $0, type: .friend)
        })
        XCTAssertTrue(independentCohort.allSatisfy { $0.primaryCircle?.name == "Design & Research Collective" && $0.isOrphan })
        XCTAssertEqual(Set(demos.filter(\.isOrphan).map(\.name)), ["Priya Patel", "Mara Stein", "Jonas Keller"])

        let siblingResponse = try XCTUnwrap(manager.relationshipSearch(query: "my sibling", demoMode: true))
        XCTAssertTrue(siblingResponse.paths.contains { $0.person.name == "Tom Miller" })
        let levels = try XCTUnwrap(manager.buildGraphLayout(demoMode: true))
        XCTAssertEqual(Set(levels.flatMap(\.allContacts).map(\.id)), Set(people.map(\.id)))
        let personalLevels = try manager.buildGraphLayout(demoMode: false) ?? []
        XCTAssertTrue(personalLevels.flatMap(\.allContacts).allSatisfy(\.isMe))
        let scene = GoldfishGraphScene(size: CGSize(width: 375, height: 540))
        scene.didUpdateGroups(try manager.fetchAllCircles())
        let positions = scene.debugLayout(levels)
        XCTAssertEqual(positions.count, 51)
        XCTAssertTrue(positions.values.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }

    func testRippleReviewFixtureHasCoherentFamiliesPetsAndNamedConnectionRoutes() throws {
        let container = try GoldfishModelContainer.testing()
        let manager = GoldfishDataManager(context: container.mainContext)
        let me = try manager.performOnboarding(name: "You")
        try DemoDataService(dataManager: manager).seedRippleReviewNetwork()
        let demos = try manager.fetchAllPersons().filter(\.isDemo)
        XCTAssertEqual(demos.count, 50)
        XCTAssertEqual(Set(demos.map(\.name)).count, 50)
        XCTAssertFalse(demos.contains { $0.name.localizedCaseInsensitiveContains("review contact") })
        XCTAssertTrue(demos.contains { $0.name == "Alexandra Montgomery-Wellington" })
        XCTAssertTrue(demos.contains { $0.name == "田中 花子" })

        let people = Dictionary(uniqueKeysWithValues: demos.map { ($0.name, $0) })
        let alex = try XCTUnwrap(people["Alex"])
        let anna = try XCTUnwrap(people["Anna"])
        let lea = try XCTUnwrap(people["Lea"])
        let max = try XCTUnwrap(people["Max"])
        let nora = try XCTUnwrap(people["Nora"])
        let biscuit = try XCTUnwrap(people["Biscuit"])
        let milo = try XCTUnwrap(people["Milo"])
        let sam = try XCTUnwrap(people["Sam"])
        let jo = try XCTUnwrap(people["Jo"])
        let ben = try XCTUnwrap(people["Ben"])
        let pip = try XCTUnwrap(people["Pip"])

        XCTAssertTrue(hasRelationship(from: me, to: alex, type: .sibling))
        XCTAssertFalse(hasRelationship(between: me, and: nora, type: .friend))
        XCTAssertFalse(hasRelationship(between: jo, and: anna, type: .friend))
        XCTAssertTrue(hasRelationship(from: alex, to: lea, type: .parent))
        XCTAssertTrue(hasRelationship(from: anna, to: lea, type: .parent))
        XCTAssertTrue(hasRelationship(from: alex, to: max, type: .parent))
        XCTAssertTrue(hasRelationship(from: anna, to: max, type: .parent))
        XCTAssertTrue(hasRelationship(from: biscuit, to: alex, type: .pet))
        XCTAssertTrue(hasRelationship(from: milo, to: max, type: .pet))
        XCTAssertTrue(hasRelationship(from: pip, to: sam, type: .pet))
        XCTAssertTrue(hasRelationship(from: pip, to: jo, type: .pet))

        let graph = RippleGraph(people: [me] + demos)
        let family = demos.filter { $0.primaryCircle?.name == "Family" }
        XCTAssertFalse(family.isEmpty)
        for person in family {
            let path = try XCTUnwrap(graph.shortestPath(from: me.id, to: person.id), "Missing family path to \(person.name)")
            XCTAssertTrue(path.dropFirst().allSatisfy { id in
                demos.first { $0.id == id }?.primaryCircle?.name == "Family"
            }, "\(person.name) should be reachable through Family only")
        }

        let siblingResponse = try XCTUnwrap(manager.relationshipSearch(query: "my sibling", demoMode: true))
        XCTAssertTrue(siblingResponse.paths.contains { $0.person.id == alex.id })
        let chainResponse = try XCTUnwrap(manager.relationshipSearch(query: "Sam's friend's sibling", demoMode: true))
        XCTAssertTrue(chainResponse.paths.contains { path in
            path.people.map(\.id) == [sam.id, jo.id, ben.id]
        })

        XCTAssertFalse(demos.contains {
            $0.name.hasPrefix("Unlinked ") || $0.name.hasPrefix("Independent ") || $0.name.hasPrefix("Review ")
        })
        XCTAssertFalse(demos.contains { $0.notes?.localizedCaseInsensitiveContains("unlinked sample") == true })
        let unlinked = Set(demos.filter(\.isOrphan).map(\.name))
        XCTAssertEqual(unlinked, ["Ada Fischer", "Felix Baumann"])
    }

    func testReviewFixtureRefusesAnExistingContactStore() throws {
        let container = try GoldfishModelContainer.testing()
        let manager = GoldfishDataManager(context: container.mainContext)
        try manager.performOnboarding(name: "You")
        let person = try manager.createPerson(name: "Keep this person")
        XCTAssertThrowsError(try DemoDataService(dataManager: manager).seedQualityReviewNetwork())
        XCTAssertEqual(try manager.fetchAllPersons().filter { !$0.isMe }.map(\.id), [person.id])
    }

    private func hasRelationship(from: Person, to: Person, type: RelationshipType) -> Bool {
        from.allRelationships.contains {
            !$0.isDeleted && $0.fromContact.id == from.id && $0.toContact.id == to.id && $0.type == type
        }
    }

    private func hasRelationship(between first: Person, and second: Person, type: RelationshipType) -> Bool {
        first.allRelationships.contains {
            !$0.isDeleted && $0.type == type &&
                Set([$0.fromContact.id, $0.toContact.id]) == Set([first.id, second.id])
        }
    }
}
