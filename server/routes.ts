import type { Express } from "express";
import { createServer, type Server } from "http";
import { db } from "@db";
import { contacts } from "@db/schema";
import { sql } from "drizzle-orm";
import { and, eq, ilike, or } from "drizzle-orm/pg-core";

export function registerRoutes(app: Express): Server {
  // Contacts API
  app.get("/api/contacts", async (req, res) => {
    const search = req.query.search as string | undefined;

    try {
      const query = db.select().from(contacts);

      if (search) {
        query.where(
          or(
            ilike(contacts.name, `%${search}%`),
            ilike(contacts.email, `%${search}%`),
            ilike(contacts.phone, `%${search}%`)
          )
        );
      }

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
        .set({ ...req.body, updatedAt: sql`CURRENT_TIMESTAMP` })
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