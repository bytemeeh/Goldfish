import CoreGraphics
import Foundation

struct GraphLayoutManager {
    static func computeTargetPositions(
        pondInfos: [GoldfishGraphScene.PondInfo],
        personNodes: [UUID: PersonNode],
        newNodeIDs: Set<UUID>
    ) {
        var pondOrder: [String] = []
        for info in pondInfos {
            if !pondOrder.contains(info.circleName) {
                pondOrder.append(info.circleName)
            }
        }
        let pondCount = max(pondOrder.count, 1)
        
        var pondClusterRadii: [String: CGFloat] = [:]
        var largestEstimatedPondRadius: CGFloat = 55
        
        for pondName in pondOrder {
            guard let info = pondInfos.first(where: { $0.circleName == pondName }) else { continue }
            let memberCount = info.memberIDs.count
            let clusterR: CGFloat = memberCount <= 1 ? 0.0 : max(40, sqrt(CGFloat(memberCount)) * 45)
            pondClusterRadii[pondName] = clusterR
            let estimatedVisualRadius: CGFloat = memberCount <= 1 ? 55.0 : clusterR + 60
            largestEstimatedPondRadius = max(largestEstimatedPondRadius, estimatedVisualRadius)
        }
        
        let arcRadius: CGFloat = max(350, largestEstimatedPondRadius * 2.5)
        
        for (pondIndex, pondName) in pondOrder.enumerated() {
            guard let info = pondInfos.first(where: { $0.circleName == pondName }) else { continue }
            let members = info.memberIDs
            let memberCount = members.count
            guard memberCount > 0 else { continue }
            
            let pondAngle = (CGFloat(pondIndex) / CGFloat(pondCount)) * 2 * .pi - .pi / 2
            let anchorX = cos(pondAngle) * arcRadius
            let anchorY = sin(pondAngle) * arcRadius
            
            let clusterRadius: CGFloat = pondClusterRadii[pondName] ?? 0
            
            for (memberIndex, memberID) in members.enumerated() {
                guard let node = personNodes[memberID] else { continue }
                
                let memberAngle = (CGFloat(memberIndex) / CGFloat(max(memberCount, 1))) * 2 * .pi
                let tx = anchorX + cos(memberAngle) * clusterRadius
                let ty = anchorY + sin(memberAngle) * clusterRadius
                node.targetPosition = CGPoint(x: tx, y: ty)
                
                if newNodeIDs.contains(memberID) {
                    node.position = CGPoint(x: tx, y: ty)
                }
            }
        }
        
        for (_, node) in personNodes {
            if node.isMe { node.targetPosition = .zero; continue }
            let inPond = pondInfos.contains { $0.memberIDs.contains(node.personID) }
            if !inPond {
                node.targetPosition = CGPoint(x: 0, y: -arcRadius - 100)
            }
        }
    }
}
