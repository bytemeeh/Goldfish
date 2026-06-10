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

    /// Seeds 10 demo contacts that exercise every key use case at a glance:
    /// - 3 ponds with members (Family ×3, Friends ×4, Professional ×2)
    /// - A connected family cluster with parent/sibling/spouse links between non-Me contacts
    /// - Second-degree contacts (reachable only through another contact, not Me)
    /// - 2 favorites, 2 near-future birthdays, varied relationship types
    /// - Exactly one unlinked contact (no relationships, no pond) for the "Unlinked" section
    ///
    /// Safe to call multiple times — checks if demo data already exists.
    /// Returns `true` if demo data was fully seeded, `false` if skipped (e.g. Me doesn't exist yet).
    @discardableResult
    func seedDemoData() throws -> Bool {
        // Require the "Me" contact to exist — relationships are anchored to Me.
        guard let me = try dataManager.fetchMePerson() else { return false }

        let existing = try dataManager.fetchAllPersons()
        let demoPersons = existing.filter { $0.isDemo }

        if !demoPersons.isEmpty {
            // Check if seeding was incomplete (contacts exist but no relationships).
            // This repairs orphaned demo contacts from prior interrupted seeding.
            let hasRelationships = demoPersons.contains { !$0.allRelationships.isEmpty }
            if hasRelationships {
                // Contacts + relationships exist, but verify circle assignments (ponds).
                // If any connected demo contact is missing a circle, repair them all.
                // Contacts without relationships are intentionally unlinked (no pond)
                // and must NOT trigger or receive repair.
                let missingCircles = demoPersons.contains { person in
                    !person.isMe
                        && !person.allRelationships.isEmpty
                        && person.circleContacts.filter({ !$0.manuallyExcluded }).isEmpty
                }
                if missingCircles {
                    try repairCircleAssignments(demoPersons: demoPersons)
                }
                return true // Fully seeded (with repaired circles if needed)
            }
            // Incomplete — clean up orphaned contacts so we can re-seed properly
            for person in demoPersons {
                dataManager.context.delete(person)
            }
            try dataManager.context.save()
        }

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

        // Family — a connected cluster: Rosa & Miguel are spouses and the
        // parents of both Me and Diego, so the graph shows depth beyond
        // a simple star around Me.
        let rosa = try dataManager.createPerson(
            name: "Rosa Alvarez",
            phone: "+1 (312) 555-0198",
            email: "rosa.alvarez@email.com",
            notes: "Mom. Calls every Sunday. Makes the best paella in the family.",
            isDemo: true,
            isFavorite: true,
            color: "#FF6B6B"
        )

        let miguel = try dataManager.createPerson(
            name: "Miguel Alvarez",
            phone: "+1 (312) 555-0199",
            email: "miguel.alvarez@email.com",
            isDemo: true,
            color: "#E0584C"
        )

        let diego = try dataManager.createPerson(
            name: "Diego Alvarez",
            phone: "+1 (312) 555-0177",
            email: "diego.alvarez@email.com",
            birthday: upcomingBirthday(inDays: 19, age: 26),
            isDemo: true,
            color: "#F0907F"
        )

        // Friends — includes a second-degree contact (Jordan is Priya's
        // partner, not directly linked to Me) and a friend-of-friend link.
        let priya = try dataManager.createPerson(
            name: "Priya Sharma",
            phone: "+1 (415) 555-0142",
            email: "priya.sharma@email.com",
            birthday: upcomingBirthday(inDays: 4, age: 31),
            notes: "Climbing partner. Training for her first marathon.",
            isDemo: true,
            isFavorite: true,
            color: "#4ECDC4"
        )

        let jordan = try dataManager.createPerson(
            name: "Jordan Lee",
            phone: "+1 (415) 555-0143",
            email: "jordan.lee@email.com",
            isDemo: true,
            color: "#7FD8CD"
        )

        let tunde = try dataManager.createPerson(
            name: "Tunde Okafor",
            phone: "+1 (510) 555-0167",
            email: "tunde.okafor@email.com",
            isDemo: true,
            color: "#2FA89C"
        )

        let lena = try dataManager.createPerson(
            name: "Lena Fischer",
            phone: "+1 (628) 555-0134",
            email: "lena.fischer@email.com",
            isDemo: true,
            color: "#5ABEAF"
        )

        // Professional
        let ingrid = try dataManager.createPerson(
            name: "Ingrid Johansson",
            phone: "+1 (650) 555-0189",
            email: "ingrid.j@company.com",
            isDemo: true,
            color: "#45B7D1"
        )

        let kenji = try dataManager.createPerson(
            name: "Kenji Tanaka",
            phone: "+1 (408) 555-0156",
            email: "kenji.tanaka@company.com",
            isDemo: true,
            color: "#5AC1D8"
        )

        // Unlinked — exactly one contact with no relationships and no pond,
        // so the "Unlinked" section and edge-float behavior are visible.
        // Intentionally given no relationships and no circle assignment below.
        try dataManager.createPerson(
            name: "Maya Castillo",
            phone: "+1 (213) 555-0121",
            email: "maya.castillo@email.com",
            notes: "Met at a design conference — still need to connect her.",
            isDemo: true,
            color: "#B8A9D9"
        )

        // ── Create Relationships ──
        // skipAutoAssign: true — circle assignments are handled explicitly below

        // Family cluster (Me + parents + brother)
        try dataManager.createRelationship(from: rosa, to: me, type: .mother, skipAutoAssign: true)
        try dataManager.createRelationship(from: miguel, to: me, type: .father, skipAutoAssign: true)
        try dataManager.createRelationship(from: me, to: diego, type: .sibling, skipAutoAssign: true)

        // Rosa & Miguel are also Diego's parents, and spouses of each other
        try dataManager.createRelationship(from: rosa, to: diego, type: .mother, skipAutoAssign: true)
        try dataManager.createRelationship(from: miguel, to: diego, type: .father, skipAutoAssign: true)
        try dataManager.createRelationship(from: rosa, to: miguel, type: .spouse, skipAutoAssign: true)

        // Friends (from Me)
        try dataManager.createRelationship(from: me, to: priya, type: .friend, skipAutoAssign: true)
        try dataManager.createRelationship(from: me, to: tunde, type: .friend, skipAutoAssign: true)
        try dataManager.createRelationship(from: me, to: lena, type: .friend, skipAutoAssign: true)

        // Priya and Lena are friends with each other
        try dataManager.createRelationship(from: priya, to: lena, type: .friend, skipAutoAssign: true)

        // Jordan is Priya's partner — connected only through Priya, not Me
        try dataManager.createRelationship(from: priya, to: jordan, type: .partner, skipAutoAssign: true)

        // Professional (from Me), plus a coworker link between colleagues
        try dataManager.createRelationship(from: me, to: ingrid, type: .coworker, skipAutoAssign: true)
        try dataManager.createRelationship(from: me, to: kenji, type: .coworker, skipAutoAssign: true)
        try dataManager.createRelationship(from: ingrid, to: kenji, type: .coworker, skipAutoAssign: true)

        // ── Explicit Circle Assignments ──
        // Single circle per contact: each contact belongs to exactly one circle.
        // Maya is deliberately left out of every circle (the unlinked showcase).

        if let familyCircle {
            try dataManager.addToCircle(rosa, circle: familyCircle)
            try dataManager.addToCircle(miguel, circle: familyCircle)
            try dataManager.addToCircle(diego, circle: familyCircle)
        }

        if let friendsCircle {
            try dataManager.addToCircle(priya, circle: friendsCircle)
            try dataManager.addToCircle(jordan, circle: friendsCircle)
            try dataManager.addToCircle(tunde, circle: friendsCircle)
            try dataManager.addToCircle(lena, circle: friendsCircle)
        }

        if let proCircle {
            try dataManager.addToCircle(ingrid, circle: proCircle)
            try dataManager.addToCircle(kenji, circle: proCircle)
        }

        // Force final synchronous commit to ensure all relationships
        // and circle memberships are persisted before UI initialization
        try dataManager.context.save()

        return true
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

    /// Repairs missing circle (pond) assignments for demo contacts.
    /// Uses `RelationshipType.autoCircleName` to determine the correct circle,
    /// keeping this in sync with the auto-assignment logic in `GoldfishDataManager`.
    /// Contacts without any relationships are skipped — they are intentionally
    /// unlinked (no pond) so the "Unlinked" showcase survives repair passes.
    func repairCircleAssignments(demoPersons: [Person]) throws {
        let circles = try dataManager.fetchAllCircles()
        let circlesByName = Dictionary(uniqueKeysWithValues: circles.map { ($0.name, $0) })

        for person in demoPersons {
            guard !person.isMe else { continue }
            // Intentionally unlinked contacts stay out of every pond
            guard !person.allRelationships.isEmpty else { continue }
            let hasCircle = person.circleContacts.contains { !$0.manuallyExcluded }
            guard !hasCircle else { continue }

            // Find the first relationship with a known autoCircleName
            let targetCircleName = person.allRelationships.lazy
                .compactMap { rel -> String? in
                    let relType = RelationshipType(rawValue: rel.typeRawValue)
                    return relType?.autoCircleName
                }
                .first

            if let name = targetCircleName, let circle = circlesByName[name] {
                try dataManager.addToCircle(person, circle: circle)
            } else if let fallback = circlesByName["Friends"] {
                // Contacts with only .other relationships get Friends as fallback
                try dataManager.addToCircle(person, circle: fallback)
            }
        }

        try dataManager.context.save()
    }

    /// Returns a birthday whose month/day falls `inDays` days in the future,
    /// with a birth year making the contact roughly `age` years old.
    /// Keeps demo birthdays perpetually "upcoming" so any birthday UI
    /// always has something to show, regardless of when the demo is seeded.
    private func upcomingBirthday(inDays days: Int, age: Int) -> Date? {
        let calendar = Calendar.current
        let now = Date()
        guard let upcoming = calendar.date(byAdding: .day, value: days, to: now) else { return nil }
        var components = calendar.dateComponents([.month, .day], from: upcoming)
        components.year = calendar.component(.year, from: now) - age
        return calendar.date(from: components)
    }
}
