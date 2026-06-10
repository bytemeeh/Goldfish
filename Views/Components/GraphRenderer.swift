import SpriteKit

final class GraphRenderer {
    weak var contentNode: SKNode?
    
    private var pondLabels: [String: SKLabelNode] = [:]
    private var pondClouds: [String: SKShapeNode] = [:]
    private var pondCloudCachedRadius: [String: CGFloat] = [:]
    
    private var edgeNodes: [String: SKShapeNode] = [:]
    private var edgeConnections: Set<String> = []
    
    var snapPreviewLine: SKShapeNode?
    
    init(contentNode: SKNode) {
        self.contentNode = contentNode
    }
    
    func updateEdges(desiredEdges: Set<String>, personNodes: [UUID: PersonNode]) {
        // Remove old edges
        for edgeKey in Array(edgeNodes.keys) where !desiredEdges.contains(edgeKey) {
            edgeNodes[edgeKey]?.removeFromParent()
            edgeNodes.removeValue(forKey: edgeKey)
        }
        edgeConnections = desiredEdges
        
        // Create new edges
        for edgeKey in desiredEdges {
            if edgeNodes[edgeKey] == nil {
                let edgeNode = SKShapeNode()
                edgeNode.strokeColor = UIColor(red: 212/255, green: 116/255, blue: 78/255, alpha: 0.5)
                edgeNode.lineWidth = 2.0
                edgeNode.alpha = 0.6
                edgeNode.zPosition = -1
                edgeNode.name = edgeKey
                edgeNode.glowWidth = 1.0
                
                let parts = edgeKey.split(separator: "_")
                if parts.count == 2,
                   let id1 = UUID(uuidString: String(parts[0])),
                   let id2 = UUID(uuidString: String(parts[1])) {
                    let data = NSMutableDictionary()
                    data["id1"] = id1
                    data["id2"] = id2
                    edgeNode.userData = data
                }
                
                contentNode?.addChild(edgeNode)
                edgeNodes[edgeKey] = edgeNode
            }
        }
    }
    
    func updateEdgePaths(personNodes: [UUID: PersonNode]) {
        for (edgeKey, edgeNode) in edgeNodes {
            let ids = edgeKey.split(separator: "_")
            guard ids.count == 2,
                  let uuidA = UUID(uuidString: String(ids[0])),
                  let uuidB = UUID(uuidString: String(ids[1])),
                  let nodeA = personNodes[uuidA],
                  let nodeB = personNodes[uuidB] else { continue }
            
            edgeNode.path = calculateCurvedPath(from: nodeA.position, to: nodeB.position, avoiding: [uuidA, uuidB], nodes: personNodes)
        }
    }
    
    func updatePonds(pondInfos: [GoldfishGraphScene.PondInfo]) {
        let currentPondNames = Set(pondLabels.keys)
        let newPondNames = Set(pondInfos.map { $0.circleName })
        
        for name in currentPondNames where !newPondNames.contains(name) {
            pondLabels[name]?.removeFromParent()
            pondLabels.removeValue(forKey: name)
            pondClouds[name]?.removeFromParent()
            pondClouds.removeValue(forKey: name)
            pondCloudCachedRadius.removeValue(forKey: name)
        }
        
        for info in pondInfos {
            let name = info.circleName
            let pondColor = GoldfishUIColor(hex: info.color) ?? UIColor.systemGray3
            
            if pondLabels[name] == nil {
                let label = SKLabelNode(text: name)
                label.fontName = "SFProRounded-Bold"
                label.fontSize = 16
                label.fontColor = pondColor
                label.horizontalAlignmentMode = .center
                label.verticalAlignmentMode = .top
                label.zPosition = -1
                
                contentNode?.addChild(label)
                pondLabels[name] = label
            }
            
            if pondClouds[name] == nil {
                let cloud = SKShapeNode(circleOfRadius: 80)
                cloud.fillColor = pondColor.withAlphaComponent(0.08)
                cloud.strokeColor = pondColor.withAlphaComponent(0.25)
                cloud.lineWidth = 1.0
                cloud.glowWidth = 6.0
                cloud.zPosition = -5
                cloud.alpha = 0.9
                
                let breatheIn = SKAction.scale(to: 1.03, duration: 4.5)
                breatheIn.timingMode = .easeInEaseOut
                let breatheOut = SKAction.scale(to: 0.97, duration: 4.5)
                breatheOut.timingMode = .easeInEaseOut
                cloud.run(SKAction.repeatForever(SKAction.sequence([breatheIn, breatheOut])))
                
                // Phase 2 Optimization: Rasterize static background
                // cloud.shouldRasterize = true
                
                contentNode?.addChild(cloud)
                pondClouds[name] = cloud
                pondCloudCachedRadius[name] = 80
            }
        }
    }
    
