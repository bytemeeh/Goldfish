import SwiftUI

// MARK: - Privacy Policy View

/// Displays the full privacy policy in-app as a native SwiftUI view.
/// Covers US (CCPA, CalOPPA, COPPA) and EU (GDPR, ePrivacy Directive) requirements.
struct PrivacyPolicyView: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                introduction
                dataControllerSection
                dataWeStoreSection
                dataWeDoNotCollectSection
                legalBasisSection
                iCloudSyncSection
                contactImportSection
                locationDataSection
                photosSection
                vCardExportSection
                yourRightsSection
                ccpaSection
                childrenSection
                dataDeletionSection
                dataSecuritySection
                thirdPartiesSection
                internationalSection
                changesToPolicySection
                contactUsSection
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Privacy Policy")
                .font(.largeTitle.bold())

            Text("Last updated: February 19, 2026")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Effective date: February 19, 2026")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Introduction

    private var introduction: some View {
        PolicySection(title: "Introduction") {
            Text("Goldfish (\"the App\") is a personal relationship manager for iOS developed by Marcel Meeh (\"we\", \"us\", \"our\"). We are committed to protecting your privacy and being transparent about how the App handles your data.")
            Text("This privacy policy explains what information the App processes, how it is stored, your rights regarding that information, and how we comply with applicable privacy laws — including the European Union General Data Protection Regulation (GDPR), the ePrivacy Directive, the California Consumer Privacy Act (CCPA) as amended by the CPRA, the California Online Privacy Protection Act (CalOPPA), and the Children's Online Privacy Protection Act (COPPA).")
            Text("By using Goldfish, you acknowledge that you have read and understood this privacy policy.")
        }
    }

    // MARK: - Data Controller

    private var dataControllerSection: some View {
        PolicySection(title: "1. Data Controller") {
            Text("For the purposes of the GDPR and other applicable data protection laws, the data controller is:")
            VStack(alignment: .leading, spacing: 4) {
                Text("Marcel Meeh")
                    .fontWeight(.semibold)
                Text("Email: support@goldfish-app.com")
            }
            .padding(.leading, 16)
            Text("However, because Goldfish processes all data exclusively on your device and in your personal iCloud account — and we never receive, access, or store any of your data on our systems — our role as data controller is limited. You retain full control over all data at all times.")
        }
    }

    // MARK: - Data We Store

    private var dataWeStoreSection: some View {
        PolicySection(title: "2. What Data Is Processed") {
            Text("Goldfish processes the following categories of data that you create or import within the App:")
            BulletList(items: [
                "Contact information: names, phone numbers, email addresses, physical addresses, and birthdays",
                "Contact photos you add or import",
                "Free-form notes and tags you attach to contacts",
                "Relationship connections you define between contacts (e.g., mother, friend, coworker)",
                "Circle (group) memberships you assign",
                "Your app preferences and settings (e.g., view mode, sort order)"
            ])
            Text("All of this data is stored exclusively on your device in a local SwiftData database. If you have iCloud enabled, it is also synced to your personal iCloud account (see Section 5). We do not operate any servers and have no access to your data.")
                .fontWeight(.medium)
        }
    }

    // MARK: - Data We Do Not Collect

    private var dataWeDoNotCollectSection: some View {
        PolicySection(title: "3. Data We Do Not Collect or Transmit") {
            Text("Goldfish does not:")
            BulletList(items: [
                "Send any data to our servers or any third-party servers",
                "Include any analytics, telemetry, or usage tracking",
                "Include any advertising SDKs, ad networks, or advertising identifiers",
                "Track your usage, behavior, interactions, or browsing patterns",
                "Access your data in the background without your knowledge",
                "Create user accounts or require registration of any kind",
                "Share, sell, rent, or disclose data to any third party for any purpose",
                "Use cookies, web beacons, pixels, or similar tracking technologies",
                "Make any network requests to servers we operate"
            ])
            Text("Our App Store privacy label declares: \"Data Not Collected.\"")
                .fontWeight(.semibold)
        }
    }

    // MARK: - Legal Basis

    private var legalBasisSection: some View {
        PolicySection(title: "4. Legal Basis for Processing (GDPR, Art. 6)") {
            Text("To the extent the GDPR applies, the legal basis for processing your data is:")
            BulletList(items: [
                "Consent (Art. 6(1)(a)): You voluntarily enter and manage all data within the App. You can withdraw consent at any time by deleting data from the App or deleting the App itself.",
                "Contract performance (Art. 6(1)(b)): Processing is necessary to provide the App's core functionality — organizing, displaying, and managing your personal contacts and relationships.",
                "Legitimate interest (Art. 6(1)(f)): We have a legitimate interest in providing a functional, privacy-respecting app. Since all processing occurs on-device and no data is transmitted to us, the impact on your rights and freedoms is minimal."
            ])
            Text("Where the App requests device permissions (Contacts, Camera, Location), we rely on your explicit consent through the iOS permission dialogs. You may revoke these permissions at any time through your device's Settings app.")
        }
    }

    // MARK: - iCloud Sync

    private var iCloudSyncSection: some View {
        PolicySection(title: "5. iCloud Sync") {
            Text("If you have iCloud enabled on your device, Goldfish syncs your data across your Apple devices using Apple's CloudKit private database. This means:")
            BulletList(items: [
                "Your data is stored in your personal iCloud account, encrypted and managed by Apple.",
                "We (the developers) have no access to your iCloud data. We cannot read, view, retrieve, or modify any of your information stored in iCloud.",
                "iCloud sync is managed entirely by Apple under Apple's Privacy Policy (apple.com/legal/privacy).",
                "You can disable iCloud sync for Goldfish at any time in your device's Settings → [Your Name] → iCloud.",
                "Under the GDPR, Apple acts as a data processor for iCloud services. Apple's compliance with EU data protection law is documented in Apple's Data Processing Addendum."
            ])
        }
    }

    // MARK: - Contact Import

    private var contactImportSection: some View {
        PolicySection(title: "6. Contact Import") {
            Text("When you choose to import contacts from your device's address book:")
            BulletList(items: [
                "The import is initiated only by your explicit action (tapping \"Import Contacts\").",
                "The App reads your address book only at the moment you initiate the import.",
                "Imported data is copied into Goldfish's local database on your device.",
                "Your address book is never accessed in the background.",
                "No address book data is transmitted off your device or shared with us or any third party."
            ])
            Text("iOS will show a system permission dialog the first time you attempt to import contacts. You may revoke this permission at any time via Settings → Privacy & Security → Contacts.")
        }
    }

    // MARK: - Location Data

    private var locationDataSection: some View {
        PolicySection(title: "7. Location Data") {
            Text("If you grant location permission, Goldfish uses your location solely to show nearby contacts on the map view. Your location is:")
            BulletList(items: [
                "Used only while the App is open and the map feature is active.",
                "Held temporarily in memory and never saved to any database, file, or persistent storage.",
                "Never transmitted off your device, to us, or to any third party.",
                "Immediately discarded when the map feature is deactivated."
            ])
            Text("Goldfish requests only \"When In Use\" location access — it never requests \"Always\" or background location access. You may revoke location permission at any time via Settings → Privacy & Security → Location Services.")
        }
    }

    // MARK: - Photos

    private var photosSection: some View {
        PolicySection(title: "8. Photos and Camera") {
            Text("When you add photos to contacts:")
            BulletList(items: [
                "Choosing a photo from your library uses Apple's privacy-preserving photo picker (PHPicker), which does not require photo library permission.",
                "Taking a photo with the camera requires camera permission, which you grant through a system dialog.",
                "Photos are compressed and stored locally on your device, and in your personal iCloud if sync is enabled.",
                "Photos are never uploaded to our servers or shared with any third party."
            ])
            Text("You may revoke camera permission at any time via Settings → Privacy & Security → Camera.")
        }
    }

    // MARK: - vCard Export

    private var vCardExportSection: some View {
        PolicySection(title: "9. Data Export (vCard Sharing)") {
            Text("Goldfish allows you to export contacts as standard vCard (.vcf) files. When you use this feature:")
            BulletList(items: [
                "The export is initiated entirely by you.",
                "You choose the recipient and sharing method (AirDrop, Messages, Mail, etc.) through the iOS share sheet.",
                "We do not receive, intercept, or store any exported data.",
                "You are solely responsible for the data you choose to share and with whom you share it."
            ])
        }
    }

    // MARK: - Your Rights (GDPR)

    private var yourRightsSection: some View {
        PolicySection(title: "10. Your Rights Under the GDPR") {
            Text("If you are located in the European Economic Area (EEA), the United Kingdom, or Switzerland, you have the following rights under the GDPR:")
            BulletList(items: [
                "Right of access (Art. 15): You can view all your data directly within the App at any time.",
                "Right to rectification (Art. 16): You can edit any of your data directly within the App.",
                "Right to erasure / \"Right to be forgotten\" (Art. 17): You can delete individual contacts within the App, or delete the App entirely to erase all local data. See Section 14 for complete instructions.",
                "Right to restriction of processing (Art. 18): You can stop using specific features (e.g., revoke permissions) to restrict how the App processes your data.",
                "Right to data portability (Art. 20): You can export all your data as vCard files using the App's export function.",
                "Right to object (Art. 21): Since all processing is on-device and under your control, you can stop processing at any time by ceasing to use the App.",
                "Right to withdraw consent (Art. 7(3)): You can withdraw consent at any time by revoking device permissions or deleting the App."
            ])
            Text("Because we do not collect or receive any of your data, we cannot fulfill access or deletion requests on our end — there is nothing for us to access or delete. All data management is performed directly by you within the App or through your device settings.")
            Text("If you believe your data protection rights have been violated, you have the right to lodge a complaint with a supervisory authority in the EU member state of your habitual residence, place of work, or place of the alleged infringement.")
        }
    }

    // MARK: - CCPA

    private var ccpaSection: some View {
        PolicySection(title: "11. Your Rights Under the CCPA / CPRA") {
            Text("If you are a California resident, the California Consumer Privacy Act (CCPA), as amended by the California Privacy Rights Act (CPRA), grants you the following rights:")
            BulletList(items: [
                "Right to know: You have the right to know what personal information is collected about you. Goldfish does not collect any personal information — all data stays on your device.",
                "Right to delete: You can delete all your data at any time (see Section 14).",
                "Right to opt-out of sale or sharing: We do not sell, share, or disclose your personal information to any third party for monetary or other valuable consideration. There is nothing to opt out of.",
                "Right to non-discrimination: We will not discriminate against you for exercising your CCPA rights."
            ])
            Text("Under the CCPA, \"personal information\" means information that identifies, relates to, or could reasonably be linked with you or your household. Since Goldfish does not transmit any data off your device, we do not \"collect\" personal information as defined by the CCPA.")
            Text("CalOPPA compliance: Consistent with CalOPPA, this privacy policy is conspicuously accessible from within the App. We disclose how we handle \"Do Not Track\" signals — because Goldfish makes no network requests and performs no tracking, \"Do Not Track\" browser signals are not applicable.")
        }
    }

    // MARK: - Children

    private var childrenSection: some View {
        PolicySection(title: "12. Children's Privacy (COPPA)") {
            Text("Goldfish does not knowingly collect personal information from children under the age of 13 (or the applicable age of digital consent in your jurisdiction, such as 16 in Germany or the Netherlands).")
            Text("The App does not require an account, does not transmit any data, and is rated 4+ on the App Store. Because no data from the App ever reaches us, we cannot knowingly or unknowingly collect children's data.")
            Text("If you are a parent or guardian and believe that a child has provided personal information through the App, please contact us at the address below — though by design, no data from the App reaches us or any third party.")
        }
    }

    // MARK: - Data Deletion

    private var dataDeletionSection: some View {
        PolicySection(title: "13. Data Retention and Deletion") {
            Text("All your data is stored on your device and, if iCloud is enabled, in your personal iCloud account. We do not retain any of your data on any server.")
            Text("To delete all Goldfish data:")
            NumberedList(items: [
                "Delete individual contacts: Swipe to delete or use the delete button on any contact's detail page.",
                "Delete all local data: Delete the Goldfish app from your device. This immediately and permanently removes all local data.",
                "Delete iCloud data: Go to Settings → [Your Name] → iCloud → Manage Storage → Goldfish and tap \"Delete Data.\""
            ])
            Text("Because we do not retain any data on our systems, there is nothing additional for us to delete when you remove the App.")
        }
    }

    // MARK: - Data Security

    private var dataSecuritySection: some View {
        PolicySection(title: "14. Data Security") {
            Text("Goldfish protects your data through the following measures:")
            BulletList(items: [
                "On-device storage: All data is stored in a local SwiftData database protected by your device's hardware encryption and passcode/biometric lock.",
                "iCloud encryption: Data synced via iCloud is encrypted in transit and at rest by Apple.",
                "No network exposure: Because the App makes no network connections to our servers, there is no attack surface for data breaches, interception, or remote unauthorized access.",
                "Photo compression: Contact photos are compressed to a maximum of 800×800 pixels and ≤500KB before storage, minimizing the data footprint.",
                "Minimal permissions: The App requests only the minimum permissions necessary for each feature, and all permissions are optional."
            ])
        }
    }

    // MARK: - Third Parties

    private var thirdPartiesSection: some View {
        PolicySection(title: "15. Third-Party Services") {
            Text("Goldfish does not integrate any third-party SDKs, libraries, or services that collect, process, or transmit your data. Specifically, the App:")
            BulletList(items: [
                "Contains no analytics SDKs (no Firebase Analytics, Mixpanel, Amplitude, etc.)",
                "Contains no crash reporting SDKs (no Crashlytics, Sentry, Bugsnag, etc.)",
                "Contains no advertising SDKs or ad networks",
                "Contains no social media SDKs",
                "Contains no third-party authentication or login services",
                "Uses only Apple's first-party frameworks (SwiftUI, SwiftData, SpriteKit, MapKit, Contacts, CoreLocation, PhotosUI, AVFoundation)"
            ])
            Text("The only third-party service involved is Apple's iCloud (CloudKit), which is governed by Apple's own privacy policy and your iCloud terms of service.")
        }
    }

    // MARK: - International

    private var internationalSection: some View {
        PolicySection(title: "16. International Data Transfers") {
            Text("Goldfish does not transfer your data to us or to any third party in any country. All data processing occurs locally on your device.")
            Text("If you use iCloud sync, Apple may store your encrypted data in data centers located in various countries. Apple's international data transfers are governed by Apple's own privacy policy and compliance mechanisms, including Standard Contractual Clauses (SCCs) for transfers from the EEA to countries without an adequacy decision.")
        }
    }

    // MARK: - Changes

    private var changesToPolicySection: some View {
        PolicySection(title: "17. Changes to This Privacy Policy") {
            Text("We may update this privacy policy from time to time. When we do, we will:")
            BulletList(items: [
                "Update the \"Last updated\" date at the top of this policy.",
                "Include the updated policy in the next App update.",
                "If the changes are material, add a notice in the App's release notes."
            ])
            Text("Because we do not collect email addresses or any contact information, we cannot notify you directly of changes. We encourage you to review this privacy policy periodically.")
        }
    }

    // MARK: - Contact Us

    private var contactUsSection: some View {
        PolicySection(title: "18. Contact Us") {
            Text("If you have questions, concerns, or requests regarding this privacy policy or our data practices, please contact us at:")
            VStack(alignment: .leading, spacing: 4) {
                Text("📧 support@goldfish-app.com")
                    .fontWeight(.semibold)
            }
            .padding(.leading, 16)
            Text("If you are in the European Union and wish to raise a concern about our use of your data (notwithstanding that we do not collect any), you may contact your local Data Protection Authority. A list of EU Data Protection Authorities is available at: edpb.europa.eu.")
        }
    }
}

// MARK: - Reusable Components

/// A styled policy section with a title and content.
private struct PolicySection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.bold())
                .padding(.top, 4)
            content()
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.85))
                .lineSpacing(3)
        }
    }
}

/// A bulleted list using standard bullet points.
private struct BulletList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(item)
                        .font(.subheadline)
                        .lineSpacing(3)
                }
            }
        }
        .padding(.leading, 8)
    }
}

/// A numbered list.
private struct NumberedList: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 20, alignment: .trailing)
                    Text(item)
                        .font(.subheadline)
                        .lineSpacing(3)
                }
            }
        }
        .padding(.leading, 8)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PrivacyPolicyView()
    }
}
