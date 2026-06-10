import SpriteKit

protocol GraphCameraManagerDelegate: AnyObject {
    func didUpdateZoom(_ zoom: CGFloat)
    func didUpdateCameraPosition(_ position: CGPoint)
}

final class GraphCameraManager {
    let cameraNode = SKCameraNode()
    var currentZoom: CGFloat = 1.0
    weak var delegate: GraphCameraManagerDelegate?
    
    // Bounds tracking
    private var viewportSize: CGSize = .zero
    
    func setViewportSize(_ size: CGSize) {
        self.viewportSize = size
    }
    
    func updateZoom(_ zoom: CGFloat, animated: Bool = true) {
        let clamped = min(max(zoom, 0.1), 4.0)
        currentZoom = clamped
        
        if animated {
            let action = SKAction.scale(to: 1.0 / clamped, duration: 0.25)
            action.timingMode = .easeInEaseOut
            cameraNode.run(action, withKey: "cameraScale")
        } else {
            cameraNode.setScale(1.0 / clamped)
        }
        
        delegate?.didUpdateZoom(currentZoom)
    }
    
    func panCamera(by delta: CGPoint) {
        let newPos = CGPoint(x: cameraNode.position.x + delta.x, y: cameraNode.position.y + delta.y)
        cameraNode.position = newPos
        delegate?.didUpdateCameraPosition(newPos)
    }
    
    func centerOn(position: CGPoint, targetZoom: CGFloat = 1.0, animated: Bool = true) {
        currentZoom = targetZoom
        if animated {
            let moveAction = SKAction.move(to: position, duration: 0.5)
            moveAction.timingMode = .easeInEaseOut
            let scaleAction = SKAction.scale(to: 1.0 / targetZoom, duration: 0.5)
            scaleAction.timingMode = .easeInEaseOut
            
            cameraNode.run(moveAction, withKey: "cameraMove")
            cameraNode.run(scaleAction, withKey: "cameraScale")
        } else {
            cameraNode.position = position
            cameraNode.setScale(1.0 / targetZoom)
        }
        delegate?.didUpdateCameraPosition(position)
        delegate?.didUpdateZoom(targetZoom)
    }
    
    func fitToBoundingBox(minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat, padding: CGFloat, minZoom: CGFloat, maxZoom: CGFloat) {
        let width = max(maxX - minX, 100) + (padding * 2)
        let height = max(maxY - minY, 100) + (padding * 2)
        
        let cx = (minX + maxX) / 2
        let cy = (minY + maxY) / 2
        let target = CGPoint(x: cx, y: cy)
        
        guard viewportSize.width > 0 && viewportSize.height > 0 else { return }
        
        let zoomX = viewportSize.width / width
        let zoomY = viewportSize.height / height
        var targetZoom = min(zoomX, zoomY)
        
        if !targetZoom.isFinite || targetZoom <= 0 { targetZoom = 1.0 }
        targetZoom = min(max(targetZoom, minZoom), maxZoom)
        
        centerOn(position: target, targetZoom: targetZoom)
    }
    
    // Cull and update LOD for nodes
    func cullAndUpdateLOD(nodes: [PersonNode]) {
        let halfW = viewportSize.width / (2.0 * currentZoom) + 200
        let halfH = viewportSize.height / (2.0 * currentZoom) + 200
        let visibleRect = CGRect(
            x: cameraNode.position.x - halfW,
            y: cameraNode.position.y - halfH,
            width: halfW * 2,
            height: halfH * 2
        )
        
        for node in nodes {
            let pos = node.position
            if pos.x.isFinite && pos.y.isFinite {
                node.isHidden = !visibleRect.contains(pos)
            }
            
            if !node.isHidden {
                if currentZoom < 0.3 {
                    node.showDotOnly()
                } else if currentZoom < 0.5 {
                    node.hideLabel()
                } else {
                    node.showFull()
                }
            }
        }
    }
}
