import SwiftUI
import SpriteKit
import Combine

// MARK: - Graph Scene Delegate
/// Protocol to communicate from ViewModel -> SpriteKit Scene
protocol GraphSceneDelegate: AnyObject {
    func didUpdateGraphLevels(_ levels: [GraphLevel])
    func didSelectContact(_ id: UUID?)
    func didUpdateZoom(_ zoom: CGFloat)
    func didUpdateCameraPosition(_ position: CGPoint)
    func centerOnContact(_ id: UUID)
}

// MARK: - GraphViewModel
@MainActor
final class GraphViewModel: ObservableObject {
    
    // MARK: - Dependencies
    private let dataManager: GoldfishDataManager
    
    // MARK: - Scene Communication
    weak var sceneDelegate: GraphSceneDelegate?
    
    // MARK: - State
    @Published var selectedContactID: UUID? {
        didSet {
            sceneDelegate?.didSelectContact(selectedContactID)
        }
    }
    
    // We use @SceneStorage in the View, but track it here for logic
    @Published var zoomLevel: CGFloat = 1.0 {
        didSet {
            // Clamp
            if zoomLevel < 0.1 { zoomLevel = 0.1 }
            if zoomLevel > 4.0 { zoomLevel = 4.0 }
            sceneDelegate?.didUpdateZoom(zoomLevel)
        }
    }
    
    @Published var cameraPosition: CGPoint = .zero {
        didSet {
            sceneDelegate?.didUpdateCameraPosition(cameraPosition)
        }
    }
    
    @Published var graphLevels: [GraphLevel]?
    @Published var isLoading: Bool = false
    
    private var levelsLoaded = false
    
    // MARK: - Init
    init(dataManager: GoldfishDataManager) {
        self.dataManager = dataManager
    }
    
    // MARK: - Methods
    func loadGraph() {
        guard !levelsLoaded else { return } // Avoid re-calc loop if not needed
        
        isLoading = true
        Task {
            do {
                // Offload BFS to background actor if needed, but GraphService is structurally simple enough
                // However, GoldfishDataManager is @MainActor, so we call it here.
                if let levels = try dataManager.buildGraphLayout() {
                    self.graphLevels = levels
                    self.levelsLoaded = true
                    
                    // Notify scene
                    sceneDelegate?.didUpdateGraphLevels(levels)
                }
            } catch {
                print("Failed to build graph layout: \(error)")
            }
            isLoading = false
        }
    }
    
    func refreshGraph() {
        levelsLoaded = false
        loadGraph()
    }
    
    func selectContact(_ id: UUID?) {
        selectedContactID = id
        if let id = id {
            centerOnContact(id)
        }
    }
    
    func centerOnContact(_ id: UUID) {
        sceneDelegate?.centerOnContact(id)
    }
    
    func zoomIn() {
        zoomLevel *= 1.2
    }
    
    func zoomOut() {
        zoomLevel /= 1.2
    }
    
    func resetCamera() {
        zoomLevel = 1.0
        cameraPosition = .zero
        sceneDelegate?.didUpdateZoom(1.0)
        sceneDelegate?.didUpdateCameraPosition(.zero)
    }
    
    // MARK: - Scene Feedback
    /// Called by the scene when user drags camera
    func updateCameraFromScene(position: CGPoint, zoom: CGFloat) {
        // We update properties without triggering didSet loops if possible
        // or just accept the cycle (SwiftUI @Published usually dedupes equality)
        if self.cameraPosition != position {
            self.cameraPosition = position
        }
        if self.zoomLevel != zoom {
            self.zoomLevel = zoom
        }
    }
}
