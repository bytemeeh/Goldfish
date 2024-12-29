import type { Express } from "express";
import { createServer, type Server } from "http";
import { db } from "@db";
import { contacts, relationships } from "@db/schema";
import { and, eq, like, or } from "drizzle-orm/pg-core";

export function registerRoutes(app: Express): Server {
  // Contacts API
  app.get("/api/contacts", async (req, res) => {
    const search = req.query.search as string | undefined;

    try {
      let query = db.select().from(contacts);

      if (search) {
        query = query.where(
          or(
            like(contacts.name, `%${search}%`),
            like(contacts.email, `%${search}%`),
            like(contacts.phone, `%${search}%`)
          )
        );
      }

      const result = await query;
      const contactsWithChildren = await Promise.all(
        result.map(async (contact) => {
          const children = await db
            .select()
            .from(contacts)
            .where(eq(contacts.parentId, contact.id));
          return { ...contact, children };
        })
      );

      res.json(contactsWithChildren);
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
        .set(req.body)
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

  // Relationships API
  app.post("/api/relationships", async (req, res) => {
    try {
      const result = await db
        .insert(relationships)
        .values(req.body)
        .returning();
      res.json(result[0]);
    } catch (error) {
      console.error('Error creating relationship:', error);
      res.status(500).json({ message: "Failed to create relationship" });
    }
  });

  app.delete("/api/relationships/:id", async (req, res) => {
    const { id } = req.params;

    try {
      await db
        .delete(relationships)
        .where(eq(relationships.id, parseInt(id)));
      res.status(204).end();
    } catch (error) {
      console.error('Error deleting relationship:', error);
      res.status(500).json({ message: "Failed to delete relationship" });
    }
  });

  const httpServer = createServer(app);
  return httpServer;
}