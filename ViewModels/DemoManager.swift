import SwiftUI
import Combine

enum DemoStep: Int, CaseIterable {
    case welcome = 0
    case createContact
    case assignToPond
    case autoCreateSecond
    case connectContacts
    case reviewPonds
    case finished
}

@MainActor
class DemoManager: ObservableObject {
    @Published var isActive: Bool = false
    @Published var currentStep: DemoStep = .welcome
    @Published var demoContactIDs: Set<UUID> = []
    
    // For storing pre-existing state if we need to restore anything after demo (optional, depending on DB isolation)
    private var dataManager: GoldfishDataManager?
    private var monitorTask: Task<Void, Never>?
    
    func startDemo(with manager: GoldfishDataManager) {
        self.dataManager = manager
        isActive = true
        currentStep = .welcome
        demoContactIDs.removeAll()
        startMonitoring()
    }
    
    func nextStep() {
        if let next = DemoStep(rawValue: currentStep.rawValue + 1) {
            currentStep = next
        } else {
            finishDemo()
        }
    }
    
    func finishDemo() {
        isActive = false
        currentStep = .finished
        stopMonitoring()
    }
    
    func endAndCleanSlate() async {
        guard let manager = dataManager else { return }
        
        let idsToDelete = demoContactIDs
        for person in (try? manager.fetchAllPersons()) ?? [] {
            if idsToDelete.contains(person.id) {
                try? manager.deletePerson(person)
            }
        }
        
        // Also cleanup ponds if any were specifically created for demo
        demoContactIDs.removeAll()
        finishDemo()
    }
    
    func endAndKeepContacts() {
        demoContactIDs.removeAll()
        finishDemo()
    }
    
    // Monitors database changes or UI events to automatically advance steps when possible
    private func startMonitoring() {
        stopMonitoring()
        
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s polling for demo actions
                guard let self = self, self.isActive, let manager = self.dataManager else { continue }
                
                await MainActor.run {
                    self.evaluateCurrentStep(with: manager)
                }
            }
        }
    }
    
    private func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }
    
    private func evaluateCurrentStep(with manager: GoldfishDataManager) {
        guard let persons = try? manager.fetchAllPersons() else { return }
        let currentDemoContacts = persons.filter { demoContactIDs.contains($0.id) }
        
        // Let's identify demo behavior
        // E.g., if step is creating a contact, and demoContactIDs count increases, next step
        switch currentStep {
        case .welcome:
            break // user must tap next
        case .createContact:
            // Check if user created a new person by monitoring the DB for new persons beyond what we had
            break
        case .assignToPond:
            break
        case .autoCreateSecond:
            break
        case .connectContacts:
            break
        case .reviewPonds:
            break
        case .finished:
            break
        }
    }
    
    // Called by UI when a contact is created during demo mode
    func registerDemoContact(_ id: UUID) {
        demoContactIDs.insert(id)
    }
    
    func createSimulatedContact(name: String, pond: String?) async {
        guard let manager = dataManager else { return }
        do {
            try manager.createPerson(name: name, phone: nil, email: nil, birthday: nil, photoData: nil)
            guard let newlyCreated = try? manager.fetchAllPersons().first(where: { $0.name == name }) else { return }
            
            registerDemoContact(newlyCreated.id)
            
            if let targetPond = pond {
                // Ensure pond exists
                let circles = try manager.fetchAllCircles()
                var circle = circles.first(where: { $0.name == targetPond })
                if circle == nil {
                    try manager.createCircle(name: targetPond, color: "#1D9BF0", capacity: 15) // Use a default color
                    circle = try manager.fetchAllCircles().first(where: { $0.name == targetPond })
                }
                
                if let validCircle = circle {
                    try manager.addPersonToCircle(personID: newlyCreated.id, circleID: validCircle.id)
                }
            }
            
        } catch {
            print("Failed generating demo contact: \(error)")
        }
    }
}
