import SwiftUI

// MARK: - AI Voice Add View
/// The main modal for the AI Voice Add Mode.
/// Presents the recording/processing/follow-up experience.
struct AIVoiceAddView: View {
    @StateObject private var viewModel: AIVoiceAddViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataManager: GoldfishDataManager

    // Shown when the AI has extracted contacts and review is ready
    @State private var showApproval = false

    init(dataManager: GoldfishDataManager) {
        _viewModel = StateObject(
            wrappedValue: AIVoiceAddViewModel()
        )
    }

    var body: some View {
        ZStack {
            // Deep dark background
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.12),
                    Color(red: 0.08, green: 0.06, blue: 0.18)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.white.opacity(0.6))
                        .font(.system(size: 16))
                    Spacer()
                    Text("AI Contact Add")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    // Invisible balance element
                    Text("Cancel").opacity(0)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                Spacer()

                // Central content — switches based on state
                switch viewModel.state {
                case .idle:
                    idleContent
                case .recording:
                    recordingContent
                case .processing:
                    processingContent
                case .awaitingFollowUp(let question):
                    followUpContent(question: question)
                case .reviewing:
                    reviewingTransition
                case .saved:
                    savedContent
                case .failed(let message):
                    failedContent(message: message)
                }

                Spacer()
            }
        }
        .sheet(isPresented: $showApproval, onDismiss: {
            if viewModel.state == .saved {
                dismiss()
            } else {
                viewModel.reset()
            }
        }) {
            AIBulkApprovalView(viewModel: viewModel, dataManager: dataManager)
                // Block accidental swipe-down while drafts are pending review
                .interactiveDismissDisabled(!viewModel.draftContacts.isEmpty)
        }
        .onChange(of: viewModel.state) { _, newState in
            if case .reviewing = newState {
                // Short delay so the animation lands before sheet appears
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showApproval = true
                }
            }
        }
        .onAppear {
            let names = (try? dataManager.fetchAllPersons().map(\.name)) ?? []
            viewModel.prepare(existingContacts: names)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - State Views

    private var idleContent: some View {
        VStack(spacing: 32) {
            // Instructional label
            VStack(spacing: 8) {
                Text("Speak freely")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(.white)
                Text("Tell me about the contacts you want to add.\nNames, relationships, birthdays — anything.")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // Mic button
            MicOrbButton(isRecording: false) {
                viewModel.startRecording()
            }
        }
    }

    private var recordingContent: some View {
        VStack(spacing: 32) {
            Text("Listening...")
                .font(.system(size: 22, weight: .light))
                .foregroundColor(.white)

            MicOrbButton(isRecording: true) {
                viewModel.stopRecording()
            }

            // Live transcript
            if !viewModel.liveTranscript.isEmpty {
                Text(viewModel.liveTranscript)
                    .font(.system(size: 15, weight: .light, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .animation(.easeInOut, value: viewModel.liveTranscript)
            }

            Text("Tap to stop")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.35))
        }
    }

    private var processingContent: some View {
        VStack(spacing: 24) {
            PulsingOrb(color: Color(hue: 0.72, saturation: 0.8, brightness: 0.9))
                .frame(width: 100, height: 100)

            VStack(spacing: 6) {
                Text("Thinking...")
                    .font(.system(size: 22, weight: .light))
                    .foregroundColor(.white)
                Text("Transcribing and extracting contacts")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
    }

    private func followUpContent(question: String) -> some View {
        VStack(spacing: 28) {
            // AI question bubble
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20))
                    .foregroundColor(.purple)
                    .frame(width: 40, height: 40)
                    .background(.purple.opacity(0.15))
                    .clipShape(Circle())

                Text(question)
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundColor(.white)
                    .padding(14)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(16)
            }
            .padding(.horizontal, 24)

            // Options: voice or text
            VStack(spacing: 14) {
                // Mic button for voice response
                MicOrbButton(isRecording: false) {
                    viewModel.startRecording()
                }

                Text("or")
                    .foregroundColor(.white.opacity(0.3))
                    .font(.system(size: 13))

                // Text input
                HStack {
                    TextField("Type your answer...", text: $viewModel.followUpInput)
                        .foregroundColor(.white)
                        .submitLabel(.send)
                        .onSubmit { viewModel.submitFollowUpText() }
                    if !viewModel.followUpInput.isEmpty {
                        Button(action: viewModel.submitFollowUpText) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.purple)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.08))
                .cornerRadius(14)
                .padding(.horizontal, 24)
            }
        }
    }

    private var reviewingTransition: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundColor(.green)
                .symbolEffect(.bounce)
            Text("Extracted \(viewModel.draftContacts.count) contact\(viewModel.draftContacts.count == 1 ? "" : "s")")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
            Text("Opening review...")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.4))
        }
    }

    private var savedContent: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.badge.plus")
                .font(.system(size: 52))
                .foregroundColor(.goldfishAccent)
                .symbolEffect(.bounce)
            Text("Contacts saved!")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
        }
    }

    private func failedContent(message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundColor(.orange)
            Text("Something went wrong")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again") { viewModel.reset() }
                .buttonStyle(PrimaryAIButtonStyle())
        }
    }
}

// MARK: - Mic Orb Button
private struct MicOrbButton: View {
    let isRecording: Bool
    let action: () -> Void

    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer pulse ring (only when recording)
                if isRecording {
                    Circle()
                        .stroke(Color.red.opacity(0.3), lineWidth: 2)
                        .frame(width: 130, height: 130)
                        .scaleEffect(pulse ? 1.3 : 1.0)
                        .opacity(pulse ? 0 : 1)
                        .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: pulse)

                    Circle()
                        .stroke(Color.red.opacity(0.2), lineWidth: 2)
                        .frame(width: 150, height: 150)
                        .scaleEffect(pulse ? 1.5 : 1.0)
                        .opacity(pulse ? 0 : 0.6)
                        .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false).delay(0.3), value: pulse)
                }

                // Main circle
                Circle()
                    .fill(
                        isRecording
                            ? LinearGradient(colors: [.red, Color(red: 0.9, green: 0.2, blue: 0.4)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            : LinearGradient(colors: [Color(hue: 0.72, saturation: 0.7, brightness: 0.85), Color(hue: 0.75, saturation: 0.8, brightness: 0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 100, height: 100)
                    .shadow(color: isRecording ? .red.opacity(0.5) : Color(hue: 0.72, saturation: 0.8, brightness: 0.9).opacity(0.4), radius: 20)

                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .onAppear { if isRecording { pulse = true } }
        .onChange(of: isRecording) { _, recording in pulse = recording }
    }
}

// MARK: - Pulsing Orb (processing state)
private struct PulsingOrb: View {
    let color: Color
    @State private var scale: CGFloat = 0.9
    @State private var opacity: Double = 0.7

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color.opacity(0.15 - Double(i) * 0.04))
                    .scaleEffect(scale + CGFloat(i) * 0.2)
                    .animation(
                        .easeInOut(duration: 1.4).repeatForever(autoreverses: true).delay(Double(i) * 0.2),
                        value: scale
                    )
            }
            Circle()
                .fill(color.opacity(opacity))
                .scaleEffect(scale)
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: scale)
            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.9))
        }
        .onAppear {
            scale = 1.1
            opacity = 1.0
        }
    }
}

// MARK: - Button Style
private struct PrimaryAIButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 32)
            .padding(.vertical, 14)
            .background(Color.purple.opacity(configuration.isPressed ? 0.7 : 1.0))
            .cornerRadius(14)
    }
}
