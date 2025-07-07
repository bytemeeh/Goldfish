
import { Router } from "express";
import { db } from "@db";
import { contacts, locations } from "@db/schema";
import { eq, inArray, like, or, and } from "drizzle-orm";
import { insertContactSchema, type Contact, type Location } from "@db/schema";
import { logJson } from "../logger";
import { reparentSchema } from "../validation/reparentSchema";

const router = Router();

interface SearchFilters {
  name?: string;
  email?: string;
  phone?: string;
  notes?: string;
}

// Helper function to get all descendants of a contact
async function getDescendants(contactId: number): Promise<number[]> {
  const descendants: number[] = [];
  const queue = [contactId];
  
  while (queue.length > 0) {
    const currentId = queue.shift()!;
    const children = await db
      .select({ id: contacts.id })
      .from(contacts)
      .where(eq(contacts.parentId, currentId));
    
    for (const child of children) {
      descendants.push(child.id);
      queue.push(child.id);
    }
  }
  
  return descendants;
}

// GET /api/contacts
router.get("/", async (req, res) => {
  try {
    const filters: SearchFilters = {};
    if (req.query.name) filters.name = req.query.name as string;
    if (req.query.email) filters.email = req.query.email as string;
    if (req.query.phone) filters.phone = req.query.phone as string;
    if (req.query.notes) filters.notes = req.query.notes as string;

    let query = db.select().from(contacts);

    // Apply filters
    if (Object.keys(filters).length > 0) {
      const conditions = [];
      if (filters.name) {
        conditions.push(like(contacts.name, `%${filters.name}%`));
      }
      if (filters.email) {
        conditions.push(like(contacts.email, `%${filters.email}%`));
      }
      if (filters.phone) {
        conditions.push(like(contacts.phone, `%${filters.phone}%`));
      }
      if (filters.notes) {
        conditions.push(like(contacts.notes, `%${filters.notes}%`));
      }
      query = query.where(or(...conditions));
    }

    const contactsResult = await query;

    // Fix N+1: Get all locations for all contacts in one query
    if (contactsResult.length > 0) {
      const contactIds = contactsResult.map(c => c.id);
      const allLocations = await db
        .select()
        .from(locations)
        .where(inArray(locations.contactId, contactIds));

      // Group locations by contact ID
      const locationsByContactId: Record<number, Location[]> = {};
      allLocations.forEach(location => {
        if (!locationsByContactId[location.contactId]) {
          locationsByContactId[location.contactId] = [];
        }
        locationsByContactId[location.contactId].push(location);
      });

      // Attach locations to contacts
      const contactsWithLocations = contactsResult.map(contact => ({
        ...contact,
        locations: locationsByContactId[contact.id] || []
      }));

      logJson(res, contactsWithLocations);
      return res.json(contactsWithLocations);
    }

    logJson(res, contactsResult);
    res.json(contactsResult);
  } catch (error) {
    console.error("Error fetching contacts:", error);
    res.status(500).json({ error: "Failed to fetch contacts" });
  }
});

// GET /api/contacts/:id
router.get("/:id", async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    if (isNaN(id)) {
      return res.status(400).json({ error: "Invalid contact ID" });
    }

    const [contact] = await db
      .select()
      .from(contacts)
      .where(eq(contacts.id, id));

    if (!contact) {
      return res.status(404).json({ error: "Contact not found" });
    }

    // Fix N+1: Use inArray even for single ID for consistency
    const locs = await db
      .select()
      .from(locations)
      .where(inArray(locations.contactId, [id]));

    const contactWithLocations = {
      ...contact,
      locations: locs
    };

    logJson(res, contactWithLocations);
    res.json(contactWithLocations);
  } catch (error) {
    console.error("Error fetching contact:", error);
    res.status(500).json({ error: "Failed to fetch contact" });
  }
});

