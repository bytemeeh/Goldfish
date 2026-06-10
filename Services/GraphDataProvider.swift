import Foundation
import SwiftData

/// Background actor responsible for compiling the graph topology.
/// Fetches all nodes, edges, and circles using highly optimized, single-pass queries.
/// This guarantees zero implicit faulting and completely insulates the main thread.
///
/// **Caching:** The compiled topology is cached in-memory per demo-mode flag.
/// Call `invalidateCache()` when relationships, circles, or contacts change.
@ModelActor
actor GraphDataProvider {
    
    // MARK: - Cache
    private var cachedTopology: [Bool: GraphTopology] = [:]
    
    /// Invalidates the cached topology, forcing a full recompilation on the next call.
    func invalidateCache() {
        cachedTopology.removeAll()
    }
    
    /// Compiles the entire graph topology efficiently for SpriteKit.
    /// Returns a cached result if available; recomputes otherwise.
    func compileGraphTopology(demoMode: Bool = false) throws -> GraphTopology {
        if let cached = cachedTopology[demoMode] {
            return cached
        }
        let topology = try _compileGraphTopology(demoMode: demoMode)
        cachedTopology[demoMode] = topology
        return topology
    }
    
    /// Internal implementation — always recomputes from scratch.
    private func _compileGraphTopology(demoMode: Bool = false) throws -> GraphTopology {
        // 1. Fetch all models in a single pass
        let persons = try modelContext.fetch(FetchDescriptor<Person>())
        let relationships = try modelContext.fetch(FetchDescriptor<Relationship>())
        let circles = try modelContext.fetch(FetchDescriptor<GoldfishCircle>())
        let circleContacts = try modelContext.fetch(FetchDescriptor<CircleContact>())
        
        // 2. Build quick lookup maps (Zero Faulting!)
        var personMap: [UUID: Person] = [:]
        var isOrphanMap: [UUID: Bool] = [:]
        for p in persons {
            personMap[p.id] = p
            isOrphanMap[p.id] = true // Assume orphan until proven otherwise
        }
        
        // Adjacency list for BFS (Undirected graph for layout purposes)
        var adjacencyList: [UUID: [UUID]] = [:]
        var edgesDTO: [GraphEdge] = []
        
        for rel in relationships {
            let fromID = rel.fromContact.id
            let toID = rel.toContact.id
            
            adjacencyList[fromID, default: []].append(toID)
            adjacencyList[toID, default: []].append(fromID)
            
            isOrphanMap[fromID] = false
            isOrphanMap[toID] = false
            
            edgesDTO.append(GraphEdge(
                sourceId: fromID,
                targetId: toID,
                relationshipType: rel.typeRawValue,
                isSymmetric: rel.isSymmetric
            ))
        }
        
        // 3. Map Circle Memberships
        var circleMembership: [UUID: Set<UUID>] = [:]
        for cc in circleContacts where !cc.manuallyExcluded {
            let cID = cc.circle.id
            let pID = cc.contact.id
            circleMembership[cID, default: []].insert(pID)
        }
        
        var circlesDTO: [GraphCircle] = []
        for c in circles {
            circlesDTO.append(GraphCircle(
                id: c.id,
                name: c.name,
                hexColor: c.color,
                emoji: c.emoji,
                sortOrder: c.sortOrder,
                activeContactIds: circleMembership[c.id] ?? []
            ))
        }
        
        // 4. Perform BFS to determine graph levels
        guard let root = persons.first(where: { $0.isMe }) else {
            return GraphTopology(levels: [], circles: circlesDTO, edges: edgesDTO)
        }
        
        var visited: Set<UUID> = [root.id]
        var currentLevelIDs: [UUID] = [root.id]
        var levelsDTO: [GraphTopologyLevel] = []
        var depth = 0
        
        while !currentLevelIDs.isEmpty {
            var nodesDTO: [GraphNode] = []
            var nextLevelIDs: [UUID] = []
            
            for pID in currentLevelIDs {
                guard let person = personMap[pID] else { continue }
                // For demo mode filtering: root is always included, others must match the flag
                if !person.isMe && person.isDemo != demoMode { continue }
                
                let initials = person.initials
                
                nodesDTO.append(GraphNode(
                    id: person.id,
                    name: person.name,
                    initials: initials,
                    hexColor: person.color ?? "#808080",
                    photoData: person.photoData,
                    isMe: person.isMe,
                    isDemo: person.isDemo,
                    isOrphan: isOrphanMap[person.id] ?? true,
                    isFavorite: person.isFavorite
                ))
                
                let neighbors = adjacencyList[pID] ?? []
                for nID in neighbors {
                    if !visited.contains(nID) {
                        visited.insert(nID)
                        nextLevelIDs.append(nID)
                    }
                }
            }
            
            levelsDTO.append(GraphTopologyLevel(depth: depth, nodes: nodesDTO))
            currentLevelIDs = nextLevelIDs
            depth += 1
        }
        
        // 5. Gather Orphans (nodes not reachable via BFS)
        var orphanNodes: [GraphNode] = []
        for p in persons {
            if !visited.contains(p.id) && p.isDemo == demoMode {
                let initials = p.initials
                orphanNodes.append(GraphNode(
                    id: p.id,
                    name: p.name,
                    initials: initials,
                    hexColor: p.color ?? "#808080",
                    photoData: p.photoData,
                    isMe: p.isMe,
                    isDemo: p.isDemo,
                    isOrphan: true,
                    isFavorite: p.isFavorite
                ))
            }
        }
        
        if !orphanNodes.isEmpty {
            levelsDTO.append(GraphTopologyLevel(depth: depth, nodes: orphanNodes))
        }
        
        return GraphTopology(levels: levelsDTO, circles: circlesDTO, edges: edgesDTO)
    }
}
