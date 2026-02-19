import SwiftUI

// MARK: - Empty State View
/// A consistent empty state component used across the app.
/// See Spec §4.
struct EmptyStateView: View {
    let systemImage: String
    let headline: String
    let subtext: String
    let action: (() -> Void)?
    let actionLabel: String?
    
    init(
        systemImage: String,
        headline: String,
        subtext: String,
        actionLabel: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.systemImage = systemImage
        self.headline = headline
        self.subtext = subtext
        self.actionLabel = actionLabel
        self.action = action
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            
            VStack(spacing: 4) {
                Text(headline)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                
                Text(subtext)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            if let action = action, let label = actionLabel {
                Button(action: action) {
                    Text(label)
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(20)
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground)) // ensure it covers content
    }
}

#Preview {
    EmptyStateView(
        systemImage: "person.3.fill",
        headline: "No contacts yet",
        subtext: "People you add will appear here.",
        actionLabel: "Add Contact",
        action: {}
    )
}
