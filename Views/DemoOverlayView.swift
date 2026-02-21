import SwiftUI

struct DemoOverlayView: View {
    @EnvironmentObject var demoManager: DemoManager
    
    var body: some View {
        VStack {
            Spacer()
            
            // Instruction Card
            VStack(spacing: 12) {
                Text(demoTitle)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(demoInstruction)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                
                if demoManager.currentStep == .welcome {
                    Button(action: {
                        demoManager.nextStep()
                    }) {
                        Text("Start Demo")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.goldfishAccent)
                            .foregroundColor(.black)
                            .cornerRadius(12)
                    }
                    .padding(.top, 8)
                    
                    Button("Skip Demo") {
                        demoManager.finishDemo() // Directly finish
                    }
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.top, 4)
                } else if demoManager.currentStep != .finished {
                    Button("Next (Dev)") {
                        demoManager.nextStep()
                    }
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.3))
                }
            }
            .padding(24)
            .background(Color(red: 0x1E/255, green: 0x18/255, blue: 0x15/255).opacity(0.95))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 120) // Keep above the tab bar and FAB
        }
    }
    
    private var demoTitle: String {
        switch demoManager.currentStep {
        case .welcome: return "Interactive Demo"
        case .createContact: return "Create a Contact"
        case .assignToPond: return "Assign to a Pond"
        case .autoCreateSecond: return "Meet Alex"
        case .connectContacts: return "Connect People"
        case .reviewPonds: return "Organizing Ponds"
        case .finished: return ""
        }
    }
    
    private var demoInstruction: String {
        switch demoManager.currentStep {
        case .welcome: return "Let's explore how Goldfish works with a quick hands-on tour."
        case .createContact: return "Tap the + button to add your first contact to the graph."
        case .assignToPond: return "Open the contact and assign them to a pond (like 'Friends')."
        case .autoCreateSecond: return "We've added 'Alex' to your graph for this demo."
        case .connectContacts: return "Drag Alex onto your new contact to connect them."
        case .reviewPonds: return "Unassigned contacts float freely. Assigning them pulls them into ponds."
        case .finished: return ""
        }
    }
}
