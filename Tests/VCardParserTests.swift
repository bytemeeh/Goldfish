import XCTest
@testable import Goldfish

final class VCardParserTests: XCTestCase {
    func testManifestMarkerInRealContactDoesNotDiscardContact() {
        let card = "BEGIN:VCARD\nFN:Alice\nNOTE:Discuss _GOLDFISH_MANIFEST and BEGIN:VCARD later\nEND:VCARD\n"
        let result = VCardParser.parseWithManifest(Data(card.utf8))
        XCTAssertNil(result.manifest)
        XCTAssertEqual(result.contacts.first?.name, "Alice")
        XCTAssertEqual(result.contacts.first?.notes, "Discuss _GOLDFISH_MANIFEST and BEGIN:VCARD later")
    }
    func testLegacyGoldfishAddressAndTagsRemainReadable() {
        // Exact escaping produced by the supplied 1.0 exporter: every ADR
        // delimiter escaped, and the entire pre-escaped tag list escaped again.
        let card = #"""
        BEGIN:VCARD
        FN:Legacy Contact
        ADR;TYPE=HOME:\;\;Musterstr. 1\;Berlin\;\;\;Germany
        X-GOLDFISH-TAGS:dev\,ios\\\, swift
        END:VCARD
        """#
        let contact = VCardParser.parse(Data(card.utf8)).first
        XCTAssertEqual(contact?.street, "Musterstr. 1")
        XCTAssertEqual(contact?.city, "Berlin")
        XCTAssertEqual(contact?.country, "Germany")
        XCTAssertEqual(contact?.tags, ["dev", "ios, swift"])
    }
    func testCurrentStructuredFieldsAndLiteralBackslashPreserved() {
        let card = #"""
        BEGIN:VCARD
        X-GOLDFISH-CONTACT-VERSION:1.1
        FN:New Contact
        ADR;TYPE=HOME:;;Street\; 1;Zürich;;8049;CH
        X-GOLDFISH-TAGS:dev,ios\, swift
        NOTE:literal \\n and line\nbreak
        END:VCARD
        """#
        let contact = VCardParser.parse(Data(card.utf8)).first
        XCTAssertEqual(contact?.street, "Street; 1")
        XCTAssertEqual(contact?.city, "Zürich")
        XCTAssertEqual(contact?.tags, ["dev", "ios, swift"])
        XCTAssertEqual(contact?.notes, "literal \\n and line\nbreak")
    }
    func testFoldedUnicodeAndGroupMetadata() throws {
        let group = GroupTransferMetadata(id: UUID(), name: "Same", color: "#AABBCC", systemRole: nil)
        let note = String(repeating: "水🐟", count: 100)
        let card = ["BEGIN:VCARD", "FN:Alice", "X-GOLDFISH-CONTACT-VERSION:1.1",
                    VCardTextCodec.property("NOTE", components: [note], separator: ""),
                    VCardTextCodec.fold("X-GOLDFISH-GROUP:" + (try XCTUnwrap(group.encoded))), "END:VCARD"].joined(separator: "\r\n")
        let contact = VCardParser.parse(Data(card.utf8)).first
        XCTAssertEqual(contact?.notes, note)
        XCTAssertEqual(contact?.groups, [group])
    }
    func testMalformedIncompleteAndBlankContactsAreRejected() {
        XCTAssertTrue(VCardParser.parse(Data("BEGIN:VCARD\nFN:Incomplete".utf8)).isEmpty)
        XCTAssertTrue(VCardParser.parse(Data("BEGIN:VCARD\nFN:   \nEND:VCARD".utf8)).isEmpty)
        XCTAssertTrue(VCardParser.parse(Data([0xFF, 0xFE])).isEmpty)
    }
}
