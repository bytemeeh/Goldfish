import SwiftUI
import PhotosUI
import SwiftData

// MARK: - ContactFormViewModel
@MainActor
final class ContactFormViewModel: ObservableObject {
    
    // MARK: - Dependencies
    private let dataManager: GoldfishDataManager
    
    // MARK: - Target
    let existingPerson: Person?
    let isDemoMode: Bool
    @Published var errorMessage: String?
    private var initialFormState: [String] = []
    private var initialPhotoData: Data?
    
    // MARK: - Form State
    @Published var firstName: String = ""
    @Published var lastName: String = ""
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
    @Published var contactKind: ContactKind = .human
    
    // Photo / Emoji
    @Published var emojiAvatar: String = ""
    @Published var photoData: Data?
    
    // Connections
    @Published var selectedConnectionID: UUID?
    @Published var selectedRelationshipType: RelationshipType = .friend
    @Published var allPersons: [Person] = []
    
    // Circles
    @Published var allCircles: [GoldfishCircle] = []
    @Published var selectedCircleIDs: Set<UUID> = []
    
    // MARK: - Validation
    var isValid: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var formState: [String] {
        [firstName, lastName, phone, email, notes, String(includeBirthday),
         String(birthday.timeIntervalSince1970), street, city, state, country, postalCode,
         String(isFavorite), tagsString, colorHex, emojiAvatar,
         contactKind.rawValue,
         selectedConnectionID?.uuidString ?? "", selectedRelationshipType.rawValue,
         selectedCircleIDs.map(\.uuidString).sorted().joined(separator: ",")]
    }

    var hasUnsavedChanges: Bool {
        formState != initialFormState || photoData != initialPhotoData
    }

    var pageTitle: String {
        existingPerson == nil ? (isDemoMode ? "New Demo Contact" : "New Contact") : "Edit Contact"
    }

