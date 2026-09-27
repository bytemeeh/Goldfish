import Foundation

/// Copies a failed local store and adjacent supporting files, without altering originals.
/// This is a recovery snapshot, not a guarantee that the damaged database is readable.
enum StoreRecoveryService {
    static func copyStore(at storeURL: URL, into temporaryRoot: URL = FileManager.default.temporaryDirectory) throws -> [URL] {
        let manager = FileManager.default
        guard manager.fileExists(atPath: storeURL.path) else {
            throw NSError(domain: "StoreRecovery", code: 1, userInfo: [NSLocalizedDescriptionKey: "No local database file was found to export."])
        }
        // SwiftData may store photo blobs outside the SQLite file. Preserve the
        // containing directory, including hidden support folders, without assuming
        // Core Data's private blob-directory naming convention.
        let sources = try manager.contentsOfDirectory(at: storeURL.deletingLastPathComponent(),
                                                      includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix("Goldfish-Recovery-") }
        let output = temporaryRoot.appendingPathComponent("Goldfish-Recovery-" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: output, withIntermediateDirectories: true)
        do {
            var files: [URL] = []
            for source in sources {
                let destination = output.appendingPathComponent(source.lastPathComponent)
                try manager.copyItem(at: source, to: destination)
                files.append(destination)
            }
            let instructions = output.appendingPathComponent("RECOVERY.txt")
            try "Local database recovery snapshot. Keep all files together. It may contain private contact information. The source could not be opened; recoverability has not been established. This is not a vCard export. Do not delete the installed app until your data is safely recovered.".write(to: instructions, atomically: true, encoding: .utf8)
            files.append(instructions)
            return files
        } catch {
            try? manager.removeItem(at: output)
            throw error
        }
    }

}

#if canImport(Darwin)
extension StoreRecoveryService {
    /// Foundation creates one archive while preserving the recovery directory hierarchy.
    /// Sharing individual SQLite files could separate them from external photo storage.
    static func shareableArchive(for copies: [URL]) throws -> URL {
        guard let snapshot = copies.first?.deletingLastPathComponent() else {
            throw NSError(domain: "StoreRecovery", code: 2, userInfo: [NSLocalizedDescriptionKey: "No recovery copy is available."])
        }
        let manager = FileManager.default
        let output = snapshot.deletingLastPathComponent().appendingPathComponent("Goldfish-Recovery-" + UUID().uuidString, isDirectory: true)
        try manager.createDirectory(at: output, withIntermediateDirectories: true)
        let archive = output.appendingPathComponent("Goldfish-Recovery.zip")
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: snapshot, options: .forUploading, error: &coordinationError) { url in
            do { try manager.copyItem(at: url, to: archive) }
            catch { copyError = error }
        }
        if let error = coordinationError {
            try? manager.removeItem(at: output)
            throw error
        }
        if let error = copyError {
            try? manager.removeItem(at: output)
            throw error
        }
        return archive
    }
}
#endif
