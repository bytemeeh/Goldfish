import Foundation

enum ContactKind: String, Codable, CaseIterable, Identifiable {
    case human, dog, cat, pet
    var id: String { rawValue }
    var isPet: Bool { self != .human }
    var label: String {
        switch self { case .human: return "Person"; case .dog: return "Dog"; case .cat: return "Cat"; case .pet: return "Pet" }
    }
}
