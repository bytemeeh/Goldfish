import SwiftUI

struct SearchOverlayView: View {
    @ObservedObject var viewModel: HomeViewModel
    @EnvironmentObject var dataManager: GoldfishDataManager
    let onSelect: (Person) -> Void

    var body: some View {
        Group {
            if viewModel.filteredContacts.isEmpty {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    headline: "No people match.",
                    subtext: "Try another name."
                )
            } else {
                ScrollView {
                LazyVStack(spacing: 0) {
                    Text("\(viewModel.filteredContacts.count) \(viewModel.filteredContacts.count == 1 ? "result" : "results")")
                        .font(.gfMeta)
                        .foregroundStyle(GoldfishDS.ink(.tertiary))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, GoldfishDS.Space.pageMargin)
                        .padding(.vertical, GoldfishDS.Space.sm)
                    ForEach(Array(viewModel.filteredContacts.enumerated()), id: \.element.id) { index, person in
                        Button(action: { onSelect(person) }) {
                            SearchResultRow(
                                person: person,
                                query: viewModel.normalizedSearchText,
                                matchContext: viewModel.matchContext(for: person)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel([person.name, viewModel.matchContext(for: person)].compactMap { $0 }.joined(separator: ", "))
                        .accessibilityHint("Opens contact details")

                        if index < viewModel.filteredContacts.count - 1 {
                            Rectangle()
                                .fill(GoldfishDS.ink(.hairline))
                                .frame(height: 0.5)
                                .padding(.leading, GoldfishDS.Space.pageMargin)
                        }
                    }
                }
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityIdentifier("searchResults")
        .background(GoldfishDS.warmBlack)
        .overlay(
            Rectangle()
                .fill(GoldfishDS.ink(.hairline))
                .frame(height: 0.5),
            alignment: .bottom
        )
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Search Result Row

private struct SearchResultRow: View {
    let person: Person
    let query: String
    let matchContext: String?

    private var pondName: String? {
        person.circleContacts.first(where: { !$0.manuallyExcluded })?.circle.name
    }

    var body: some View {
        HStack(spacing: GoldfishDS.Space.md) {
            ContactPhotoView(person: person, size: .extraSmall)

            VStack(alignment: .leading, spacing: 2) {
                highlightedName(person.name, query: query)
                    .font(.gfName)
                    .foregroundStyle(GoldfishDS.ink(.primary))

                if let matchContext {
                    Text(matchContext)
                        .font(.gfCaption)
                        .foregroundStyle(GoldfishDS.ink(.secondary))
                        .lineLimit(1)
                }

                if let pond = pondName, !pond.isEmpty {
                    // Line name as small uppercase signage caption in the line's color.
                    Text(pond)
                        .font(.gfCaption)
                        .textCase(.uppercase)
                        .kerning(1.0)
                        .foregroundStyle(GoldfishDS.groupTone(person.primaryCircle))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, GoldfishDS.Space.pageMargin)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    /// Returns a Text view with the matching substring highlighted in terracotta.
    private func highlightedName(_ name: String, query: String) -> Text {
        guard !query.isEmpty,
              let range = name.range(of: query, options: .caseInsensitive) else {
            return Text(name)
        }
        let before  = String(name[name.startIndex..<range.lowerBound])
        let matched = String(name[range])
        let after   = String(name[range.upperBound..<name.endIndex])

        return Text(before)
            + Text(matched).foregroundColor(GoldfishDS.terracotta)
            + Text(after)
    }
}
