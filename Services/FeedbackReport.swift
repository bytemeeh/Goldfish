import Foundation
import UIKit
import ImageIO

enum FeedbackKind: String, CaseIterable, Identifiable, Sendable {
    case bug
    case idea

    var id: String { rawValue }
    var title: String { self == .bug ? "Report a bug" : "Share an idea" }
    var label: String { self == .bug ? "Bug" : "Idea" }
}

/// The support destination is supplied by the app owner in Info.plist.
/// A missing address leaves the copy/share route available without guessing an inbox.
enum FeedbackConfiguration {
    static var recipient: String? {
        validatedRecipient(Bundle.main.object(forInfoDictionaryKey: "FeedbackSupportEmail") as? String)
    }

    static var appName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "App"
    }

    static var supportURL: URL? {
        validatedHTTPSURL(Bundle.main.object(forInfoDictionaryKey: "GoldfishSupportURL") as? String)
    }

    static var privacyPolicyURL: URL? {
        validatedHTTPSURL(Bundle.main.object(forInfoDictionaryKey: "GoldfishPrivacyPolicyURL") as? String)
    }

    static func validatedRecipient(_ value: String?) -> String? {
        guard let value else { return nil }
        let address = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty, address.count <= 254,
              address.range(of: #"\A[A-Z0-9._%+\-]+@[A-Z0-9](?:[A-Z0-9\-]*[A-Z0-9])?(?:\.[A-Z0-9](?:[A-Z0-9\-]*[A-Z0-9])?)+\z"#,
                            options: [.regularExpression, .caseInsensitive]) != nil else { return nil }
        return address
    }

    static func validatedHTTPSURL(_ value: String?) -> URL? {
        guard let value,
              let url = URL(string: value),
              url.scheme == "https",
              url.host != nil else { return nil }
        return url
    }
}

enum FeedbackScreenshot {
    static let inputByteLimit = 25 * 1024 * 1024
    static let outputByteLimit = 5 * 1024 * 1024
    static let maximumPixelDimension = 2_048

    enum PreparationError: LocalizedError, Equatable {
        case invalidImage
        case inputTooLarge
        case outputTooLarge

        var errorDescription: String? {
            switch self {
            case .invalidImage: return "That image could not be opened. Please choose another screenshot."
            case .inputTooLarge: return "Choose an image smaller than 25 MB."
            case .outputTooLarge: return "That image is too large to attach. Please choose a smaller screenshot."
            }
        }
    }

    /// Downsample before decoding the full bitmap, then encode a new image
    /// without copying source metadata such as GPS or camera information.
    @MainActor
    static func prepare(_ data: Data) throws -> Data {
        guard data.count <= inputByteLimit else { throw PreparationError.inputTooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData,
                            [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension
              ] as CFDictionary),
              let encoded = UIImage(cgImage: image).jpegData(compressionQuality: 0.82) else {
            throw PreparationError.invalidImage
        }
        guard encoded.count <= outputByteLimit else { throw PreparationError.outputTooLarge }
        return encoded
    }
}

/// An explicit allowlist: no contacts, account identifiers, device name, logs,
/// location, or database contents can enter the automatically generated report.
struct FeedbackDiagnostics: Equatable, Sendable {
    let appName: String
    let version: String
    let build: String
    let osVersion: String
    let deviceModel: String

    @MainActor
    static func current(bundle: Bundle = .main) -> Self {
        Self(appName: (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String) ?? "App",
             version: (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "Unknown",
             build: (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "Unknown",
             osVersion: UIDevice.current.systemVersion,
             deviceModel: UIDevice.current.model)
    }

    var text: String {
        "App: \(appName)\nVersion: \(version) (\(build))\niOS: \(osVersion)\nDevice: \(deviceModel)"
    }
}

struct FeedbackReport: Equatable, Sendable {
    static let messageLimit = 10_000
    static let stepsLimit = 5_000
    static let expectedResultLimit = 2_000
    static let areaLimit = 120

    var kind: FeedbackKind
    var message: String
    var steps: String
    var expectedResult: String
    var area: String
    var includesAppDetails: Bool
    let diagnostics: FeedbackDiagnostics

    init(kind: FeedbackKind, message: String = "", steps: String = "", expectedResult: String = "",
         area: String = "", includesAppDetails: Bool = true, diagnostics: FeedbackDiagnostics) {
        self.kind = kind
        self.message = message
        self.steps = steps
        self.expectedResult = expectedResult
        self.area = area
        self.includesAppDetails = includesAppDetails
        self.diagnostics = diagnostics
    }

    var validationMessage: String? {
        if trimmed(message).isEmpty { return "Add a message before sharing your report." }
        if message.count > Self.messageLimit { return "Keep your message under \(Self.messageLimit) characters." }
        if area.count > Self.areaLimit { return "Keep the screen name under \(Self.areaLimit) characters." }
        if kind == .bug {
            if steps.count > Self.stepsLimit { return "Keep the steps under \(Self.stepsLimit) characters." }
            if expectedResult.count > Self.expectedResultLimit { return "Keep the expected result under \(Self.expectedResultLimit) characters." }
        }
        return nil
    }

    var isValid: Bool { validationMessage == nil }

    var subject: String {
        let topic = kind == .bug ? "Bug report" : "Idea"
        let location = singleLine(area, limit: 60)
        return "[\(singleLine(diagnostics.appName, limit: 40))] \(topic)" + (location.isEmpty ? "" : " — \(location)")
    }

    var body: String {
        var sections = ["\(diagnostics.appName) \(kind == .bug ? "bug report" : "feedback")",
                        "\(kind == .bug ? "What happened" : "Idea")\n\(trimmed(message))"]
        if !trimmed(area).isEmpty { sections.append("Screen or feature\n\(trimmed(area))") }
        if kind == .bug {
            if !trimmed(steps).isEmpty { sections.append("Steps to reproduce\n\(trimmed(steps))") }
            if !trimmed(expectedResult).isEmpty { sections.append("Expected result\n\(trimmed(expectedResult))") }
        }
        if includesAppDetails { sections.append("App details\n\(diagnostics.text)") }
        return sections.joined(separator: "\n\n")
    }

    var shareText: String { "Subject: \(subject)\n\n\(body)" }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func singleLine(_ value: String, limit: Int) -> String {
        let clean = value.components(separatedBy: .controlCharacters.union(.whitespacesAndNewlines))
            .filter { !$0.isEmpty }.joined(separator: " ")
        return String(clean.prefix(limit))
    }
}
