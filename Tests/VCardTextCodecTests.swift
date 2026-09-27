import XCTest
@testable import Goldfish

final class VCardTextCodecTests: XCTestCase {
    func testEscapedSeparatorsAndLiteralBackslashesRoundTrip() {
        let tags = ["dev", "ios, swift", "semi;colon", "literal\\n", "trailing\\"]
        let value = tags.map(VCardTextCodec.escape).joined(separator: ",")
        XCTAssertEqual(VCardTextCodec.components(value, separatedBy: ","), tags)
        for tag in tags { XCTAssertEqual(VCardTextCodec.unescape(VCardTextCodec.escape(tag)), tag) }
    }
    func testStructuredAddressRetainsEmptyFieldsAndPunctuation() {
        let fields = ["", "", "Street; 1", "Zürich", "", "8049", "CH"]
        let value = fields.map(VCardTextCodec.escape).joined(separator: ";")
        XCTAssertEqual(VCardTextCodec.components(value, separatedBy: ";"), fields)
    }
    func testUnicodeFoldingCountsBytesAndRestoresContent() {
        let line = "NOTE:" + String(repeating: "水🐟e\u{301}", count: 80)
        let folded = VCardTextCodec.fold(line)
        for part in folded.components(separatedBy: "\r\n") { XCTAssertLessThanOrEqual(part.utf8.count, 75) }
        XCTAssertEqual(folded.replacingOccurrences(of: "\r\n ", with: ""), line)
    }
    func testGroupMetadataPreservesIdentityAndRejectsMalformedPayload() {
        let first = GroupTransferMetadata(id: UUID(), name: "Same; name", color: "#123ABC", systemRole: nil)
        let second = GroupTransferMetadata(id: UUID(), name: first.name, color: "#ABC123", systemRole: .family)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(first.encoded.flatMap(GroupTransferMetadata.decode), first)
        XCTAssertEqual(second.encoded.flatMap(GroupTransferMetadata.decode), second)
        XCTAssertNil(GroupTransferMetadata.decode("garbage"))
        XCTAssertNil(GroupTransferMetadata.decode(String(repeating: "a", count: 16_385)))
        let blank = GroupTransferMetadata(id: UUID(), name: "  ", color: "#123ABC", systemRole: nil)
        XCTAssertNil(blank.encoded.flatMap(GroupTransferMetadata.decode))
    }
}
