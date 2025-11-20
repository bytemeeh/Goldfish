
import { db } from "../../db";
import { relationshipDefinitions } from "../../db/schema";

const coreRelationships = [
    { name: "mother", category: "family", isCore: true },
    { name: "father", category: "family", isCore: true },
    { name: "brother", category: "family", isCore: true },
    { name: "sister", category: "family", isCore: true },
    { name: "child", category: "family", isCore: true },
    { name: "spouse", category: "family", isCore: true },
    { name: "pet", category: "family", isCore: true },
    { name: "friend", category: "friends", isCore: true },
    { name: "boyfriend/girlfriend", category: "friends", isCore: true },
    { name: "co-worker", category: "professional", isCore: true },
];

async function seed() {
    console.log("Seeding relationship definitions...");

    for (const rel of coreRelationships) {
        try {
            await db.insert(relationshipDefinitions).values(rel).onConflictDoNothing();
            console.log(`Seeded: ${rel.name}`);
        } catch (error) {
            console.error(`Error seeding ${rel.name}:`, error);
        }
    }

    console.log("Seeding complete!");
    process.exit(0);
}

seed();
