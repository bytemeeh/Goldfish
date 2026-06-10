import XCTest
import SwiftData
@testable import Goldfish

@MainActor
final class StressTests: XCTestCase {

    var manager: GoldfishDataManager!

    override func setUp() async throws {
        manager = try makeTestManager()
        try manager.createSystemCircles()
    }

    func testGraphDataProvider1000Nodes() async throws {
        // 1. Create Me
        let me = try manager.createPerson(name: "Me", isMe: true)
        let familyCircle = try manager.fetchSystemCircles().first { $0.name == "Family" }!

        // 2. Generate 1000 contacts and randomly attach them
        let count = 1000
        var contacts: [Person] = [me]

        // measure time for creation
        let startTime = CFAbsoluteTimeGetCurrent()
        for i in 1...count {
            let person = try manager.createPerson(name: "Person \(i)")
            contacts.append(person)

            // Randomly connect to an existing person
            let randomExisting = contacts.randomElement()!
            if randomExisting.id != person.id {
                try manager.createRelationship(from: person, to: randomExisting, type: .friend)
            }
            if i % 10 == 0 {
                try manager.addToCircle(person, circle: familyCircle)
            }
        }
        let createTime = CFAbsoluteTimeGetCurrent() - startTime
        print("Created \(count) nodes in \(createTime) seconds")

        // 3. Test GraphDataProvider performance
        let provider = GraphDataProvider(modelContainer: manager.context.container)
        
        measure {
            let exp = expectation(description: "Topology built")
            Task {
                let topology = try await provider.compileGraphTopology(demoMode: false)
                
                XCTAssertEqual(topology.allNodes.count, count + 1) // +1 for Me
                XCTAssertGreaterThan(topology.edges.count, 0)
                exp.fulfill()
            }
            wait(for: [exp], timeout: 10.0)
        }
    }
}
