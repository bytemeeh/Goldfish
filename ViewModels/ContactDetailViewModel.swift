import SwiftUI
import MessageUI

// MARK: - ContactDetailViewModel
@MainActor
final class ContactDetailViewModel: ObservableObject {
    
    // MARK: - Dependencies
    private let dataManager: GoldfishDataManager
    
    // MARK: - State
    @Published var person: Person
    @Published var isEditing: Bool = false
    @Published var showDeleteConfirmation: Bool = false
    
    // MARK: - Computed Data
    @Published var groupedRelationships: [String: [Relationship]] = [:]
    
    // MARK: - Init
    init(person: Person, dataManager: GoldfishDataManager) {
        self.person = person
        self.dataManager = dataManager
        refreshData()
    }
    
    // MARK: - Methods
    func refreshData() {
        // Person is a reference type (SwiftData class), so properties update automatically if managed.
        // However, we might need to re-fetch relationships or group them.
        groupRelationships()
    }
    
    func groupRelationships() {
        let relations = dataManager.fetchRelationships(for: person)
        
        // Group by type (effective type from this person's perspective)
        var grouped: [String: [Relationship]] = [:]
        
        for rel in relations {
            let type = rel.effectiveType(for: person)
            let key = type.displayName
            var list = grouped[key] ?? []
            list.append(rel)
            grouped[key] = list
        }
        
        self.groupedRelationships = grouped
    }
    
    func toggleFavorite() {
        do {
            try dataManager.updatePerson(person, isFavorite: !person.isFavorite)
            objectWillChange.send() // Trigger UI refresh
        } catch {
            print("Failed to toggle favorite: \(error)")
        }
    }
    
    func deleteContact(completion: @escaping () -> Void) {
        do {
            try dataManager.deletePerson(person)
            completion()
        } catch {
            print("Failed to delete contact: \(error)")
        }
    }
    
    // MARK: - Actions
    func callContact() {
        guard let phone = person.phone else { return }
        let clean = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        if let url = URL(string: "tel://\(clean)"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
    
    func messageContact() {
        guard let phone = person.phone else { return }
        let clean = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        if let url = URL(string: "sms://\(clean)"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
    
    func emailContact() {
        guard let email = person.email else { return }
        if let url = URL(string: "mailto:\(email)"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}
