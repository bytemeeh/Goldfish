import Foundation

// MARK: - AI Transcription Provider Protocol
/// Abstracts AI voice transcription and contact extraction.
/// Conform to this protocol for production (`AIContactService`)
/// or for unit testing (mock implementation).
protocol AITranscriptionProvider: AnyObject {
    /// Transcribes an audio file and returns the text.
    func transcribe(audioURL: URL) async throws -> String

    /// Extracts structured contact data from a transcript.
    func extractContacts(
        transcript: String,
        conversationHistory: [ChatMessage],
        existingContactNames: [String]
    ) async throws -> AIExtractionResponse
}
