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
    @Published var errorMessage: String?
    
    // MARK: - Computed Data
    @Published var groupedRelationships: [String: [Relationship]] = [:]
    /// Me is shared by both modes; its visible connections follow the current scope.
    var isDemoMode = false {
        didSet { if oldValue != isDemoMode { groupRelationships() } }
    }

    var relationshipContext: ContactRelationshipContext? {
        RelationshipContextService(people: scopedPeople).context(for: person)
    }

    var relationshipSummary: String? {
        relationshipContext?.summary
    }

    var pondSummary: String? {
        RelationshipContextService(people: scopedPeople).pondSummary(for: person)
    }

    /// Kept as the direct role label used by existing callers. Indirect paths
    /// intentionally return nil here and are exposed through relationshipSummary.
    var relationshipToMe: String? {
        guard let relationshipContext,
              case .direct(let primary, _) = relationshipContext.connection else { return nil }
        return primary.displayName
    }

    var connectedPeopleCount: Int {
        Set(visibleRelationships.map { $0.otherContact(from: person).id }).count
    }

    private var visibleRelationships: [Relationship] {
        let scopeIsDemo = person.isMe ? isDemoMode : person.isDemo
        return dataManager.fetchRelationships(for: person).filter {
            let other = $0.otherContact(from: person)
            return other.isMe || other.isDemo == scopeIsDemo
        }
    }

    private var scopedPeople: [Person] {
        let scopeIsDemo = person.isMe ? isDemoMode : person.isDemo
        return (try? dataManager.fetchAllPersons())?.filter {
            $0.isMe || $0.isDemo == scopeIsDemo
        } ?? []
    }
    
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
        let relations = visibleRelationships
        
        // Group by type (effective type from this person's perspective)
        var grouped: [String: [Relationship]] = [:]
        
        for rel in relations {
            let type = rel.effectiveType(for: rel.otherContact(from: person))
            let key = type.displayName
            var list = grouped[key] ?? []
            list.append(rel)
            grouped[key] = list
        }
        
        self.groupedRelationships = grouped
    }
    
    func removeRelationship(_ relationship: Relationship) {
        do {
            let token = try dataManager.removeRelationshipWithUndo(relationship)
            refreshData()
            NotificationCenter.default.post(name: .goldfishDataDidChange, object: nil)
            let manager = dataManager
            ToastManager.shared.showToast(message: "Connection removed", actionTitle: "Undo") { [weak self, manager] in
                do {
                    _ = try manager.restoreRemovedRelationship(using: token)
                    self?.refreshData()
                    NotificationCenter.default.post(name: .goldfishDataDidChange, object: nil)
                    ToastManager.shared.showToast(message: "Connection restored")
                } catch {
                    self?.errorMessage = "Could not restore connection: \(error.localizedDescription)"
                    ToastManager.shared.showToast(message: "Could not restore connection")
                }
            }
        } catch {
            errorMessage = "Could not remove connection: \(error.localizedDescription)"
            ToastManager.shared.showToast(message: "Could not remove connection")
        }
    }

    func addMemory(_ memory: String, date: Date = Date()) -> Bool {
        errorMessage = nil
        guard let updatedNotes = Self.notesByAppendingMemory(memory, to: person.notes, date: date) else {
            errorMessage = "Write a memory before saving."
            return false
        }
        do {
            try dataManager.updatePerson(person, notes: .set(updatedNotes))
            refreshData()
            NotificationCenter.default.post(name: .goldfishDataDidChange, object: nil)
            ToastManager.shared.showToast(message: "Memory added")
            return true
        } catch {
            errorMessage = "Could not save memory: \(error.localizedDescription)"
            return false
        }
    }

    static func notesByAppendingMemory(_ memory: String, to existingNotes: String?, date: Date) -> String? {
        let trimmedMemory = memory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMemory.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        let entry = "\(formatter.string(from: date)) — \(trimmedMemory)"

        guard let existingNotes, !existingNotes.isEmpty else { return entry }
        let separator: String
        if existingNotes.hasSuffix("\n\n") {
            separator = ""
        } else if existingNotes.hasSuffix("\n") {
            separator = "\n"
        } else {
            separator = "\n\n"
        }
        return existingNotes + separator + entry
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
        guard let url = phoneURL(scheme: "tel") else {
            errorMessage = "This contact does not have a callable phone number."
            return
        }
        guard UIApplication.shared.canOpenURL(url) else {
            errorMessage = "Calling is unavailable on this device."
            return
        }
        UIApplication.shared.open(url)
    }
    
    func messageContact() {
        guard let url = phoneURL(scheme: "sms") else {
            errorMessage = "This contact does not have a textable phone number."
            return
        }
        guard UIApplication.shared.canOpenURL(url) else {
            errorMessage = "Texting is unavailable on this device."
            return
        }
        UIApplication.shared.open(url)
    }
    
    func emailContact() {
        guard let email = person.email, !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "This contact does not have an email address."
            return
        }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = components.url else {
            errorMessage = "This email address cannot be opened."
            return
        }
        guard UIApplication.shared.canOpenURL(url) else {
            errorMessage = "Email is unavailable on this device."
            return
        }
        UIApplication.shared.open(url)
    }

    private func phoneURL(scheme: String) -> URL? {
        guard let phone = person.phone else { return nil }
        let value = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let hasInternationalPrefix = value.first == "+"
        let digits = value.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return URL(string: "\(scheme):\(hasInternationalPrefix ? "+" : "")\(digits)")
    }
}
