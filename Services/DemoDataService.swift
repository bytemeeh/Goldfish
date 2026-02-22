import Foundation
import SwiftData

// MARK: - Demo Data Service
/// Seeds realistic demo contacts, relationships, and circle memberships
/// so the feature tour can showcase a populated, living network.
/// All demo data is flagged with `isDemo: true` for easy cleanup.
@MainActor
final class DemoDataService {
    
    private let dataManager: GoldfishDataManager
    
    init(dataManager: GoldfishDataManager) {
        self.dataManager = dataManager
    }
    
    // MARK: - Seed Demo Data
    
    /// Seeds ~8 demo contacts with relationships and circle memberships.
    /// Safe to call multiple times — checks if demo data already exists.
    func seedDemoData() throws {
        // Guard against double-seeding
        let existing = try dataManager.fetchAllPersons()
        let hasDemoData = existing.contains { $0.isDemo }
        guard !hasDemoData else { return }
        
        // Ensure system circles exist
        let circles = try dataManager.fetchAllCircles()
        let familyCircle = circles.first { $0.name == "Family" }
        let friendsCircle = circles.first { $0.name == "Friends" }
        let proCircle = circles.first { $0.name == "Professional" }
        
        // ── Create Demo Contacts ──
        
        let sarah = try dataManager.createPerson(
            name: "Sarah Chen",
            phone: "+1 (415) 555-0142",
            email: "sarah.chen@email.com",
            birthday: makeDate(month: 3, day: 15, year: 1992),
            notes: "Loves hiking and photography. Met at college.",
            isDemo: true,
            color: "#E8857A"
        )
        
        let mom = try dataManager.createPerson(
            name: "Linda Miller",
            phone: "+1 (312) 555-0198",
            email: "linda.m@email.com",
            birthday: makeDate(month: 7, day: 22, year: 1960),
            notes: "Mom. Calls every Sunday.",
            isDemo: true,
            color: "#FF6B6B"
        )
        
        let dad = try dataManager.createPerson(
            name: "Robert Miller",
            phone: "+1 (312) 555-0199",
            email: "robert.miller@email.com",
            birthday: makeDate(month: 11, day: 8, year: 1958),
            notes: "Dad. Loves woodworking and jazz.",
            isDemo: true,
            color: "#D4574A"
        )
        
        let jake = try dataManager.createPerson(
            name: "Jake Morrison",
            phone: "+1 (628) 555-0167",
            email: "jake.m@email.com",
            birthday: makeDate(month: 5, day: 3, year: 1994),
            notes: "College roommate. Always up for weekend trips.",
            isDemo: true,
            isFavorite: true,
            color: "#4ECDC4"
        )
        
        let emma = try dataManager.createPerson(
            name: "Emma Wilson",
            phone: "+1 (510) 555-0134",
            email: "emma.wilson@email.com",
            birthday: makeDate(month: 9, day: 28, year: 1993),
            notes: "Book club friend. Recommends great reads.",
            isDemo: true,
            color: "#5ABEAF"
        )
        
        let david = try dataManager.createPerson(
            name: "David Park",
            phone: "+1 (650) 555-0189",
            email: "david.park@company.com",
            birthday: makeDate(month: 1, day: 14, year: 1990),
            notes: "Team lead at work. Great mentor.",
            isDemo: true,
            color: "#45B7D1"
        )
        
        let lisa = try dataManager.createPerson(
            name: "Lisa Thompson",
            phone: "+1 (408) 555-0156",
            email: "lisa.t@company.com",
            birthday: makeDate(month: 12, day: 1, year: 1991),
            notes: "Coworker. Works on the design team.",
            isDemo: true,
            color: "#5AC1D8"
        )
        
        let tom = try dataManager.createPerson(
            name: "Tom Miller",
            phone: "+1 (312) 555-0177",
            email: "tom.miller@email.com",
            birthday: makeDate(month: 4, day: 19, year: 1996),
            notes: "Younger brother. Studying engineering.",
            isDemo: true,
            color: "#E06858"
        )
        
        // ── Fetch the "Me" contact ──
        guard let me = try dataManager.fetchMePerson() else { return }
        
        // ── Create Relationships ──
        
        // Family relationships (from Me)
        try dataManager.createRelationship(from: me, to: sarah, type: .spouse)
        try dataManager.createRelationship(from: mom, to: me, type: .mother)
        try dataManager.createRelationship(from: dad, to: me, type: .father)
        try dataManager.createRelationship(from: me, to: tom, type: .sibling)
        
        // Mom & Dad are also Tom's parents
        try dataManager.createRelationship(from: mom, to: tom, type: .mother)
        try dataManager.createRelationship(from: dad, to: tom, type: .father)
        
        // Mom & Dad are spouses
        try dataManager.createRelationship(from: mom, to: dad, type: .spouse)
        
        // Friends (from Me)
        try dataManager.createRelationship(from: me, to: jake, type: .friend)
        try dataManager.createRelationship(from: me, to: emma, type: .friend)
        
        // Jake and Emma know each other
        try dataManager.createRelationship(from: jake, to: emma, type: .friend)
        
        // Professional (from Me)
        try dataManager.createRelationship(from: me, to: david, type: .coworker)
        try dataManager.createRelationship(from: me, to: lisa, type: .coworker)
        
        // David and Lisa are coworkers with each other
        try dataManager.createRelationship(from: david, to: lisa, type: .coworker)
        
        // ── Additional Demo Contacts for Custom Pond ──
        
        let mia = try dataManager.createPerson(
            name: "Mia Rodriguez",
            phone: "+1 (415) 555-0201",
            email: "mia.r@email.com",
            birthday: makeDate(month: 6, day: 10, year: 1995),
            notes: "Book club organizer. Loves mystery novels.",
            isDemo: true,
            color: "#9B59B6"
        )
        
        let ryan = try dataManager.createPerson(
            name: "Ryan O'Brien",
            phone: "+1 (415) 555-0202",
            email: "ryan.ob@email.com",
            birthday: makeDate(month: 2, day: 28, year: 1991),
            notes: "Book club member. Sci-fi enthusiast.",
            isDemo: true,
            color: "#8E44AD"
        )
        
        // Partner relationship (Jake & Emma)
        try dataManager.createRelationship(from: jake, to: sarah, type: .partner)
        
        // Book club friends (from Me)
        try dataManager.createRelationship(from: me, to: mia, type: .friend)
        try dataManager.createRelationship(from: me, to: ryan, type: .friend)
        
        // Mia and Ryan know each other
        try dataManager.createRelationship(from: mia, to: ryan, type: .friend)
        
        // Emma and Mia are friends (cross-pond connection)
        try dataManager.createRelationship(from: emma, to: mia, type: .friend)
        
        // ── Explicit Circle Assignments (for contacts not auto-assigned) ──
        
        if let familyCircle {
            try dataManager.addToCircle(sarah, circle: familyCircle)
        }
        if let friendsCircle {
            try dataManager.addToCircle(jake, circle: friendsCircle)
            try dataManager.addToCircle(emma, circle: friendsCircle)
        }
        if let proCircle {
            try dataManager.addToCircle(david, circle: proCircle)
            try dataManager.addToCircle(lisa, circle: proCircle)
        }
        
        // ── Custom "Book Club" Pond ──
        let bookClub = try dataManager.createCircle(
            name: "Book Club",
            color: "#9B59B6",
            emoji: "📚",
            desc: "Monthly book discussion group"
        )
        try dataManager.addToCircle(mia, circle: bookClub)
        try dataManager.addToCircle(ryan, circle: bookClub)
        try dataManager.addToCircle(emma, circle: bookClub)
    }
    
    // MARK: - Remove Demo Data
    
    /// Removes all contacts flagged as demo data and their relationships.
    /// Also cleans up any custom (non-system) circles that become empty.
    func removeDemoData() throws {
        let allPersons = try dataManager.fetchAllPersons()
        let demoPersons = allPersons.filter { $0.isDemo }
        
        for person in demoPersons {
            // Person's cascade delete rule handles relationships, locations, circle memberships
            dataManager.context.delete(person)
        }
        try dataManager.context.save()
        
        // Clean up custom circles that are now empty (e.g. "Book Club")
        let allCircles = try dataManager.fetchAllCircles()
        for circle in allCircles where !circle.isSystem {
            if circle.activeContacts.isEmpty {
                dataManager.context.delete(circle)
            }
        }
        try dataManager.context.save()
    }
    
    // MARK: - Helpers
    
    private func makeDate(month: Int, day: Int, year: Int) -> Date? {
        var components = DateComponents()
        components.month = month
        components.day = day
        components.year = year
        return Calendar.current.date(from: components)
    }
}
