import SwiftUI

// MARK: - CircleManagerViewModel
@MainActor
final class CircleManagerViewModel: ObservableObject {

    enum NameFeedback: Equatable {
        case valid
        case invalid(String)
        case duplicate(String)
        case advisory(String)

        var message: String? {
            switch self {
            case .valid: return nil
            case .invalid(let message), .duplicate(let message), .advisory(let message): return message
            }
        }

        var preventsSave: Bool {
            if case .invalid = self { return true }
            return false
        }
    }

    // MARK: - Dependencies
    private let dataManager: GoldfishDataManager

    // MARK: - State
    @Published var errorMessage: String?
    @Published var circles: [GoldfishCircle] = []

    // MARK: - Init
    init(dataManager: GoldfishDataManager) {
        self.dataManager = dataManager
        loadCircles()
    }

    func loadCircles() {
        do {
            self.circles = try dataManager.fetchAllCircles()
        } catch {
            errorMessage = "Could not load ponds: \(error.localizedDescription)"
        }
    }

    func nameFeedback(_ name: String, excluding circle: GoldfishCircle? = nil) -> NameFeedback {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .invalid("Enter a name for this pond.") }
        guard trimmed.rangeOfCharacter(from: .controlCharacters) == nil else {
            return .invalid("Use visible characters in the pond name.")
        }

        if let duplicate = circles.first(where: {
            $0.id != circle?.id && $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return .duplicate("Another pond is already named \u{201C}\(duplicate.name)\u{201D}. Both can stay if their colors or purpose make them clear.")
        }

        if trimmed.count > 60 {
            return .advisory("May be shortened on the map.")
        }
        return .valid
    }

    // MARK: - CRUD
    @discardableResult
    func createCircle(name: String, emoji: String, color: String) -> Bool {
        do {
            try dataManager.createCircle(name: name.trimmingCharacters(in: .whitespacesAndNewlines), color: color, emoji: emoji)
            loadCircles()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
            // print("Error creating circle: \(error)")
        }
    }

    @discardableResult
    func deleteCircle(_ circle: GoldfishCircle) -> Bool {
        do {
            try dataManager.deleteCircle(circle)
            loadCircles()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
            // print("Error deleting circle: \(error)")
        }
    }

    @discardableResult
    func updateCircle(_ circle: GoldfishCircle, name: String, emoji: String, color: String) -> Bool {
        do {
            try dataManager.updateCircle(circle, name: name.trimmingCharacters(in: .whitespacesAndNewlines), emoji: emoji, color: color)
            loadCircles()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
            // print("Error updating circle: \(error)")
        }
    }
}
