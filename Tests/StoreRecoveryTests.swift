import XCTest
@testable import Goldfish

final class StoreRecoveryTests: XCTestCase {
    func testMissingStoreDoesNotProduceFakeBackup() {
        XCTAssertThrowsError(try StoreRecoveryService.copyStore(at: URL(fileURLWithPath: "/nonexistent/\(UUID()).store")))
    }
    func testSnapshotPreservesStoreAndSidecars() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = root.appendingPathComponent("default.store")
        for suffix in ["", "-wal", "-shm"] { try Data(("test-content" + suffix).utf8).write(to: URL(fileURLWithPath: store.path + suffix)) }
        let blobDirectory = root.appendingPathComponent(".default_SUPPORT/_EXTERNAL_DATA")
        try FileManager.default.createDirectory(at: blobDirectory, withIntermediateDirectories: true)
        let photo = Data([0, 17, 128, 255])
        try photo.write(to: blobDirectory.appendingPathComponent("photo"))
        let copies = try StoreRecoveryService.copyStore(at: store, into: root)
        XCTAssertEqual(copies.count, 5)
        let support = try XCTUnwrap(copies.first { $0.lastPathComponent == ".default_SUPPORT" })
        XCTAssertEqual(try Data(contentsOf: support.appendingPathComponent("_EXTERNAL_DATA/photo")), photo)
        for suffix in ["", "-wal", "-shm"] {
            let original = URL(fileURLWithPath: store.path + suffix)
            let copy = copies.first { $0.lastPathComponent == original.lastPathComponent }!
            XCTAssertNotEqual(original.path, copy.path)
            XCTAssertEqual(try Data(contentsOf: original), try Data(contentsOf: copy))
        }
    }
}
