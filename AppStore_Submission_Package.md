# Goldfish release listing draft

**Source checked:** 9 October 2026. This is draft copy from the current app source, not a claim that App Store Connect has been completed. The signed release candidate is version 1.0, build 3. Do not submit fields marked “owner entry”. Public-facing copy uses the Goldfish brand and `goldfish.pond.app@gmail.com`; it contains no personal attribution.

## TestFlight

**Beta description**

Goldfish is a private relationship journal for remembering people, their connections, and the ponds they belong to. Start with fictional sample contacts or create your own. Your journal is stored locally on your device. You can choose to share selected contacts in a Goldfish bundle or vCard.

**What to Test**

Thanks for helping test Goldfish. Please use fictional or non-sensitive data. Try the sample and personal starting choices; add or import a contact; create and remove a relationship; organize several people into one pond; and try batch connection creation. In Settings, share selected people as a `.goldfish` file, review its contents, then import it; compare with vCard export. Check Pond/List navigation, search, sample/personal separation, and Undo. If you use larger text, VoiceOver, or Reduce Motion, tell us what felt unclear or hard to reach. Send observations and screenshots through TestFlight feedback. Your journal stays on this device; sharing happens only when you choose it. Location tracking, AI, and voice features are not part of this beta.

**Beta review notes**

No sign-in is required. On first launch, choose “Explore a Sample” for fictional data or “Start My Pond” for an empty personal journal. Contacts permission is optional and is requested only for phonebook import; contacts can be created manually. Settings includes `.goldfish` and vCard sharing/import. A `.goldfish` file shows a contents review before import; it copies selected data and does not sync. Data is stored locally. There are no purchases or subscriptions. Location tracking, AI, and voice are not implemented. Enter the App Review contact name, phone number, and email from the current App Store Connect account details.

## Public App Store listing

**App name (8/30):** Goldfish

**Subtitle (27/30):** A Journal for Relationships

**Promotional text (draft, 130/170):** Keep the people and connections that matter in view. Organize your network into ponds and share selected contacts when you choose.

**Description (draft):**

Goldfish is a private relationship journal that helps you remember people, the connections between them, and the ponds where you organize them.

Create a personal network with contact details, birthdays, notes, photos, favorites, and tags. View your people in the Pond or List, search by name and relationship details, and record typed connections, including directional family roles. Move selected people into a pond together or create several connections in one batch.

Start with fictional sample contacts or an empty personal pond. Import contacts you select from your phonebook or a vCard file. Export selected contacts as vCards, or share a selected Goldfish bundle that can preserve supported relationships and pond membership. Before importing a Goldfish bundle, review its people, connections, ponds, and note setting.

Your journal is stored locally on your device. Goldfish does not require an account or provide cloud synchronization. Sharing is optional and happens through a destination you choose. Goldfish does not include advertising or analytics SDKs. Contact access is optional and used when you choose phonebook import.

Goldfish includes a visual Pond with a subtle watercolor background, an ordered List, sample and personal scopes, a replayable feature tour, and accessibility support including Dynamic Type and Reduce Motion.

For help or to share feedback, visit the Goldfish support page or contact goldfish.pond.app@gmail.com.

**Keywords (draft, 99/100):** contact,journal,relationships,network,people,connections,pond,organizer,family,friends,groups,vcard

**What's New (v1.0 initial release draft):**

Welcome to Goldfish. Create a local relationship journal, organize people into ponds, and explore your connections in Pond or List. Import selected contacts, then export a vCard or share selected people in a reviewable Goldfish bundle.

**App Review notes:** use the TestFlight review notes above as a starting point. Review the `.goldfish` import and export flow and optional phonebook import. Enter current review contact details in App Store Connect.

## Source-confirmed support and privacy values

- **Support URL:** https://goldfish-pond-support.bwjhhk9fbp.chatgpt.site/
- **Privacy Policy URL:** https://goldfish-pond-support.bwjhhk9fbp.chatgpt.site/privacy
- **Support and feedback email:** goldfish.pond.app@gmail.com

These values are configured in `Goldfish/Info.plist` and `project.yml`. Both URLs returned HTTP 200 via curl on 9 October 2026. Review the hosted privacy policy and reconcile it against this build before completing the App Privacy questionnaire. In particular, review locally stored contact data, optional phonebook import, chosen sharing/export destinations, Apple MapKit use, and device backup behavior. Do not copy old claims of CloudKit synchronization, location tracking, or “Data Not Collected” without reconciling the current build and Apple’s questionnaire. The share/import page copy is drafted in [SUPPORT_SITE_UPDATE.md](Refinement/SUPPORT_SITE_UPDATE.md), pending site access.

## Owner entries still required in App Store Connect

- Verify the existing app record, SKU, primary language, bundle ID, category, age rating, copyright, seller identity, agreements, and legal details.
- Complete App Privacy answers against the binary and the current published privacy policy.
- Supply current App Review contact name, phone, and email.
- Upload current screenshots for supported iPhone and iPad localizations; they must show actual app screens and sample data. Remove old mockups depicting maps, cloud sync, multiple pond membership, or other unavailable behavior.
- Enter the final listing text, promotional text, keywords, and release notes in the intended localization.
- Verify support/privacy pages and support inbox monitoring.
- Confirm source version/build and processed candidate in App Store Connect; this checkout declares 1.0 (3).

**Design decision to make:** whether the public name should remain simply “Goldfish” or use a more descriptive name within Apple’s 30-character limit. The concise name is source-safe; a search-oriented subtitle is another option. No product-claim design decision blocks this draft.
