import SwiftUI

/// Describes the actual local-only configuration shipped by this source snapshot.
struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: GoldfishDS.Space.xl) {
                Text("Privacy & your data").font(.gfDisplay)
                Text("Updated 28 September 2026").font(.gfMeta).foregroundStyle(GoldfishDS.ink(.secondary))
                section("Stored on your device", "Goldfish keeps the contacts, photos, notes, birthdays, addresses, relationships and pond memberships you add in the app’s local database. This version does not enable CloudKit sync, require an account, or include advertising or analytics SDKs.")
                section("Contacts and photos", "You choose which contacts and images to import. If you use a feature that requests Contacts access, iOS asks for your permission. You can change that permission in Settings. Imported information becomes part of the app’s local database.")
                section("Maps", "Contact locations can be displayed using Apple’s MapKit. Map content and Apple services are subject to Apple’s privacy policy. This version does not request background location access or provide location tracking.")
                section("Exports and recovery copies", "A Goldfish sharing file copies selected contacts, their connections, pond memberships, photos, and saved locations. Notes can be omitted before sharing. Recipients review the file before import; their existing details and pond assignments take precedence. This is a copy, not ongoing synchronization. Empty ponds and device-specific layout positions are not included. A vCard is a shareable contact export, not a complete pond backup. It includes selected people and contact details; Goldfish relationship and pond metadata may not be retained by other contact apps. Empty ponds, manual exclusions, and some location records are not serialized. A recovery copy contains raw local files and supporting photos for support; share it only with someone you trust.")
                section("Manage or delete your data", "You can edit or delete contacts in the app, hide sample contacts, and use the reset action in Settings. Export anything you want to keep before resetting or deleting the app. Device backups are controlled by your iOS settings.")
                section("Feedback and bug reports", "If you choose Report a bug or Share an idea, Goldfish prepares a report from what you wrote, an optional screenshot, and optional app details. Nothing is sent automatically. You choose whether to review it in Mail, share it, or copy it; delivery and handling then depend on the service you choose.")
                section("Questions", "For questions about Goldfish or its handling of your information, use Help & feedback in Settings.")
                if let privacyURL = FeedbackConfiguration.privacyPolicyURL {
                    Link("Goldfish Privacy Policy", destination: privacyURL)
                        .font(.gfBody).foregroundStyle(GoldfishDS.terracotta)
                }
                Link("Apple Privacy Policy", destination: URL(string: "https://www.apple.com/legal/privacy/")!)
                    .font(.gfBody).foregroundStyle(GoldfishDS.terracotta)
            }
            .foregroundStyle(GoldfishDS.ink(.primary))
            .padding(GoldfishDS.Space.pageMargin)
        }
        .background(GoldfishDS.warmBlack)
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: GoldfishDS.Space.sm) {
            Text(title).font(.gfName)
            Text(text).font(.gfBody).foregroundStyle(GoldfishDS.ink(.secondary))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
