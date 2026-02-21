import Foundation
import SwiftData

// MARK: - VCardExporter
/// Serializes `Person` objects into vCard 3.0 format (RFC 2426).
/// Includes custom `X-GOLDFISH-*` extensions to preserve graph metadata.
struct VCardExporter {

    // MARK: - Manifest Constants
    
    /// The special FN used to identify the Goldfish manifest vCard.
    static let manifestName = "_GOLDFISH_MANIFEST"
    
    /// Current export format version.
    static let exportVersion = "1.0"

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

        // UID
        lines.append("UID:\(person.id.uuidString)")

        // FN (Full Name)
        lines.append(formatLine(key: "FN", value: person.name))

        // N (Structured Name: Family;Given;Middle;Prefix;Suffix)
        // We only have a single name string, so we try to split it intelligently
        let (given, family) = splitName(person.name)
        lines.append(formatLine(key: "N", value: "\(family);\(given);;;"))

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
            let addressValue = ";;\(street);\(city);\(state);\(zip);\(country)"
            lines.append(formatLine(key: "ADR;TYPE=HOME", value: addressValue))
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
            // Lowercase and escape commas within tags
            let escapedTags = person.tags.map {
                $0.lowercased().replacingOccurrences(of: ",", with: "\\,")
            }.joined(separator: ",")
            lines.append(formatLine(key: "X-GOLDFISH-TAGS", value: escapedTags))
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

        // CIRCLES
        // We export all circles the person is a member of (excluding manually excluded ones)
        let activeCircles = person.circleContacts.filter { !$0.manuallyExcluded }.map { $0.circle.name }
        for circleName in activeCircles {
            lines.append(formatLine(key: "X-GOLDFISH-CIRCLE", value: circleName))
        }

        // RELATED-TO
        // We include relationship types this person HAS relative to others in the export.
        // Format: <UUID>;<type>
        // "This person IS the <type> of <UUID>"
        // So we look at outgoing relationships where this person is the 'from'.
        // Directionality: Relationship(from: A, to: B, type: mother) -> A is mother of B.
        // So in A's vCard: X-GOLDFISH-RELATED-TO: B_UUID;mother
        
        // We also need to handle symmetric relationships.
        // Relationship(from: A, to: B, type: friend) -> A is friend of B.
        // So in A's vCard: X-GOLDFISH-RELATED-TO: B_UUID;friend
        
        // We also need incoming relationships?
        // If B is A's child (Relationship(from: B, to: A, type: child)), then A is B's mother/father?
        // The spec says: "The vCard containing X-GOLDFISH-RELATED-TO:<UUID>;mother means 'this contact IS the mother OF the contact with the given UUID.'"
        // So we strictly export specific relationship records where this person is the 'from' (subject).
        // Wait, for bidirectional graph, we should export everything we know about this person.
        //
        // If we have Relationship(from: A, to: B, type: mother), A is mother.
        // A's vCard: RELATED-TO: B;mother
        //
        // If we have Relationship(from: B, to: A, type: child), B is child.
        // A is the parent. Does A's vCard need to say "I am parent of B"?
        // The relationship B->A (child) implies A is parent of B.
        // But the relationship record is stored as (from: B, to: A, type: child).
        // A's vCard could act as the source of truth for A's roles.
        //
        // However, the spec example shows:
        // Anna (Mother): X-GOLDFISH-RELATED-TO: <Luca's UUID>;mother
        // Luca (Child): X-GOLDFISH-RELATED-TO: <Anna's UUID>;child
        //
        // This implies we simply iterate `outgoingRelationships` and export them.
        // For symmetric relationships (friend), they are stored once.
        // If stored as (A, B, friend), A has it in outgoing. B has it in incoming.
        // If we only export outgoing, B's vCard won't say "friend of A".
        //
        // Correct logic:
        // Iterate all relationships connected to this person.
        // Calculate the effective type *from this person's perspective*.
        // If effective type is valid, export it.
        //
        // Example: Friend (symmetric)
        // Stored: A -> B (friend)
        // A's vCard: effectiveType(for: A) = friend. Export: B;friend
        // B's vCard: effectiveType(for: B) = friend (inverse of friend is friend). Export: A;friend
        //
        // Example: Mother/Child
        // Stored: A -> B (mother)
        // A's vCard: effectiveType(for: A) = mother. Export: B;mother
        // B's vCard: effectiveType(for: B) = child (inverse of mother). Export: A;child
        //
        // This ensures fully connected graph restoration even if only one person is imported.
        
        for rel in person.allRelationships {
            let other = rel.otherContact(from: person)
            let type = rel.effectiveType(for: person)
            
            // Only export if we have a valid relationship type
            if type != .other {
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
        let escapedValue = escapeValue(value)
        let line = "\(key):\(escapedValue)"
        return foldLine(line)
    }

    /// Escapes special characters in vCard text values (RFC 2426).
    /// Escapes: \ -> \\, , -> \, , ; -> \;, \n -> \n
    private static func escapeValue(_ value: String) -> String {
        return value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "") // Remove CR, keep LF as escaped \n
    }

    /// Folds lines to max 75 octets (bytes), as per RFC 2426.
    /// Continuation lines start with specific whitespace (SPACE).
    private static func foldLine(_ line: String) -> String {
        let maxLineLength = 75
        
        // If strict UTF-8 byte counting is needed, it's complex.
        // Most vCard parsers accept character-based folding or are lenient.
        // Swift strings are character-based. We'll use character count for simplicity
        // as standard ASCII chars are 1 byte and typical names match.
        // For strict compliance we should count bytes, but that might split multi-byte chars.
        // Safe approach: split by char count, which is always <= byte count for ASCII,
        // and safe for UTF-8 (won't split a character).
        
        if line.count <= maxLineLength {
            return line
        }

        var result = ""
        var currentIndex = line.startIndex
        
        // First line: 75 chars
        let firstLineEnd = line.index(currentIndex, offsetBy: maxLineLength, limitedBy: line.endIndex) ?? line.endIndex
        result += line[currentIndex..<firstLineEnd]
        currentIndex = firstLineEnd

        // Subsequent lines: 74 chars (prefixed with 1 space)
        while currentIndex < line.endIndex {
            result += "\r\n " // Fold sequence: CRLF + Space
            
            let remaining = line.distance(from: currentIndex, to: line.endIndex)
            let chunkLength = min(74, remaining)
            let nextIndex = line.index(currentIndex, offsetBy: chunkLength)
            
            result += line[currentIndex..<nextIndex]
            currentIndex = nextIndex
        }

        return result
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
