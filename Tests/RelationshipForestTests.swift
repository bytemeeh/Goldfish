import XCTest
@testable import Goldfish

final class RelationshipForestTests: XCTestCase {
    func testCyclesDuplicateEdgesAndMissingNodes() {
        let a = UUID(), b = UUID(), c = UUID(), missing = UUID()
        let result = RelationshipForest.build(roots: [a, a], neighbors: [a: [a, b, b, missing], b: [a, c], c: [a, b]], allowed: [a, b, c])
        XCTAssertNil(result.parent[a])
        XCTAssertEqual(result.parent[b], a)
        XCTAssertEqual(result.parent[c], b)
        XCTAssertEqual(result.root[c], a)
        XCTAssertNil(result.root[missing])
    }

    func testClosestRootWinsAndPeerRootsStayOnTrunks() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let graph = [a: [b, c], b: [a, d], c: [a, d], d: [c, b]]
        let result = RelationshipForest.build(roots: [a, b], neighbors: graph, allowed: [a, b, c, d])
        XCTAssertNil(result.parent[b])
        XCTAssertEqual(result.parent[d], b)
        XCTAssertEqual(result.root[d], b)
        let reversed = graph.mapValues { Array($0.reversed()) }
        XCTAssertEqual(result.parent, RelationshipForest.build(roots: [a, b], neighbors: reversed, allowed: [a, b, c, d]).parent)
    }

    func testDeepTreeAndDisconnectedContact() {
        let ids = (0..<10000).map { _ in UUID() }
        var graph: [UUID: [UUID]] = [:]
        for i in 1..<ids.count { graph[ids[i - 1]] = [ids[i]] }
        let disconnected = UUID()
        let result = RelationshipForest.build(roots: [ids[0]], neighbors: graph, allowed: Set(ids + [disconnected]))
        XCTAssertEqual(result.parent.count, ids.count - 1)
        XCTAssertEqual(result.root[ids.last!], ids[0])
        XCTAssertNil(result.root[disconnected])
    }
}
