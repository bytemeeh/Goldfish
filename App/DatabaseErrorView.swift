import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Database Error View
/// Full-screen recovery UI shown when the ModelContainer fails to initialize.
/// See Spec §5.5.
struct DatabaseErrorView: View {
    let error: Error?
    let retryAction: () -> Void
    
    @State private var isExporting = false
    @State private var recoveryFiles: [URL] = []
    @State private var recoveryError: String?
    @State private var showTechnicalDetails = false
    @State private var showingFeedback = false

    private var supportDetails: String {
        error?.localizedDescription ?? "No additional details were provided."
    }
    
    var body: some View {
        GeometryReader { geometry in
        ScrollView {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 56, weight: .medium))
                .foregroundStyle(GoldfishDS.ink(.primary))
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                // Marker-red headline bar — the one accent on this sign.
                Rectangle()
                    .fill(GoldfishDS.terracotta)
                    .frame(width: 48, height: GoldfishDS.Rule.bar)
                    .accessibilityHidden(true)

                Text("Unable to Open Your Pond")
                    .font(.gfDisplay)
                    .textCase(.uppercase)
                    .kerning(1.6)
                    .foregroundStyle(GoldfishDS.ink(.primary))
                    .multilineTextAlignment(.center)

                Text("Your local data could not be opened. Try again, or save a recovery copy before seeking help. Keep the app installed until your contacts are recovered.")
                    .font(.gfBody)
                    .foregroundStyle(GoldfishDS.ink(.secondary))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                DisclosureGroup("Show technical details", isExpanded: $showTechnicalDetails) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Details for Support")
                            .font(.gfMeta.weight(.medium))
                            .foregroundStyle(GoldfishDS.ink(.primary))
                        Text(supportDetails)
                            .font(.gfMeta)
                            .foregroundStyle(GoldfishDS.ink(.secondary))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Copy Details") {
                            UIPasteboard.general.string = supportDetails
                            UIAccessibility.post(notification: .announcement, argument: "Details copied")
                        }
                        .font(.gfMeta.weight(.medium))
                        .foregroundStyle(GoldfishDS.terracotta)
                        .frame(minHeight: 44, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
                }
                .font(.gfMeta)
                .foregroundStyle(GoldfishDS.ink(.primary))
                .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 16) {
                Button(action: {
                    do {
                        let copies = try StoreRecoveryService.copyStore(at: GoldfishModelContainer.localStoreURL)
                        defer {
                            if let folder = copies.first?.deletingLastPathComponent() { try? FileManager.default.removeItem(at: folder) }
                        }
                        recoveryFiles = [try StoreRecoveryService.shareableArchive(for: copies)]
                        isExporting = true
                    } catch { recoveryError = error.localizedDescription }
                }) {
                    Label("SAVE RECOVERY COPY", systemImage: "square.and.arrow.up")
                        .font(.gfLabel)
                        .kerning(1.4)
                        .foregroundStyle(GoldfishDS.warmBlack)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .background(
                            RoundedRectangle(cornerRadius: GoldfishDS.Radius.control)
                                .fill(GoldfishDS.ink(.primary))
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)

                Button(action: retryAction) {
                    Text("TRY AGAIN")
                        .font(.gfLabel)
                        .kerning(1.4)
                        .foregroundStyle(GoldfishDS.ink(.primary))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .background(
                            RoundedRectangle(cornerRadius: GoldfishDS.Radius.control)
                                .fill(GoldfishDS.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: GoldfishDS.Radius.control)
                                .stroke(GoldfishDS.ink(.hairline), lineWidth: GoldfishDS.Rule.hairline)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 32)

                Button {
                    showingFeedback = true
                } label: {
                    Label("Report a problem", systemImage: "ladybug")
                        .font(.gfMeta)
                        .foregroundStyle(GoldfishDS.ink(.secondary))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
        .padding(.vertical, 20)
        }
        }
        .background(GoldfishDS.warmBlack.ignoresSafeArea())
        .sheet(isPresented: $showingFeedback) {
            NavigationStack {
                FeedbackView(initialKind: .bug, context: "Database recovery")
            }
            .presentationCornerRadius(GoldfishDS.Radius.sheet)
        }
        .sheet(isPresented: $isExporting, onDismiss: {
            if let folder = recoveryFiles.first?.deletingLastPathComponent() { try? FileManager.default.removeItem(at: folder) }
            recoveryFiles = []
        }) {
            ShareSheet(activityItems: recoveryFiles)
        }
        .alert("Could not create recovery copy", isPresented: Binding(
            get: { recoveryError != nil }, set: { if !$0 { recoveryError = nil } }
        )) { Button("OK") { recoveryError = nil } } message: { Text(recoveryError ?? "") }
    }
}



#Preview {
    DatabaseErrorView(error: nil, retryAction: {})
}