    func updatePondVisuals(metrics: [GoldfishGraphScene.PondMetrics]) {
        for metric in metrics {
            if let label = pondLabels[metric.name] {
                label.position = CGPoint(x: metric.center.x, y: metric.center.y - metric.radius - 16)
                label.isHidden = false
            }
            
            if let cloud = pondClouds[metric.name] {
                cloud.position = metric.center
                cloud.isHidden = false
                
                let cachedR = pondCloudCachedRadius[metric.name] ?? 0
                let cloudPadding: CGFloat = 30
                let targetRadius = metric.radius + cloudPadding
                
                if abs(targetRadius - cachedR) > 8 {
                    cloud.path = CGPath(ellipseIn: CGRect(
                        x: -targetRadius, y: -targetRadius,
                        width: targetRadius * 2, height: targetRadius * 2
                    ), transform: nil)
                    pondCloudCachedRadius[metric.name] = targetRadius
                }
            }
        }
    }
    
    func setupSnapPreview() {
        if snapPreviewLine == nil {
            let preview = SKShapeNode()
            preview.strokeColor = UIColor(red: 183/255, green: 79/255, blue: 58/255, alpha: 0.55)
            preview.lineWidth = 1.5
            preview.isHidden = true
            preview.zPosition = 10
            contentNode?.addChild(preview)
            snapPreviewLine = preview
        }
    }
    
    func calculateCurvedPath(from start: CGPoint, to end: CGPoint, avoiding personIDs: Set<UUID>, nodes: [UUID: PersonNode]) -> CGPath {
        let midX = (start.x + end.x) / 2
        let midY = (start.y + end.y) / 2
        var controlPoint = CGPoint(x: midX, y: midY)
        
        let dx = end.x - start.x
        let dy = end.y - start.y
        let distance = max(hypot(dx, dy), 1.0)
        
        let perpX = -dy / distance
        let perpY = dx / distance
        
        var totalOffset: CGFloat = 0
        let avoidanceRadius: CGFloat = 80.0
        
        for (id, node) in nodes {
            guard !personIDs.contains(id) else { continue }
            let nodePos = node.position
            let t = max(0, min(1, ((nodePos.x - start.x) * dx + (nodePos.y - start.y) * dy) / (distance * distance)))
            let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
            let distToLine = hypot(nodePos.x - projection.x, nodePos.y - projection.y)
            
            if distToLine < avoidanceRadius {
                let crossProduct = (end.x - start.x) * (nodePos.y - start.y) - (end.y - start.y) * (nodePos.x - start.x)
                let side: CGFloat = crossProduct >= 0 ? 1 : -1
                let force = (avoidanceRadius - distToLine) * 1.5
                totalOffset -= side * force
            }
        }
        
        let baseCurvature: CGFloat = 15.0
        totalOffset += (totalOffset == 0) ? baseCurvature : 0
        
        let maxOffset = distance * 0.4
        totalOffset = max(-maxOffset, min(maxOffset, totalOffset))
        
        controlPoint.x += perpX * totalOffset
        controlPoint.y += perpY * totalOffset
        
        let path = CGMutablePath()
        path.move(to: start)
        path.addQuadCurve(to: end, control: controlPoint)
        return path
    }
    