    var relationshipPreview: String? {
        guard let selectedConnectionID,
              let target = allPersons.first(where: { $0.id == selectedConnectionID }) else { return nil }
        let enteredName = [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let subject = enteredName.isEmpty ? "This contact" : enteredName
        if selectedRelationshipType == .other {
            return "This saves: \(subject) has another connection to \(target.name)."
        }
        return "This saves: \(subject) is \(target.name)’s \(selectedRelationshipType.displayName.lowercased())."
    }
    
    // MARK: - Init
    init(dataManager: GoldfishDataManager, person: Person? = nil, isDemoMode: Bool? = nil, initialCircleID: UUID? = nil) {
        self.dataManager = dataManager
        self.existingPerson = person
        self.isDemoMode = person?.isDemo ?? isDemoMode ?? UserDefaults.standard.bool(forKey: "isDemoModeActive")
        
        if let person = person {
            // Edit Mode: Populate fields
            let parts = person.name.split(separator: " ", maxSplits: 1)
            self.firstName = String(parts.first ?? "")
            self.lastName = parts.count > 1 ? String(parts.last ?? "") : ""
            
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
            self.contactKind = person.contactKind
            
            // Populate selected circles
            // This requires fetching logic, or we assume circleContacts are loaded
            let memberIDs = person.circleContacts.filter { !$0.manuallyExcluded }.map(\.circle.id)
            self.selectedCircleIDs = Set(memberIDs)
        } else {
            // Create Mode: defaults
        }
        
        loadCircles()
        loadPersons()
        if person == nil, let initialCircleID, allCircles.contains(where: { $0.id == initialCircleID }) {
            selectedCircleIDs = [initialCircleID]
        }
        initialFormState = formState
        initialPhotoData = photoData
    }
    
    private func loadPersons() {
        if let persons = try? dataManager.fetchAllPersons() {
            // Exclude current person to prevent self-connection
            self.allPersons = persons.filter { $0.id != self.existingPerson?.id && ($0.isMe || $0.isDemo == self.isDemoMode) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
    
    func loadCircles() {
        do {
            var circles = try dataManager.fetchAllCircles()
            // Safety net: create system circles if they don't exist
            if circles.isEmpty {
                try dataManager.createSystemCircles()
                circles = try dataManager.fetchAllCircles()
            }
            self.allCircles = circles
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
        
        let fullName = [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            
        // Generate Emoji Image if provided
        var finalPhotoData = photoData
        if !emojiAvatar.isEmpty {
            finalPhotoData = createEmojiImage(emoji: emojiAvatar)
        }
        
        do {
            try dataManager.performAtomicEdit {
                let savedPerson: Person
                if let person = existingPerson {
                    // Update
                    try dataManager.updatePerson(
                        person,
                        name: fullName,
                        phone: .set(phone.isEmpty ? nil : phone),
                        email: .set(email.isEmpty ? nil : email),
                        birthday: .set(dob),
                        notes: .set(notes.isEmpty ? nil : notes),
                        petKindRaw: .set(person.isMe ? nil : (contactKind == .human ? nil : contactKind.rawValue)),
                        isFavorite: isFavorite,
                        tags: tags,
                        color: colorHex,
                        photoData: .set(finalPhotoData),
                        street: .set(street.isEmpty ? nil : street),
                        city: .set(city.isEmpty ? nil : city),
                        state: .set(state.isEmpty ? nil : state),
                        country: .set(country.isEmpty ? nil : country),
                        postalCode: .set(postalCode.isEmpty ? nil : postalCode)
                    )
                
                    // Update circles
                    try updateCircleMemberships(for: person)
                    savedPerson = person
                } else {
                    // Create
                    let person = try dataManager.createPerson(
                        name: fullName,
                        phone: phone.isEmpty ? nil : phone,
                        email: email.isEmpty ? nil : email,
                        birthday: dob,
                        notes: notes.isEmpty ? nil : notes,
                        petKindRaw: contactKind == .human ? nil : contactKind.rawValue,
                        isDemo: isDemoMode,
                        isFavorite: isFavorite,
                        tags: tags,
                        color: colorHex,
                        photoData: finalPhotoData,
                        street: street.isEmpty ? nil : street,
                        city: city.isEmpty ? nil : city,
                        state: state.isEmpty ? nil : state,
                        country: country.isEmpty ? nil : country,
                        postalCode: postalCode.isEmpty ? nil : postalCode
                    )
                
                    try updateCircleMemberships(for: person)
                    savedPerson = person
                }
            
                // Create Connection if selected
                if let connID = selectedConnectionID {
                    guard let target = try dataManager.fetchAllPersons().first(where: { $0.id == connID }) else {
                        throw GoldfishError.contactNotFound
                    }
                    _ = try dataManager.createRelationship(from: savedPerson, to: target, type: selectedRelationshipType, skipAutoAssign: true)
                }
            
            }
            ToastManager.shared.showToast(message: "Contact saved ✓")
            return true
        } catch {
            errorMessage = "Could not save: \(error.localizedDescription)"
            return false
        }
    }
    
    private func updateCircleMemberships(for person: Person) throws {
        // Simple approach: Add to selected, remove from unselected
        guard !person.isMe else { return }
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
            selectedCircleIDs.removeAll() // Enforce single selection
            selectedCircleIDs.insert(circle.id)
        }
    }
    
    private func createEmojiImage(emoji: String) -> Data? {
        let size = CGSize(width: 200, height: 200)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { _ in
            let string = emoji as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 160)
            ]
            let stringSize = string.size(withAttributes: attributes)
            string.draw(
                in: CGRect(
                    x: (size.width - stringSize.width) / 2,
                    y: (size.height - stringSize.height) / 2,
                    width: stringSize.width,
                    height: stringSize.height
                ),
                withAttributes: attributes
            )
        }
        return image.jpegData(compressionQuality: 0.8)
    }
}
