import SwiftUI
import Contacts

struct DemoCompletionView: View {
    @EnvironmentObject var demoManager: DemoManager
    @EnvironmentObject var dataManager: GoldfishDataManager
    
    @State private var isImporting = false
    @State private var showContactPicker = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    var body: some View {
        ZStack {
            Color(red: 0x1E/255, green: 0x18/255, blue: 0x15/255)
                .ignoresSafeArea()
            
            VStack(spacing: 32) {
                Spacer()
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(Color.goldfishAccent)
                
                VStack(spacing: 8) {
                    Text("Demo Complete")
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(.white)
                    
                    Text("You're ready to start building your network. What would you like to do next?")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                VStack(spacing: 16) {
                    Button(action: {
                        demoManager.endAndKeepContacts()
                        hasCompletedOnboarding = true
                    }) {
                        Text("Keep Demo Contacts")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.white.opacity(0.1))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    
                    Button(action: {
                        showContactPicker = true
                    }) {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.plus")
                            Text("Import from Phonebook")
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.goldfishAccent)
                        .foregroundColor(.black)
                        .cornerRadius(12)
                    }
                    
                    Button(action: {
                        Task {
                            await demoManager.endAndCleanSlate()
                            hasCompletedOnboarding = true
                        }
                    }) {
                        Text("Start with a Clean Slate")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.red.opacity(0.8))
                            .padding(.vertical, 8)
                    }
                }
                .padding(.horizontal, 32)
                
                if isImporting {
                    ProgressView("Importing Contacts...")
                        .tint(.white)
                        .foregroundColor(.white)
                }
                
                Spacer()
            }
        }
        .sheet(isPresented: $showContactPicker) {
            ContactPicker(isPresented: $showContactPicker) { selectedContacts in
                Task {
                    await doImport(contacts: selectedContacts)
                }
            }
        }
    }
    
    // Exact same import logic from OnboardingFlow
    private func doImport(contacts: [CNContact]) async {
        isImporting = true
        do {
            for cn in contacts {
                let fullName = [cn.givenName, cn.familyName]
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                guard !fullName.isEmpty else { continue }
                
                try dataManager.createPerson(
                    name: fullName,
                    phone: cn.phoneNumbers.first?.value.stringValue,
                    email: cn.emailAddresses.first?.value as String?,
                    birthday: cn.birthday.flatMap { Calendar.current.date(from: $0) },
                    photoData: cn.imageData
                )
            }
        } catch {
            print("Import error: \(error)")
        }
        await MainActor.run {
            isImporting = false
            hasCompletedOnboarding = true
            demoManager.endAndKeepContacts() // Finish demo sequence
        }
    }
}
