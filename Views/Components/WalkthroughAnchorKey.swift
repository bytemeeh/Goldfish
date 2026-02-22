import SwiftUI

/// PreferenceKey to collect the frames of walkthrough targets
struct WalkthroughAnchorKey: PreferenceKey {
    static var defaultValue: [WalkthroughStep: CGRect] = [:]
    
    static func reduce(value: inout [WalkthroughStep: CGRect], nextValue: () -> [WalkthroughStep: CGRect]) {
        value.merge(nextValue()) { current, _ in current }
    }
}

/// Modifier that reports a view's global frame to the WalkthroughAnchorKey
struct WalkthroughAnchorModifier: ViewModifier {
    let step: WalkthroughStep
    
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(
                            key: WalkthroughAnchorKey.self,
                            value: [step: geo.frame(in: .global)]
                        )
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
