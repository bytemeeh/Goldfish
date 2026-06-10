import SwiftUI

// MARK: - Add Contact Sheet (Option 1)
/// Bottom sheet with icon-forward rows for choosing how to add a contact.
struct AddContactSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Called when the user picks an option.
    let onVoiceEntry: () -> Void
    let onPhonebook: () -> Void
    let onManual: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 20)

            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("New Contact")
                    .font(.title2.bold())
                Text("Choose how to add someone")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)

            // Options
            VStack(spacing: 0) {
                AddContactRow(
                    icon: "mic.fill",
                    title: "Voice Entry",
                    subtitle: "Describe your contact out loud",
                    isFirst: true,
                    isLast: false
                ) {
                    dismiss()
                    onVoiceEntry()
                }

                Divider().padding(.leading, 68)

                AddContactRow(
                    icon: "person.text.rectangle.fill",
                    title: "From Phonebook",
                    subtitle: "Pick from your existing contacts",
                    isFirst: false,
                    isLast: false
                ) {
                    dismiss()
                    onPhonebook()
                }

                Divider().padding(.leading, 68)

                AddContactRow(
                    icon: "square.and.pencil",
                    title: "Enter Manually",
                    subtitle: "Fill in the details yourself",
                    isFirst: false,
                    isLast: true
                ) {
                    dismiss()
                    onManual()
                }
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)

            // Cancel
            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Row Component
private struct AddContactRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let isFirst: Bool
    let isLast: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon circle
                ZStack {
                    Circle()
                        .fill(Color.goldfishAccent.opacity(0.15))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.goldfishAccent)
                }

                // Labels
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(.tertiaryLabel))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
