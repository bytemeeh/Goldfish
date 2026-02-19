import SwiftUI
import PhotosUI
import SwiftData

// MARK: - ContactFormViewModel
@MainActor
final class ContactFormViewModel: ObservableObject {
    
    // MARK: - Dependencies
    private let dataManager: GoldfishDataManager
    
    // MARK: - Target
    private let existingPerson: Person?
    
    // MARK: - Form State
    @Published var name: String = ""
    @Published var phone: String = ""
    @Published var email: String = ""
    @Published var notes: String = ""
    @Published var birthday: Date = Date()
    @Published var includeBirthday: Bool = false
    
    // Address (simplified for now, ideally separate Location objects)
    @Published var street: String = ""
    @Published var city: String = ""
    @Published var state: String = ""
    @Published var country: String = ""
    @Published var postalCode: String = ""
    
    // Metadata
    @Published var isFavorite: Bool = false
    @Published var tagsString: String = "" // Comma separated for editing
    @Published var colorHex: String = "#808080"
    
    // Photo
    @Published var selectedPhotoItem: PhotosPickerItem? {
        didSet {
            Task {
                if let data = try? await selectedPhotoItem?.loadTransferable(type: Data.self) {
                    self.photoData = data
                }
            }
        }
    }
    @Published var photoData: Data?
    
    // Circles
    @Published var allCircles: [GoldfishCircle] = []
    @Published var selectedCircleIDs: Set<UUID> = []
    
    // MARK: - Validation
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var pageTitle: String {
        existingPerson == nil ? "New Contact" : "Edit Contact"
    }
    
    // MARK: - Init
    init(dataManager: GoldfishDataManager, person: Person? = nil) {
        self.dataManager = dataManager
        self.existingPerson = person
        
        if let person = person {
            // Edit Mode: Populate fields
            self.name = person.name
            self.phone = person.phone ?? ""
            self.email = person.email ?? ""
            self.notes = person.notes ?? ""
            if let dob = person.birthday {
                self.birthday = dob
                self.includeBirthday = true
            }
            self.street = person.street ?? ""
            self.city = person.city ?? ""
            self.state = person.state ?? ""
            self.country = person.country ?? ""
            self.postalCode = person.postalCode ?? ""
            self.isFavorite = person.isFavorite
            self.tagsString = person.tags.joined(separator: ", ")
            self.colorHex = person.color ?? "#808080"
            self.photoData = person.photoData
            
            // Populate selected circles
            // This requires fetching logic, or we assume circleContacts are loaded
            let memberIDs = person.circleContacts.map(\.circle.id)
            self.selectedCircleIDs = Set(memberIDs)
        } else {
            // Create Mode: defaults
        }
        
        loadCircles()
    }
    
    func loadCircles() {
        do {
            self.allCircles = try dataManager.fetchAllCircles()
        } catch {
            print("Error loading circles: \(error)")
        }
    }
    
    // MARK: - Actions
    func save() -> Bool {
        guard isValid else { return false }
        
        let tags = tagsString
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        let dob: Date? = includeBirthday ? birthday : nil
        
        do {
            if let person = existingPerson {
                // Update
                try dataManager.updatePerson(
                    person,
                    name: name,
                    phone: phone.isEmpty ? nil : phone,
                    email: email.isEmpty ? nil : email,
                    birthday: dob,
                    notes: notes.isEmpty ? nil : notes,
                    isFavorite: isFavorite,
                    tags: tags,
                    color: colorHex,
                    photoData: photoData,
                    street: street.isEmpty ? nil : street,
                    city: city.isEmpty ? nil : city,
                    state: state.isEmpty ? nil : state,
                    country: country.isEmpty ? nil : country,
                    postalCode: postalCode.isEmpty ? nil : postalCode
                )
                
                // Update circles
                try updateCircleMemberships(for: person)
                
            } else {
                // Create
                let person = try dataManager.createPerson(
                    name: name,
                    phone: phone.isEmpty ? nil : phone,
                    email: email.isEmpty ? nil : email,
                    birthday: dob,
                    notes: notes.isEmpty ? nil : notes,
                    isFavorite: isFavorite,
                    tags: tags,
                    color: colorHex,
                    photoData: photoData,
                    street: street.isEmpty ? nil : street,
                    city: city.isEmpty ? nil : city,
                    state: state.isEmpty ? nil : state,
                    country: country.isEmpty ? nil : country,
                    postalCode: postalCode.isEmpty ? nil : postalCode
                )
                
                try updateCircleMemberships(for: person)
            }
            return true
        } catch {
            print("Error saving contact: \(error)")
            return false
        }
    }
    
    private func updateCircleMemberships(for person: Person) throws {
        // Simple approach: Add to selected, remove from unselected
        for circle in allCircles {
            if selectedCircleIDs.contains(circle.id) {
                try dataManager.addToCircle(person, circle: circle)
            } else {
                try dataManager.removeFromCircle(person, circle: circle)
            }
        }
    }
    
    func toggleCircle(_ circle: GoldfishCircle) {
        if selectedCircleIDs.contains(circle.id) {
            selectedCircleIDs.remove(circle.id)
        } else {
            selectedCircleIDs.insert(circle.id)
        }
    }
}
