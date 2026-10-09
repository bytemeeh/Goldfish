import Foundation
import UniformTypeIdentifiers

extension UTType {
    static let goldfishContactBundle = UTType(exportedAs: "app.pond.goldfish.contact-bundle", conformingTo: .json)
}

enum GoldfishShareFile {
    /// Retain a file opened by another app until the recipient finishes reviewing it.
    static func stage(_ url: URL) throws -> URL {
        guard url.isFileURL, url.pathExtension.lowercased() == "goldfish" else {
            throw GoldfishContactBundle.BundleError.invalidData("choose a .goldfish file")
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, let size = values.fileSize, size <= 50 * 1_024 * 1_024 else {
            throw GoldfishContactBundle.BundleError.tooLarge
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("Received-\(UUID().uuidString).goldfish")
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }
}
