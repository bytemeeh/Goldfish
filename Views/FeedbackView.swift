import SwiftUI
import PhotosUI
import MessageUI
import UIKit

/// A small, self-contained feedback form that works even when the data store
/// cannot be opened. Reports are prepared locally and only leave the device
/// after the user chooses Mail, Share, or Copy.
@MainActor
struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss

    private let recipient: String?
    private let diagnostics: FeedbackDiagnostics
    /// Captured once when this form opens; later interactions cannot rewrite the
    /// preview or report being prepared in this session.
    @State private var interactionHistory: [InteractionDiagnosticEvent]

    @State private var kind: FeedbackKind
    @State private var message: String
    @State private var steps: String
    @State private var expectedResult: String
    @State private var area: String
    @State private var showBugDetails: Bool
    @State private var didStartEditing = false
    @State private var includesAppDetails = true
    @State private var includesInteractionHistory = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var screenshotImage: UIImage?
    @State private var screenshotData: Data?
    @State private var screenshotError: String?
    @State private var isLoadingScreenshot = false
    @State private var screenshotLoadID = UUID()
    @State private var showingMailComposer = false
    @State private var showingShareSheet = false
    @State private var mailOutcome: MailOutcome?
    @State private var copyConfirmationVisible = false

    init(initialKind: FeedbackKind = .bug, context: String? = nil) {
        self.recipient = FeedbackConfiguration.recipient
        self.diagnostics = FeedbackDiagnostics.current()
        _interactionHistory = State(initialValue: InteractionDiagnostics.snapshot())
        _kind = State(initialValue: initialKind)
        _message = State(initialValue: "")
        _steps = State(initialValue: "")
        _expectedResult = State(initialValue: "")
        _area = State(initialValue: context ?? "")
        _showBugDetails = State(initialValue: context != nil)
    }

    private var report: FeedbackReport {
        FeedbackReport(
            kind: kind,
            message: message,
            steps: steps,
            expectedResult: expectedResult,
            area: area,
            includesAppDetails: includesAppDetails,
            includesInteractionHistory: includesInteractionHistory,
            interactionHistory: interactionHistory,
            diagnostics: diagnostics
        )
    }

    private var canUseMail: Bool {
        recipient != nil && MFMailComposeViewController.canSendMail()
    }

    private var sharingText: String {
        guard let recipient, !recipient.isEmpty else { return report.shareText }
        return "To: \(recipient)\n\n\(report.shareText)"
    }

    private var shareItems: [Any] {
        if let screenshotImage {
            return [sharingText, screenshotImage]
        }
        return [sharingText]
    }

    var body: some View {
        let hasScreenshot = screenshotImage != nil
        let appName = diagnostics.appName
        Form {
            Section {
                Picker("I want to", selection: $kind) {
                    ForEach(FeedbackKind.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Feedback type, \(kind.label)")
            } header: {
                Text("Feedback type")
            }
            .listRowBackground(GoldfishDS.surface)

            Section {
                VStack(alignment: .leading, spacing: GoldfishDS.Space.xs) {
                    ZStack(alignment: .topLeading) {
                        if message.isEmpty {
                            Text(kind == .bug ? "Describe what happened in \(appName)…" : "Describe the idea you have for \(appName)…")
                                .font(.gfBody)
                                .foregroundStyle(GoldfishDS.ink(.tertiary))
                                .padding(.top, GoldfishDS.Space.sm)
                                .padding(.leading, GoldfishDS.Space.xs)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $message)
                            .font(.gfBody)
                            .foregroundStyle(GoldfishDS.ink(.primary))
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 132)
                            .accessibilityLabel(kind == .bug ? "What went wrong" : "Your idea")
                    }
                    HStack {
                        Text(kind == .bug ? "What happened?" : "Tell us what would help.")
                            .font(.gfMeta)
                            .foregroundStyle(GoldfishDS.ink(.tertiary))
                        Spacer()
                        Text("\(message.count)/10,000")
                            .font(.gfMeta.monospacedDigit())
                            .foregroundStyle(message.count > 10_000 ? Color.goldfishError : GoldfishDS.ink(.tertiary))
                    }
                }
            } header: {
                Text(kind == .bug ? "What went wrong" : "Your idea")
            } footer: {
                Text("A short description helps us understand what you mean.")
            }
            .listRowBackground(GoldfishDS.surface)

            if kind == .bug {
                Section {
                    DisclosureGroup(isExpanded: $showBugDetails) {
                        VStack(spacing: GoldfishDS.Space.md) {
                            TextField("Where were you in \(appName)?", text: $area)
                                .font(.gfBody)
                                .onChange(of: area) { _, _ in didStartEditing = true }
                            TextField("What did you do first?", text: $steps, axis: .vertical)
                                .font(.gfBody)
                                .lineLimit(2...6)
                                .onChange(of: steps) { _, _ in didStartEditing = true }
                            TextField("What did you expect to happen?", text: $expectedResult, axis: .vertical)
                                .font(.gfBody)
                                .lineLimit(2...6)
                                .onChange(of: expectedResult) { _, _ in didStartEditing = true }
                        }
                        .padding(.top, GoldfishDS.Space.xs)
                    } label: {
                        Text("Add details")
                            .font(.gfBody)
                    }
                } footer: {
                    Text("All of these details are optional.")
                }
                .listRowBackground(GoldfishDS.surface)
            } else {
                    Section {
                        TextField("Which part of \(appName) is this about?", text: $area)
                            .font(.gfBody)
                            .onChange(of: area) { _, _ in didStartEditing = true }
                } header: {
                    Text("About your idea")
                } footer: {
                    Text("This is optional, but it helps us understand the right context.")
                }
                .listRowBackground(GoldfishDS.surface)
            }

            Section {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label(hasScreenshot ? "Replace image" : "Add an image", systemImage: "photo")
                        .font(.gfBody)
                        .foregroundStyle(GoldfishDS.terracotta)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .disabled(isLoadingScreenshot)

                if isLoadingScreenshot {
                    HStack(spacing: GoldfishDS.Space.sm) {
                        ProgressView().tint(GoldfishDS.terracotta)
                        Text("Preparing screenshot…")
                            .font(.gfMeta)
                            .foregroundStyle(GoldfishDS.ink(.secondary))
                    }
                }

                if let screenshotImage {
                    HStack(spacing: GoldfishDS.Space.md) {
                        Image(uiImage: screenshotImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
                            .accessibilityLabel("Selected screenshot")
                        VStack(alignment: .leading, spacing: GoldfishDS.Space.xs) {
                            Text("Screenshot attached")
                                .font(.gfBody)
                            if let screenshotData {
                                Text(ByteCountFormatter.string(fromByteCount: Int64(screenshotData.count), countStyle: .file))
                                    .font(.gfMeta)
                                    .foregroundStyle(GoldfishDS.ink(.tertiary))
                            }
                        }
                        Spacer(minLength: 0)
                        Button("Remove") {
                            selectedPhotoItem = nil
                            self.screenshotImage = nil
                            screenshotData = nil
                        }
                        .font(.gfMeta.weight(.medium))
                        .foregroundStyle(GoldfishDS.terracotta)
                    }
                }

                if let screenshotError {
                    Text(screenshotError)
                        .font(.gfMeta)
                        .foregroundStyle(Color.goldfishError)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Screenshot (optional)")
            } footer: {
                Text("Choose an image to include with your report.")
            }
            .listRowBackground(GoldfishDS.surface)

            Section {
                Toggle(isOn: $includesAppDetails) {
                    VStack(alignment: .leading, spacing: GoldfishDS.Space.xs) {
                        Text("Include app details")
                            .font(.gfBody)
                        Text("Version, device, and operating system")
                            .font(.gfMeta)
                            .foregroundStyle(GoldfishDS.ink(.tertiary))
                    }
                }
                .tint(GoldfishDS.terracotta)

                if includesAppDetails {
                    DisclosureGroup("Preview app details") {
                        Text(diagnostics.text)
                            .font(.gfMeta)
                            .foregroundStyle(GoldfishDS.ink(.secondary))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, GoldfishDS.Space.xs)
                    }
                }

                Toggle(isOn: $includesInteractionHistory) {
                    VStack(alignment: .leading, spacing: GoldfishDS.Space.xs) {
                        Text("Include recent interaction history")
                            .font(.gfBody)
                        Text("Optional view-switch events kept in memory, up to 40 events")
                            .font(.gfMeta)
                            .foregroundStyle(GoldfishDS.ink(.tertiary))
                    }
                }
                .tint(GoldfishDS.terracotta)

                if includesInteractionHistory {
                    DisclosureGroup("Preview interaction history") {
                        Group {
                            if interactionHistory.isEmpty {
                                Text("No recent interaction history is available.")
                            } else {
                                Text(interactionHistory.map(\.reportLine).joined(separator: "\n"))
                            }
                        }
                        .font(.gfMeta)
                        .foregroundStyle(GoldfishDS.ink(.secondary))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, GoldfishDS.Space.xs)
                    }
                }
            } header: {
                Text("Optional details")
            } footer: {
                Text("Choose which details to include. View-switch history contains no contact details or search text. Nothing is sent until you use Mail or Share. Copy places the report text on your clipboard.")
            }
            .listRowBackground(GoldfishDS.surface)

            Section {
                if canUseMail {
                    Button {
                        showingMailComposer = true
                    } label: {
                        Label("Review email", systemImage: "envelope")
                            .font(.gfLabel)
                            .foregroundStyle(GoldfishDS.warmBlack)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 52)
                    }
                    .buttonStyle(.plain)
                    .disabled(!report.isValid || isLoadingScreenshot)
                    .background(RoundedRectangle(cornerRadius: GoldfishDS.Radius.control).fill(GoldfishDS.ink(.primary)))
                    Button {
                        showingShareSheet = true
                    } label: {
                        Label("Share report", systemImage: "square.and.arrow.up")
                            .font(.gfBody)
                            .foregroundStyle(GoldfishDS.terracotta)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(!report.isValid || isLoadingScreenshot)
                } else {
                    Button {
                        showingShareSheet = true
                    } label: {
                        Label("Share report", systemImage: "square.and.arrow.up")
                            .font(.gfLabel)
                            .foregroundStyle(GoldfishDS.warmBlack)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 52)
                    }
                    .buttonStyle(.plain)
                    .disabled(!report.isValid || isLoadingScreenshot)
                    .background(RoundedRectangle(cornerRadius: GoldfishDS.Radius.control).fill(GoldfishDS.ink(.primary)))
                }

                Button {
                    UIPasteboard.general.string = sharingText
                    UIAccessibility.post(notification: .announcement, argument: "Report copied")
                    copyConfirmationVisible = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        copyConfirmationVisible = false
                    }
                } label: {
                    Label(copyConfirmationVisible ? "Copied" : "Copy text", systemImage: copyConfirmationVisible ? "checkmark" : "doc.on.doc")
                        .font(.gfBody)
                        .foregroundStyle(GoldfishDS.terracotta)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(!report.isValid || isLoadingScreenshot)

                if recipient == nil {
                    Text("Choose how to share your report: share it with another app or copy it for later.")
                        .font(.gfMeta)
                        .foregroundStyle(GoldfishDS.ink(.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                } else if !MFMailComposeViewController.canSendMail() {
                    Text("Mail is not available on this device, so share or copy the report instead.")
                        .font(.gfMeta)
                        .foregroundStyle(GoldfishDS.ink(.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if didStartEditing, let validationMessage = report.validationMessage {
                    Text(validationMessage)
                        .font(.gfMeta)
                        .foregroundStyle(Color.goldfishError)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Ready to share")
            } footer: {
                Text(footerText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .listRowBackground(GoldfishDS.surface)
        }
        .font(.gfBody)
        .scrollContentBackground(.hidden)
        .background(GoldfishDS.warmBlack.ignoresSafeArea())
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
                    .font(.gfBody)
                    .foregroundStyle(GoldfishDS.ink(.secondary))
            }
        }
        .onChange(of: message) { _, _ in didStartEditing = true }
        .task(id: selectedPhotoItem) {
            await loadScreenshot()
        }
        .sheet(isPresented: $showingMailComposer) {
            FeedbackMailComposer(
                recipient: recipient,
                subject: report.subject,
                body: report.body,
                screenshotData: screenshotData
            ) { result, error in
                showingMailComposer = false
                mailOutcome = MailOutcome(result: result, error: error)
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(activityItems: shareItems)
                .presentationCornerRadius(GoldfishDS.Radius.sheet)
        }
        .alert(item: $mailOutcome) { outcome in
            Alert(
                title: Text(outcome.title),
                message: Text(outcome.message),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var footerText: String {
        var parts = ["Your message"]
        if screenshotImage != nil { parts.append("selected screenshot") }
        if includesAppDetails { parts.append("app details") }
        return "This report includes: " + parts.joined(separator: ", ") + "."
    }

    private func loadScreenshot() async {
        let loadID = UUID()
        screenshotLoadID = loadID
        guard let item = selectedPhotoItem else {
            isLoadingScreenshot = false
            return
        }
        isLoadingScreenshot = true
        screenshotError = nil
        screenshotImage = nil
        screenshotData = nil
        defer {
            if screenshotLoadID == loadID {
                isLoadingScreenshot = false
            }
        }
        do {
            guard let sourceData = try await item.loadTransferable(type: Data.self) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try Task.checkCancellation()
            let preparedData = try FeedbackScreenshot.prepare(sourceData)
            guard !Task.isCancelled, selectedPhotoItem == item, screenshotLoadID == loadID,
                  let image = UIImage(data: preparedData) else { return }
            screenshotImage = image
            screenshotData = preparedData
        } catch {
            guard !Task.isCancelled, selectedPhotoItem == item, screenshotLoadID == loadID else { return }
            screenshotError = (error as? FeedbackScreenshot.PreparationError)?.errorDescription
                ?? "The screenshot could not be loaded. Try again or choose another image."
            selectedPhotoItem = nil
        }
    }
}

private struct MailOutcome: Identifiable {
    let id = UUID()
    let result: MFMailComposeResult
    let error: Error?

    var title: String {
        if error != nil { return "Email not sent" }
        switch result {
        case .sent: return "Email sent"
        case .saved: return "Draft saved"
        case .cancelled: return "Email cancelled"
        case .failed: return "Email not sent"
        @unknown default: return "Email update"
        }
    }

    var message: String {
        if error != nil { return "Mail could not send the report. Your form is still here; try Share report or Copy text." }
        switch result {
        case .sent: return "Mail accepted the report for sending. Your form is still here."
        case .saved: return "The report was saved as a draft in Mail. Your form is still here."
        case .cancelled: return "The email composer was cancelled. Your report is still here."
        case .failed: return "Mail could not send the report. Your form is still here; try Share report or Copy text."
        @unknown default: return "Your report is still here."
        }
    }
}

private struct FeedbackMailComposer: UIViewControllerRepresentable {
    let recipient: String?
    let subject: String
    let body: String
    let screenshotData: Data?
    let onFinish: (MFMailComposeResult, Error?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let controller = MFMailComposeViewController()
        if let recipient, !recipient.isEmpty {
            controller.setToRecipients([recipient])
        }
        controller.setSubject(subject)
        controller.setMessageBody(body, isHTML: false)
        if let screenshotData {
            controller.addAttachmentData(screenshotData, mimeType: "image/jpeg", fileName: "feedback-screenshot.jpg")
        }
        controller.mailComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: (MFMailComposeResult, Error?) -> Void

        init(onFinish: @escaping (MFMailComposeResult, Error?) -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            controller.dismiss(animated: true) {
                self.onFinish(result, error)
            }
        }
    }
}

#Preview {
    NavigationStack { FeedbackView() }
}
