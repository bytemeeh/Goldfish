import SwiftUI

/// A premium, animated background that simulates a complex mesh gradient
/// using heavily blurred moving circles in a Canvas. iOS 17 compatible.
struct FluidBlobBackground: View {
    
    // We animate based on time to make the blobs drift
    let blobColors: [Color]
    let speed: Double
    
    public init(colors: [Color] = [
        Color(hex: "b74f3a"),       // Terracotta
        Color(hex: "e8a238"),    // Amber
        Color(hex: "06141b"),     // Midnight Teal
        Color(hex: "102830")       // Deep Sea
    ], speed: Double = 1.0) {
        self.blobColors = colors
        self.speed = speed
    }
    
    public var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate * speed
                
                // Draw a dark base background
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: "06141b")))
                
                // Draw drifting blobs
                for (index, color) in blobColors.enumerated() {
                    let offset = Double(index) * 100.0
                    let angle1 = now * 0.2 + offset
                    let angle2 = now * 0.15 + offset * 1.5
                    
                    let radiusX = size.width * 0.6
                    let radiusY = size.height * 0.6
                    
                    // Complex motion using sine/cosine
                    let x = size.width/2 + cos(angle1) * size.width * 0.3
                    let y = size.height/2 + sin(angle2) * size.height * 0.3
                    
                    let rect = CGRect(
                        x: x - radiusX/2,
                        y: y - radiusY/2,
                        width: radiusX,
                        height: radiusY
                    )
                    
                    let path = Path(ellipseIn: rect)
                    
                    // We apply a soft blend mode and opacity for the fluid effect inside the canvas
                    context.blendMode = .screen
                    context.fill(path, with: .color(color.opacity(0.6)))
                }
            }
            .blur(radius: 80) // Heavy blur creates the "mesh gradient" feel
            .ignoresSafeArea()
            .opacity(0.8) // Tone it down slightly so the graph nodes pop
        }
    }
}
