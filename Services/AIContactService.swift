import Foundation
import AVFoundation

// MARK: - AI Contact Service
/// Handles all communication with the backend proxy for voice transcription and contact extraction.
/// The backend proxy holds the OpenAI API key server-side — never stored on device.
@MainActor
final class AIContactService: ObservableObject, AITranscriptionProvider {

    // MARK: - Configuration
    /// The base URL of the deployed backend proxy. Stored in UserDefaults.
    static var backendURL: String {
        get { UserDefaults.standard.string(forKey: "aiBackendURL") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "aiBackendURL") }
    }
    
    /// The secret key to authenticate with the deployed proxy. Stored in UserDefaults.
    static var backendSecret: String {
        get { UserDefaults.standard.string(forKey: "aiBackendSecret") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "aiBackendSecret") }
    }

    // MARK: - Injected Dependencies
    private let resolvedBackendURL: String
    private let resolvedBackendSecret: String
    private let session: URLSession

    /// Designated initializer with dependency injection.
    /// Defaults pull from UserDefaults for backward compatibility.
    init(
        backendURL: String? = nil,
        backendSecret: String? = nil,
        session: URLSession = .shared
    ) {
        self.resolvedBackendURL = backendURL ?? AIContactService.backendURL
        self.resolvedBackendSecret = backendSecret ?? AIContactService.backendSecret
        self.session = session
    }

    // MARK: - Transcribe
    /// Sends an audio file to the backend /transcribe endpoint (which calls OpenAI Whisper).
    /// - Parameter audioURL: Local file URL of the recorded .m4a audio.
    /// - Returns: The transcribed text string.
    func transcribe(audioURL: URL) async throws -> String {
        guard let baseURL = URL(string: resolvedBackendURL), !resolvedBackendURL.isEmpty else {
            throw AIServiceError.missingBackendURL
        }

        let endpoint = baseURL.appendingPathComponent("transcribe")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(resolvedBackendSecret)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let audioData = try Data(contentsOf: audioURL)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let data = try await performNetworkRequestWithRetries(request: request)

        struct TranscribeResponse: Decodable { let transcript: String }
        let result = try JSONDecoder().decode(TranscribeResponse.self, from: data)
        return result.transcript
    }

    // MARK: - Extract Contacts
    /// Sends the transcript + conversation history + existing contact names to the backend.
    /// The backend calls GPT-4o with a structured JSON prompt.
    /// - Parameters:
    ///   - transcript: The latest user utterance.
    ///   - conversationHistory: Prior turns in the conversation for follow-up support.
    ///   - existingContactNames: All current contact names for context linking.
    /// - Returns: An `AIExtractionResponse` that contains either draft contacts or a follow-up question.
    func extractContacts(
        transcript: String,
        conversationHistory: [ChatMessage],
        existingContactNames: [String]
    ) async throws -> AIExtractionResponse {
        guard let baseURL = URL(string: resolvedBackendURL), !resolvedBackendURL.isEmpty else {
            throw AIServiceError.missingBackendURL
        }

        let endpoint = baseURL.appendingPathComponent("extract-contacts")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(resolvedBackendSecret)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "transcript": transcript,
            "conversationHistory": conversationHistory.map { ["role": $0.role, "content": $0.content] },
            "existingContacts": existingContactNames
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let data = try await performNetworkRequestWithRetries(request: request)

        let decoder = JSONDecoder()
        return try decoder.decode(AIExtractionResponse.self, from: data)
    }

    // MARK: - Helpers
    private func performNetworkRequestWithRetries(request: URLRequest) async throws -> Data {
        let maxRetries = 3
        var currentAttempt = 0
        let baseDelay: UInt64 = 1_000_000_000 // 1 second

        while currentAttempt <= maxRetries {
            let (data, response) = try await session.data(for: request)
            
            guard let http = response as? HTTPURLResponse else {
                throw AIServiceError.serverError(0)
            }
            
            if (200..<300).contains(http.statusCode) {
                return data
            } else if http.statusCode == 429 || http.statusCode == 503 {
                if currentAttempt == maxRetries {
                    throw AIServiceError.serverError(http.statusCode)
                }
                // Exponential backoff
                let delay = baseDelay * UInt64(pow(2.0, Double(currentAttempt)))
                try await Task.sleep(nanoseconds: delay)
                currentAttempt += 1
                continue
            } else {
                throw AIServiceError.serverError(http.statusCode)
            }
        }
        
        throw AIServiceError.serverError(0)
    }
}

// MARK: - Errors
enum AIServiceError: LocalizedError {
    case missingBackendURL
    case serverError(Int)
    case audioRecordingFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingBackendURL:
            return "No AI backend URL configured. Please add it in Settings."
        case .serverError(let code):
            return "The AI backend returned an error (HTTP \(code))."
        case .audioRecordingFailed(let reason):
            return "Audio recording failed: \(reason)"
        }
    }
}

// MARK: - Audio Recorder Helper
/// Manages AVAudioRecorder for capturing voice input to a local .m4a file.
final class AudioRecorderHelper: NSObject, ObservableObject, AVAudioRecorderDelegate {
    private var recorder: AVAudioRecorder?
    @Published var isRecording = false

    var recordingURL: URL {
        let dir = FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("ai_voice_input.m4a")
    }

    func startRecording() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        recorder = try AVAudioRecorder(url: recordingURL, settings: settings)
        recorder?.delegate = self
        recorder?.record()
        isRecording = true
    }

    func stopRecording() {
        recorder?.stop()
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        isRecording = false
    }
}
