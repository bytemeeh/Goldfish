import Foundation
import SwiftData

// MARK: - VCardExporter
/// Serializes `Person` objects into vCard 3.0 format (RFC 2426).
/// Includes custom `X-GOLDFISH-*` extensions to preserve graph metadata.
struct VCardExporter {

    // MARK: - Manifest Constants
    
    /// The special FN used to identify the Goldfish manifest vCard.
    static let manifestName = VCardParser.manifestName
    
    /// Current export format version.
    static let exportVersion = "1.1"

    /// Exports a list of contacts to vCard 3.0 data (UTF-8).
    /// - Parameters:
    ///   - contacts: The contacts to export.
    ///   - includeManifest: If true, prepends a Goldfish manifest vCard header.
    /// - Returns: vCard data (UTF-8).
    static func export(_ contacts: [Person], includeManifest: Bool = false) -> Data {
        var vcardString = ""

        if includeManifest {
            vcardString += generateManifest(contacts: contacts)
        }

        for person in contacts {
            vcardString += formatContact(person)
        }

        return vcardString.data(using: .utf8) ?? Data()
    }
    
    // MARK: - Manifest Generation
    
    /// Generates a Goldfish manifest vCard that encodes export metadata.
    /// Non-Goldfish apps will see this as a harmless contact named `_GOLDFISH_MANIFEST`.
    /// The Goldfish import parser detects and strips it.
    static func generateManifest(contacts: [Person]) -> String {
        var lines: [String] = []
        
        lines.append("BEGIN:VCARD")
        lines.append("VERSION:3.0")
        lines.append("FN:\(manifestName)")
        lines.append("X-GOLDFISH-EXPORT-VERSION:\(exportVersion)")
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        lines.append("X-GOLDFISH-EXPORT-DATE:\(formatter.string(from: Date()))")
        
        lines.append("X-GOLDFISH-EXPORT-COUNT:\(contacts.count)")
        
        // Count total relationship edges across all contacts
        // Each relationship is stored once, but referenced from both sides.
        // We count unique Relationship objects by collecting IDs.
        var relationshipIDs: Set<UUID> = []
        for person in contacts {
            for rel in person.allRelationships {
                relationshipIDs.insert(rel.id)
            }
        }
        lines.append("X-GOLDFISH-EXPORT-CONNECTIONS:\(relationshipIDs.count)")
        
        lines.append("END:VCARD")
        
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func formatContact(_ person: Person) -> String {
        var lines: [String] = []

        lines.append("BEGIN:VCARD")
        lines.append("VERSION:3.0")

        lines.append("X-GOLDFISH-CONTACT-VERSION:1.1")

        // UID
        lines.append("UID:\(person.id.uuidString)")

        // FN (Full Name)
        lines.append(formatLine(key: "FN", value: person.name))

        // N (Structured Name: Family;Given;Middle;Prefix;Suffix)
        // We only have a single name string, so we try to split it intelligently
        let (given, family) = splitName(person.name)
        lines.append(VCardTextCodec.property("N", components: [family, given, "", "", ""], separator: ";"))

        // TEL (Phone)
        if let phone = person.phone, !phone.isEmpty {
            lines.append(formatLine(key: "TEL;TYPE=CELL", value: phone))
        }

        // EMAIL
        if let email = person.email, !email.isEmpty {
            lines.append(formatLine(key: "EMAIL;TYPE=INTERNET", value: email))
        }

        // BDAY (ISO 8601: YYYY-MM-DD)
        if let birthday = person.birthday {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            lines.append("BDAY:" + formatter.string(from: birthday))
        }

        // NOTE
        if let notes = person.notes, !notes.isEmpty {
            lines.append(formatLine(key: "NOTE", value: notes))
        }

        // ADR (Address: ;;Street;City;State;Zip;Country)
        // Only include if at least one field is present
        let street = person.street ?? ""
        let city = person.city ?? ""
        let state = person.state ?? ""
        let zip = person.postalCode ?? ""
        let country = person.country ?? ""
        
        if !street.isEmpty || !city.isEmpty || !state.isEmpty || !zip.isEmpty || !country.isEmpty {
            lines.append(VCardTextCodec.property("ADR;TYPE=HOME", components: ["", "", street, city, state, zip, country], separator: ";"))
        }

        // PHOTO
        if let photoData = person.photoData {
            let base64 = photoData.base64EncodedString()
            // Photo lines are long, so we rely on the line folding logic in formatLine
            // However, vCard 3.0 style for photo is often just one folded line.
            lines.append(formatLine(key: "PHOTO;ENCODING=b;TYPE=JPEG", value: base64))
        }

        // MARK: - X-GOLDFISH Extensions

        // TAGS
        if !person.tags.isEmpty {
            lines.append(VCardTextCodec.property("X-GOLDFISH-TAGS", components: person.tags, separator: ","))
        }

        // FAVORITE
        if person.isFavorite {
            lines.append("X-GOLDFISH-FAVORITE:true")
        }

        // COLOR
        if let color = person.color {
            lines.append(formatLine(key: "X-GOLDFISH-COLOR", value: color))
        }

        // IS-ME
        if person.isMe {
            lines.append("X-GOLDFISH-IS-ME:true")
        }
        if person.isPet {
            lines.append("X-GOLDFISH-KIND:\(person.contactKind.rawValue)")
        }

        // CIRCLES
        // We export all circles the person is a member of (excluding manually excluded ones)
        let activeCircles = person.circleContacts.filter { !$0.manuallyExcluded }.map(\.circle)
            .sorted { $0.id.uuidString < $1.id.uuidString }
        for circle in activeCircles {
            // Keep the original name field for older versions and other vCard consumers.
            lines.append(formatLine(key: "X-GOLDFISH-CIRCLE", value: circle.name))
            if let metadata = circle.transferMetadata.encoded {
                lines.append(formatLine(key: "X-GOLDFISH-GROUP", value: metadata))
            }
        }

        // Export each known perspective. Unknown-direction "other" edges are
        // emitted only by their stored subject, so a round trip keeps one row.
        for rel in person.allRelationships {
            let other = rel.otherContact(from: person)
            let type = rel.effectiveType(for: person)
            
            // Only export if we have a valid relationship type
            if type != .other || rel.fromContact.id == person.id {
                 lines.append("X-GOLDFISH-RELATED-TO:\(other.id.uuidString);\(type.rawValue)")
            }
        }

        lines.append("END:VCARD")
        
        // Join with CRLF and fold
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    // MARK: - Helper Methods

    /// Formats a vCard property line, escaping values and folding lines at 75 octets.
    private static func formatLine(key: String, value: String) -> String {
        VCardTextCodec.property(key, components: [value], separator: "")
    }

    /// Simple heuristic to split a full name into Given and Family names.
    private static func splitName(_ name: String) -> (given: String, family: String) {
        let parts = name.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: " ")
        if parts.isEmpty { return ("", "") }
        if parts.count == 1 { return (parts[0], "") }
        
        let given = parts.dropLast().joined(separator: " ")
        let family = parts.last ?? ""
        return (given, family)
    }
}

extension GoldfishCircle {
    var transferMetadata: GroupTransferMetadata {
        let role: GroupTransferMetadata.SystemRole?
        if !isSystem { role = nil }
        else if shouldAutoAssign(for: .mother) || shouldAutoAssign(for: .parent) { role = .family }
        else if shouldAutoAssign(for: .friend) { role = .friends }
        else if shouldAutoAssign(for: .coworker) { role = .professional }
        else { role = nil }
        return GroupTransferMetadata(id: id, name: name, color: color, systemRole: role)
    }
}
