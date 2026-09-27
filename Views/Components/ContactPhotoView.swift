import SwiftUI

// MARK: - Contact Photo View
/// Identity uses a painted koi for Me and a matte pond-toned medallion for each contact.
/// "Me" is the painted koi itself —
/// you are the goldfish. See DESIGN_CHANGELOG.md §2 (spine: "Ink in water").
struct ContactPhotoView: View {
    enum AvatarSize: CGFloat {
        case extraSmall = 36
        case small = 44
        case medium = 50
        case large = 80
        case extraLarge = 100
    }

    let photoData: Data?
    let name: String
    let colorHex: String?
    let size: AvatarSize
    var pondName: String? = nil
    var isMe: Bool = false
    var pondColor: Color? = nil
    var petSpeciesLabel: String? = nil

    private var tone: Color { isMe ? GoldfishDS.gold : (pondColor ?? GoldfishDS.pondTone(pondName)) }
    private var hasValidPhoto: Bool {
        guard let photoData else { return false }
        return UIImage(data: photoData) != nil
    }
    var body: some View {
        Group {
            if let data = photoData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable().scaledToFill()
                    .frame(width: size.rawValue, height: size.rawValue)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(tone.opacity(0.5), lineWidth: 1))
            } else if isMe {
                KoiCoin(size: size.rawValue)
            } else {
                PigmentCoin(name: name, tone: tone, size: size.rawValue)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !isMe && petSpeciesLabel != nil {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: max(9, size.rawValue * 0.22), weight: .semibold))
                    .foregroundStyle(GoldfishDS.ink(.primary))
                    .padding(max(2, size.rawValue * 0.06))
                    .background(Circle().fill(GoldfishDS.warmBlack))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel(isMe ? "You" : "\(name), \(hasValidPhoto ? "photo" : "mark")\(petSpeciesLabel.map { ", \($0)" } ?? "")")
    }

}

// MARK: - Koi coin (the "Me" token — the painted goldfish itself)
private struct KoiCoin: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(GoldfishDS.warmBlack)
            Circle().fill(GoldfishDS.gold.opacity(0.16))
            Image("HeroKoi")
                .resizable().scaledToFill()
                .frame(width: size, height: size)
                .scaleEffect(1.0)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(GoldfishDS.gold.opacity(0.5), lineWidth: 0.75))
        .background(
            Circle().fill(GoldfishDS.gold.opacity(0.30))
                .frame(width: size * 1.18, height: size * 1.18)
                .blur(radius: size * 0.14)
        )
    }
}

// MARK: - Matte coin (a contact — solid pond tone with crisp initials)
private struct PigmentCoin: View {
    let name: String
    let tone: Color
    let size: CGFloat

    private var initialForeground: Color {
        Color(uiColor: GoldfishDS.avatarInk(on: UIColor(tone)))
    }

    private var initials: String {
        let parts = name.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        guard !parts.isEmpty else { return "?" }
        if parts.count == 1 { return String(parts[0].prefix(1)).uppercased() }
        return "\(parts.first!.prefix(1))\(parts.last!.prefix(1))".uppercased()
    }

    var body: some View {
        ZStack {
            // One quiet matte surface keeps the initials crisp at every size.
            Circle().fill(tone.opacity(0.94))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(tone.opacity(0.72), lineWidth: 1))
        .overlay(
            Text(initials)
                .font(.system(size: size * 0.34, weight: .medium, design: .serif))
                .tracking(0.5)
                .foregroundStyle(initialForeground)
                .minimumScaleFactor(0.65)
        )
        .accessibilityLabel("\(name)'s initials, \(initials)")
    }
}

extension ContactPhotoView {
    init(person: Person, size: AvatarSize) {
        self.init(photoData: person.photoData, name: person.name, colorHex: person.color,
                  size: size, pondName: person.primaryCircle?.name, isMe: person.isMe,
                  pondColor: GoldfishDS.graphTone(person.primaryCircle), petSpeciesLabel: person.petSpeciesLabel)
    }
}
