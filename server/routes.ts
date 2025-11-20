import type { Express } from "express";
import { createServer, type Server } from "http";
import { db } from "../db";
import { contacts, locations, analyticsEvents, insertContactSchema, insertLocationSchema, getCascadedRelationshipType, getValidChildRelationshipTypes, type RelationshipType, type Location } from "../db/schema";
import { and, or, eq, ilike, sql, inArray } from "drizzle-orm";
import contactsRouter from "./routes/contacts";
import aiRouter from "./routes/ai";
import contactsBulkRouter from "./routes/contacts_bulk";

interface SearchFilters {
  name?: string;
  email?: string;
  phone?: string;
  notes?: string;
}

async function updateRelationshipsCascading(contactId: string, newParentId: string | null, newRelationType: RelationshipType | null) {
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
  // Use contacts router
  app.use("/api/contacts", contactsRouter);
  app.use("/api/contacts", contactsBulkRouter);
  app.use("/api/ai", aiRouter);

  // Locations API
  app.get("/api/locations", async (req, res) => {
    const filters: SearchFilters = {};
    console.log(filters);
  });

  // Analytics API
  app.post("/api/analytics", async (req, res) => {
    try {
      const { anonymousId, eventType, properties } = req.body;

      if (!anonymousId || !eventType) {
        return res.status(400).json({ error: "Missing required fields" });
      }

      await db.insert(analyticsEvents).values({
        anonymousId,
        eventType,
        properties,
      });

      res.status(200).json({ success: true });
    } catch (error) {
      console.error("Analytics error:", error);
      // Don't block the client if analytics fails
      res.status(200).json({ success: false });
    }
  });

  const httpServer = createServer(app);
  return httpServer;
}