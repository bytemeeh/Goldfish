import SwiftUI

struct ImportSummarySheet: View {
    let result: ImportResult
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)
                .padding(.top, 32)
            
            Text(result.isGoldfishFormat ? "Goldfish File Detected" : "Import Complete")
                .font(.title2.bold())
            
            VStack(spacing: 16) {
                summaryRow(title: "Contacts Imported", count: result.importedCount, icon: "person.crop.circle.badge.plus", color: .blue)
                
                if result.skippedCount > 0 {
                    summaryRow(title: "Duplicates Skipped", count: result.skippedCount, icon: "person.2.slash", color: .orange)
                }
                
                if result.isGoldfishFormat {
                    if result.connectionsRestored > 0 {
                        summaryRow(title: "Connections Restored", count: result.connectionsRestored, icon: "link", color: .green)
                    }
                    if result.connectionsSkipped > 0 {
                        summaryRow(title: "Connections Existed", count: result.connectionsSkipped, icon: "link.badge.plus", color: .secondary)
                    }
                    if result.circlesCreated > 0 {
                        summaryRow(title: "New Ponds Created", count: result.circlesCreated, icon: "water.waves", color: .cyan)
                    }
                } else if result.importedCount > 0 {
                    Text("Imported without pond or connection data.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
                }
                
                if !result.errors.isEmpty {
                    summaryRow(title: "Errors Occurred", count: result.errors.count, icon: "exclamationmark.triangle", color: .red)
                }
            }
            .padding(.horizontal, 32)
            
            Spacer()
            
            Button(action: onDismiss) {
                Text("Done")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.goldfishAccent)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 16)
        }
    }
    
    @ViewBuilder
    private func summaryRow(title: String, count: Int, icon: String, color: Color) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 30)
            Text(title)
            Spacer()
            Text("\(count)")
                .fontWeight(.bold)
        }
        .font(.body)
    }
}
