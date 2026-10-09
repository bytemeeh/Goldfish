import SwiftUI

struct ConnectionSessionCard: View {
    @ObservedObject private var session = ConnectionSession.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onReveal: (() -> Void)? = nil

    var body: some View {
        if session.isActive {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    QuietPondReward(completed: session.isComplete)
                        .id(session.feedbackID)
                        .frame(width: 44, height: 44)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.isComplete ? "A little more connected" : "Connect five people")
                            .font(.gfBody.weight(.medium))
                        Text("\(session.count) of \(session.goal) people connected this session")
                            .font(.gfCaption).foregroundStyle(GoldfishDS.ink(.secondary))
                    }
                    Spacer(minLength: 0)
                    Button { session.finish() } label: {
                        Image(systemName: "xmark").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(session.isComplete ? "Finish connection session" : "End session for now")
                }
                if !session.isComplete {
                    ProgressView(value: Double(min(session.count, session.goal)), total: Double(session.goal))
                        .tint(GoldfishDS.terracotta)
                        .accessibilityLabel("Connection session progress")
                }
                if session.isComplete, let onReveal {
                    Button("See the connections") { onReveal() }
                        .font(.gfBody).frame(minHeight: 44)
                }
            }
            .padding(12)
            .foregroundStyle(GoldfishDS.ink(.primary))
            .background(GoldfishDS.surface, in: RoundedRectangle(cornerRadius: GoldfishDS.Radius.control))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: session.count)
        }
    }
}

/// A single gentle ripple; no looping reward, delay, score, or streak.
struct QuietPondReward: View {
    let completed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var settled = false
    var body: some View {
        ZStack {
            Circle().stroke(GoldfishDS.terracotta.opacity(settled ? 0 : 0.45), lineWidth: 1)
                .scaleEffect(settled ? 1.35 : 0.55)
            if completed {
                Image("WatercolorKoi").resizable().scaledToFit()
                    .rotationEffect(.degrees(settled ? 6 : -8))
                    .offset(y: settled ? -3 : 4)
            } else {
                Image(systemName: "checkmark").foregroundStyle(GoldfishDS.terracotta)
            }
        }
        .onAppear {
            if reduceMotion { settled = true }
            else { withAnimation(.easeOut(duration: 1.1)) { settled = true } }
        }
    }
}
