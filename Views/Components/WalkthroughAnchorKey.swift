import SwiftUI

/// PreferenceKey to collect the frames of walkthrough targets
struct WalkthroughAnchorKey: PreferenceKey {
    static var defaultValue: [WalkthroughStep: CGRect] = [:]
    
    static func reduce(value: inout [WalkthroughStep: CGRect], nextValue: () -> [WalkthroughStep: CGRect]) {
        value.merge(nextValue()) { current, _ in current }
    }
}

/// Modifier that reports a view's global frame to the WalkthroughAnchorKey and
/// gives the active step a quiet, visible target outline. The outline is
/// deliberately hit-test transparent so the real control remains interactive.
struct WalkthroughAnchorModifier: ViewModifier {
    let step: WalkthroughStep
    var enabled = true
    @EnvironmentObject private var walkthroughManager: FeatureWalkthroughManager
    
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(
                            key: WalkthroughAnchorKey.self,
                            value: enabled ? [step: geo.frame(in: .global)] : [:]
                    )
                }
            )
            .overlay {
                if enabled && walkthroughManager.isActive && walkthroughManager.currentStep == step {
                    RoundedRectangle(cornerRadius: GoldfishDS.Radius.control)
                        .stroke(GoldfishDS.terracotta, lineWidth: 2)
                        .padding(-4)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}

/// Extension to easily apply the anchor modifier
extension View {
    func walkthroughAnchor(step: WalkthroughStep, enabled: Bool = true) -> some View {
        modifier(WalkthroughAnchorModifier(step: step, enabled: enabled))
    }
}
