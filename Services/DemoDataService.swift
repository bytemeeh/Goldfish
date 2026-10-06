import Foundation

#if DEBUG
extension DemoDataService {
    /// An isolated review fixture. The caller must supply a new in-memory store.
    /// Uses the real repositories so review interactions exercise real persistence.
    func seedQualityReviewNetwork() throws {
        guard try dataManager.fetchAllPersons().allSatisfy({ $0.isMe }) else {
            throw GoldfishError.invalidName
        }
        try dataManager.performAtomicEdit {
            guard try seedDemoData() else { throw GoldfishError.contactNotFound }
            let existingGroups = try dataManager.fetchAllCircles()
            let walking = try existingGroups.first { $0.name == "Design & Research Collective" }
                ?? dataManager.createCircle(name: "Design & Research Collective", color: "#587B67", emoji: "")
            let groups = try dataManager.fetchAllCircles()
            let original = try dataManager.fetchAllPersons().filter { $0.isDemo }
            let professional = groups.first { $0.name == "Professional" } ?? walking
            let bookClub = groups.first { $0.name == "Book Club" } ?? walking
            let designResearch = walking
            let professionalAnchor = original.first { $0.name == "David Park" }
            let bookClubAnchor = original.first { $0.name == "Emma Wilson" }
            let designAnchor = original.first { $0.name == "Alex Jordan" }
            let names = [
                "Morgan Reyes", "Alexandra Montgomery-Wellington", "Sofia García", "Léa Dubois",
                "Emil Schneider", "Yuki Tanaka", "田中 花子", "محمد حسن",
                "Amara Okafor", "Nora Andersen", "Gabriel Silva", "Maya Desai",
                "Oliver Davies", "Hannah Fischer", "Elena Rossi", "Lucas Martin",
                "Isabel Costa", "Theo Williams", "Aisha Khan", "Daniel Kim",
                "Freya Jensen", "Mateo Fernández", "Zoe Wilson", "Noah Brown",
                "Iris van der Meer", "Oscar Berg", "Fatima Ali", "Louis Bernard",
                "Clara Müller", "Arjun Patel", "Mara Stein", "Jonas Keller"
            ]
            for (index, name) in names.prefix(27).enumerated() {
                let cohort: (circle: GoldfishCircle, anchor: Person?, relationship: RelationshipType?, note: String, tag: String)
                switch index {
                case 0..<10:
                    cohort = (professional, professionalAnchor, .coworker,
                              "A professional colleague in David Park's network.", "Professional network")
                case 10..<18:
                    cohort = (bookClub, bookClubAnchor, .friend,
                              "A book-club connection I know through Emma Wilson.", "Book club")
                case 18..<30:
                    cohort = (designResearch, designAnchor, .friend,
                              "A design and research collaborator in Alex Jordan's network.", "Design research")
                default:
                    cohort = (designResearch, nil, nil,
                              "An independent contact from a local design meetup who studies accessible tools.", "Independent contact")
                }
                let person = try dataManager.createPerson(
                    name: name,
                    email: "sample\(index)@example.com",
                    notes: index == 1
                        ? "David works with Alexandra on accessibility research for public services. He recommended her after their team found that an early prototype relied too heavily on color. Her review helped them add clear labels, keyboard paths, and room for larger text.\n\nDavid says she keeps a running list of questions from participants and checks translated labels with native speakers. In their latest study, several people understood the wording but could not tell which action had completed. The team added a short confirmation and an obvious way to correct a mistake. Alexandra followed up with the same participants to see whether that helped.\n\nShe also belongs to a group that exchanges multilingual research methods. I would like to ask David for an introduction when our next study is ready. Useful topics to discuss: recruiting people who use screen readers, writing consent forms in plain language, and leaving enough time for participants to explain what confused them."
                        : cohort.note,
                    isDemo: true,
                    tags: [cohort.tag],
                    city: index.isMultiple(of: 2) ? "Zurich" : "London"
                )
                if let anchor = cohort.anchor, let relationship = cohort.relationship {
                    try dataManager.createRelationship(from: anchor, to: person,
                                                        type: relationship,
                                                        skipAutoAssign: true)
                }
                try dataManager.addToCircle(person, circle: cohort.circle)
            }
        }
    }
    /// Fifty fictional contacts, including the approved ripple example, a dense
    /// branch, shared contacts, a cycle, and two disconnected people.
    func seedRippleReviewNetwork() throws {
        guard try dataManager.fetchAllPersons().allSatisfy({ $0.isMe }),
              let me = try dataManager.fetchMePerson() else { throw GoldfishError.invalidName }
        try dataManager.performAtomicEdit {
            try dataManager.createSystemCircles()
            let groups = try dataManager.fetchAllCircles()
            let family = groups.first { $0.name == "Family" }!
            let friends = groups.first { $0.name == "Friends" }!
            let choir = try groups.first { $0.name == "Community Choir" }
                ?? dataManager.createCircle(name: "Community Choir", color: "#587B67", emoji: "🎶")
            @MainActor func person(_ name: String, pond: GoldfishCircle, age: Int? = nil, pet: String? = nil, notes: String) throws -> Person {
                let birthday = age.flatMap { Calendar.current.date(byAdding: .year, value: -$0, to: Date()) }
                let contact = try dataManager.createPerson(name: name, birthday: birthday,
                                                          notes: notes, isDemo: true)
                if let pet { try dataManager.updatePerson(contact, petKindRaw: .set(pet)) }
                try dataManager.addToCircle(contact, circle: pond)
                return contact
            }
            let alex = try person("Alex", pond: family, age: 55, notes: "My sibling; helps organize family gatherings.")
            let anna = try person("Anna", pond: family, age: 54, notes: "Alex's partner; they co-parent Lea and Max.")
            let lea = try person("Lea", pond: family, age: 9, notes: "Alex and Anna's child; she loves drawing and school stories.")
            let max = try person("Max", pond: family, age: 29, notes: "Alex and Anna's son; Nora's partner and a friend of Sam.")
            let biscuit = try person("Biscuit", pond: family, pet: "dog", notes: "Alex and Anna's dog; one of their family pets.")
            let nora = try person("Nora", pond: family, age: 29, notes: "Max's partner; she organizes a community choir.")
            let sam = try person("Sam", pond: friends, notes: "Max's friend; shares a flat with Jo and their cat Pip.")
            let milo = try person("Milo", pond: family, pet: "dog", notes: "Max and Nora's dog; one of their shared family pets.")
            let jo = try person("Jo", pond: friends, notes: "Sam's friend and housemate; Ben's sibling.")
            let pip = try person("Pip", pond: friends, pet: "cat", notes: "Sam and Jo's cat; shares their home.")
            let links: [(Person, Person, RelationshipType)] = [
                (me, alex, .sibling), (alex, anna, .partner),
                (alex, lea, .parent), (anna, lea, .parent),
                (alex, max, .parent), (anna, max, .parent), (lea, max, .sibling),
                (biscuit, alex, .pet), (biscuit, anna, .pet),
                (max, nora, .partner), (max, sam, .friend),
                (milo, max, .pet), (milo, nora, .pet),
                (sam, jo, .friend), (pip, sam, .pet), (pip, jo, .pet)
            ]
            for (from, to, type) in links {
                try dataManager.createRelationship(from: from, to: to, type: type, skipAutoAssign: true)
            }
            let names = [
                "Alexandra Montgomery-Wellington", "田中 花子", "Ben", "Sofia Alvarez",
                "Léa Dubois", "Emil Schneider", "Yuki Tanaka", "محمد حسن",
                "Amara Okafor", "Gabriel Silva", "Maya Desai", "Oliver Davies",
                "Hannah Fischer", "Elena Rossi", "Lucas Martin", "Isabel Costa",
                "Theo Williams", "Aisha Khan", "Daniel Kim", "Freya Jensen",
                "Mateo Fernández", "Zoe Wilson", "Noah Brown", "Iris van der Meer",
                "Oscar Berg", "Fatima Ali", "Louis Bernard", "Clara Müller",
                "Arjun Patel", "Samuel Okoye", "Priyanka Shah", "Jules Laurent",
                "Camila Torres", "Rowan Blake", "Noor Rahman", "Elise Martin",
                "Hugo Weber", "Valentina Cruz", "Ada Fischer", "Felix Baumann"
            ]
            for index in 1...40 {
                let name = names[index - 1]
                let isBen = index == 3
                let note: String
                if isBen {
                    note = "Jo's sibling; also sings in Nora's community choir."
                } else if index == 39 {
                    note = "A pianist whose details I saved from the community choir's concert programme."
                } else if index == 40 {
                    note = "A local music teacher whose details I saved from the community choir's noticeboard."
                } else {
                    note = "A community choir member who rehearses with Nora."
                }
                let contact = try person(name, pond: isBen ? friends : choir, notes: note)
                if index == 3 {
                    try dataManager.createRelationship(from: jo, to: contact, type: .sibling, skipAutoAssign: true)
                }
                if index <= 38 {
                    try dataManager.createRelationship(from: nora, to: contact, type: .friend, skipAutoAssign: true)
                }
            }
        }
    }
}
#endif
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

    /// Seeds demo contacts with relationships and circle memberships.
    /// Safe to call multiple times:
    /// - If no demo data exists yet, creates contacts + relationships + circle assignments.
    /// - If demo contacts exist but have no circle assignments (e.g. from an interrupted
    ///   previous seed), re-applies the assignments without re-creating contacts.
    @discardableResult
    func seedDemoData() throws -> Bool {
        guard let me = try dataManager.fetchMePerson() else { return false }
        // Keep the fixture as one transaction. Every repository operation is
        // atomic on its own, so without this outer edit an interrupted seed can
        // leave a partial fixture that later calls mistake for a complete one.
        let seeded = try dataManager.performAtomicEdit {
            try seedDemoData(me: me)
        }
        if seeded {
            let key = daycareSeedMarkerKey(me.id)
            dataManager.afterCurrentAtomicEditCommits {
                UserDefaults.standard.set(true, forKey: key)
            }
        }
        return seeded
    }

    /// Applies only known corrections to retained sample contacts. This is used
    /// on launches where the sample context already exists, so it must never
    /// create a second fixture or require the full seed cardinality.
    func updateExistingDemoContexts() throws {
        guard let me = try dataManager.fetchMePerson() else { return }
        var hadDemoPersons = false
        try dataManager.performAtomicEdit {
            let demoPersons = try dataManager.fetchAllPersons().filter { $0.isDemo }
            hadDemoPersons = !demoPersons.isEmpty
            try repairKnownLegacyDemoData(me: me, demoPersons: demoPersons)
            try seedDaycareClusterIfNeeded(me: me, demoPersons: demoPersons)
        }
        if hadDemoPersons {
            let key = daycareSeedMarkerKey(me.id)
            dataManager.afterCurrentAtomicEditCommits {
                UserDefaults.standard.set(true, forKey: key)
            }
        }
    }

    private func daycareSeedMarkerKey(_ meID: UUID) -> String {
        "demo.daycare-cluster.v1.\(meID.uuidString)"
    }

    private func seedDemoData(me: Person) throws -> Bool {

        // Ensure system circles exist (may not yet if called before onboarding)
        let existingCircles = try dataManager.fetchAllCircles()
        let requiredSystemNames = Set(["Family", "Friends", "Professional"])
        let existingSystemNames = Set(existingCircles.filter(\.isSystem).map(\.name))
        if !requiredSystemNames.isSubset(of: existingSystemNames) {
            try dataManager.createSystemCircles()
        }

        // Check for existing demo data
        let existing = try dataManager.fetchAllPersons()
        let hasDemoData = existing.contains { $0.isDemo }

        if hasDemoData {
            // Repair retained fixtures before deciding whether this is a complete
            // seed. The repair is fingerprinted and safe to repeat.
            let demoPersons = existing.filter { $0.isDemo }
            try repairKnownLegacyDemoData(me: me, demoPersons: demoPersons)
            // A partial seed must not be reported as usable. Names remain
            // editable, so use the fixture's expected cardinality rather than
            // rejecting a retained contact whose name was changed by the user.
            guard demoPersons.count >= 18 else { return false }
            let hasAssignments = demoPersons.contains { !$0.circleContacts.filter { !$0.manuallyExcluded }.isEmpty }
            if hasAssignments {
                try seedDaycareClusterIfNeeded(me: me, demoPersons: demoPersons)
                return true
            }
            let assigned = try applyCircleAssignments(for: demoPersons)
            if assigned { try seedDaycareClusterIfNeeded(me: me, demoPersons: demoPersons) }
            return assigned
        }

        // Fetch circles for assignment
        let circles = try dataManager.fetchAllCircles()
        let familyCircle = circles.first { $0.isSystem && $0.name == "Family" }
            ?? circles.first { $0.isSystem && $0.shouldAutoAssign(for: .parent) }
        let friendsCircle = circles.first { $0.isSystem && $0.name == "Friends" }
            ?? circles.first { $0.isSystem && $0.shouldAutoAssign(for: .friend) }
        let proCircle = circles.first { $0.isSystem && $0.name == "Professional" }
            ?? circles.first { $0.isSystem && $0.shouldAutoAssign(for: .coworker) }

        // Custom (user-style) pond — demonstrates that ponds aren't limited to the
        // three system circles. The walkthrough's "ponds" step shows this off, and
        // removeDemoData() removes its demo members while preserving the circle.
        let bookClubCircle = try circles.first { $0.name == "Book Club" }
            ?? dataManager.createCircle(name: "Book Club", color: "#9B59B6", emoji: "📚")
        
        // ── Create Demo Contacts ──
        
        let sarah = try dataManager.createPerson(
            name: "Sarah Chen",
            phone: "+1 (415) 555-0142",
            email: "sarah.chen@email.com",
            birthday: makeDate(month: 3, day: 15, year: 1992),
            notes: "My spouse; we hike and take photos together.",
            isDemo: true,
            color: "#E8857A",
            street: "1100 Hayes St",
            city: "San Francisco",
            state: "CA",
            country: "United States",
            postalCode: "94117"
        )
        
        let mom = try dataManager.createPerson(
            name: "Linda Miller",
            phone: "+1 (312) 555-0198",
            email: "linda.m@email.com",
            birthday: makeDate(month: 7, day: 22, year: 1960),
            notes: "My mom; we talk every Sunday.",
            isDemo: true,
            color: "#FF6B6B"
        )
        
        let dad = try dataManager.createPerson(
            name: "Robert Miller",
            phone: "+1 (312) 555-0199",
            email: "robert.miller@email.com",
            birthday: makeDate(month: 11, day: 8, year: 1958),
            notes: "My dad; he enjoys woodworking and jazz.",
            isDemo: true,
            color: "#D4574A"
        )
        
        let jake = try dataManager.createPerson(
            name: "Jake Morrison",
            phone: "+1 (628) 555-0167",
            email: "jake.m@email.com",
            birthday: makeDate(month: 5, day: 3, year: 1994),
            notes: "A college friend; Jake and Nicole are raising three children and enjoy weekend trips.",
            isDemo: true,
            isFavorite: true,
            color: "#4ECDC4",
            street: "207 Rainey St",
            city: "Austin",
            state: "TX",
            country: "United States",
            postalCode: "78701"
        )
        
        // ── Jake's household ──
        
        let nicole = try dataManager.createPerson(
            name: "Nicole Morrison",
            phone: "+1 (628) 555-0168",
            email: "nicole.m@email.com",
            birthday: makeDate(month: 7, day: 3, year: 1995),
            notes: "Jake's spouse; a graphic designer who loves pasta making and farmers markets.",
            isDemo: true,
            isFavorite: true,
            color: "#E8A87C"
        )
        
        let liam = try dataManager.createPerson(
            name: "Liam Morrison",
            phone: nil,
            email: nil,
            birthday: makeDate(month: 9, day: 12, year: 2018),
            notes: "Jake and Nicole's oldest child; loves dinosaurs, Lego, and little league.",
            isDemo: true,
            color: "#85DCBA"
        )
        
        let ella = try dataManager.createPerson(
            name: "Ella Morrison",
            phone: nil,
            email: nil,
            birthday: makeDate(month: 3, day: 21, year: 2021),
            notes: "Jake and Nicole's middle child; takes ballet and loves drawing rainbows.",
            isDemo: true,
            color: "#F6C3B7"
        )
        
        let noah = try dataManager.createPerson(
            name: "Noah Morrison",
            phone: nil,
            email: nil,
            birthday: makeDate(month: 12, day: 8, year: 2025),
            notes: "Jake and Nicole's youngest child; already has Jake's smile.",
            isDemo: true,
            color: "#B5EAD7"
        )
        
        let emma = try dataManager.createPerson(
            name: "Emma Wilson",
            phone: "+1 (510) 555-0134",
            email: "emma.wilson@email.com",
            birthday: makeDate(month: 9, day: 28, year: 1993),
            notes: "My book-club friend; she recommends great reads.",
            isDemo: true,
            color: "#5ABEAF"
        )
        
        let david = try dataManager.createPerson(
            name: "David Park",
            phone: "+1 (650) 555-0189",
            email: "david.park@company.com",
            birthday: makeDate(month: 1, day: 14, year: 1990),
            notes: "My team lead; a thoughtful mentor at work.",
            isDemo: true,
            color: "#45B7D1",
            street: "3400 Hillview Ave",
            city: "Palo Alto",
            state: "CA",
            country: "United States",
            postalCode: "94304"
        )
        
        let lisa = try dataManager.createPerson(
            name: "Lisa Thompson",
            phone: "+1 (408) 555-0156",
            email: "lisa.t@company.com",
            birthday: makeDate(month: 12, day: 1, year: 1991),
            notes: "David's colleague; she works on the design team.",
            isDemo: true,
            color: "#5AC1D8"
        )
        
        let tom = try dataManager.createPerson(
            name: "Tom Miller",
            phone: "+1 (312) 555-0177",
            email: "tom.miller@email.com",
            birthday: makeDate(month: 4, day: 19, year: 1996),
            notes: "My sibling; studying engineering.",
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
        try dataManager.createRelationship(from: me, to: emma, type: .friend, skipAutoAssign: true)
        
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
            notes: "My book-club connection through Emma; she organizes our meetings.",
            isDemo: true,
            color: "#9B59B6"
        )
        
        let ryan = try dataManager.createPerson(
            name: "Ryan O'Brien",
            phone: "+1 (415) 555-0202",
            email: "ryan.ob@email.com",
            birthday: makeDate(month: 2, day: 28, year: 1991),
            notes: "My book-club connection through Emma; he enjoys science fiction.",
            isDemo: true,
            color: "#8E44AD"
        )
        
        // Depth 2 contacts
        let chris = try dataManager.createPerson(
            name: "Chris Evans",
            phone: "+1 (650) 555-0811",
            email: "chris.e@company.com",
            birthday: makeDate(month: 8, day: 22, year: 1988),
            notes: "David's colleague; he works with David on our company team.",
            isDemo: true,
            color: "#3498DB"
        )
        
        let sam = try dataManager.createPerson(
            name: "Sam Taylor",
            phone: "+1 (628) 555-0922",
            email: "sam.taylor@email.com",
            birthday: makeDate(month: 10, day: 5, year: 1995),
            notes: "A friend from Jake's network; we trade ideas about weekend projects.",
            isDemo: true,
            color: "#2ECC71"
        )

        // Depth 3 contact
        let alex = try dataManager.createPerson(
            name: "Alex Jordan",
            phone: "+1 (415) 555-0344",
            email: "alex.j@email.com",
            birthday: makeDate(month: 2, day: 14, year: 1994),
            notes: "Sam's partner; I know Alex through Jake's network.",
            isDemo: true,
            color: "#F1C40F"
        )

        // Deliberately unconnected contact — the drag-to-link walkthrough step asks
        // the user to connect this person to "Me". Left with no relationships and no
        // pond so it floats free in the graph as an obvious, grabbable target.
        let priya = try dataManager.createPerson(
            name: "Priya Patel",
            phone: "+1 (415) 555-0455",
            email: "priya.patel@email.com",
            birthday: makeDate(month: 8, day: 30, year: 1993),
            notes: "Met at a design conference. Interested in accessible design.",
            isDemo: true,
            color: "#E67E22"
        )
        _ = priya // referenced by the walkthrough; no seeded relationships/pond by design


        // ── Jake's household relationships ──
        
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
        
        // Book club friends (Mia and Ryan are connected through Emma)
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
        }
        if let friendsCircle {
            try dataManager.addToCircle(jake, circle: friendsCircle)
            try dataManager.addToCircle(nicole, circle: friendsCircle)
            try dataManager.addToCircle(liam, circle: friendsCircle)
            try dataManager.addToCircle(ella, circle: friendsCircle)
            try dataManager.addToCircle(noah, circle: friendsCircle)
            try dataManager.addToCircle(sam, circle: friendsCircle)
            try dataManager.addToCircle(alex, circle: friendsCircle)
        }
        if let proCircle {
            try dataManager.addToCircle(david, circle: proCircle)
            try dataManager.addToCircle(lisa, circle: proCircle)
            try dataManager.addToCircle(chris, circle: proCircle)
        }
        // Book Club — a custom pond drawn from across the network (Emma is a friend,
        // Mia & Ryan come in through her). Demonstrates ponds beyond the system three.
        try dataManager.addToCircle(emma, circle: bookClubCircle)
        try dataManager.addToCircle(mia, circle: bookClubCircle)
        try dataManager.addToCircle(ryan, circle: bookClubCircle)
        try seedDaycareClusterIfNeeded(me: me, demoPersons: [
            sarah, mom, dad, jake, nicole, liam, ella, noah, emma, david, lisa, tom,
            mia, ryan, chris, sam, alex, priya
        ])
        return true
    }

    /// A deterministic identity makes retries idempotent and lets retained fixtures
    /// distinguish a user-deleted cluster member from a contact that was never seeded.
    /// The existing Daycare pond also acts as a conservative tombstone if every member
    /// is later deleted; no new schema field is needed.
    private func seedDaycareClusterIfNeeded(me: Person, demoPersons: [Person]) throws {
        guard !UserDefaults.standard.bool(forKey: daycareSeedMarkerKey(me.id)) else { return }
        let expectedNames: Set<String> = [
            "Sarah Chen", "Linda Miller", "Robert Miller", "Jake Morrison", "Nicole Morrison",
            "Liam Morrison", "Ella Morrison", "Noah Morrison", "Emma Wilson", "David Park",
            "Lisa Thompson", "Tom Miller", "Mia Rodriguez", "Ryan O'Brien", "Chris Evans",
            "Sam Taylor", "Alex Jordan", "Priya Patel"
        ]
        guard Set(demoPersons.map(\.name)).isSuperset(of: expectedNames),
              let sarah = demoPersons.first(where: { $0.name == "Sarah Chen" }),
              me.allRelationships.contains(where: {
                  $0.type == .spouse
                      && (($0.fromContact.id == me.id && $0.toContact.id == sarah.id)
                          || ($0.fromContact.id == sarah.id && $0.toContact.id == me.id))
              })
        else { return }
        let ids = [
            UUID(uuidString: "8A8B6B00-5C3E-4E62-9F21-000000000001")!,
            UUID(uuidString: "8A8B6B00-5C3E-4E62-9F21-000000000002")!,
            UUID(uuidString: "8A8B6B00-5C3E-4E62-9F21-000000000003")!,
            UUID(uuidString: "8A8B6B00-5C3E-4E62-9F21-000000000004")!,
            UUID(uuidString: "8A8B6B00-5C3E-4E62-9F21-000000000005")!
        ]
        let persons = try dataManager.fetchAllPersons()
        guard ids.allSatisfy({ id in !persons.contains(where: { $0.id == id }) }) else { return }
        let circles = try dataManager.fetchAllCircles()
        // The known standard seed is identified by its complete original set plus
        // the stable Me-to-Sarah spouse edge. Me itself is not part of demoPersons.
        let family = circles.first(where: { $0.isSystem && $0.name == "Family" })
            ?? circles.first(where: { $0.isSystem && $0.shouldAutoAssign(for: .parent) })
        guard let family else { return }
        let daycare: GoldfishCircle
        if let existing = circles.first(where: { $0.name == "Daycare" }) {
            // Reuse only the pond this sample created. A user-created pond with
            // the same name remains outside the sample upgrade.
            guard UserDefaults.standard.string(forKey: daycarePondKey(me.id)) == existing.id.uuidString else { return }
            daycare = existing
        } else {
            daycare = try dataManager.createCircle(name: "Daycare", color: "#78A9A1", emoji: "🧸")
        }
        let adriana = Person(id: ids[0], name: "Adriana", notes: nil, isDemo: true)
        let riley = Person(id: ids[1], name: "Riley", notes: nil, isDemo: true)
        let zach = Person(id: ids[2], name: "Zach", notes: nil, isDemo: true)
        let aaron = Person(id: ids[3], name: "Aaron", notes: nil, isDemo: true)
        let selma = Person(id: ids[4], name: "Selma", notes: nil, isDemo: true)
        for person in [adriana, riley, zach, aaron, selma] { dataManager.context.insert(person) }
        try dataManager.createRelationship(from: adriana, to: me, type: .child, skipAutoAssign: true)
        try dataManager.createRelationship(from: adriana, to: riley, type: .friend, skipAutoAssign: true)
        try dataManager.createRelationship(from: zach, to: riley, type: .parent, skipAutoAssign: true)
        try dataManager.createRelationship(from: aaron, to: riley, type: .parent, skipAutoAssign: true)
        try dataManager.createRelationship(from: selma, to: adriana, type: .caregiver, skipAutoAssign: true)
        try dataManager.addToCircle(adriana, circle: family)
        for person in [riley, zach, aaron, selma] { try dataManager.addToCircle(person, circle: daycare) }
        let markerKey = daycareSeedMarkerKey(me.id)
        let pondKey = daycarePondKey(me.id)
        dataManager.afterCurrentAtomicEditCommits {
            UserDefaults.standard.set(true, forKey: markerKey)
            UserDefaults.standard.set(daycare.id.uuidString, forKey: pondKey)
        }
    }

    private func daycarePondKey(_ meID: UUID) -> String {
        "demo.daycare-pond.v1.\(meID.uuidString)"
    }

    // MARK: - Repair Circle Assignments

    /// Repairs only the unchanged legacy fixture. Every note update is guarded
    /// by its exact old value, so a later seed replay cannot overwrite a user's
    /// edits. Circle moves preserve active custom ponds and only move contacts
    /// still in the old Family assignment.
    private func repairKnownLegacyDemoData(me: Person, demoPersons: [Person]) throws {
        var byName: [String: Person] = [:]
        for person in demoPersons where byName[person.name] == nil {
            byName[person.name] = person
        }

        let noteUpdates: [(name: String, old: String, new: String)] = [
            ("Sarah Chen", "Loves hiking and photography. Met at college.",
             "My spouse; we hike and take photos together."),
            ("Linda Miller", "Mom. Calls every Sunday.",
             "My mom; we talk every Sunday."),
            ("Robert Miller", "Dad. Loves woodworking and jazz.",
             "My dad; he enjoys woodworking and jazz."),
            ("Jake Morrison", "College roommate. Married to Nicole, 3 kids. Always up for weekend trips and BBQs.",
             "A college friend; Jake and Nicole are raising three children and enjoy weekend trips."),
            ("Nicole Morrison", "Jake's wife. Graphic designer, loves pasta making and Saturday farmers markets.",
             "Jake's spouse; a graphic designer who loves pasta making and farmers markets."),
            ("Liam Morrison", "Jake & Nicole's oldest. Obsessed with dinosaurs and Lego. Plays little league.",
             "Jake and Nicole's oldest child; loves dinosaurs, Lego, and little league."),
            ("Ella Morrison", "Middle child. Taking ballet classes. Loves drawing rainbows.",
             "Jake and Nicole's middle child; takes ballet and loves drawing rainbows."),
            ("Noah Morrison", "The baby! Born Dec 2025. Already has his dad's smile.",
             "Jake and Nicole's youngest child; already has Jake's smile."),
            ("Emma Wilson", "Book club friend. Recommends great reads.",
             "My book-club friend; she recommends great reads."),
            ("David Park", "Team lead at work. Great mentor.",
             "My team lead; a thoughtful mentor at work."),
            ("Lisa Thompson", "Coworker. Works on the design team.",
             "David's colleague; she works on the design team."),
            ("Tom Miller", "Younger brother. Studying engineering.",
             "My sibling; studying engineering."),
            ("Mia Rodriguez", "Book club organizer. Loves mystery novels.",
             "My book-club connection through Emma; she organizes our meetings."),
            ("Ryan O'Brien", "Book club member. Sci-fi enthusiast.",
             "My book-club connection through Emma; he enjoys science fiction."),
            ("Chris Evans", "David's manager.",
             "David's colleague; he works with David on our company team."),
            ("Sam Taylor", "Jake's teammate.",
             "A friend from Jake's network; we trade ideas about weekend projects."),
            ("Alex Jordan", "Sam's partner.",
             "Sam's partner; I know Alex through Jake's network."),
            ("Priya Patel", "Met at a design conference. Not linked yet — try connecting her!",
             "Met at a design conference. Interested in accessible design."),
            ("Priya Patel", "Met at a design conference. Not linked yet - try connecting her!",
             "Met at a design conference. Interested in accessible design."),
            ("Priya Patel", "Met at a design conference. A sample contact for practicing connections.",
             "Met at a design conference. Interested in accessible design.")
        ]
        let legacyEmma = byName["Emma Wilson"]?.notes == "Book club friend. Recommends great reads."
        let oldFamilyNotes: [String: String] = [
            "Nicole Morrison": "Jake's wife. Graphic designer, loves pasta making and Saturday farmers markets.",
            "Liam Morrison": "Jake & Nicole's oldest. Obsessed with dinosaurs and Lego. Plays little league.",
            "Ella Morrison": "Middle child. Taking ballet classes. Loves drawing rainbows.",
            "Noah Morrison": "The baby! Born Dec 2025. Already has his dad's smile."
        ]
        let legacyFamilyIDs = Set(oldFamilyNotes.compactMap { name, note in
            byName[name]?.notes == note ? byName[name]?.id : nil
        })
        for update in noteUpdates {
            guard let person = byName[update.name], person.notes == update.old else { continue }
            try dataManager.updatePerson(person, notes: .set(update.new))
        }

        // The legacy fixture connected Emma only through Jake. Add the direct
        // friendship only while her legacy note still proves this is that fixture,
        // and never duplicate any existing Me/Emma relationship.
        if let emma = byName["Emma Wilson"], legacyEmma == true,
           !hasRelationship(between: me, and: emma) {
            try dataManager.createRelationship(from: me, to: emma, type: .friend, skipAutoAssign: true)
        }

        let circles = try dataManager.fetchAllCircles()
        if let family = circles.first(where: { $0.isSystem && $0.name == "Family" })
            ?? circles.first(where: { $0.isSystem && $0.shouldAutoAssign(for: .parent) }),
           let friends = circles.first(where: { $0.isSystem && $0.name == "Friends" })
            ?? circles.first(where: { $0.isSystem && $0.shouldAutoAssign(for: .friend) }) {
            for person in demoPersons where legacyFamilyIDs.contains(person.id) {
                let active = person.circleContacts.filter { !$0.manuallyExcluded }
                guard active.count == 1, active[0].circle.id == family.id else { continue }
                try dataManager.addToCircle(person, circle: friends)
            }
        }
    }

    private func hasRelationship(between first: Person, and second: Person) -> Bool {
        first.allRelationships.contains {
            ($0.fromContact.id == first.id && $0.toContact.id == second.id)
                || ($0.fromContact.id == second.id && $0.toContact.id == first.id)
        }
    }

    /// Re-applies circle assignments for already-created demo contacts.
    /// Called when demo persons exist but have no pond memberships (interrupted seed).
    private func applyCircleAssignments(for demoPersons: [Person]) throws -> Bool {
        let circles = try dataManager.fetchAllCircles()
        guard let familyCircle = circles.first(where: { $0.isSystem && $0.name == "Family" })
                ?? circles.first(where: { $0.isSystem && $0.shouldAutoAssign(for: .parent) }),
              let friendsCircle = circles.first(where: { $0.isSystem && $0.name == "Friends" })
                ?? circles.first(where: { $0.isSystem && $0.shouldAutoAssign(for: .friend) }),
              let proCircle = circles.first(where: { $0.isSystem && $0.name == "Professional" })
                ?? circles.first(where: { $0.isSystem && $0.shouldAutoAssign(for: .coworker) }) else {
            throw GoldfishError.circleNotFound
        }

        // Duplicate user/demo names are valid. Keep the first matching fixture
        // contact instead of trapping while constructing the repair dictionary.
        var byName: [String: Person] = [:]
        for person in demoPersons where byName[person.name] == nil {
            byName[person.name] = person
        }

        let familyNames = ["Sarah Chen", "Linda Miller", "Robert Miller", "Tom Miller"]
        let friendNames = ["Jake Morrison", "Nicole Morrison", "Liam Morrison", "Ella Morrison",
                           "Noah Morrison", "Sam Taylor", "Alex Jordan"]
        let proNames    = ["David Park", "Lisa Thompson", "Chris Evans"]
        let bookClubNames = ["Emma Wilson", "Mia Rodriguez", "Ryan O'Brien"]
        // Priya Patel is intentionally left unassigned (drag-to-link target).

        let assignmentNames = familyNames + friendNames + proNames + bookClubNames
        guard assignmentNames.allSatisfy({ byName[$0] != nil }) else { return false }

        // Book Club is a custom circle — it may not exist if the seed was interrupted
        // before it was created, so recreate it on demand after preflight succeeds.
        let bookClubCircle: GoldfishCircle
        if let existing = circles.first(where: { $0.name == "Book Club" }) {
            bookClubCircle = existing
        } else {
            bookClubCircle = try dataManager.createCircle(name: "Book Club", color: "#9B59B6", emoji: "📚")
        }

        for name in familyNames { try addToCircleIfNoCustomAssignment(byName[name]!, circle: familyCircle) }
        for name in friendNames { try addToCircleIfNoCustomAssignment(byName[name]!, circle: friendsCircle) }
        for name in proNames { try addToCircleIfNoCustomAssignment(byName[name]!, circle: proCircle) }
        for name in bookClubNames { try addToCircleIfNoCustomAssignment(byName[name]!, circle: bookClubCircle) }
        return true
    }

    private func addToCircleIfNoCustomAssignment(_ person: Person, circle: GoldfishCircle) throws {
        let hasCustomAssignment = person.circleContacts.contains {
            !$0.manuallyExcluded && !$0.circle.isSystem
        }
        guard !hasCustomAssignment else { return }
        try dataManager.addToCircle(person, circle: circle)
    }

    // MARK: - Remove Demo Data
    
    /// Removes all contacts flagged as demo data and their relationships.
    /// User-created circles remain intact, including empty circles.
    func removeDemoData() throws {
        try dataManager.performAtomicEdit {
            let allPersons = try dataManager.fetchAllPersons()
            let demoPersons = allPersons.filter { $0.isDemo }

            for person in demoPersons {
                // Person's cascade delete rule handles relationships, locations,
                // and circle memberships. Custom circles are deliberately kept:
                // a same-named or empty circle may belong to the user.
                dataManager.context.delete(person)
            }
        }
        guard let me = try dataManager.fetchMePerson() else { return }
        let markerKey = daycareSeedMarkerKey(me.id)
        dataManager.afterCurrentAtomicEditCommits {
            // Keep the pond identity so a later explicit sample re-seed can reuse
            // this sample-owned circle while leaving user ponds alone.
            UserDefaults.standard.removeObject(forKey: markerKey)
        }
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
