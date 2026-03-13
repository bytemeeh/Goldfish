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
    func centerOnMe()
    func centerOnPond(name: String)
    func didUpdatePondFilter(_ name: String?)
    func requestConnection(from: UUID, to: UUID)
    func didUpdateSearchMatches(_ ids: Set<UUID>?)
    func animateNewConnection(from: UUID, to: UUID)
    func didLongPressContact(_ id: UUID)
    func fitToGraph()
}

// MARK: - GraphViewModel
@MainActor
final class GraphViewModel: ObservableObject {
    
    // MARK: - Dependencies
    private let dataManager: GoldfishDataManager
    
    // MARK: - Scene Communication
    weak var sceneDelegate: GraphSceneDelegate?
    
    // MARK: - State
    
    /// Flag to prevent infinite feedback loops when updating from the scene
    private var isUpdatingFromScene = false
    
    @Published var selectedContactID: UUID? {
        didSet {
            sceneDelegate?.didSelectContact(selectedContactID)
        }
    }
    
    @Published var searchMatchedIDs: Set<UUID>? {
        didSet {
            sceneDelegate?.didUpdateSearchMatches(searchMatchedIDs)
            if let ids = searchMatchedIDs, ids.count == 1, let id = ids.first {
                centerOnContact(id)
            }
        }
    }
    

    
    @Published var selectedPondFilter: String? {
        didSet {
            sceneDelegate?.didUpdatePondFilter(selectedPondFilter)
        }
    }
    
    // We use @SceneStorage in the View, but track it here for logic
    @Published var zoomLevel: CGFloat = 1.0 {
        didSet {
            // Clamp
            if zoomLevel < 0.1 { zoomLevel = 0.1 }
            if zoomLevel > 4.0 { zoomLevel = 4.0 }
            guard !isUpdatingFromScene else { return }
            sceneDelegate?.didUpdateZoom(zoomLevel)
        }
    }
    
    @Published var cameraPosition: CGPoint = .zero {
        didSet {
            guard !isUpdatingFromScene else { return }
            sceneDelegate?.didUpdateCameraPosition(cameraPosition)
        }
    }
    
    @Published var graphLevels: [GraphLevel]?
    @Published var isLoading: Bool = false
    @Published var hasNoData: Bool = false
    
    /// When `true`, only demo contacts are shown in the graph.
    var isDemoMode: Bool = false
    
    /// When set, triggers the Add Relationship sheet for drag-to-connect
    @Published var pendingConnectionFrom: UUID?
    @Published var pendingConnectionTo: UUID?
    
    @Published var pendingPondMovePerson: UUID?
    @Published var pendingPondMoveTarget: String?
    
    @Published var pendingActionContactID: UUID?
    
    @Published var levelsLoaded = false
    private var isLoadingInProgress = false
    
    // MARK: - Init
    init(dataManager: GoldfishDataManager) {
        self.dataManager = dataManager
    }
    
    // MARK: - Methods
    func loadGraph() {
        guard !levelsLoaded else {
            print("[GraphVM] loadGraph skipped — already loaded")
            return
        }
        guard !isLoadingInProgress else {
            print("[GraphVM] loadGraph skipped — already in progress")
            return
        }
        
        print("[GraphVM] loadGraph started, isDemoMode=\(isDemoMode)")
        isLoadingInProgress = true
        isLoading = true
        Task {
            defer {
                isLoading = false
                isLoadingInProgress = false
                print("[GraphVM] isLoading = false")
            }
            do {
                print("[GraphVM] Task started, calling buildGraphLayout...")
                let levels: [GraphLevel]?
                if isDemoMode {
                    levels = try dataManager.buildGraphLayout(demoMode: true)
                } else {
                    levels = try dataManager.buildGraphLayout(demoMode: false)
                }
                print("[GraphVM] buildGraphLayout returned: \(levels?.count ?? -1) levels")
                if let levels {
                    self.graphLevels = levels
                    self.levelsLoaded = true
                    self.hasNoData = levels.flatMap(\.allContacts).isEmpty
                    sceneDelegate?.didUpdateGraphLevels(levels)
                    print("[GraphVM] Graph loaded with \(levels.flatMap(\.allContacts).count) contacts")
                } else {
                    self.hasNoData = true
                    print("[GraphVM] No Me contact found — hasNoData = true")
                }
            } catch {
                print("[GraphVM] Failed to build graph layout: \(error)")
                self.hasNoData = true
            }
        }
    }
    
    func refreshGraph() {
        print("[GraphVM] refreshGraph called")
        levelsLoaded = false
        isLoadingInProgress = false  // Allow new load
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
    
    func centerOnPond(name: String) {
        if selectedPondFilter == name {
            // Toggle off if already selected
            selectedPondFilter = nil
        } else {
            selectedPondFilter = name
            sceneDelegate?.centerOnPond(name: name)
        }
    }
    
    func zoomIn() {
        zoomLevel = min(zoomLevel * 1.2, 4.0)
        sceneDelegate?.didUpdateZoom(zoomLevel)
    }
    
    func zoomOut() {
        zoomLevel = max(zoomLevel / 1.2, 0.1)
        sceneDelegate?.didUpdateZoom(zoomLevel)
    }
    
    func resetCamera() {
        sceneDelegate?.centerOnMe()
    }
    
    // MARK: - Scene Feedback
    /// Called by the scene when user drags camera
    func updateCameraFromScene(position: CGPoint, zoom: CGFloat) {
        isUpdatingFromScene = true
        if self.cameraPosition != position {
            self.cameraPosition = position
        }
        if self.zoomLevel != zoom {
            self.zoomLevel = zoom
        }
        isUpdatingFromScene = false
    }
    
    /// Called by the scene when user drags a node onto another node
    func requestConnection(from sourceID: UUID, to targetID: UUID) {
        pendingConnectionFrom = sourceID
        pendingConnectionTo = targetID
    }
    
    func confirmConnection() {
        guard let fromID = pendingConnectionFrom, let toID = pendingConnectionTo else { return }
        // The animation will be triggered by GraphContainerView after the data is updated
        // But we can also trigger it directly if we want it to feel immediate
        sceneDelegate?.animateNewConnection(from: fromID, to: toID)
    }
    
    /// Called by the scene when user drags a node into empty space within a pond
    func requestPondMove(for personID: UUID, to pondName: String) {
        pendingPondMovePerson = personID
        pendingPondMoveTarget = pondName
    }
    
    /// Called by the scene when a user long presses a node
    func didLongPressContact(_ id: UUID) {
        pendingActionContactID = id
    }
}