    func setPondLabelsHidden(_ hidden: Bool, for name: String) {
        pondLabels[name]?.isHidden = hidden
        pondClouds[name]?.isHidden = hidden
    }
    
    // Evaluate Visibility for filters
    func evaluateVisibility(personNodes: [UUID: PersonNode], activeSearchIDs: Set<UUID>?, soloedPondName: String?, pondInfos: [GoldfishGraphScene.PondInfo], animated: Bool) {
        let duration: TimeInterval = animated ? 0.3 : 0.0
        let isSearchActive = activeSearchIDs != nil
        let isSoloActive = soloedPondName != nil
        
        let soloedPondInfo = soloedPondName.flatMap { name in pondInfos.first { $0.circleName == name } }
        let soloedNodeIDs = Set(soloedPondInfo?.memberIDs ?? [])
        
        for (id, node) in personNodes {
            var alpha: CGFloat = 1.0
            var popToFront = false
            
            if isSearchActive {
                if activeSearchIDs?.contains(id) == true {
                    alpha = 1.0
                    popToFront = true
                } else {
                    alpha = 0.2
                }
            }
            
            if isSoloActive {
                if soloedNodeIDs.contains(id) || node.isMe {
                    // keep alpha
                } else {
                    alpha = min(alpha, 0.15)
                }
            }
            
            let action = SKAction.fadeAlpha(to: alpha, duration: duration)
            action.timingMode = .easeInEaseOut
            node.run(action)
            node.zPosition = popToFront ? 5 : 0
        }
        
        for (_, edge) in edgeNodes {
            var targetEdgeAlpha: CGFloat = 0.6
            
            let id1 = edge.userData?["id1"] as? UUID
            let id2 = edge.userData?["id2"] as? UUID
            
            if isSearchActive {
                if let s1 = id1, let s2 = id2, let searches = activeSearchIDs {
                    if searches.contains(s1) || searches.contains(s2) {
                        targetEdgeAlpha = 0.3
                    } else {
                        targetEdgeAlpha = 0.05
                    }
                } else {
                    targetEdgeAlpha = 0.05
                }
            } else if isSoloActive {
                if let s1 = id1, let s2 = id2 {
                    let n1Visible = soloedNodeIDs.contains(s1) || personNodes[s1]?.isMe == true
                    let n2Visible = soloedNodeIDs.contains(s2) || personNodes[s2]?.isMe == true
                    
                    if n1Visible && n2Visible {
                        targetEdgeAlpha = 0.6
                    } else if n1Visible || n2Visible {
                        targetEdgeAlpha = 0.15
                    } else {
                        targetEdgeAlpha = 0.05
                    }
                } else {
                    targetEdgeAlpha = 0.05
                }
            }
            
            let action = SKAction.fadeAlpha(to: targetEdgeAlpha, duration: duration)
            action.timingMode = .easeInEaseOut
            edge.run(action)
        }
        
        for (name, label) in pondLabels {
            let isThisSolo = (name == soloedPondName)
            let labelAlpha: CGFloat = isSearchActive ? 0.1 : (isSoloActive ? (isThisSolo ? 1.0 : 0.1) : 1.0)
            let action = SKAction.fadeAlpha(to: labelAlpha, duration: duration)
            action.timingMode = .easeInEaseOut
            label.run(action)
        }
        
        for (name, cloud) in pondClouds {
            let isThisSolo = (name == soloedPondName)
            let cloudAlpha: CGFloat = isSearchActive ? 0.03 : (isSoloActive ? (isThisSolo ? 0.9 : 0.05) : 0.9)
            let action = SKAction.fadeAlpha(to: cloudAlpha, duration: duration)
            action.timingMode = .easeInEaseOut
            cloud.run(action)
        }
    }
}
