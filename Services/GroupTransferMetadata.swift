import Foundation

/// Optional vCard extension. UUIDs preserve distinct groups with the same display name.
struct GroupTransferMetadata: Codable, Equatable {
    enum SystemRole: String, Codable { case family, friends, professional }
    let id: UUID
    let name: String
    let color: String
    let systemRole: SystemRole?

    var encoded: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self))?.base64EncodedString()
    }

    static func decode(_ value: String) -> Self? {
        guard value.utf8.count <= 16_384,
              let data = Data(base64Encoded: value),
              let group = try? JSONDecoder().decode(Self.self, from: data),
              !group.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              group.color.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil else { return nil }
        return group
    }
}
