import SwiftUI

@MainActor
struct RelationshipSearchResultsView: View {
    let response: RelationshipSearchResponse
    let onSelect: (Person) -> Void
    let onExplore: (RelationshipSearchPath) -> Void

    private var hasResults: Bool { !response.paths.isEmpty }
    private var statusMessage: String {
        if let message = response.message, !message.isEmpty { return message }
        if response.query == nil {
            return "Try a saved relationship chain such as “my sibling”."
        }
        return "No recorded connection matched that chain. Try “my sibling” or check that each link is saved."
    }

    private var countLabel: String {
        let contactLabel = response.matchedContactCount == 1 ? "contact" : "contacts"
        let routeLabel = response.paths.count == 1 ? "route" : "routes"
        let prefix = response.isTruncated ? "Shown " : ""
        return "\(prefix)\(response.matchedContactCount) \(contactLabel) · \(response.paths.count) \(routeLabel)"
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: GoldfishDS.Space.md) {
                summary
                if hasResults {
                    ForEach(response.paths) { path in
                        resultCard(path)
                    }
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, GoldfishDS.Space.pageMargin)
            .padding(.vertical, GoldfishDS.Space.lg)
        }
        .scrollIndicators(.hidden)
        .background(GoldfishDS.warmBlack.ignoresSafeArea())
        .foregroundStyle(GoldfishDS.ink(.primary))
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: GoldfishDS.Space.xs) {
            Text(countLabel)
                .font(.gfMeta)
                .foregroundStyle(GoldfishDS.ink(.secondary))
                .accessibilityIdentifier("relationship-search-result-count")
            if hasResults, let message = response.message, !message.isEmpty {
                Text(message)
                    .font(.gfBody)
                    .foregroundStyle(GoldfishDS.ink(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if response.isTruncated {
                Text("Showing the first recorded routes.")
                    .font(.gfMeta)
                    .foregroundStyle(GoldfishDS.ink(.tertiary))
            }
        }
    }

    private func resultCard(_ path: RelationshipSearchPath) -> some View {
        VStack(alignment: .leading, spacing: GoldfishDS.Space.md) {
            HStack(alignment: .top, spacing: GoldfishDS.Space.md) {
                ContactPhotoView(person: path.person, size: .medium)
                    .accessibilityHidden(true)
                Text(path.person.isMe ? "You" : path.person.name)
                    .font(.gfName)
                    .foregroundStyle(GoldfishDS.ink(.primary))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(path.summary)
                .font(.gfBody)
                .foregroundStyle(GoldfishDS.ink(.secondary))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("relationship-search-path-\(path.id)")
            if response.anchorMatches.count > 1, let anchor = path.people.first {
                Text("From \(anchor.name.split(separator: " ").first.map(String.init) ?? anchor.name) · \(anchor.primaryCircle?.name ?? "Unassigned")")
                    .font(.gfMeta)
                    .foregroundStyle(GoldfishDS.ink(.tertiary))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("relationship-search-anchor-context-\(path.id)")
            }
            ViewThatFits(in: .horizontal) {
                actionButtons(path, vertical: false)
                actionButtons(path, vertical: true)
            }
        }
        .padding(GoldfishDS.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GoldfishDS.surface, in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: GoldfishDS.Radius.card)
                .stroke(GoldfishDS.ink(.hairline), lineWidth: GoldfishDS.Rule.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("relationship-search-result-\(path.id)")
    }

    private func actionButtons(_ path: RelationshipSearchPath, vertical: Bool) -> some View {
        Group {
            if vertical {
                VStack(spacing: GoldfishDS.Space.sm) {
                    contactButton(path).frame(maxWidth: .infinity)
                    exploreButton(path).frame(maxWidth: .infinity)
                }
            } else {
                HStack(spacing: GoldfishDS.Space.sm) {
                    contactButton(path)
                    exploreButton(path)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }

    private func contactButton(_ path: RelationshipSearchPath) -> some View {
        Button("Open contact") { onSelect(path.person) }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(GoldfishDS.ink(.primary))
            .frame(minHeight: 44)
            .accessibilityIdentifier("relationship-search-open-contact-\(path.id)")
    }

    private func exploreButton(_ path: RelationshipSearchPath) -> some View {
        Button("Show in Pond") { onExplore(path) }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(GoldfishDS.terracotta)
            .frame(minHeight: 44)
            .accessibilityIdentifier("relationship-search-explore-\(path.id)")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: GoldfishDS.Space.sm) {
            Image(systemName: response.query == nil ? "magnifyingglass" : "point.3.connected.trianglepath.dotted")
                .font(.title2)
                .foregroundStyle(GoldfishDS.terracotta)
                .accessibilityHidden(true)
            Text(statusMessage)
                .font(.gfBody)
                .foregroundStyle(GoldfishDS.ink(.secondary))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, GoldfishDS.Space.xl)
        .accessibilityIdentifier("relationship-search-empty-state")
    }
}