// POST /api/contacts
router.post("/", async (req, res) => {
  try {
    const result = insertContactSchema.safeParse(req.body);
    if (!result.success) {
      return res.status(400).json({ error: result.error.issues });
    }

    const data = result.data;
    
    // Wrap in transaction with change tracking
    const rec = await db.transaction(async (tx) => {
      const [newContact] = await tx.insert(contacts).values(data).returning();
      
      // Note: contactChanges table will be created by migration
      // For now, just log the change
      console.log('Contact created:', { id: newContact.id, operation: 'insert' });
      
      return newContact;
    });

    logJson(res, rec);
    res.status(201).json(rec);
  } catch (error) {
    console.error("Error creating contact:", error);
    res.status(500).json({ error: "Failed to create contact" });
  }
});

// PUT /api/contacts/:id
router.put("/:id", async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    if (isNaN(id)) {
      return res.status(400).json({ error: "Invalid contact ID" });
    }

    console.log('PUT request for contact', id, 'with data:', req.body);

    // Check if contact exists first
    const [existingContact] = await db
      .select()
      .from(contacts)
      .where(eq(contacts.id, id));

    if (!existingContact) {
      return res.status(404).json({ error: "Contact not found" });
    }

    // Handle specific parent_id update for drag-and-drop
    if (req.body.parentId !== undefined) {
      const validation = reparentSchema.safeParse(req.body);
      if (!validation.success) {
        return res.status(400).json({ error: "Invalid reparent request", details: validation.error.issues });
      }

      const newParentId = validation.data.parentId;
      console.log('Updating parentId for contact', id, 'to', newParentId);
      
      // Cycle detection: ensure newParentId is not a descendant of id
      if (newParentId) {
        const descendants = await getDescendants(id);
        if (descendants.includes(newParentId)) {
          return res.status(400).json({ error: "Cannot create cycle: target is a descendant of source" });
        }
      }
      
      const [updatedContact] = await db
        .update(contacts)
        .set({ 
          parentId: newParentId,
          updatedAt: new Date().toISOString() 
        })
        .where(eq(contacts.id, id))
        .returning();

      console.log('Contact parent updated successfully:', updatedContact);
      logJson(res, updatedContact);
      return res.json(updatedContact);
    }

    // For other updates, use schema validation
    const updateSchema = insertContactSchema.partial();
    const result = updateSchema.safeParse(req.body);
    if (!result.success) {
      return res.status(400).json({ error: result.error.issues });
    }

    const data = result.data;

    // Update the contact
    const [updatedContact] = await db
      .update(contacts)
      .set({ ...data, updatedAt: new Date().toISOString() })
      .where(eq(contacts.id, id))
      .returning();

    console.log('Contact updated:', { id, operation: 'update', data });
    const rec = updatedContact;

    logJson(res, rec);
    res.json(rec);
  } catch (error) {
    console.error("Error updating contact:", error);
    console.error("Full error details:", error);
    res.status(500).json({ error: "Failed to update contact", details: error.message });
  }
});

// DELETE /api/contacts/:id
router.delete("/:id", async (req, res) => {
  try {
    const id = parseInt(req.params.id);
    if (isNaN(id)) {
      return res.status(400).json({ error: "Invalid contact ID" });
    }

    // Check if contact exists and get data for change tracking
    const [contact] = await db
      .select()
      .from(contacts)
      .where(eq(contacts.id, id));

    if (!contact) {
      return res.status(404).json({ error: "Contact not found" });
    }

    // Block self-delete
    if (contact.isMe) {
      return res.status(400).json({ error: 'Cannot delete self' });
    }

    // Wrap in transaction with change tracking
    await db.transaction(async (tx) => {
      await tx.delete(contacts).where(eq(contacts.id, id));
      
      // Note: contactChanges table will be created by migration
      // For now, just log the change
      console.log('Contact deleted:', { id, operation: 'delete' });
    });

    return res.sendStatus(204);
  } catch (error) {
    console.error("Error deleting contact:", error);
    res.status(500).json({ error: "Failed to delete contact" });
  }
});

export default router;
