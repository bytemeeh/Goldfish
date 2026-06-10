import SpriteKit

protocol GraphPhysicsEngineDelegate: AnyObject {
    func didSettlePhysics()
}

final class GraphPhysicsEngine {
    
    weak var delegate: GraphPhysicsEngineDelegate?
    
    // Physics Config
    var kRepulsion: CGFloat = 3000.0
    var kTarget: CGFloat = 0.15
    var maxSpeed: CGFloat = 200.0
    var damping: CGFloat = 0.85
    var maxRepulsionDist: CGFloat = 200.0
    var pondGravity: CGFloat = 0.05 // Force pulling nodes to their pond's center of mass
    var interPondRepulsion: CGFloat = 10000.0 // Force pushing ponds apart
    
    // Energy-based settling
    var physicsSettled = false
    private var frameEnergyHistory: [CGFloat] = []
    private let energyHistoryWindowSize = 10
    
    // State
    private var lastUpdateTime: TimeInterval = 0
    private let maxDeltaTime: TimeInterval = 1.0 / 30.0
    
    // Grid-based spatial partitioning
    private struct GridCell: Hashable {
        let col: Int
        let row: Int
    }
    
    func resetSettling() {
        physicsSettled = false
        frameEnergyHistory.removeAll()
        lastUpdateTime = 0
    }
    
