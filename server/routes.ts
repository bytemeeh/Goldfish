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
      console.log('Fetching contacts with filters:', filters);
      const result = await db
        .select({
          id: contacts.id,
          name: contacts.name,
          phone: contacts.phone,
          email: contacts.email,
          birthday: contacts.birthday,
          notes: contacts.notes,
          parentId: contacts.parentId,
          relationshipType: contacts.relationshipType,
          isMe: contacts.isMe,
          shareToken: contacts.shareToken,
          shareDepth: contacts.shareDepth,
          shareableUntil: contacts.shareableUntil,
          createdAt: contacts.createdAt,
          updatedAt: contacts.updatedAt,
        })
        .from(contacts)
        .orderBy(contacts.name);

      console.log('Found contacts:', result.length);
      console.log('Contact hierarchy:', result.map(c => ({
        id: c.id,
        name: c.name,
        parentId: c.parentId,
        relationshipType: c.relationshipType
      })));

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

      // Get all related contacts (both parent and children)
      const relatedContacts = await db
        .select()
        .from(contacts)
        .where(
          or(
            eq(contacts.parentId, contact.id),
            contact.parentId ? eq(contacts.id, contact.parentId) : sql`false`
          )
        );

      console.log(`Found ${relatedContacts.length} related contacts for ${contact.name}:`, 
        relatedContacts.map(c => ({
          id: c.id,
          name: c.name,
          relationshipType: c.relationshipType,
          parentId: c.parentId
        }))
      );

      res.json({ 
        ...contact, 
        children: relatedContacts.filter(c => c.parentId === contact.id),
        parent: relatedContacts.find(c => c.id === contact.parentId),
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