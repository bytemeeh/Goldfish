import Foundation

/// Escaping, structured fields and UTF-8 folding shared by vCard import/export.
enum VCardTextCodec {
    static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    static func unescape(_ value: String) -> String {
        var result = "", escaped = false
        for character in value {
            if escaped {
                switch character {
                case "n", "N": result.append("\n")
                case "\\", ",", ";": result.append(character)
                default: result.append("\\"); result.append(character)
                }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                result.append(character)
            }
        }
        if escaped { result.append("\\") }
        return result
    }

    /// Split before unescaping so a comma within a tag stays within that tag.
    static func components(_ value: String, separatedBy separator: Character) -> [String] {
        var pieces: [String] = [], current = "", escaped = false
        for character in value {
            if character == separator && !escaped {
                pieces.append(unescape(current)); current = ""
            } else {
                current.append(character)
            }
            if escaped { escaped = false }
            else if character == "\\" { escaped = true }
        }
        pieces.append(unescape(current))
        return pieces
    }

    static func property(_ key: String, components: [String], separator: String) -> String {
        fold(key + ":" + components.map(escape).joined(separator: separator))
    }

    /// Fold at 75 octets, including continuation whitespace, without splitting UTF-8 scalars.
    static func fold(_ line: String) -> String {
        var result = "", octets = 0
        for scalar in line.unicodeScalars {
            let text = String(scalar), count = text.utf8.count
            if octets + count > 75 { result += "\r\n "; octets = 1 }
            result += text
            octets += count
        }
        return result
    }
}
