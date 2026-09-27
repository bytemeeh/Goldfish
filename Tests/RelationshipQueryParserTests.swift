import XCTest
@testable import Goldfish

final class RelationshipQueryParserTests: XCTestCase {
    func testExactNaturalLanguageExample() {
        XCTAssertEqual(RelationshipQueryParser.parse("How is Sam's friend's brother called?"),
                       .query(RelationshipQuery(anchor: "Sam", roles: [.friend, .sibling])))
    }

    func testWrappersPronounsPluralsAndAliases() {
        XCTAssertEqual(RelationshipQueryParser.parse("Who is my colleague's daughter?"),
                       .query(RelationshipQuery(anchor: "me", roles: [.coworker, .child])))
        XCTAssertEqual(RelationshipQueryParser.parse("What's James’ wives' sisters?"),
                       .query(RelationshipQuery(anchor: "James", roles: [.spouse, .sibling])))
        XCTAssertEqual(RelationshipQueryParser.parse("What is the name of O'Neil's friend?"),
                       .query(RelationshipQuery(anchor: "O'Neil", roles: [.friend])))
        XCTAssertEqual(RelationshipQueryParser.parse("Who is my friend?"),
                       .query(RelationshipQuery(anchor: "me", roles: [.friend])))
        XCTAssertEqual(RelationshipQueryParser.parse("Who are Sam's friends?"),
                       .query(RelationshipQuery(anchor: "Sam", roles: [.friend])))
        XCTAssertEqual(RelationshipQueryParser.parse("What is Sam's friend called?"),
                       .query(RelationshipQuery(anchor: "Sam", roles: [.friend])))
    }

    func testMultiwordAndReverseChains() {
        XCTAssertEqual(RelationshipQueryParser.parse("Who is Alex Morgan's best?"), .unsupported("I couldn't understand that relationship search. Try “Sam's friend”."))
        XCTAssertEqual(RelationshipQueryParser.parse("sibling of the friend of Sam"),
                       .query(RelationshipQuery(anchor: "Sam", roles: [.friend, .sibling])))
        XCTAssertEqual(RelationshipQueryParser.parse("friend of Taylor Swift"),
                       .query(RelationshipQuery(anchor: "Taylor Swift", roles: [.friend])))
        XCTAssertEqual(RelationshipQueryParser.parse("Who is “Sam's friend's friend”?"),
                       .query(RelationshipQuery(anchor: "Sam", roles: [.friend, .friend])))
    }

    func testPlainTextDoesNotBecomeAQuery() {
        XCTAssertEqual(RelationshipQueryParser.parse("Sam"), .plainText)
        XCTAssertEqual(RelationshipQueryParser.parse("notes about Sam's birthday"), .plainText)
        XCTAssertEqual(RelationshipQueryParser.parse("call Sam's office"), .plainText)
    }

    func testMalformedAndUnknownIntendedSearchesAreUnsupported() {
        if case .unsupported = RelationshipQueryParser.parse("Who is Sam's?") {} else { XCTFail("Expected unsupported") }
        if case .unsupported = RelationshipQueryParser.parse("How is Sam's neighbor called?") {} else { XCTFail("Expected unsupported") }
        if case .unsupported = RelationshipQueryParser.parse("What is friend of?") {} else { XCTFail("Expected unsupported") }
        if case .unsupported = RelationshipQueryParser.parse("Sam's friend's unknownrole") {} else { XCTFail("Expected malformed chain") }
        if case .unsupported = RelationshipQueryParser.parse("Sam's cousin") {} else { XCTFail("Expected unsupported kinship") }
        if case .unsupported = RelationshipQueryParser.parse("Sam's friend’s") {} else { XCTFail("Expected trailing relationship error") }
    }

    func testReverseChainsRejectUnknownAnchors() {
        if case .query = RelationshipQueryParser.parse("sibling of cousin of Sam") {
            XCTFail("Unknown reverse relationship must not become part of the anchor")
        }
    }

    func testBounds() {
        let longText = String(repeating: "Sam's friend ", count: 50)
        if case .unsupported = RelationshipQueryParser.parse(longText) {} else { XCTFail("Expected unsupported") }

        let chain = ([String](repeating: "friend", count: 13)).enumerated().reduce("Sam") { partial, item in
            partial + "'s " + item.element
        }
        if case .unsupported = RelationshipQueryParser.parse(chain) {} else { XCTFail("Expected unsupported") }
    }
}
