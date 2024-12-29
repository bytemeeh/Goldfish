import type { Express } from "express";
import { createServer, type Server } from "http";
import { db } from "@db";
import { contacts } from "@db/schema";
import { and, or, eq, ilike, sql } from "drizzle-orm";

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
        similarity: sql<number>`similarity(${contacts.name}, ${filters.name || ''})`
      }).from(contacts);

      // Build WHERE conditions based on filters
      const conditions = [];

      if (filters.name) {
        conditions.push(
          sql`similarity(${contacts.name}, ${filters.name}) > 0.3`
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

      // Order by similarity if name search is present
      if (filters.name) {
        query.orderBy(sql`similarity(${contacts.name}, ${filters.name}) DESC`);
      }

      const result = await query;
      res.json(result);
    } catch (error) {
      console.error('Error fetching contacts:', error);
      res.status(500).json({ message: "Failed to fetch contacts" });
    }
  });

  // Keep other routes unchanged
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
      const result = await db.insert(contacts).values(req.body).returning();
      res.json(result[0]);
    } catch (error) {
      console.error('Error creating contact:', error);
      res.status(500).json({ message: "Failed to create contact" });
    }
  });

  app.put("/api/contacts/:id", async (req, res) => {
    const { id } = req.params;

    try {
      const result = await db
        .update(contacts)
        .set({ ...req.body, updatedAt: new Date() })
        .where(eq(contacts.id, parseInt(id)))
        .returning();
      res.json(result[0]);
    } catch (error) {
      console.error('Error updating contact:', error);
      res.status(500).json({ message: "Failed to update contact" });
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