    func update(currentTime: TimeInterval, nodes: [PersonNode], physicsWorld: SKPhysicsWorld) {
        if physicsSettled { return }
        
        if lastUpdateTime == 0 {
            lastUpdateTime = currentTime
            return
        }
        
        let dt = min(currentTime - lastUpdateTime, maxDeltaTime)
        lastUpdateTime = currentTime
        
        let substeps = 3
        let subDt = dt / Double(substeps)
        
        struct NodeData {
            let body: SKPhysicsBody
            let position: CGPoint
            let targetPosition: CGPoint
            let node: PersonNode
            let id: UUID
        }
        
        var dynamicNodes: [NodeData] = []
        for node in nodes {
            if let body = node.physicsBody, body.isDynamic {
                dynamicNodes.append(NodeData(body: body, position: node.position, targetPosition: node.targetPosition, node: node, id: node.personID))
            }
        }
        
        for _ in 0..<substeps {
            // 1. Build Spatial Grid for Repulsion
            let cellSize = maxRepulsionDist
            var grid: [GridCell: [NodeData]] = [:]
            for dn in dynamicNodes {
                let cell = GridCell(col: Int(floor(dn.position.x / cellSize)), row: Int(floor(dn.position.y / cellSize)))
                grid[cell, default: []].append(dn)
            }
            
            // 2. Pond Centers of Mass (for Gravity Wells)
            var pondCenters: [CGPoint: (center: CGPoint, count: Int)] = [:]
            for dn in dynamicNodes {
                // Group by target position (which roughly defines the pond's baseline center in LayoutManager)
                let key = dn.targetPosition
                if let existing = pondCenters[key] {
                    pondCenters[key] = (CGPoint(x: existing.center.x + dn.position.x, y: existing.center.y + dn.position.y), existing.count + 1)
                } else {
                    pondCenters[key] = (dn.position, 1)
                }
            }
            let resolvedPondCenters = pondCenters.mapValues { CGPoint(x: $0.center.x / CGFloat($0.count), y: $0.center.y / CGFloat($0.count)) }
            let allPondCenters = Array(resolvedPondCenters.values)
            
            // 3. Calculate Forces
            var newVelocities: [CGVector] = []
            
            for i in 0..<dynamicNodes.count {
                let nodeA = dynamicNodes[i]
                var forceX: CGFloat = 0
                var forceY: CGFloat = 0
                
                // Spring to target (Baseline stability)
                let tdx = nodeA.targetPosition.x - nodeA.position.x
                let tdy = nodeA.targetPosition.y - nodeA.position.y
                forceX += tdx * kTarget
                
                // Pond Gravity Well (Pull to center of mass of its own pond)
                if let myPondCenter = resolvedPondCenters[nodeA.targetPosition] {
                    let pdx = myPondCenter.x - nodeA.position.x
                    let pdy = myPondCenter.y - nodeA.position.y
                    forceX += pdx * pondGravity
                    forceY += pdy * pondGravity
                    
                    // Inter-Pond Repulsion (Push ponds away from each other)
                    for otherCenter in allPondCenters {
                        if otherCenter == myPondCenter { continue }
                        let cdx = myPondCenter.x - otherCenter.x
                        let cdy = myPondCenter.y - otherCenter.y
                        let distSq = max(cdx * cdx + cdy * cdy, 1.0)
                        if distSq < 1000000 { // Only repel if somewhat close (1000 points)
                            let dist = sqrt(distSq)
                            let force = (interPondRepulsion / distSq)
                            forceX += (cdx / dist) * force
                            forceY += (cdy / dist) * force
                        }
                    }
                }
                
                // Coulomb Repulsion using Spatial Grid
                let cellCol = Int(floor(nodeA.position.x / cellSize))
                let cellRow = Int(floor(nodeA.position.y / cellSize))
                
                for c in cellCol-1...cellCol+1 {
                    for r in cellRow-1...cellRow+1 {
                        let neighborCell = GridCell(col: c, row: r)
                        guard let neighbors = grid[neighborCell] else { continue }
                        
                        for nodeB in neighbors {
                            if nodeB.id == nodeA.id { continue } // Self
                            
                            let dx = nodeA.position.x - nodeB.position.x
                            let dy = nodeA.position.y - nodeB.position.y
                            
                            // Fast check
                            if abs(dx) > maxRepulsionDist || abs(dy) > maxRepulsionDist { continue }
                            
                            let distSq = max(dx * dx + dy * dy, 1.0)
                            let dist = sqrt(distSq)
                            if dist > maxRepulsionDist { continue }
                            
                            let falloff = 1.0 - dist / maxRepulsionDist
                            let force = (kRepulsion / distSq) * falloff * falloff
                            
                            forceX += (dx / dist) * force
                            forceY += (dy / dist) * force
                        }
                    }
                }
                
                var vx = (nodeA.body.velocity.dx + forceX * CGFloat(subDt)) * damping
                var vy = (nodeA.body.velocity.dy + forceY * CGFloat(subDt)) * damping
                
                let speed = hypot(vx, vy)
                if speed > maxSpeed {
                    vx = vx / speed * maxSpeed
                    vy = vy / speed * maxSpeed
                }
                
                newVelocities.append(CGVector(dx: vx, dy: vy))
            }
            
            // 4. Apply velocities and integrate
            for i in 0..<dynamicNodes.count {
                let nodeA = dynamicNodes[i]
                nodeA.body.velocity = newVelocities[i]
                nodeA.node.position.x += newVelocities[i].dx * CGFloat(subDt)
                nodeA.node.position.y += newVelocities[i].dy * CGFloat(subDt)
                
                dynamicNodes[i] = NodeData(body: nodeA.body, position: nodeA.node.position, targetPosition: nodeA.targetPosition, node: nodeA.node, id: nodeA.id)
            }
        }
    }
    
    func didSimulatePhysics(nodes: [PersonNode], physicsWorld: SKPhysicsWorld) {
        guard !physicsSettled else { return }
        
        var totalVelocity: CGFloat = 0
        var dynamicNodeCount: Int = 0
        for node in nodes {
            guard let body = node.physicsBody, body.isDynamic else { continue }
            totalVelocity += abs(body.velocity.dx) + abs(body.velocity.dy)
            dynamicNodeCount += 1
        }
        
        let perNodeVelocity = dynamicNodeCount > 0 ? totalVelocity / CGFloat(dynamicNodeCount) : 0
        
        frameEnergyHistory.append(perNodeVelocity)
        if frameEnergyHistory.count > energyHistoryWindowSize {
            frameEnergyHistory.removeFirst()
        }
        
        let averageVelocity = frameEnergyHistory.reduce(0, +) / CGFloat(max(frameEnergyHistory.count, 1))
        
        if frameEnergyHistory.count == energyHistoryWindowSize && averageVelocity < 5.0 {
            for node in nodes {
                node.physicsBody?.velocity = .zero
                node.removeAction(forKey: "floating")
            }
            physicsWorld.speed = 0.0
            physicsSettled = true
            frameEnergyHistory.removeAll()
            
            delegate?.didSettlePhysics()
        }
    }
}
