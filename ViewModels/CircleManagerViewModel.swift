import SwiftUI

// MARK: - CircleManagerViewModel
@MainActor
final class CircleManagerViewModel: ObservableObject {
    
    // MARK: - Dependencies
    private let dataManager: GoldfishDataManager
    
    // MARK: - State
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
            print("Error loading circles: \(error)")
        }
    }
    
    // MARK: - CRUD
    func createCircle(name: String, emoji: String, color: String) {
        do {
            try dataManager.createCircle(name: name, color: color, emoji: emoji)
            loadCircles()
        } catch {
            print("Error creating circle: \(error)")
        }
    }
    
    func deleteCircle(_ circle: GoldfishCircle) {
        do {
            try dataManager.deleteCircle(circle)
            loadCircles()
        } catch {
            print("Error deleting circle: \(error)")
        }
    }
    
    func updateCircle(_ circle: GoldfishCircle, name: String, emoji: String, color: String) {
        do {
            try dataManager.updateCircle(circle, name: name, emoji: emoji, color: color)
            loadCircles()
        } catch {
            print("Error updating circle: \(error)")
        }
    }
}
