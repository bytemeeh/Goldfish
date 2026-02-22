import SwiftUI
import Contacts
import ContactsUI
import SpriteKit

// MARK: - Onboarding Flow
/// A simple step-based onboarding that creates the "isMe" contact
/// and optionally imports contacts from the address book.
struct OnboardingFlow: View {
    @EnvironmentObject var dataManager: GoldfishDataManager

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    @State private var name = "Me"
    @State private var isImporting = false
    @State private var showContactPicker = false
    
    var body: some View {
        ZStack {
            Color(red: 0x1E/255, green: 0x18/255, blue: 0x15/255)
                .ignoresSafeArea()
            
            welcomeScreen
                .transition(.opacity)
        }
    }
    
    // MARK: - Screen 1: Welcome (Full-Bleed Hero)
    private var welcomeScreen: some View {
        ZStack {
            // Full-bleed hero goldfish image
            Image("HeroGoldfish")
                .resizable()
                .scaledToFill()
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()
            
            // Watercolor disperse particle effect
            SpriteView(scene: {
                let scene = WatercolorDisperseScene(size: UIScreen.main.bounds.size)
                scene.scaleMode = .aspectFill
                return scene
            }(), options: [.allowsTransparency])
            .ignoresSafeArea()
            
            // Gradient overlay — transparent at top to show fish, dark at bottom for text
            LinearGradient(
                stops: [
                    .init(color: Color.clear, location: 0.0),
                    .init(color: Color(red: 0x1E/255, green: 0x18/255, blue: 0x15/255).opacity(0.3), location: 0.4),
                    .init(color: Color(red: 0x1E/255, green: 0x18/255, blue: 0x15/255).opacity(0.85), location: 0.65),
                    .init(color: Color(red: 0x1E/255, green: 0x18/255, blue: 0x15/255).opacity(0.97), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // Content pinned to bottom
            VStack(spacing: 8) {
                Spacer()
                
                Text("Goldfish")
                    .font(.system(size: 48, weight: .light))
                    .italic()
                    .foregroundColor(Color(red: 0xF5/255, green: 0xF0/255, blue: 0xEB/255))
                
                Text("Remember everyone")
                    .font(.system(size: 15, weight: .light))
                    .foregroundColor(Color(red: 0xF5/255, green: 0xF0/255, blue: 0xEB/255).opacity(0.5))
                    .padding(.bottom, 32)
                
                VStack(spacing: 12) {
                    Button(action: { createMeAndContinue() }) {
                        HStack {
                            Image(systemName: "applelogo")
                            Text("Sign in with Apple")
                        }
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(.white)
                        .foregroundColor(.black)
                        .cornerRadius(12)
                    }
                    
                    Button(action: { createMeAndContinue() }) {
                        HStack {
                            Image(systemName: "envelope.fill")
                            Text("Sign in with Email")
                        }
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(red: 0x1A/255, green: 0x16/255, blue: 0x14/255))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
    }
    
    

    
    // MARK: - Helpers
    
    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color.opacity(0.3))
                .stroke(color, lineWidth: 1.5)
                .frame(width: 10, height: 10)
            Text(label)
                .font(.system(size: 11, weight: .regular))
                .foregroundColor(Color(red: 0xF5/255, green: 0xF0/255, blue: 0xEB/255).opacity(0.6))
        }
    }
    
    private func pondBubble(emoji: String, label: String, color: Color) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 72, height: 72)
                Circle()
                    .stroke(color.opacity(0.5), lineWidth: 2)
                    .frame(width: 72, height: 72)
                Text(emoji)
                    .font(.system(size: 32))
            }
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(red: 0xF5/255, green: 0xF0/255, blue: 0xEB/255).opacity(0.45))
        }
    }
    
    private func createMeAndContinue() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        
        do {
            if try dataManager.fetchMePerson() == nil {
                try dataManager.performOnboarding(name: trimmed)
            }
            hasCompletedOnboarding = true
        } catch {
            print("Onboarding error: \(error)")
        }
    }
    
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
        }
    }
}

