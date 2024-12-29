import type { Express } from "express";
import { createServer, type Server } from "http";
import { db } from "@db";
import { contacts, insertContactSchema } from "@db/schema";
import { and, or, eq, ilike, sql } from "drizzle-orm";
import { randomBytes } from "crypto";

interface SearchFilters {
  name?: string;
  email?: string;
  phone?: string;
  notes?: string;
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
      const query = db.select({
        id: contacts.id,
        name: contacts.name,
        email: contacts.email,
        phone: contacts.phone,
        birthday: contacts.birthday,
        notes: contacts.notes,
        parentId: contacts.parentId,
        relationshipType: contacts.relationshipType,
        isMe: contacts.isMe,
        shareToken: contacts.shareToken,
        shareDepth: contacts.shareDepth,
        shareableUntil: contacts.shareableUntil,
        similarity: sql<number>`similarity(${contacts.name}, ${filters.name || ''})`
      }).from(contacts);

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
        conditions.push(
          ilike(contacts.email, `%${filters.email}%`)
        );
      }

      if (filters.phone) {
        conditions.push(
          ilike(contacts.phone, `%${filters.phone}%`)
        );
      }

      if (filters.notes) {
        conditions.push(
          ilike(contacts.notes, `%${filters.notes}%`)
        );
      }

      if (conditions.length > 0) {
        query.where(or(...conditions));
      }

      // Order by similarity if name search is present, then by name
      if (filters.name) {
        query.orderBy(sql`similarity(${contacts.name}, ${filters.name}) DESC`);
      } else {
        query.orderBy(contacts.name);
      }

      const result = await query;
      res.json(result);
    } catch (error) {
      console.error('Error fetching contacts:', error);
      res.status(500).json({ message: "Failed to fetch contacts" });
    }
  });

  app.post("/api/contacts/share", async (req, res) => {
    try {
      const { contactIds } = req.body;

      if (!Array.isArray(contactIds) || contactIds.length === 0) {
        return res.status(400).json({ message: "No contacts selected for sharing" });
      }

      // Generate a unique share token
      const shareToken = randomBytes(32).toString('hex');

      // Set expiration to 7 days from now
      const shareableUntil = new Date();
      shareableUntil.setDate(shareableUntil.getDate() + 7);

      // Update all selected contacts with share details
      await db
        .update(contacts)
        .set({
          shareToken,
          shareableUntil: shareableUntil.toISOString(),
          updatedAt: new Date().toISOString()
        })
        .where(sql`id = ANY(${contactIds})`);

      res.json({ shareToken });
    } catch (error) {
      console.error('Error generating share token:', error);
      res.status(500).json({ message: "Failed to generate share token" });
    }
  });

  app.get("/api/contacts/:id", async (req, res) => {
    const { id } = req.params;

    try {
      const contact = await db
        .select()
        .from(contacts)
        .where(eq(contacts.id, parseInt(id)))
        .limit(1);

      if (!contact.length) {
        res.status(404).json({ message: "Contact not found" });
        return;
      }

      const children = await db
        .select()
        .from(contacts)
        .where(eq(contacts.parentId, contact[0].id));

      res.json({ ...contact[0], children });
    } catch (error) {
      console.error('Error fetching contact:', error);
      res.status(500).json({ message: "Failed to fetch contact" });
    }
  });

  app.post("/api/contacts", async (req, res) => {
    try {
      console.log('Received contact data:', req.body);

      // Validate the input data
      const validatedData = insertContactSchema.parse(req.body);

      const now = new Date().toISOString();
      const result = await db.insert(contacts).values({
        ...validatedData,
        createdAt: now,
        updatedAt: now,
      }).returning();

      console.log('Created contact:', result[0]);
      res.json(result[0]);
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
      // Validate the input data
      const validatedData = insertContactSchema.parse(req.body);

      const result = await db
        .update(contacts)
        .set({ 
          ...validatedData,
          updatedAt: new Date().toISOString()
        })
        .where(eq(contacts.id, parseInt(id)))
        .returning();
      res.json(result[0]);
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