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
        
        // Require the "Me" contact to exist before seeding —
        // relationships are anchored to Me, so seeding without it
        // would create orphaned demo contacts.
        guard let me = try dataManager.fetchMePerson() else { return }
        
        // Ensure system circles exist (may not yet if called before onboarding)
        let existingCircles = try dataManager.fetchAllCircles()
        if !existingCircles.contains(where: { $0.isSystem }) {
            try dataManager.createSystemCircles()
        }
        
        // Fetch circles for assignment
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
            notes: "College roommate. Married to Nicole, 3 kids. Always up for weekend trips and BBQs.",
            isDemo: true,
            isFavorite: true,
            color: "#4ECDC4"
        )
        
        // ── Jake's Family ──
        
        let nicole = try dataManager.createPerson(
            name: "Nicole Morrison",
            phone: "+1 (628) 555-0168",
            email: "nicole.m@email.com",
            birthday: makeDate(month: 7, day: 3, year: 1995),
            notes: "Jake's wife. Graphic designer, loves pasta making and Saturday farmers markets.",
            isDemo: true,
            isFavorite: true,
            color: "#E8A87C"
        )
        
        let liam = try dataManager.createPerson(
            name: "Liam Morrison",
            phone: nil,
            email: nil,
            birthday: makeDate(month: 9, day: 12, year: 2018),
            notes: "Jake & Nicole's oldest. Obsessed with dinosaurs and Lego. Plays little league.",
            isDemo: true,
            color: "#85DCBA"
        )
        
        let ella = try dataManager.createPerson(
            name: "Ella Morrison",
            phone: nil,
            email: nil,
            birthday: makeDate(month: 3, day: 21, year: 2021),
            notes: "Middle child. Taking ballet classes. Loves drawing rainbows.",
            isDemo: true,
            color: "#F6C3B7"
        )
        
        let noah = try dataManager.createPerson(
            name: "Noah Morrison",
            phone: nil,
            email: nil,
            birthday: makeDate(month: 12, day: 8, year: 2025),
            notes: "The baby! Born Dec 2025. Already has his dad's smile.",
            isDemo: true,
            color: "#B5EAD7"
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
        
        // ── Create Relationships ──
        // skipAutoAssign: true — circle assignments are handled explicitly below
        
        // Family relationships (from Me)
        try dataManager.createRelationship(from: me, to: sarah, type: .spouse, skipAutoAssign: true)
        try dataManager.createRelationship(from: mom, to: me, type: .mother, skipAutoAssign: true)
        try dataManager.createRelationship(from: dad, to: me, type: .father, skipAutoAssign: true)
        try dataManager.createRelationship(from: me, to: tom, type: .sibling, skipAutoAssign: true)
        
        // Mom & Dad are also Tom's parents
        try dataManager.createRelationship(from: mom, to: tom, type: .mother, skipAutoAssign: true)
        try dataManager.createRelationship(from: dad, to: tom, type: .father, skipAutoAssign: true)
        
        // Mom & Dad are spouses
        try dataManager.createRelationship(from: mom, to: dad, type: .spouse, skipAutoAssign: true)
        
        // Friends (from Me)
        try dataManager.createRelationship(from: me, to: jake, type: .friend, skipAutoAssign: true)
        
        // Jake and Emma know each other
        try dataManager.createRelationship(from: jake, to: emma, type: .friend, skipAutoAssign: true)
        
        // Professional (from Me)
        try dataManager.createRelationship(from: me, to: david, type: .coworker, skipAutoAssign: true)
        
        // David and Lisa are coworkers with each other
        try dataManager.createRelationship(from: david, to: lisa, type: .coworker, skipAutoAssign: true)
        
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
        
        // Depth 2 contacts
        let chris = try dataManager.createPerson(
            name: "Chris Evans",
            phone: "+1 (650) 555-0811",
            email: "chris.e@company.com",
            birthday: makeDate(month: 8, day: 22, year: 1988),
            notes: "David's manager.",
            isDemo: true,
            color: "#3498DB"
        )
        
        let sam = try dataManager.createPerson(
            name: "Sam Taylor",
            phone: "+1 (628) 555-0922",
            email: "sam.taylor@email.com",
            birthday: makeDate(month: 10, day: 5, year: 1995),
            notes: "Jake's teammate.",
            isDemo: true,
            color: "#2ECC71"
        )

        // Depth 3 contact
        let alex = try dataManager.createPerson(
            name: "Alex Jordan",
            phone: "+1 (415) 555-0344",
            email: "alex.j@email.com",
            birthday: makeDate(month: 2, day: 14, year: 1994),
            notes: "Sam's partner.",
            isDemo: true,
            color: "#F1C40F"
        )
        
        // ── Jake's Family Relationships ──
        
        // Jake & Nicole are spouses
        try dataManager.createRelationship(from: jake, to: nicole, type: .spouse, skipAutoAssign: true)
        
        // Jake is father of all three kids
        try dataManager.createRelationship(from: jake, to: liam, type: .father, skipAutoAssign: true)
        try dataManager.createRelationship(from: jake, to: ella, type: .father, skipAutoAssign: true)
        try dataManager.createRelationship(from: jake, to: noah, type: .father, skipAutoAssign: true)
        
        // Nicole is mother of all three kids
        try dataManager.createRelationship(from: nicole, to: liam, type: .mother, skipAutoAssign: true)
        try dataManager.createRelationship(from: nicole, to: ella, type: .mother, skipAutoAssign: true)
        try dataManager.createRelationship(from: nicole, to: noah, type: .mother, skipAutoAssign: true)
        
        // Liam, Ella, and Noah are siblings
        try dataManager.createRelationship(from: liam, to: ella, type: .sibling, skipAutoAssign: true)
        try dataManager.createRelationship(from: liam, to: noah, type: .sibling, skipAutoAssign: true)
        try dataManager.createRelationship(from: ella, to: noah, type: .sibling, skipAutoAssign: true)
        
        // Book club friends (connected through Emma, not directly to Me)
        try dataManager.createRelationship(from: emma, to: mia, type: .friend, skipAutoAssign: true)
        try dataManager.createRelationship(from: emma, to: ryan, type: .friend, skipAutoAssign: true)
        
        // Mia and Ryan know each other
        try dataManager.createRelationship(from: mia, to: ryan, type: .friend, skipAutoAssign: true)
        
        // Multi-level connections (Depth 2 & 3)
        try dataManager.createRelationship(from: david, to: chris, type: .coworker, skipAutoAssign: true)
        try dataManager.createRelationship(from: jake, to: sam, type: .friend, skipAutoAssign: true)
        try dataManager.createRelationship(from: sam, to: alex, type: .partner, skipAutoAssign: true)
        
        // ── Explicit Circle Assignments ──
        // Single pond per contact: each contact belongs to exactly one pond.
        
        if let familyCircle {
            try dataManager.addToCircle(sarah, circle: familyCircle)
            try dataManager.addToCircle(mom, circle: familyCircle)
            try dataManager.addToCircle(dad, circle: familyCircle)
            try dataManager.addToCircle(tom, circle: familyCircle)
            try dataManager.addToCircle(nicole, circle: familyCircle)
            try dataManager.addToCircle(liam, circle: familyCircle)
            try dataManager.addToCircle(ella, circle: familyCircle)
            try dataManager.addToCircle(noah, circle: familyCircle)
        }
        if let friendsCircle {
            try dataManager.addToCircle(jake, circle: friendsCircle)
            try dataManager.addToCircle(emma, circle: friendsCircle)
            try dataManager.addToCircle(sam, circle: friendsCircle)
            try dataManager.addToCircle(alex, circle: friendsCircle)
            try dataManager.addToCircle(mia, circle: friendsCircle)
            try dataManager.addToCircle(ryan, circle: friendsCircle)
        }
        if let proCircle {
            try dataManager.addToCircle(david, circle: proCircle)
            try dataManager.addToCircle(lisa, circle: proCircle)
            try dataManager.addToCircle(chris, circle: proCircle)
        }
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
