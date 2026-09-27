import SwiftUI
import Contacts
import ContactsUI

// MARK: - First-Run Introduction
/// Introduces the product and makes the interactive sample-tour choice explicit.
struct OnboardingSignInOverlay: View {
    @EnvironmentObject var dataManager: GoldfishDataManager
    @EnvironmentObject var walkthroughManager: FeatureWalkthroughManager
    @EnvironmentObject var demoModeManager: DemoModeManager

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showPrivacy = false
    @State private var onboardingError: String?

    var body: some View {
        ZStack {
            GoldfishDS.warmBlack.ignoresSafeArea()

            GeometryReader { geometry in
            ScrollView {
            VStack(spacing: 0) {
                Spacer()

                // Interchange mark — three lines converging on one station.
                interchangeMark
                    .padding(.bottom, 28)

                // Wordmark + tagline
                VStack(spacing: 12) {
                    Text("Goldfish")
                        .font(.system(size: 36, weight: .medium, design: .serif))
                        .kerning(0)
                        // Re-center: kerning trails the last glyph.
                        .padding(.leading, 0)
                        .foregroundStyle(GoldfishDS.ink(.primary))

                    Text("Remember everyone")
                        .font(.gfBody)
                        .foregroundStyle(GoldfishDS.ink(.secondary))
                }
                .padding(.bottom, 28)

                Text("Meet a person. Make a connection. Focus a pond.")
                    .font(.gfBody)
                    .foregroundStyle(GoldfishDS.ink(.secondary))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 32)

                Spacer()

                Button(action: exploreSample) {
                    Text("EXPLORE A SAMPLE")
                        .font(.gfLabel)
                        .kerning(1.6)
                        .foregroundStyle(GoldfishDS.warmBlack)
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 12)
                        .frame(minHeight: 52)
                        .background(
                            RoundedRectangle(cornerRadius: GoldfishDS.Radius.control)
                                .fill(GoldfishDS.ink(.primary))
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 28)
                .padding(.bottom, 10)
                .accessibilityIdentifier("startSampleTourButton")
                .accessibilityHint("Opens real sample contacts and a guided tour. You can end the tour at any time.")

                Button(action: startPersonalPond) {
                    Text("START MY POND")
                        .font(.gfLabel)
                        .kerning(1.4)
                        .foregroundStyle(GoldfishDS.ink(.primary))
                        .frame(maxWidth: .infinity)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 12)
                        .frame(minHeight: 52)
                        .overlay(
                            RoundedRectangle(cornerRadius: GoldfishDS.Radius.control)
                                .strokeBorder(GoldfishDS.ink(.hairline), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 28)
                .padding(.bottom, 16)
                .accessibilityIdentifier("startPersonalPondButton")
                .accessibilityHint("Starts with an empty personal pond and does not create sample contacts.")

                Text("Explore a guided sample, or begin with your own contacts. You can switch later.")
                    .font(.gfMeta)
                    .foregroundStyle(GoldfishDS.ink(.secondary))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                Text("Your contacts stay stored on this device.")
                    .font(.gfMeta)
                    .foregroundStyle(GoldfishDS.ink(.secondary))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 28)
                    .padding(.top, 8)
                Button("Privacy & Your Data") { showPrivacy = true }
                    .font(.gfMeta)
                    .foregroundStyle(GoldfishDS.terracotta)
                    .frame(minHeight: 44)
                    .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            }
        }
        .sheet(isPresented: $showPrivacy) {
            NavigationStack {
                PrivacyPolicyView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showPrivacy = false } } }
            }
        }
        .alert("Could not get started", isPresented: Binding(
            get: { onboardingError != nil }, set: { if !$0 { onboardingError = nil } }
        )) {
            Button("Remove Sample Data", role: .destructive) {
                if demoModeManager.removeDemoData(dataManager: dataManager) {
                    walkthroughManager.isDemoDataSeeded = false
                    onboardingError = nil
                } else {
                    let message = demoModeManager.demoErrorMessage
                        ?? "Couldn’t remove sample contacts. Try again."
                    onboardingError = nil
                    Task { @MainActor in
                        await Task.yield()
                        onboardingError = message
                    }
                }
            }
            Button("OK", role: .cancel) { onboardingError = nil }
        } message: { Text(onboardingError ?? "") }
        #if DEBUG
        // Headless-verification hook: `SIMCTL_CHILD_GF_AUTO_ONBOARD=1 simctl launch …`
        // completes the sign-in step without a tap so CI/agents can reach the app.
        .onAppear {
            if ProcessInfo.processInfo.environment["GF_AUTO_ONBOARD"] == "1" {
                startPersonalPond()
            }
        }
        #endif
    }

    /// Flat icon-like mark: three thick transit lines (Family red, Friends
    /// blue, Professional green) converging on a black interchange disc with
    /// a white core. No effects — pure signage.
    private var interchangeMark: some View {
        ContactPhotoView(photoData: nil, name: "Me", colorHex: nil,
                         size: .extraLarge, isMe: true)
            .frame(width: 120, height: 120)
            .accessibilityHidden(true)
    }

    private func exploreSample() {
        completeProfileIfNeeded()
        guard onboardingError == nil else { return }
        walkthroughManager.isDemoDataSeeded = false
        guard demoModeManager.activateDemoMode(dataManager: dataManager) else {
            onboardingError = demoModeManager.demoErrorMessage ?? "Couldn’t load sample contacts. Try again."
            return
        }
        hasCompletedOnboarding = true
    }

    private func startPersonalPond() {
        completeProfileIfNeeded()
        guard onboardingError == nil else { return }
        demoModeManager.deactivateDemoMode()
        walkthroughManager.completeOnboardingWithoutWalkthrough()
        hasCompletedOnboarding = true
    }

    private func completeProfileIfNeeded() {
        onboardingError = nil
        do {
            if try dataManager.fetchMePerson() == nil {
                try dataManager.performOnboarding(name: "Me")
            }
        } catch {
            print("Onboarding setup error: \(error)")
            onboardingError = error.localizedDescription
        }
    }
}

// MARK: - Contact Picker Wrapper
struct ContactPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onContactsSelected: ([CNContact]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    class Coordinator: NSObject, CNContactPickerDelegate {
        var parent: ContactPicker

        init(_ parent: ContactPicker) {
            self.parent = parent
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            parent.onContactsSelected(contacts)
            parent.isPresented = false
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            parent.isPresented = false
        }
    }
}
