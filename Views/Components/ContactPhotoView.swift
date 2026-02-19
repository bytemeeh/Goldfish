import SwiftUI

// MARK: - Contact Photo View
/// Displays a contact's photo or a fallback circle with initials.
/// See Spec §4.5 and §8.5/8.6.
struct ContactPhotoView: View {
    let photoData: Data?
    let name: String
    let colorHex: String?
    let size: CGFloat
    
    var body: some View {
        Group {
            if let data = photoData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                FallbackCircle(name: name, colorHex: colorHex, size: size)
            }
        }
        .accessibilityLabel("\(name)'s photo")
    }
}

// MARK: - Fallback Circle
private struct FallbackCircle: View {
    let name: String
    let colorHex: String?
    let size: CGFloat
    
    var initials: String {
        let components = name.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        guard !components.isEmpty else { return "?" }
        if components.count == 1 {
            return String(components[0].prefix(2)).uppercased()
        }
        let first = components.first?.prefix(1) ?? ""
        let last = components.last?.prefix(1) ?? ""
        return "\(first)\(last)".uppercased()
    }
    
    var backgroundColor: Color {
        if let hex = colorHex, !hex.isEmpty {
            return Color(hex: hex)
        }
        return generatePastelColor(for: name)
    }
    
    var body: some View {
        ZStack {
            backgroundColor
            
            Text(initials)
                .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityLabel("\(name)'s initials, \(initials)")
    }
    
    // Deterministic pastel color generator per spec §4.5
    // hue = (hash % 360) / 360, sat=0.4, bright=0.85
    private func generatePastelColor(for name: String) -> Color {
        var hash = 0
        for char in name {
            hash = (hash &* 31) &+ Int(char.asciiValue ?? 0)
        }
        // Swift hash might be negative
        hash = abs(hash)
        
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.4, brightness: 0.85)
    }
}
