import SwiftUI

/// PreferenceKey to collect the frames of walkthrough targets
struct WalkthroughAnchorKey: PreferenceKey {
    static var defaultValue: [WalkthroughStep: CGRect] = [:]

    static func reduce(value: inout [WalkthroughStep: CGRect], nextValue: () -> [WalkthroughStep: CGRect]) {
        value.merge(nextValue()) { current, _ in current }
    }
}

/// Modifier that reports a view's global frame for walkthrough spotlighting.
///
/// Frames are reported two ways:
/// - via `WalkthroughAnchorKey` preferences (for regular view hierarchies)
/// - directly into `FeatureWalkthroughManager.anchorFrames` (required for
///   toolbar items, whose preferences don't propagate to the host view)
struct WalkthroughAnchorModifier: ViewModifier {
    let step: WalkthroughStep
    @EnvironmentObject var walkthroughManager: FeatureWalkthroughManager

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(
                            key: WalkthroughAnchorKey.self,
                            value: [step: geo.frame(in: .global)]
                        )
                        .onAppear {
                            walkthroughManager.reportAnchor(geo.frame(in: .global), for: step)
                        }
                        .onChange(of: geo.frame(in: .global)) { _, newFrame in
                            walkthroughManager.reportAnchor(newFrame, for: step)
                        }
                }
            )
    }
}

/// Extension to easily apply the anchor modifier
extension View {
    func walkthroughAnchor(step: WalkthroughStep) -> some View {
        modifier(WalkthroughAnchorModifier(step: step))
    }
}