// MARK: - Constellation Demo Scene
class ConstellationDemoScene: SKScene {
    override func didMove(to view: SKView) {
        backgroundColor = .clear
        
        let centerNode = createDot(at: CGPoint(x: 150, y: 150), color: .systemBlue)
        let leftNode = createDot(at: CGPoint(x: 80, y: 100), color: .systemPurple)
        let rightNode = createDot(at: CGPoint(x: 220, y: 120), color: .systemOrange)
        
        // Draw static connections
        drawConnection(from: centerNode.position, to: leftNode.position)
        drawConnection(from: centerNode.position, to: rightNode.position)
        
        // Node to be dragged
        let dragNode = createDot(at: CGPoint(x: 150, y: 30), color: .systemTeal)
        
        // Ghost hand cursor
        let hand = SKLabelNode(text: "👆")
        hand.fontSize = 24
        hand.position = CGPoint(x: 150, y: 10)
        hand.zPosition = 10
        addChild(hand)
        
        // Snap line preview
        let dashLine = SKShapeNode()
        dashLine.strokeColor = UIColor.white.withAlphaComponent(0.4)
        dashLine.lineWidth = 2
        let pattern: [CGFloat] = [4, 4]
        dashLine.zPosition = -1
        addChild(dashLine)
        
        // Animation sequence
        let grabDuration = 0.5
        let moveDuration = 1.2
        let resetWait = 1.0
        
        let startPos = dragNode.position
        let targetPos = leftNode.position
        
        let dragAndSnap = SKAction.sequence([
            // Move hand to node
            SKAction.run { hand.run(SKAction.move(to: CGPoint(x: startPos.x, y: startPos.y - 15), duration: grabDuration)) },
            SKAction.wait(forDuration: grabDuration),
            
            // Hand "grabs" and moves node
            SKAction.run {
                let handMove = SKAction.move(to: CGPoint(x: targetPos.x + 30, y: targetPos.y - 15), duration: moveDuration)
                let nodeMove = SKAction.move(to: CGPoint(x: targetPos.x + 30, y: targetPos.y), duration: moveDuration)
                
                handMove.timingMode = .easeInEaseOut
                nodeMove.timingMode = .easeInEaseOut
                
                hand.run(handMove)
                dragNode.run(nodeMove)
                
                // Animate dashed line while moving
                dashLine.run(SKAction.customAction(withDuration: moveDuration) { node, time in
                    let progress = time / CGFloat(moveDuration)
                    let currentPos = CGPoint(
                        x: startPos.x + (targetPos.x + 30 - startPos.x) * progress,
                        y: startPos.y + (targetPos.y - startPos.y) * progress
                    )
                    
                    if hypot(targetPos.x - currentPos.x, targetPos.y - currentPos.y) < 60 {
                        let path = CGMutablePath()
                        path.move(to: currentPos)
                        path.addLine(to: targetPos)
                        let dashed = path.copy(dashingWithPhase: 0, lengths: pattern)
                        (node as? SKShapeNode)?.path = dashed
                    }
                })
            },
            SKAction.wait(forDuration: moveDuration),
            
            // Snap together
            SKAction.run {
                dashLine.path = nil
                dragNode.run(SKAction.move(to: CGPoint(x: targetPos.x + 10, y: targetPos.y - 10), duration: 0.2))
            },
            SKAction.wait(forDuration: resetWait),
            
            // Reset
            SKAction.run {
                dragNode.position = startPos
                hand.position = CGPoint(x: 150, y: 10)
            },
            SKAction.wait(forDuration: 0.5)
        ])
        
        run(SKAction.repeatForever(dragAndSnap))
    }
    
    private func createDot(at position: CGPoint, color: UIColor) -> SKShapeNode {
        let node = SKShapeNode(circleOfRadius: 12)
        node.fillColor = color.withAlphaComponent(0.3)
        node.strokeColor = color
        node.lineWidth = 1.5
        node.position = position
        node.zPosition = 2
        addChild(node)
        return node
    }
    
    private func drawConnection(from: CGPoint, to: CGPoint) {
        let line = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: from)
        path.addLine(to: to)
        line.path = path
        line.strokeColor = UIColor.white.withAlphaComponent(0.2)
        line.lineWidth = 1.0
        line.zPosition = 1
        addChild(line)
    }
}

// MARK: - Watercolor Disperse Scene
class WatercolorDisperseScene: SKScene {
    override func didMove(to view: SKView) {
        backgroundColor = .clear
        
        // Spawn gentle watercolor blooms
        let spawnAction = SKAction.repeatForever(SKAction.sequence([
            SKAction.run { [weak self] in self?.spawnBlob() },
            SKAction.wait(forDuration: 1.5, withRange: 1.0)
        ]))
        run(spawnAction)
    }
    
    private func spawnBlob() {
        let colors: [UIColor] = [
            UIColor(red: 0.6, green: 0.2, blue: 0.8, alpha: 0.4), // Purple
            UIColor(red: 0.9, green: 0.4, blue: 0.2, alpha: 0.4), // Orange
            UIColor(red: 0.2, green: 0.6, blue: 0.8, alpha: 0.4)  // Blue
        ]
        
        let radius = CGFloat.random(in: 40...100)
        let blob = SKShapeNode(circleOfRadius: radius)
        blob.fillColor = colors.randomElement()!
        blob.strokeColor = .clear
        blob.position = CGPoint(
            x: CGFloat.random(in: 0...size.width),
            y: CGFloat.random(in: 0...size.height)
        )
        blob.alpha = 0
        blob.blendMode = .add
        
        addChild(blob)
        
        let duration = TimeInterval.random(in: 4...8)
        let group = SKAction.group([
            SKAction.scale(to: CGFloat.random(in: 1.5...3.0), duration: duration),
            SKAction.sequence([
                SKAction.fadeIn(withDuration: duration * 0.3),
                SKAction.wait(forDuration: duration * 0.4),
                SKAction.fadeOut(withDuration: duration * 0.3)
            ])
        ])
        
        blob.run(SKAction.sequence([group, SKAction.removeFromParent()]))
    }
}


// MARK: - Contact Picker Wrapper
struct ContactPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onContactsSelected: ([CNContact]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    class Coordinator: NSObject, CNContactPickerDelegate {
        var parent: ContactPicker

        init(_ parent: ContactPicker) {
            self.parent = parent
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            parent.onContactsSelected(contacts)
            parent.isPresented = false
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            parent.isPresented = false
        }
    }
}
