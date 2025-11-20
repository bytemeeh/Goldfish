import { db } from "../../db";
import { relationshipDefinitions } from "../../db/schema";
import { eq, sql } from "drizzle-orm";

/**
 * Cleanup script to fix duplicate and inconsistent relationship types
 * 
 * Issues to fix:
 * 1. Remove redundant "sibling" type (use brother/sister instead)
 * 2. Standardize to lowercase (Father -> father, Mother -> mother, Son -> son)
 * 3. Remove any other duplicate entries
 */

async function cleanup() {
    console.log("🧹 Cleaning up relationship definitions...");

    try {
        // Delete redundant "sibling" type (we have brother/sister instead)
        const deletedSibling = await db
            .delete(relationshipDefinitions)
            .where(eq(relationshipDefinitions.name, "sibling"))
            .returning();

        if (deletedSibling.length > 0) {
            console.log("✓ Removed redundant 'sibling' type");
        }

        // Fix capitalization issues - delete capitalized versions
        const capitalizedTypes = ["Father", "Mother", "Son", "Daughter", "Brother", "Sister", "Spouse", "Child", "Pet"];

        for (const type of capitalizedTypes) {
            const deleted = await db
                .delete(relationshipDefinitions)
                .where(eq(relationshipDefinitions.name, type))
                .returning();

            if (deleted.length > 0) {
                console.log(`✓ Removed capitalized type: ${type}`);
            }
        }

        // Get all remaining relationship types and check for duplicates
        const allTypes = await db.select().from(relationshipDefinitions);
        console.log("\n📋 Remaining relationship types:");
        allTypes.forEach(type => {
            console.log(`  - ${type.name} (${type.category}) ${type.isCore ? '[Core]' : ''}`);
        });

        console.log("\n✅ Cleanup complete!");
    } catch (error) {
        console.error("❌ Error during cleanup:", error);
        throw error;
    }
}

cleanup()
    .then(() => process.exit(0))
    .catch(() => process.exit(1));
