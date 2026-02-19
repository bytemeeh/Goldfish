import Foundation
import SwiftData

// MARK: - VCardExportService
/// Orchestrates the export of contacts to vCard format.
/// Supports full database export and depth-limited partial export.
struct VCardExportService {

    /// Exports ALL contacts in the database.
    ///
    /// - Parameter context: The ModelContext to fetch from.
    /// - Returns: vCard data containing all contacts.
    static func exportAll(context: ModelContext) throws -> Data {
        let descriptor = FetchDescriptor<Person>(sortBy: [SortDescriptor(\.name)])
        let allContacts = try context.fetch(descriptor)
        return VCardExporter.export(allContacts)
    }

    /// Exports selected contacts and their connections up to a specified depth.
    ///
    /// **Behavior:**
    /// - Depth 0: Export only the selected contacts.
    /// - Depth 1: Selected + immediate neighbors.
    /// - Depth N: BFS traversal up to N hops.
    ///
    /// **isMe Exclusion:**
    /// The `isMe` contact is excluded from the expansion (neighbors) unless
    /// it was explicitly in the initial `contacts` list. This prevents accidentally
    /// sharing your own profile when sharing a friend's network.
    ///
    /// - Parameters:
    ///   - contacts: The root contacts to start the export from.
    ///   - depth: How many hops to traverse (0 = roots only).
    /// - Returns: vCard data containing the collected subgraph.
    static func exportSelected(_ contacts: [Person], depth: Int) -> Data {
        let roots = Set(contacts)
        var visited: Set<Person> = roots
        var currentLevel: Set<Person> = roots
        
        // BFS Expansion
        if depth > 0 {
            for _ in 1...depth {
                var nextLevel: Set<Person> = []
                
                for person in currentLevel {
                    // Get all connected contacts (bidirectional)
                    let neighbors = person.connectedContacts
                    
                    for neighbor in neighbors {
                        // Skip isMe unless it was a root
                        if neighbor.isMe && !roots.contains(neighbor) {
                            continue
                        }
                        
                        if !visited.contains(neighbor) {
                            visited.insert(neighbor)
                            nextLevel.insert(neighbor)
                        }
                    }
                }
                
                if nextLevel.isEmpty { break }
                currentLevel = nextLevel
            }
        }
        
        // Convert to Array and sort for deterministic output
        let sortedContacts = visited.sorted { $0.name < $1.name }
        return VCardExporter.export(sortedContacts)
    }
}
