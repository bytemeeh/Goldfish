import SwiftUI
import UniformTypeIdentifiers

// MARK: - Database Error View
/// Full-screen recovery UI shown when the ModelContainer fails to initialize.
/// See Spec §5.5.
struct DatabaseErrorView: View {
    let error: Error?
    let retryAction: () -> Void
    
    @State private var isExporting = false
    
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            
            VStack(spacing: 8) {
                Text("Something went wrong")
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text("Goldfish's data couldn't be loaded. You can export your data as a backup and reinstall the app to fix this.\n\nError Details:\n\(String(describing: error))")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
            
            VStack(spacing: 16) {
                Button(action: {
                    isExporting = true
                    // In a real implementation we would try to dump the sqlite/store file
                    // For now we just share a placeholder string or log since the store is corrupt
                }) {
                    Label("Export Backup", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 32)
                
                Button(action: retryAction) {
                    Text("Try Again")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                }
                .padding(.horizontal, 32)
                
                Link("Contact Support", destination: URL(string: "mailto:support@goldfish.app?subject=Database%20Corruption%20Issue")!)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 48)
        }
        .background(Color(.systemBackground))
        // Placeholder for export sheet
        // In a real app we'd try to grab the .sqlite file from the container URL
        .sheet(isPresented: $isExporting) {
            ShareSheet(activityItems: ["Goldfish Backup Data (Corrupt State)"])
        }
    }
}



#Preview {
    DatabaseErrorView(error: nil, retryAction: {})
}
