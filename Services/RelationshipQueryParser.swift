import Foundation

enum RelationshipQueryRole: String, CaseIterable, Equatable {
    case friend, sibling, partner, spouse, child, parent, mother, father
    case coworker, pet, dog, cat, guardian, caregiver, caredFor, connection

    var label: String {
        switch self {
        case .caredFor: return "Person receiving care"
        default: return rawValue.capitalized
        }
    }
}

struct RelationshipQuery: Equatable {
    let anchor: String
    let roles: [RelationshipQueryRole]
}

enum RelationshipQueryParseResult: Equatable {
    case plainText
    case query(RelationshipQuery)
    case unsupported(String)
}

struct RelationshipQueryParser {
    private static let aliases: [String: RelationshipQueryRole] = [
        "friend": .friend, "friends": .friend,
        "sibling": .sibling, "siblings": .sibling, "brother": .sibling, "brothers": .sibling,
        "sister": .sibling, "sisters": .sibling,
        "partner": .partner, "partners": .partner,
        "spouse": .spouse, "spouses": .spouse, "husband": .spouse, "husbands": .spouse,
        "wife": .spouse, "wives": .spouse,
        "child": .child, "children": .child, "son": .child, "sons": .child,
        "daughter": .child, "daughters": .child,
        "parent": .parent, "parents": .parent, "mother": .mother, "mothers": .mother,
        "father": .father, "fathers": .father,
        "coworker": .coworker, "coworkers": .coworker, "colleague": .coworker, "colleagues": .coworker,
        "pet": .pet, "pets": .pet, "dog": .dog, "dogs": .dog, "cat": .cat, "cats": .cat,
        "guardian": .guardian, "guardians": .guardian,
        "caregiver": .caregiver, "caregivers": .caregiver,
        "carer": .caregiver, "carers": .caregiver,
        "caredfor": .caredFor, "cared-for": .caredFor,
        "care recipient": .caredFor, "person receiving care": .caredFor,
        "connection": .connection, "connections": .connection
    ]
    private static let unsupportedRelationshipWords: Set<String> = [
        "cousin", "cousins", "neighbor", "neighbors", "neighbour", "neighbours",
        "aunt", "aunts", "uncle", "uncles", "niece", "nieces", "nephew", "nephews"
    ]

    static func parse(_ text: String) -> RelationshipQueryParseResult {
        guard text.count <= 500 else { return .unsupported("That relationship search is too long.") }
        let normalized = text.replacingOccurrences(of: "’", with: "'").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return .plainText }

        let (body, intended) = unwrap(normalized)
        let cleaned = trimPunctuation(body)
        if cleaned.isEmpty { return intended ? .unsupported("Please name a person and relationship to search.") : .plainText }

