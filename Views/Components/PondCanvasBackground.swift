import SwiftUI

/// Decoration is fixed to the viewport so exploring connections never moves the artwork.
struct PondCanvasBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                GoldfishDS.warmBlack
                if contrast != .increased && !reduceTransparency {
                    if colorScheme == .light {
                        Image(decorative: "PondWatercolor")
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .opacity(0.55)
                            .accessibilityHidden(true)
                    } else {
                        Image(decorative: "WatercolorKoi")
                            .resizable()
                            .scaledToFit()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .opacity(0.055)
                            .accessibilityHidden(true)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
