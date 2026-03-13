import SwiftUI
import SpriteKit
import Contacts
import ContactsUI

// MARK: - Onboarding Sign-In Overlay
/// Full-screen cover displayed over the live ponds graph during onboarding.
/// The top portion is transparent (graph shows through); the bottom portion
/// is a dark card with Goldfish branding and sign-in buttons.
struct OnboardingSignInOverlay: View {
    @EnvironmentObject var dataManager: GoldfishDataManager

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private let bgColor   = Color(red: 0x1E/255, green: 0x18/255, blue: 0x15/255)
    private let cardColor = Color(red: 0x28/255, green: 0x20/255, blue: 0x1C/255)
    private let cream     = Color(red: 0xF5/255, green: 0xF0/255, blue: 0xEB/255)

    var body: some View {
        ZStack(alignment: .bottom) {
            // Top: transparent gradient so graph shows through behind the overlay
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: bgColor.opacity(0.55), location: 0.55),
                    .init(color: bgColor.opacity(0.97), location: 0.78),
                    .init(color: bgColor, location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // Bottom: branding + sign-in card
            VStack(spacing: 0) {
                VStack(spacing: 6) {
                    Text("Goldfish")
                        .font(.system(size: 44, weight: .light))
                        .italic()
                        .foregroundColor(cream)

                    Text("Remember everyone")
                        .font(.system(size: 15, weight: .light))
                        .foregroundColor(cream.opacity(0.5))
                }
                .padding(.bottom, 32)

                VStack(spacing: 12) {
                    Button(action: createMeAndContinue) {
                        HStack(spacing: 8) {
                            Image(systemName: "applelogo")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Continue with Apple")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(.white)
                        .foregroundColor(.black)
                        .cornerRadius(14)
                    }

                    Button(action: createMeAndContinue) {
                        HStack(spacing: 8) {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 14, weight: .medium))
                            Text("Continue with Email")
                                .font(.system(size: 15, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(cardColor)
                        .foregroundColor(cream.opacity(0.9))
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(cream.opacity(0.1), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 16)

                Text("By continuing you agree to our Terms & Privacy Policy.")
                    .font(.system(size: 11))
                    .foregroundColor(cream.opacity(0.25))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 48)
            }
        }
        .background(.clear)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
    }

    private func createMeAndContinue() {
        do {
            if try dataManager.fetchMePerson() == nil {
                try dataManager.performOnboarding(name: "Me")
            }
            hasCompletedOnboarding = true
        } catch {
            print("Onboarding sign-in error: \(error)")
            ToastManager.shared.showToast(message: "Failed: \(error.localizedDescription)")
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