        if let forward = forwardQuery(cleaned) {
            return forward.roles.count > 12 ? .unsupported("That relationship search has too many links.") : .query(forward)
        }
        if let reverse = reverseQuery(cleaned) {
            return reverse.roles.count > 12 ? .unsupported("That relationship search has too many links.") : .query(reverse)
        }
        if intended || clearlyMalformedRelationshipChain(cleaned) || clearlyMalformedReverse(cleaned) {
            return .unsupported("I couldn't understand that relationship search. Try “Sam's friend”.")
        }
        return .plainText
    }

    private static func unwrap(_ input: String) -> (String, Bool) {
        let patterns = [
            "^how\\s+is\\s+(.+?)\\s+called[?!.]*$",
            "^what\\s+is\\s+(.+?)\\s+called[?!.]*$",
            "^what\\s+is\\s+the\\s+name\\s+of\\s+(.+?)[?!.]*$",
            "^what\\s+is\\s+(.+?)[?!.]*$",
            "^what's\\s+(.+?)[?!.]*$",
            "^who\\s+is\\s+(.+?)[?!.]*$"
            ,"^who\\s+are\\s+(.+?)[?!.]*$"
        ]
        for pattern in patterns {
            if let body = firstCapture(pattern, in: input) { return (body, true) }
        }
        return (input, false)
    }

    private static func forwardQuery(_ input: String) -> RelationshipQuery? {
        let pieces = splitPossessiveChain(input)
        if pieces.count == 1 {
            let words = pieces[0].split(whereSeparator: { $0.isWhitespace }).map(String.init)
            if words.count == 2, ["my", "me", "you", "your"].contains(words[0].lowercased()),
               let relationship = role(in: words[1]), let anchor = validAnchor(words[0]) {
                return RelationshipQuery(anchor: anchor, roles: [relationship])
            }
            return nil
        }
        var anchorPart = pieces[0]
        var roles: [RelationshipQueryRole] = []
        let firstWords = anchorPart.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if firstWords.count == 2, ["my", "me", "you", "your"].contains(firstWords[0].lowercased()),
           let firstRole = role(in: firstWords[1]) {
            anchorPart = firstWords[0]
            roles.append(firstRole)
        }
        guard let anchor = validAnchor(anchorPart) else { return nil }
        for piece in pieces.dropFirst() {
            guard let role = role(in: piece) else { return nil }
            roles.append(role)
        }
        return roles.isEmpty ? nil : RelationshipQuery(anchor: anchor, roles: roles)
    }

    private static func reverseQuery(_ input: String) -> RelationshipQuery? {
        let pattern = "^(.*?)\\s+of(?:\\s+the)?\\s+(.+)$"
        guard let first = firstCapture(pattern, in: input),
              let remainder = secondCapture(pattern, in: input),
              let outerRole = role(in: first) else { return nil }
        if let nested = reverseQuery(remainder) {
            return RelationshipQuery(anchor: nested.anchor, roles: nested.roles + [outerRole])
        }
        guard let anchor = validAnchor(remainder) else { return nil }
        return RelationshipQuery(anchor: anchor, roles: [outerRole])
    }

    private static func splitPossessiveChain(_ input: String) -> [String] {
        var parts: [String] = [], start = input.startIndex, index = start
        while index < input.endIndex {
            let character = input[index]
            if character == "'" {
                let next = input.index(after: index)
                if next < input.endIndex, input[next].lowercased() == "s" {
                    let afterS = input.index(after: next)
                    if afterS == input.endIndex || input[afterS].isWhitespace {
                        parts.append(String(input[start..<index]).trimmingCharacters(in: .whitespaces))
                        start = afterS
                        index = afterS
                        continue
                    }
                } else if next == input.endIndex || input[next].isWhitespace {
                    parts.append(String(input[start..<index]).trimmingCharacters(in: .whitespaces))
                    start = next
                    index = next
                    continue
                }
            }
            index = input.index(after: index)
        }
        parts.append(String(input[start...]).trimmingCharacters(in: .whitespaces))
        return parts
    }

    private static func role(in text: String) -> RelationshipQueryRole? {
        let words = text.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let filtered = words.filter { $0 != "the" }
        let phrase = filtered.joined(separator: " ").trimmingCharacters(in: .punctuationCharacters)
        if phrase == "person receiving care" || phrase == "care recipient" || phrase == "cared for" { return .caredFor }
        guard filtered.count == 1 else { return nil }
        return aliases[filtered[0].trimmingCharacters(in: .punctuationCharacters)]
    }

    private static func validAnchor(_ text: String) -> String? {
        var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"“”‘’"))
        guard !value.isEmpty, value.count <= 120 else { return nil }
        let lower = value.lowercased()
        guard !lower.contains(" of "), lower != "of", lower != "the" else { return nil }
        let allowed = value.allSatisfy { $0.isLetter || $0.isNumber || $0.isWhitespace || $0 == "-" || $0 == "'" || $0 == "." }
        if value.lowercased() == "my" { value = "me" }
        if value.lowercased() == "your" { value = "you" }
        return allowed ? value : nil
    }

    private static func trimPunctuation(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters).subtracting(CharacterSet(charactersIn: "'")))
    }

    private static func clearlyMalformedRelationshipChain(_ input: String) -> Bool {
        let pieces = splitPossessiveChain(input)
        guard pieces.count > 1 else { return false }
        return pieces.dropFirst().contains { piece in
            if role(in: piece) != nil { return true }
            let words = piece.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
            return words.count == 1 && unsupportedRelationshipWords.contains(words[0])
        }
    }

    private static func clearlyMalformedReverse(_ input: String) -> Bool {
        guard input.range(of: " of ", options: .caseInsensitive) != nil else { return false }
        let first = input.components(separatedBy: " of ").first ?? input
        return role(in: first) != nil || unsupportedRelationshipWords.contains(first.lowercased().trimmingCharacters(in: .whitespaces))
    }

    private static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1, let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func secondCapture(_ pattern: String, in text: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 2, let range = Range(match.range(at: 2), in: text) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
