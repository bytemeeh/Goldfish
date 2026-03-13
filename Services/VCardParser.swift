import Foundation
import os
import SwiftData // For RelationshipType

// MARK: - VCardContact
/// A lightweight intermediate representation of a parsed vCard contact.
struct VCardContact {
    var uid: UUID?
    var name: String?
    var phone: String?
    var email: String?
    var birthday: Date?
    var notes: String?
    var photoData: Data?
    
    // Address components
    var street: String?
    var city: String?
    var state: String?
    var postalCode: String?
    var country: String?

    // Goldfish Extensions
    var tags: [String] = []
    var isFavorite: Bool = false
    var color: String?
    var isMe: Bool = false
    var circles: [String] = []
    var relatedTo: [(uuid: UUID, type: RelationshipType)] = []
}

// MARK: - GoldfishManifest
/// Metadata extracted from the `_GOLDFISH_MANIFEST` vCard header.
/// Present only in files exported by Goldfish.
struct GoldfishManifest {
    /// Export format version (e.g., "1.0").
    var version: String = "1.0"
    /// ISO 8601 date when the export was created.
    var exportDate: String?
    /// Number of contacts in the export bundle.
    var contactCount: Int = 0
    /// Number of relationship edges in the export bundle.
    var connectionCount: Int = 0
}

// MARK: - VCardParseResult
/// The result of parsing a vCard file, containing an optional Goldfish manifest
/// and the list of contacts.
struct VCardParseResult {
    /// Non-nil if the file was exported from Goldfish (manifest detected).
    var manifest: GoldfishManifest?
    /// Parsed contacts (manifest vCard is excluded).
    var contacts: [VCardContact]
    
    /// Whether this file was exported from the Goldfish app.
    var isGoldfishFormat: Bool { manifest != nil }
}

// MARK: - VCardParser
/// Parses vCard 3.0 data (RFC 2426) into `VCardContact` objects.
/// Handles custom `X-GOLDFISH-*` extensions and Goldfish manifest detection.
struct VCardParser {
    
    private static let logger = Logger(subsystem: "com.goldfish.app", category: "VCardParser")

    /// Parses vCard data and returns a full result including manifest detection.
    static func parseWithManifest(_ data: Data) -> VCardParseResult {
        guard let string = String(data: data, encoding: .utf8) else {
            logger.error("Failed to decode vCard data as UTF-8")
            return VCardParseResult(manifest: nil, contacts: [])
        }

        var contacts: [VCardContact] = []
        var manifest: GoldfishManifest?
        
        let chunks: [String] = string.components(separatedBy: "BEGIN:VCARD")
        
        for chunk in chunks {
            let trim = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            if trim.isEmpty { continue }
            guard trim.contains("END:VCARD") else { continue }
            
            // Check if this is a manifest vCard
            if trim.contains(VCardExporter.manifestName) {
                manifest = parseManifest(block: trim)
                continue
            }
            
            if let contact = parseSingleContact(block: trim) {
                contacts.append(contact)
            }
        }
        
        return VCardParseResult(manifest: manifest, contacts: contacts)
    }

    /// Legacy parse method — returns contacts only (backward compatible).
    /// Gracefully skips manifest and malformed entries.
    static func parse(_ data: Data) -> [VCardContact] {
        return parseWithManifest(data).contacts
    }

    // MARK: - Manifest Parsing
    
    /// Parses a Goldfish manifest vCard block.
    private static func parseManifest(block: String) -> GoldfishManifest {
        var manifest = GoldfishManifest()
        let lines = unfoldLines(block)
        
        for line in lines {
            let parts: [String.SubSequence] = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }
            
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces).uppercased()
            let rawValue = String(parts[1]).trimmingCharacters(in: .whitespaces)
            
