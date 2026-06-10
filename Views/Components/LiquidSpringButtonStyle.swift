import SwiftUI

/// A premium, highly responsive button style that uses a physical spring animation
/// and provides haptic feedback when pressed.
public struct LiquidSpringButtonStyle: ButtonStyle {
    
    // Configurable spring parameters
    public var scaleAmount: CGFloat
    public var springResponse: Double
    public var springDamping: Double
    public var feedbackStyle: UIImpactFeedbackGenerator.FeedbackStyle?
    
    public init(
        scaleAmount: CGFloat = 0.92,
        springResponse: Double = 0.3,
        springDamping: Double = 0.6,
        feedbackStyle: UIImpactFeedbackGenerator.FeedbackStyle? = .light
    ) {
        self.scaleAmount = scaleAmount
        self.springResponse = springResponse
        self.springDamping = springDamping
        self.feedbackStyle = feedbackStyle
    }
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scaleAmount : 1.0)
            .animation(
                .spring(response: springResponse, dampingFraction: springDamping, blendDuration: 0),
                value: configuration.isPressed
            )
            .onChange(of: configuration.isPressed) { isPressed in
                if isPressed, let style = feedbackStyle {
                    let generator = UIImpactFeedbackGenerator(style: style)
                    generator.prepare()
                    generator.impactOccurred()
                }
            }
    }
}

public extension ButtonStyle where Self == LiquidSpringButtonStyle {
    static var liquidSpring: LiquidSpringButtonStyle {
        LiquidSpringButtonStyle()
    }
    
    static func liquidSpring(
        scaleAmount: CGFloat = 0.92,
        springResponse: Double = 0.3,
        springDamping: Double = 0.6,
        feedbackStyle: UIImpactFeedbackGenerator.FeedbackStyle? = .light
    ) -> LiquidSpringButtonStyle {
        LiquidSpringButtonStyle(
            scaleAmount: scaleAmount,
            springResponse: springResponse,
            springDamping: springDamping,
            feedbackStyle: feedbackStyle
        )
    }
}
