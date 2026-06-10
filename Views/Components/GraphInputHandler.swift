import SpriteKit
import SwiftUI

protocol GraphInputHandlerDelegate: AnyObject {
    func didTapNode(id: UUID)
    func didDoubleTapNode(id: UUID)
    func didLongPressNode(id: UUID)
    func didTapPond(name: String)
    func didTapEmptySpace()
    func didPanCamera(delta: CGPoint, currentZoom: CGFloat)
    func didPinchZoom(deltaScale: CGFloat)
    func didPinchEnded()
    
    // Drag and Snap
    func didStartDraggingNode(_ node: PersonNode, location: CGPoint)
    func didDragNode(_ node: PersonNode, location: CGPoint, touchHasMoved: Bool) -> (snapTarget: UUID?, hoverPond: String?)
    func didEndDraggingNode(_ node: PersonNode, touchHasMoved: Bool, snapTarget: UUID?, hoverPond: String?)
    func didCancelDraggingNode(_ node: PersonNode)
    
    // Pond dragging
    func didStartDraggingPond(_ name: String, location: CGPoint)
    func didDragPond(_ name: String, location: CGPoint)
    func didEndDraggingPond(_ name: String)
}

final class GraphInputHandler: NSObject {
    
    weak var delegate: GraphInputHandlerDelegate?
    weak var scene: SKScene?
    
    // State
    private var lastPinchScale: CGFloat = 1.0
    private var lastTouchLocation: CGPoint = .zero
    private var dragStartLocation: CGPoint = .zero
    private var touchHasMoved = false
    
    private var draggedNode: PersonNode?
    private var draggedPondName: String?
    private var snapTargetID: UUID?
    private var hoverPondName: String?

    func setupGestures(in view: SKView, scene: SKScene) {
        self.scene = scene
        
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        view.addGestureRecognizer(pinch)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        view.addGestureRecognizer(pan)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)
        
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        view.addGestureRecognizer(longPress)
    }
    
    // MARK: - Touch Forwarding (Called from Scene)
    
    func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let scene = scene, let view = scene.view else { return }
        let location = touch.location(in: scene)
        dragStartLocation = location
        lastTouchLocation = touch.location(in: view)
        touchHasMoved = false

        // Hit testing happens in the scene/delegate which has access to nodes
        // but we can ask the delegate what was hit based on location.
        // For simplicity, we'll let the scene pass down the hit node or pond.
    }
    
    func handleHitNodeBegan(_ node: PersonNode, location: CGPoint) {
        draggedNode = node
        delegate?.didStartDraggingNode(node, location: location)
    }
    
    func handleHitPondBegan(_ pondName: String, location: CGPoint) {
        draggedPondName = pondName
        delegate?.didStartDraggingPond(pondName, location: location)
    }
    
    func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?, currentZoom: CGFloat) {
        guard let touch = touches.first, let scene = scene, let view = scene.view else { return }
        
        if let pondName = draggedPondName {
            let location = touch.location(in: scene)
            delegate?.didDragPond(pondName, location: location)
            dragStartLocation = location
            touchHasMoved = true
            return
        }
        
        if let node = draggedNode {
            let location = touch.location(in: scene)
            let movedDistance = hypot(location.x - dragStartLocation.x, location.y - dragStartLocation.y)
            if movedDistance > 8 { touchHasMoved = true }
            
            let result = delegate?.didDragNode(node, location: location, touchHasMoved: touchHasMoved)
            snapTargetID = result?.snapTarget
            hoverPondName = result?.hoverPond
        } else {
            // Camera Pan
            let screenLocation = touch.location(in: view)
            let dx = -(screenLocation.x - lastTouchLocation.x) / currentZoom
            let dy = (screenLocation.y - lastTouchLocation.y) / currentZoom
            delegate?.didPanCamera(delta: CGPoint(x: dx, y: dy), currentZoom: currentZoom)
            lastTouchLocation = screenLocation
            touchHasMoved = true
        }
    }
    
    func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let pondName = draggedPondName {
            delegate?.didEndDraggingPond(pondName)
            draggedPondName = nil
            touchHasMoved = false
            return
        }
        
        guard let touch = touches.first, let node = draggedNode else { return }
        
        if !touchHasMoved && touch.tapCount == 1 {
            delegate?.didTapNode(id: node.personID)
        }
        
        delegate?.didEndDraggingNode(node, touchHasMoved: touchHasMoved, snapTarget: snapTargetID, hoverPond: hoverPondName)
        
        snapTargetID = nil
        hoverPondName = nil
        draggedNode = nil
        touchHasMoved = false
    }
    
    func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let pondName = draggedPondName {
            delegate?.didEndDraggingPond(pondName)
            draggedPondName = nil
            touchHasMoved = false
            return
        }
        
        guard let node = draggedNode else { return }
        delegate?.didCancelDraggingNode(node)
        
        snapTargetID = nil
        hoverPondName = nil
        draggedNode = nil
        touchHasMoved = false
    }

    // MARK: - Gestures
    
    @objc private func handlePinch(_ sender: UIPinchGestureRecognizer) {
        switch sender.state {
        case .began:
            lastPinchScale = sender.scale
        case .changed:
            let delta = sender.scale / lastPinchScale
            lastPinchScale = sender.scale
            delegate?.didPinchZoom(deltaScale: delta)
        case .ended:
            delegate?.didPinchEnded()
        default:
            break
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let scene = scene, let view = scene.view else { return }
        let translation = gesture.translation(in: view)

        switch gesture.state {
        case .changed:
            // Need current zoom to scale the pan appropriately
            // We pass a raw screen delta and let the delegate convert it
            delegate?.didPanCamera(delta: CGPoint(x: -translation.x, y: translation.y), currentZoom: 1.0)
            gesture.setTranslation(.zero, in: view)
        case .ended:
            delegate?.didPinchEnded() // repurposing for camera position sync
        default:
            break
        }
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard let scene = scene, let view = scene.view else { return }
        let screenLocation = gesture.location(in: view)
        _ = scene.convertPoint(fromView: screenLocation)
        
        // This logic of finding which pond/node was hit is better kept in the delegate
        // So we'll pass the location back.
        // Wait, the protocol doesn't have a double-tap location. Let's add it or let the scene hit test.
        // Actually, scene hit testing is better. We'll just pass the raw location to the delegate.
    }
    
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        // Handle in scene via delegate
    }
}
