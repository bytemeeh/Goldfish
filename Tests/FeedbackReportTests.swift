import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import Goldfish

final class FeedbackReportTests: XCTestCase {
    private let details = FeedbackDiagnostics(appName: "Goldfish", version: "1.2", build: "45",
                                              osVersion: "26.4", deviceModel: "iPhone")

    func testEmptyOrWhitespaceOnlyReportsCannotBeSent() {
        for message in ["", " \n\t "] {
            let report = FeedbackReport(kind: .bug, message: message, diagnostics: details)
            XCTAssertFalse(report.isValid)
            XCTAssertNotNil(report.validationMessage)
        }
    }

    func testBugReportKeepsUserMessageAndOptionalReproductionDetails() {
        let report = FeedbackReport(kind: .bug, message: "  A marker moved unexpectedly.\nIt happened twice.  ",
                                    steps: "1. Open Pond\n2. Drag Alex", expectedResult: "Keep Alex in Family",
                                    area: "Pond", diagnostics: details)
        XCTAssertTrue(report.isValid)
        XCTAssertEqual(report.subject, "[Goldfish] Bug report — Pond")
        XCTAssertTrue(report.body.contains("A marker moved unexpectedly.\nIt happened twice."))
        XCTAssertTrue(report.body.contains("Steps to reproduce\n1. Open Pond\n2. Drag Alex"))
        XCTAssertTrue(report.body.contains("Expected result\nKeep Alex in Family"))
        XCTAssertTrue(report.body.contains("App: Goldfish\nVersion: 1.2 (45)\niOS: 26.4\nDevice: iPhone"))
    }

    func testShortMessageAloneIsEnoughAndEmptyOptionalSectionsAreOmitted() {
        let report = FeedbackReport(kind: .bug, message: "The add button did not respond.", diagnostics: details)
        XCTAssertTrue(report.isValid)
        XCTAssertFalse(report.body.contains("Screen or feature"))
        XCTAssertFalse(report.body.contains("Steps to reproduce"))
        XCTAssertFalse(report.body.contains("Expected result"))
    }

    func testSwitchingToIdeaDoesNotSendHiddenBugFields() {
        let report = FeedbackReport(kind: .idea, message: "Let me pin a line.",
                                    steps: "Old bug steps", expectedResult: "Old expected result", diagnostics: details)
        XCTAssertTrue(report.isValid)
        XCTAssertEqual(report.subject, "[Goldfish] Idea")
        XCTAssertTrue(report.body.contains("Idea\nLet me pin a line."))
        XCTAssertFalse(report.body.contains("Old bug"))
        XCTAssertFalse(report.body.contains("Old expected"))
    }

    func testAppDetailsOptOutRemovesAllAutomaticDeviceFields() {
        let report = FeedbackReport(kind: .bug, message: "Please improve dragging.",
                                    includesAppDetails: false, diagnostics: details)
        for omitted in ["App details", "Version:", "iOS:", "Device:", "26.4", "iPhone"] {
            XCTAssertFalse(report.body.contains(omitted))
            XCTAssertFalse(report.shareText.contains(omitted))
        }
    }

    func testDiagnosticsAreAnExplicitMinimalAllowlist() {
        XCTAssertEqual(details.text, "App: Goldfish\nVersion: 1.2 (45)\niOS: 26.4\nDevice: iPhone")
    }

    func testLongReportsAreRejectedWithoutSilentlyTruncatingUserText() {
        var report = FeedbackReport(kind: .bug, message: String(repeating: "a", count: FeedbackReport.messageLimit), diagnostics: details)
        XCTAssertTrue(report.isValid)
        report.message.append("b")
        XCTAssertFalse(report.isValid)
        XCTAssertTrue(report.body.contains(report.message))
        report.message = "Bug"
        report.steps = String(repeating: "a", count: FeedbackReport.stepsLimit + 1)
        XCTAssertFalse(report.isValid)
        report.steps = ""
        report.expectedResult = String(repeating: "a", count: FeedbackReport.expectedResultLimit + 1)
        XCTAssertFalse(report.isValid)
        report.expectedResult = ""
        report.area = String(repeating: "a", count: FeedbackReport.areaLimit + 1)
        XCTAssertFalse(report.isValid)
    }

    func testNonASCIITextAndLineBreaksSurviveCopyAndShare() {
        let message = "水の輪 🐟\nGröße & Abstände + 50%"
        let report = FeedbackReport(kind: .idea, message: message, diagnostics: details)
        XCTAssertTrue(report.shareText.contains(message))
        XCTAssertTrue(report.shareText.hasPrefix("Subject: [Goldfish] Idea\n\n"))
    }

