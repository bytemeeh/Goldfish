
import * as dotenv from "dotenv";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load .env from project root
dotenv.config({ path: path.resolve(__dirname, "../../.env") });

import { db } from "../../db";
import { contacts, relationshipDefinitions } from "../../db/schema";
import { eq } from "drizzle-orm";

async function seed() {
    console.log("🌱 Seeding Game of Thrones database...");

    // Optional: Clear existing contacts? 
    // For now, let's just add them. If you want to clear, uncomment the next line.
    // await db.delete(contacts);

    // 1. Ensure Relationship Types exist
    const relationships = [
        { name: "Father", category: "family" },
        { name: "Mother", category: "family" },
        { name: "Son", category: "family" },
        { name: "Daughter", category: "family" },
        { name: "Brother", category: "family" },
        { name: "Sister", category: "family" },
        { name: "Spouse", category: "family" },
        { name: "Friend", category: "friend" },
        { name: "Enemy", category: "other" },
        { name: "Hand of the King", category: "work" },
        { name: "Bodyguard", category: "work" },
        { name: "Direwolf", category: "other" }, // For pets!
    ];

    for (const rel of relationships) {
        await db
            .insert(relationshipDefinitions)
            .values({ name: rel.name, category: rel.category, isCore: false })
            .onConflictDoNothing();
    }

    // 2. Create Characters (Nodes)
    // We'll store IDs to create links later
    const charMap: Record<string, string> = {};

    const characters = [
        // House Stark
        { name: "Eddard Stark", title: "Lord of Winterfell", type: "person", color: "slate" },
        { name: "Catelyn Stark", title: "Lady of Winterfell", type: "person", color: "slate" },
        { name: "Robb Stark", title: "King in the North", type: "person", color: "slate" },
        { name: "Sansa Stark", title: "Lady of Winterfell", type: "person", color: "pink" },
        { name: "Arya Stark", title: "No One", type: "person", color: "slate" },
        { name: "Bran Stark", title: "Three-Eyed Raven", type: "person", color: "slate" },
        { name: "Rickon Stark", title: "Prince", type: "person", color: "slate" },
        { name: "Jon Snow", title: "Lord Commander", type: "person", color: "slate" },
        { name: "Ghost", title: "Albino Direwolf", type: "pet", color: "white" },
        { name: "Grey Wind", title: "Direwolf", type: "pet", color: "slate" },

        // House Lannister
        { name: "Tywin Lannister", title: "Lord of Casterly Rock", type: "person", color: "red" },
        { name: "Cersei Lannister", title: "Queen Regent", type: "person", color: "red" },
        { name: "Jaime Lannister", title: "Kingslayer", type: "person", color: "red" },
        { name: "Tyrion Lannister", title: "The Imp", type: "person", color: "red" },
        { name: "Joffrey Baratheon", title: "King", type: "person", color: "yellow" },
        { name: "Tommen Baratheon", title: "King", type: "person", color: "yellow" },
        { name: "Myrcella Baratheon", title: "Princess", type: "person", color: "yellow" },

        // House Targaryen
        { name: "Daenerys Targaryen", title: "Mother of Dragons", type: "person", color: "violet" },
        { name: "Drogon", title: "Dragon", type: "pet", color: "red" },
        { name: "Rhaegal", title: "Dragon", type: "pet", color: "green" },
        { name: "Viserion", title: "Dragon", type: "pet", color: "yellow" },

        // Others
        { name: "Robert Baratheon", title: "King", type: "person", color: "yellow" },
        { name: "Petyr Baelish", title: "Littlefinger", type: "person", color: "emerald" },
        { name: "Varys", title: "The Spider", type: "person", color: "purple" },
    ];

    console.log("Creating characters...");
    for (const char of characters) {
        const [inserted] = await db.insert(contacts).values({
            name: char.name,
            type: char.type as "person" | "pet",
            notes: char.title,
            color: char.color,
            isMe: char.name === "Eddard Stark", // Let's make Ned the 'user' for this demo
        } as any).returning();
        charMap[char.name] = inserted.id;
    }

    // 3. Create Relationships (Edges)
    // Helper to update contact with parent/relationship
    const addRelation = async (childName: string, parentName: string, type: string, toUserRel: string | null = null) => {
        if (!charMap[childName] || !charMap[parentName]) return;

        await db.update(contacts).set({
            parentId: charMap[parentName],
            relationshipType: type,
            relationshipToUser: toUserRel,
        } as any).where(eq(contacts.id, charMap[childName]));
    };

    console.log("Linking relationships...");

    // Starks
    await addRelation("Robb Stark", "Eddard Stark", "Son", "Son");
    await addRelation("Sansa Stark", "Eddard Stark", "Daughter", "Daughter");
    await addRelation("Arya Stark", "Eddard Stark", "Daughter", "Daughter");
    await addRelation("Bran Stark", "Eddard Stark", "Son", "Son");
    await addRelation("Rickon Stark", "Eddard Stark", "Son", "Son");
    await addRelation("Jon Snow", "Eddard Stark", "Son", "Son"); // Kept simple

    // Pets
    await addRelation("Ghost", "Jon Snow", "Direwolf", "Grand-dog?");
    await addRelation("Grey Wind", "Robb Stark", "Direwolf", "Grand-dog?");

    // Lannisters
    await addRelation("Cersei Lannister", "Tywin Lannister", "Daughter", "Enemy");
    await addRelation("Jaime Lannister", "Tywin Lannister", "Son", "Enemy");
    await addRelation("Tyrion Lannister", "Tywin Lannister", "Son", "Friend"); // Maybe Ned likes Tyrion?

    await addRelation("Joffrey Baratheon", "Cersei Lannister", "Son", "Enemy");
    await addRelation("Myrcella Baratheon", "Cersei Lannister", "Daughter", "Enemy");
    await addRelation("Tommen Baratheon", "Cersei Lannister", "Son", "Enemy");

    // Targaryens
    await addRelation("Drogon", "Daenerys Targaryen", "Dragon", "Threat");
    await addRelation("Rhaegal", "Daenerys Targaryen", "Dragon", "Threat");
    await addRelation("Viserion", "Daenerys Targaryen", "Dragon", "Threat");

    // Complex / Political
    // Note: The current schema only supports ONE parent (hierarchical). 
    // So we can't easily show Catelyn as mother AND Ned as father in the tree structure directly 
    // without a more complex graph model (which is Phase 4). 
    // For now, we stick to the primary hierarchy.

    // Let's set some "Relationship to User" (Ned) for people not directly his children
    await db.update(contacts).set({ relationshipToUser: "Wife" } as any).where(eq(contacts.id, charMap["Catelyn Stark"]));
    await db.update(contacts).set({ relationshipToUser: "Friend" } as any).where(eq(contacts.id, charMap["Robert Baratheon"]));
    await db.update(contacts).set({ relationshipToUser: "Enemy" } as any).where(eq(contacts.id, charMap["Jaime Lannister"]));
    await db.update(contacts).set({ relationshipToUser: "Enemy" } as any).where(eq(contacts.id, charMap["Cersei Lannister"]));

    console.log("✅ Game of Thrones database seeded!");
}

seed().catch((err) => {
    console.error("Seeding failed:", err);
    process.exit(1);
});
