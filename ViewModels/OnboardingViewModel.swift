import SwiftUI
@preconcurrency import Contacts

// MARK: - OnboardingViewModel
@MainActor
final class OnboardingViewModel: ObservableObject {
    
    // MARK: - Dependencies
    private let dataManager: GoldfishDataManager
    
    // MARK: - State
    @Published var currentTab = 0
    @Published var name: String = ""
    @Published var phone: String = ""
    @Published var email: String = ""
    
    @Published var isImporting: Bool = false
    @Published var importStatus: String = "Importing..."
    
    // MARK: - Init
    init(dataManager: GoldfishDataManager) {
        self.dataManager = dataManager
    }
    
    // MARK: - Actions
    func createMeCardAndContinue(completion: @escaping () -> Void) {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        do {
            if let _ = try dataManager.fetchMePerson() {
                print("ME contact already exists")
            } else {
                try dataManager.performOnboarding(name: name)
                
                if let me = try dataManager.fetchMePerson() {
                    try dataManager.updatePerson(
                        me,
                        phone: .set(phone.isEmpty ? nil : phone),
                        email: .set(email.isEmpty ? nil : email)
                    )
                }
            }
            completion()
        } catch {
            print("Error creating ME card: \(error)")
        }
    }
    
    func requestContactsAccess(completion: @escaping (Bool) -> Void) {
        nonisolated(unsafe) let store = CNContactStore()
        store.requestAccess(for: .contacts) { granted, _ in
            Task { @MainActor in
                if granted {
                    self.importContacts() {
                        completion(true)
                    }
                } else {
                    completion(false)
                }
            }
        }
    }
    
    private func importContacts(completion: @escaping () -> Void) {
        let store = CNContactStore()
        isImporting = true
        importStatus = "Preparing import..."
        
        Task {
            do {
                let keysToFetch: [CNKeyDescriptor] = [
                    CNContactGivenNameKey as CNKeyDescriptor,
                    CNContactFamilyNameKey as CNKeyDescriptor,
                    CNContactPhoneNumbersKey as CNKeyDescriptor,
                    CNContactEmailAddressesKey as CNKeyDescriptor,
                    CNContactPostalAddressesKey as CNKeyDescriptor,
                    CNContactBirthdayKey as CNKeyDescriptor,
                    CNContactImageDataKey as CNKeyDescriptor,
                    CNContactNoteKey as CNKeyDescriptor
                ]
                
                let request = CNContactFetchRequest(keysToFetch: keysToFetch)
                var contacts: [CNContact] = []
                try store.enumerateContacts(with: request) { contact, _ in
                    contacts.append(contact)
                }
                
                let total = contacts.count
                for (index, cn) in contacts.enumerated() {
                    let fullName = [cn.givenName, cn.familyName]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    guard !fullName.isEmpty else { continue }
                    
                    await MainActor.run {
                        importStatus = "Importing \(index + 1) of \(total)..."
                    }
                    
                    let phone = cn.phoneNumbers.first?.value.stringValue
                    let email = cn.emailAddresses.first?.value as String?
                    let birthday: Date? = cn.birthday.flatMap { Calendar.current.date(from: $0) }
                    let note = cn.note.isEmpty ? nil : cn.note
                    let photoData = cn.imageData
                    
                    let postal = cn.postalAddresses.first?.value
                    let street = postal?.street.isEmpty == true ? nil : postal?.street
                    let city = postal?.city.isEmpty == true ? nil : postal?.city
                    let state = postal?.state.isEmpty == true ? nil : postal?.state
                    let country = postal?.country.isEmpty == true ? nil : postal?.country
                    let postalCode = postal?.postalCode.isEmpty == true ? nil : postal?.postalCode
                    
                    try dataManager.createPerson(
                        name: fullName,
                        phone: phone,
                        email: email,
                        birthday: birthday,
                        notes: note,
                        photoData: photoData,
                        street: street,
                        city: city,
                        state: state,
                        country: country,
                        postalCode: postalCode
                    )
                }
                
                await MainActor.run {
                    isImporting = false
                    completion()
                }
            } catch {
                await MainActor.run {
                    importStatus = "Import failed: \(error.localizedDescription)"
                    isImporting = false
                }
            }
        }
    }
    
    func skipImport(completion: @escaping () -> Void) {
        completion()
    }
}
