import SwiftUI
import SwiftData

// MARK: - Color Hex Initializer (String)
extension Color {
    /// Initialize Color from hex string (e.g. "#FF0000" or "FF0000").
    /// Canonical definition — used across the entire app.
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 128, 128, 128)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// Convert a Color back to its hex string representation.
    func toHex() -> String? {
        let uic = UIColor(self)
        guard let components = uic.cgColor.components, components.count >= 3 else {
            return nil
        }
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        var a = Float(1.0)

        if components.count >= 4 {
            a = Float(components[3])
        }

        if a != 1.0 {
            return String(format: "#%02lX%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255), lroundf(a * 255))
        } else {
            return String(format: "#%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
        }
    }
}

// MARK: - DataManager Preview Helper
extension GoldfishDataManager {
    /// Creates a preview instance with in-memory storage.
    /// Uses GoldfishModelContainer.preview() to avoid duplicating the schema list.
    @MainActor
    static func preview() -> GoldfishDataManager {
        do {
            let container = try GoldfishModelContainer.preview()
            return GoldfishDataManager(context: container.mainContext)
        } catch {
            fatalError("Failed to create preview container: \(error)")
        }
    }
}

// MARK: - Toast Manager
/// Singleton manager to trigger toast messages across the app acting like the web demo's showToast(msg).
@MainActor
class ToastManager: ObservableObject {
    static let shared = ToastManager()
    
    @Published var message: String?
    @Published var isShowing: Bool = false
    
    private var dismissTask: Task<Void, Never>?
    
    func showToast(message: String) {
        // Cancel any pending dismiss
        dismissTask?.cancel()
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            self.message = message
            self.isShowing = true
        }
        
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                self.isShowing = false
            }
        }
    }
}

// MARK: - Toast Modifier
struct ToastModifier: ViewModifier {
    @EnvironmentObject var manager: ToastManager
    
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if manager.isShowing, let message = manager.message {
                    Text(message)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
                        .padding(.bottom, 40)
                        // Transition
                        .transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
                        .zIndex(9999)
                }
            }
    }
}

// MARK: - View Extension
public extension View {
    /// Applies the global toast overlay
    func toastOverlay() -> some View {
        self.modifier(ToastModifier())
    }
}

// MARK: - Identifiable Wrapper
public struct IdentifiableWrapper<T: Equatable>: Identifiable, Equatable {
    public let id: UUID
    public let value: T
    
    public init(_ value: T) {
        self.id = UUID()
        self.value = value
    }
}


// MARK: - Helper: Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - UUID Identifiable
