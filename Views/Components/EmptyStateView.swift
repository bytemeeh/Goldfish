import SwiftUI

// MARK: - Empty State View
/// Signage-style empty state: quiet ink icon, uppercase tracked headline,
/// plain body subtext, compact black CTA.
/// The `editorial` parameter is kept for API compatibility but is ignored —
/// both code paths render the same centered presentation.
struct EmptyStateView: View {
    let systemImage: String
    let headline: String
    let subtext: String
    let action: (() -> Void)?
    let actionLabel: String?
    let secondaryAction: (() -> Void)?
    let secondaryActionLabel: String?
    let editorial: Bool

    init(
        systemImage: String,
        headline: String,
        subtext: String,
        actionLabel: String? = nil,
        editorial: Bool = false,
        action: (() -> Void)? = nil,
        secondaryActionLabel: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.headline = headline
        self.subtext = subtext
        self.actionLabel = actionLabel
        self.secondaryActionLabel = secondaryActionLabel
        self.secondaryAction = secondaryAction
        self.editorial = editorial
        self.action = action
    }

    var body: some View {
        GeometryReader { viewport in
            ScrollView(.vertical) {
                VStack(spacing: GoldfishDS.Space.lg) {
                    Image(systemName: systemImage)
                        .font(.system(size: 40))
                        .foregroundStyle(GoldfishDS.ink(.quaternary))
                        .accessibilityHidden(true)

                    VStack(spacing: GoldfishDS.Space.sm) {
                        Text(headline)
                            .font(.gfName)
                            .textCase(.uppercase)
                            .kerning(1.0)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(GoldfishDS.ink(.primary))

                        Text(subtext)
                            .font(.gfBody)
                            .foregroundStyle(GoldfishDS.ink(.secondary))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, GoldfishDS.Space.xxl)
                    }

                    if let action = action, let label = actionLabel {
                        VStack(spacing: GoldfishDS.Space.sm) {
                            Button(action: action) {
                                Text(label)
                                    .font(.gfLabel)
                                    .textCase(.uppercase)
                                    .kerning(1.0)
                                    .foregroundStyle(GoldfishDS.paper)
                                    .padding(.horizontal, GoldfishDS.Space.lg)
                                    .padding(.vertical, GoldfishDS.Space.sm + 2)
                                    .background(
                                        RoundedRectangle(cornerRadius: GoldfishDS.Radius.control)
                                            .fill(GoldfishDS.inkDark)
                                    )
                            }
                            .buttonStyle(.plain)
                            .frame(minHeight: 44)

                            if let secondaryAction, let secondaryActionLabel {
                                Button(action: secondaryAction) {
                                    Text(secondaryActionLabel)
                                        .font(.gfLabel)
                                        .textCase(.uppercase)
                                        .kerning(1.0)
                                        .foregroundStyle(GoldfishDS.ink(.primary))
                                        .padding(.horizontal, GoldfishDS.Space.lg)
                                        .padding(.vertical, GoldfishDS.Space.sm + 2)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: GoldfishDS.Radius.control)
                                                .strokeBorder(GoldfishDS.ink(.hairline), lineWidth: GoldfishDS.Rule.hairline)
                                        )
                                }
                                .buttonStyle(.plain)
                                .frame(minHeight: 44)
                            }
                        }
                        .padding(.top, GoldfishDS.Space.sm)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: viewport.size.height, alignment: .center)
                .padding(.horizontal, GoldfishDS.Space.pageMargin)
                .padding(.vertical, GoldfishDS.Space.xl)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color.clear)
    }
}

#Preview {
    EmptyStateView(
        systemImage: "circle.hexagongrid",
        headline: "No people yet",
        subtext: "People you add will appear here.",
        actionLabel: "Add Contact",
        editorial: true,
        action: {}
    )
}
