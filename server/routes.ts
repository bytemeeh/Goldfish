import type { Express } from "express";
import { createServer, type Server } from "http";
import { db } from "@db";
import { contacts, insertContactSchema, getCascadedRelationshipType, getValidChildRelationshipTypes, type RelationshipType } from "@db/schema";
import { and, or, eq, ilike, sql } from "drizzle-orm";

interface SearchFilters {
  name?: string;
  email?: string;
  phone?: string;
  notes?: string;
}

async function updateRelationshipsCascading(contactId: number, newParentId: number | null, newRelationType: RelationshipType | null) {
  console.log(`Cascading update for contact ${contactId}:`, { newParentId, newRelationType });

  // Get the contact and its children
  const [contact] = await db
    .select()
    .from(contacts)
    .where(eq(contacts.id, contactId));

  if (!contact) {
    console.log(`No contact found with id ${contactId}`);
    return;
  }

  console.log('Contact found:', contact);

  // Get all descendants to update their relationship types
  const children = await db
    .select()
    .from(contacts)
    .where(eq(contacts.parentId, contactId));

  console.log(`Found ${children.length} children for contact ${contactId}:`, children);

  // Update children's relationship types based on cascade rules
  for (const child of children) {
    if (child.relationshipType && newRelationType) {
      console.log(`Processing child ${child.id} with relationship type ${child.relationshipType}`);

      const cascadedType = getCascadedRelationshipType(
        newRelationType,
        child.relationshipType as RelationshipType
      );

      console.log(`Cascaded type for child ${child.id}:`, cascadedType);

      if (cascadedType) {
        console.log(`Updating child ${child.id} relationship type to ${cascadedType}`);

        // Update this child's relationship type
        await db
          .update(contacts)
          .set({
            relationshipType: cascadedType,
            updatedAt: new Date().toISOString()
          })
          .where(eq(contacts.id, child.id));

        // Recursively update this child's descendants
        await updateRelationshipsCascading(child.id, child.parentId, cascadedType);
      }
    }
  }
}

export function registerRoutes(app: Express): Server {
  // Contacts API
  app.get("/api/contacts", async (req, res) => {
    const filters: SearchFilters = {};
    if (req.query.name) filters.name = req.query.name as string;
    if (req.query.email) filters.email = req.query.email as string;
    if (req.query.phone) filters.phone = req.query.phone as string;
    if (req.query.notes) filters.notes = req.query.notes as string;

    try {
      const query = db.select().from(contacts);

      // Build WHERE conditions based on filters
      const conditions = [];

      if (filters.name) {
        conditions.push(
          or(
            sql`similarity(${contacts.name}, ${filters.name}) > 0.1`,
            ilike(contacts.name, `%${filters.name}%`)
          )
        );
      }

      if (filters.email) {
        conditions.push(ilike(contacts.email, `%${filters.email}%`));
      }

      if (filters.phone) {
        conditions.push(ilike(contacts.phone, `%${filters.phone}%`));
      }

      if (filters.notes) {
        conditions.push(ilike(contacts.notes, `%${filters.notes}%`));
      }

      if (conditions.length > 0) {
        query.where(or(...conditions));
      }

      // Order by name
      query.orderBy(contacts.name);

      const result = await query;
      res.json(result);
    } catch (error) {
      console.error('Error fetching contacts:', error);
      res.status(500).json({ message: "Failed to fetch contacts" });
    }
  });

  app.get("/api/contacts/:id", async (req, res) => {
    const { id } = req.params;

    try {
      const [contact] = await db
        .select()
        .from(contacts)
        .where(eq(contacts.id, parseInt(id)))
        .limit(1);

      if (!contact) {
        return res.status(404).json({ message: "Contact not found" });
      }

      // Get valid relationship types for children of this contact
      const validChildTypes = contact.relationshipType
        ? getValidChildRelationshipTypes(contact.relationshipType as RelationshipType)
        : [];

      const children = await db
        .select()
        .from(contacts)
        .where(eq(contacts.parentId, contact.id));

      res.json({ 
        ...contact, 
        children,
        validChildTypes 
      });
    } catch (error) {
      console.error('Error fetching contact:', error);
      res.status(500).json({ message: "Failed to fetch contact" });
    }
  });

  app.post("/api/contacts", async (req, res) => {
    try {
      console.log('Creating new contact with data:', req.body);

      // Validate the input data
      const validatedData = insertContactSchema.parse(req.body);
      console.log('Validated data:', validatedData);

      const [newContact] = await db
        .insert(contacts)
        .values({
          ...validatedData,
        })
        .returning();

      console.log('Created new contact:', newContact);

      if (validatedData.parentId && validatedData.relationshipType) {
        console.log('Initiating cascade update for new contact');
        // Trigger cascading updates if this is a child contact
        await updateRelationshipsCascading(
          newContact.id,
          validatedData.parentId,
          validatedData.relationshipType as RelationshipType
        );
      }

      res.json(newContact);
    } catch (error) {
      console.error('Error creating contact:', error);
      res.status(400).json({ 
        message: error instanceof Error ? error.message : "Failed to create contact" 
      });
    }
  });

  app.put("/api/contacts/:id", async (req, res) => {
    const { id } = req.params;

    try {
      console.log(`Updating contact with ID ${id}, Data: `, req.body);
      // Validate the input data
      const validatedData = insertContactSchema.parse(req.body);
      console.log('Validated data:', validatedData);

      const [updatedContact] = await db
        .update(contacts)
        .set({ 
          ...validatedData,
          updatedAt: new Date().toISOString()
        })
        .where(eq(contacts.id, parseInt(id)))
        .returning();

      console.log('Updated contact:', updatedContact);

      // Trigger cascading updates if relationship type changed
      if (validatedData.relationshipType) {
        console.log('Initiating cascade update for updated contact');
        await updateRelationshipsCascading(
          parseInt(id),
          validatedData.parentId,
          validatedData.relationshipType as RelationshipType
        );
      }

      res.json(updatedContact);
    } catch (error) {
      console.error('Error updating contact:', error);
      res.status(400).json({ 
        message: error instanceof Error ? error.message : "Failed to update contact" 
      });
    }
  });

  app.delete("/api/contacts/:id", async (req, res) => {
    const { id } = req.params;

    try {
      await db.delete(contacts).where(eq(contacts.id, parseInt(id)));
      res.status(204).end();
    } catch (error) {
      console.error('Error deleting contact:', error);
      res.status(500).json({ message: "Failed to delete contact" });
    }
  });

  const httpServer = createServer(app);
  return httpServer;
}