    func testSubjectHasNoUserSuppliedLineBreaksAndIsBounded() {
        let report = FeedbackReport(kind: .bug, message: "Bug", area: "Pond\r\nCc: elsewhere@example.com\t" + String(repeating: "x", count: 100), diagnostics: details)
        XCTAssertFalse(report.subject.contains("\n"))
        XCTAssertFalse(report.subject.contains("\r"))
        XCTAssertFalse(report.subject.contains("\t"))
        XCTAssertLessThanOrEqual(report.subject.count, "[Goldfish] Bug report — ".count + 60)
    }

    func testBrandComesFromEachAppsDiagnostics() {
        let lines = FeedbackDiagnostics(appName: "LINES", version: "1.0", build: "1", osVersion: "26.4", deviceModel: "iPad")
        let report = FeedbackReport(kind: .bug, message: "A line label overlaps.", diagnostics: lines)
        XCTAssertEqual(report.subject, "[LINES] Bug report")
        XCTAssertTrue(report.body.hasPrefix("LINES bug report"))
        XCTAssertFalse(report.shareText.contains("Goldfish"))
    }

    func testMissingOrMalformedSupportAddressesDoNotCreateRecipients() {
        for address: String? in [nil, "", " ", "not-an-email", "support@example.com\r\nCc: other@example.com",
                                "one@example.com,two@example.com", "mailto:support@example.com", "support@example.com?bcc=other@example.com"] {
            XCTAssertNil(FeedbackConfiguration.validatedRecipient(address))
        }
        XCTAssertEqual(FeedbackConfiguration.validatedRecipient(" support+bugs@example.com "), "support+bugs@example.com")
    }
}

@MainActor
final class FeedbackScreenshotTests: XCTestCase {
    private func encodedImage(size: CGSize, properties: [CFString: Any] = [:]) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage), properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    func testLargeScreenshotIsDownsampledBeforeAttachment() throws {
        let source = try encodedImage(size: CGSize(width: 3_072, height: 1_024))
        let output = try FeedbackScreenshot.prepare(source)
        let image = try XCTUnwrap(UIImage(data: output)?.cgImage)
        XCTAssertLessThanOrEqual(max(image.width, image.height), FeedbackScreenshot.maximumPixelDimension)
        XCTAssertLessThanOrEqual(output.count, FeedbackScreenshot.outputByteLimit)
        XCTAssertEqual(Double(image.width) / Double(image.height), 3, accuracy: 0.01)
    }

    func testScreenshotMetadataIsNotCopiedToAttachment() throws {
        let source = try encodedImage(size: CGSize(width: 120, height: 200), properties: [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 47.0,
                                          kCGImagePropertyGPSLatitudeRef: "N",
                                          kCGImagePropertyGPSLongitude: 8.0,
                                          kCGImagePropertyGPSLongitudeRef: "E"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "Private source metadata"]
        ])
        let inputImage = try XCTUnwrap(CGImageSourceCreateWithData(source as CFData, nil))
        let inputProperties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(inputImage, 0, nil) as? [CFString: Any])
        XCTAssertNotNil(inputProperties[kCGImagePropertyGPSDictionary], "The fixture must actually contain GPS metadata")
        let output = try FeedbackScreenshot.prepare(source)
        let image = try XCTUnwrap(CGImageSourceCreateWithData(output as CFData, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        XCTAssertNil(exif?[kCGImagePropertyExifUserComment])
    }

    func testScreenshotOrientationIsAppliedBeforeSharing() throws {
        let source = try encodedImage(size: CGSize(width: 400, height: 200), properties: [kCGImagePropertyOrientation: 6])
        let image = try XCTUnwrap(UIImage(data: FeedbackScreenshot.prepare(source))?.cgImage)
        XCTAssertEqual(image.width, 200)
        XCTAssertEqual(image.height, 400)
    }

    func testInvalidOrOversizedImageFailsWithRecoverableError() {
        XCTAssertThrowsError(try FeedbackScreenshot.prepare(Data([0, 1, 2]))) { error in
            XCTAssertEqual(error as? FeedbackScreenshot.PreparationError, .invalidImage)
        }
        XCTAssertThrowsError(try FeedbackScreenshot.prepare(Data(repeating: 0, count: FeedbackScreenshot.inputByteLimit + 1))) { error in
            XCTAssertEqual(error as? FeedbackScreenshot.PreparationError, .inputTooLarge)
        }
    }
}
