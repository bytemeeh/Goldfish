import Foundation

// MARK: - AI Draft Contact
/// Temporary struct representing a contact extracted by the AI.
/// Not persisted to SwiftData — used only for the approval flow.
struct AIDraftContact: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var phone: String?
    var email: String?
    var birthday: String?       // "YYYY-MM-DD" format from LLM; parsed to Date before save
    var notes: String?
    var tags: [String] = []
    var relationshipToMe: String?           // RelationshipType rawValue e.g. "friend"
    var linkedExistingContactName: String?  // Name the LLM chose; fuzzy-matched to existing Person
    var linkedExistingContactId: UUID?      // Resolved locally after receiving the API response
    var confidence: Double = 1.0            // 0–1 from the LLM; shown as badge color in UI

    /// If true, the user has approved this draft and it will be saved
    var isApproved: Bool = true
    /// If true, the user has tapped to edit this draft in the approval view
    var isEditing: Bool = false

    // MARK: - Coding keys (exclude local-only UI state from JSON decode)
    enum CodingKeys: String, CodingKey {
        case name, phone, email, birthday, notes, tags
        case relationshipToMe, linkedExistingContactName, confidence
    }
}

// MARK: - AI Extraction Response
/// Represents the full response from the backend /extract-contacts endpoint.
struct AIExtractionResponse: Codable {
    enum ResponseType: String, Codable {
        case contacts
        case followUp = "followUp"
    }

    let type: ResponseType
    let contacts: [AIDraftContact]?
    let question: String?   // Populated when type == .followUp
}

// MARK: - Chat Message
/// Represents a single turn in the conversation history sent to the backend.
struct ChatMessage: Codable {
    let role: String    // "user" or "assistant"
    let content: String
}
