import Foundation

/// Data Transfer Objects for SpriteKit graph rendering.
/// These value types completely insulate the UI/Scene layer from SwiftData,
/// preventing main-thread blocking and N+1 query loops.

// MARK: - Graph Topology Container
struct GraphTopology {
    /// Ordered by BFS depth
    let levels: [GraphTopologyLevel]
    /// Pre-computed circle clusters for the physics engine
    let circles: [GraphCircle]
    /// All active edges
    let edges: [GraphEdge]
    
    // Flattened nodes for easy ID lookups
    var allNodes: [GraphNode] {
        levels.flatMap(\.nodes)
    }
}

// MARK: - Topology Level
struct GraphTopologyLevel {
    let depth: Int
    let nodes: [GraphNode]
}

// MARK: - Graph Node
struct GraphNode: Identifiable, Hashable {
    let id: UUID
    let name: String
    let initials: String
    let hexColor: String
    let photoData: Data?
    let isMe: Bool
    let isDemo: Bool
    let isOrphan: Bool
    let isFavorite: Bool
}

// MARK: - Graph Edge
struct GraphEdge: Hashable {
    let sourceId: UUID
    let targetId: UUID
    let relationshipType: String
    let isSymmetric: Bool
}

// MARK: - Graph Circle
struct GraphCircle: Identifiable, Hashable {
    let id: UUID
    let name: String
    let hexColor: String
    let emoji: String
    let sortOrder: Int
    /// Set of contact UUIDs belonging to this circle
    let activeContactIds: Set<UUID>
}
