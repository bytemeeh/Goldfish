import Foundation
import SwiftUI
import Speech

// MARK: - AI Voice ViewModel
/// Manages the full state machine for the AI voice-add contact flow.
///
/// States:
///   idle → recording → processing → awaitingFollowUp → reviewing → saved
@MainActor
final class AIVoiceAddViewModel: ObservableObject {

    // MARK: - State Machine
    enum FlowState: Equatable {
        case idle
        case recording
        case processing
        case awaitingFollowUp(question: String)
        case reviewing
        case saved
        case failed(String)
    }

    @Published var state: FlowState = .idle

    // Live transcript shown during recording (on-device SFSpeechRecognizer for preview only)
    @Published var liveTranscript: String = ""

    // Draft contacts returned by the AI
    @Published var draftContacts: [AIDraftContact] = []

    // Follow-up question from the AI
    @Published var followUpQuestion: String = ""

    // Typed input for follow-up text (alternate input method)
    @Published var followUpInput: String = ""

    // MARK: - Private State
    private var conversationHistory: [ChatMessage] = []
    private var existingContactNames: [String] = []

    private let service: AITranscriptionProvider
    private let audioRecorder = AudioRecorderHelper()
    private var speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    // Callbacks
    var onSaveApproved: (([AIDraftContact]) -> Void)?

    // MARK: - Init
    init(service: AITranscriptionProvider? = nil) {
        self.service = service ?? AIContactService()
    }

    // MARK: - Setup
    func prepare(existingContacts: [String]) {
        self.existingContactNames = existingContacts
    }

    // MARK: - Recording

    func startRecording() {
        guard state == .idle || (state == .awaitingFollowUp(question: followUpQuestion)) else { return }
        state = .recording
        liveTranscript = ""

        // Request speech recognition permission and start live preview
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized, let self else { return }
            Task { @MainActor in
                self.startLiveSpeechPreview()
            }
        }

        // Start actual audio recording to file
        try? audioRecorder.startRecording()
    }

    func stopRecording() {
        guard state == .recording else { return }
        audioRecorder.stopRecording()
        stopLiveSpeechPreview()
        Task { await self.processRecording() }
    }

    // MARK: - Live Speech Preview (SFSpeechRecognizer)
    private func startLiveSpeechPreview() {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true

        let node = audioEngine.inputNode
        let format = node.outputFormat(forBus: 0)
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }
        try? audioEngine.start()

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self, error == nil, let result else { return }
            Task { @MainActor in
                self.liveTranscript = result.bestTranscription.formattedString
            }
        }
    }

    private func stopLiveSpeechPreview() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
    }

    // MARK: - Processing
    private func processRecording() async {
        state = .processing

        do {
            // 1. Transcribe via Whisper (accurate, handles names well)
            let transcript = try await service.transcribe(audioURL: audioRecorder.recordingURL)

            // 2. Append user turn to history
            conversationHistory.append(ChatMessage(role: "user", content: transcript))

            // 3. Extract contacts
            let response = try await service.extractContacts(
                transcript: transcript,
                conversationHistory: conversationHistory,
                existingContactNames: existingContactNames
            )

            handleExtractionResponse(response)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Follow-up (text-based)
    func submitFollowUpText() {
        let text = followUpInput.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        followUpInput = ""
        conversationHistory.append(ChatMessage(role: "user", content: text))
        state = .processing

        Task {
            do {
                let response = try await service.extractContacts(
                    transcript: text,
                    conversationHistory: conversationHistory,
                    existingContactNames: existingContactNames
                )
                handleExtractionResponse(response)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - Handle Response
    private func handleExtractionResponse(_ response: AIExtractionResponse) {
        switch response.type {
        case .contacts:
            let contacts = response.contacts ?? []
            // Fuzzy-match linked existing contact names to IDs
            // (simple startsWith / lowercase contains match for now)
            draftContacts = contacts
            state = .reviewing

        case .followUp:
            followUpQuestion = response.question ?? "Could you clarify?"
            conversationHistory.append(ChatMessage(role: "assistant", content: followUpQuestion))
            state = .awaitingFollowUp(question: followUpQuestion)
        }
    }

    // MARK: - Approval Actions
    func approveAll() {
        draftContacts = draftContacts.map { var d = $0; d.isApproved = true; return d }
    }

    func discardAll() {
        draftContacts = draftContacts.map { var d = $0; d.isApproved = false; return d }
    }

    func saveApproved() {
        let approved = draftContacts.filter { $0.isApproved }
        onSaveApproved?(approved)
        state = .saved
    }

    func reset() {
        state = .idle
        liveTranscript = ""
        draftContacts = []
        followUpQuestion = ""
        conversationHistory = []
    }

    var approvedCount: Int { draftContacts.filter { $0.isApproved }.count }
}
