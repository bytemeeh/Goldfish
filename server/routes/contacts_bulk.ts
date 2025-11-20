import { Router } from "express";
import { db } from "../../db";
import { contacts } from "../../db/schema";
import { inArray } from "drizzle-orm";

const router = Router();

// ... existing routes ...

// Bulk delete contacts
router.post("/bulk-delete", async (req, res) => {
    try {
        const { contactIds } = req.body;

        if (!contactIds || !Array.isArray(contactIds) || contactIds.length === 0) {
            return res.status(400).json({ error: "Invalid contact IDs" });
        }

        // Delete contacts (cascade will handle locations and children)
        await db.delete(contacts).where(
            inArray(contacts.id, contactIds)
        );

        res.json({ success: true, count: contactIds.length });
    } catch (error) {
        console.error("Error bulk deleting contacts:", error);
        res.status(500).json({ error: "Failed to delete contacts" });
    }
});

export default router;