            switch key {
            case "X-GOLDFISH-EXPORT-VERSION":
                manifest.version = rawValue
            case "X-GOLDFISH-EXPORT-DATE":
                manifest.exportDate = rawValue
            case "X-GOLDFISH-EXPORT-COUNT":
                manifest.contactCount = Int(rawValue) ?? 0
            case "X-GOLDFISH-EXPORT-CONNECTIONS":
                manifest.connectionCount = Int(rawValue) ?? 0
            default:
                break
            }
        }
        
        return manifest
    }

    // MARK: - Private Parsing Logic

    private static func parseSingleContact(block: String) -> VCardContact? {
        var contact = VCardContact()
        let lines = unfoldLines(block)
        
        for line in lines {
            // Split into Key and Value
            // FN:Marcel Meeh -> Key: FN, Value: Marcel Meeh
            // ADR;TYPE=HOME:;;Street... -> Key: ADR;TYPE=HOME, Value: ;;Street...
            
            let parts: [String.SubSequence] = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }
            
            let keyPart = String(parts[0]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(parts[1]).trimmingCharacters(in: .whitespaces) // Don't unescape immediately, some fields need raw structure
            
            // Key might have params: TEL;TYPE=CELL
            let keyComponents = keyPart.components(separatedBy: ";")
            let key = keyComponents.first?.uppercased() ?? ""
            
            switch key {
            case "UID":
                if let uuid = UUID(uuidString: rawValue) {
                    contact.uid = uuid
                }
            case "FN":
                contact.name = unescape(rawValue)
            case "N":
                // If FN is missing, we could try to construct name from N
                // But for now we rely on FN which is standard for display name
                if contact.name == nil {
                     let nameParts = rawValue.components(separatedBy: ";").map { unescape($0) }
                     let family = nameParts.indices.contains(0) ? nameParts[0] : ""
                     let given = nameParts.indices.contains(1) ? nameParts[1] : ""
                     contact.name = "\(given) \(family)".trimmingCharacters(in: .whitespaces)
                }
            case "TEL":
                contact.phone = unescape(rawValue)
            case "EMAIL":
                contact.email = unescape(rawValue)
            case "BDAY":
                // ISO 8601 YYYY-MM-DD
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd"
                if let date = formatter.date(from: rawValue) {
                    contact.birthday = date
                }
            case "NOTE":
                contact.notes = unescape(rawValue)
            case "ADR":
                // ;;Street;City;State;Zip;Country
                let components = rawValue.components(separatedBy: ";").map { unescape($0) }
                // RFC 2426: Post Office Box; Extended Address; Street; City; Region; Postal Code; Country
                // Index 0: PO Box
                // Index 1: Extended
                // Index 2: Street
                if components.count > 2 { contact.street = components[2] }
                if components.count > 3 { contact.city = components[3] }
                if components.count > 4 { contact.state = components[4] }
                if components.count > 5 { contact.postalCode = components[5] }
                if components.count > 6 { contact.country = components[6] }
            case "PHOTO":
                // Value is base64
                // Sometimes type is defined in params
                if let data = Data(base64Encoded: rawValue, options: .ignoreUnknownCharacters) {
                    contact.photoData = data
                }
            
            // Custom Extensions
            case "X-GOLDFISH-TAGS":
                // Comma separated, escaped
                let tags = unescape(rawValue).components(separatedBy: ",")
                contact.tags = tags.filter { !$0.isEmpty }
            case "X-GOLDFISH-FAVORITE":
                contact.isFavorite = (rawValue.lowercased() == "true")
            case "X-GOLDFISH-COLOR":
                contact.color = rawValue // Parsing handles validation later
            case "X-GOLDFISH-IS-ME":
                contact.isMe = (rawValue.lowercased() == "true")
            case "X-GOLDFISH-CIRCLE":
                contact.circles.append(unescape(rawValue))
            case "X-GOLDFISH-RELATED-TO":
                // UUID;type
                let relParts = rawValue.split(separator: ";")
                if relParts.count == 2,
                   let uuid = UUID(uuidString: String(relParts[0])),
                   let type = RelationshipType(rawValue: String(relParts[1])) {
                    contact.relatedTo.append((uuid, type))
                }
            default:
                break
            }
        }
        
        // Validation: Must have at least a Name
        if contact.name == nil || contact.name?.isEmpty == true {
            logger.warning("Skipping vCard without FN/Name")
            return nil
        }
        
        return contact
    }

    /// Unfolds "folded" lines (lines starting with space/tab are continuations).
    /// Returns array of complete property lines.
    private static func unfoldLines(_ string: String) -> [String] {
        var unfolded: [String] = []
        var currentLine = ""
        
        let rawLines = string.components(separatedBy: .newlines)
        
        for line in rawLines {
            if line.isEmpty { continue }
            
            // Check for continuation (starts with space or tab)
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                // It's a continuation -> append to current line (minus the leading space)
                // RFC 2426 says "sequence of CRLF followed by at least one white space character is unfolded"
                // The CRLF is already removed by components(separatedBy:), so we just drop the first char
                currentLine += line.dropFirst()
            } else {
                // New property line
                if !currentLine.isEmpty {
                    unfolded.append(currentLine)
                }
                currentLine = line
            }
        }
        
        if !currentLine.isEmpty {
            unfolded.append(currentLine)
        }
        
        return unfolded
    }

    /// Unescapes vCard text values.
    /// \\ -> \, \, -> , \; -> ; \n -> newline
    private static func unescape(_ value: String) -> String {
        return value
            .replacingOccurrences(of: "\\n", with: "\n")
            .replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",")
            .replacingOccurrences(of: "\\;", with: ";")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
