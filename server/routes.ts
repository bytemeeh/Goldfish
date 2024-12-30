import type { Express } from "express";
import { createServer, type Server } from "http";
import { db } from "@db";
import { contacts, insertContactSchema, getCascadedRelationshipType, getValidChildRelationshipTypes, type RelationshipType } from "@db/schema";
import { and, or, eq, ilike, sql } from "drizzle-orm";
import NodeGeocoder from "node-geocoder";

// Initialize geocoder
const geocoder = NodeGeocoder({
  provider: 'openstreetmap'
});

interface SearchFilters {
  name?: string;
  email?: string;
  phone?: string;
  notes?: string;
}

// Helper to calculate distance between two points
function calculateDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371; // Earth's radius in km
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = 
    Math.sin(dLat/2) * Math.sin(dLat/2) +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * 
    Math.sin(dLon/2) * Math.sin(dLon/2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
  return R * c;
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
        .select()
        .from(contacts)
        .orderBy(contacts.name);

      // Get user's location from IP (fallback to San Francisco coordinates)
      const userLat = 37.7749; // San Francisco latitude
      const userLon = -122.4194; // San Francisco longitude

      // Sort contacts by distance if they have coordinates
      const sortedContacts = result
        .map(contact => ({
          ...contact,
          distance: contact.latitude && contact.longitude
            ? calculateDistance(userLat, userLon, Number(contact.latitude), Number(contact.longitude))
            : Infinity
        }))
        .sort((a, b) => a.distance - b.distance);

      console.log('Found contacts:', sortedContacts.length);
      res.json(sortedContacts);
    } catch (error) {
      console.error('Error fetching contacts:', error);
      res.status(500).json({ message: "Failed to fetch contacts" });
    }
  });

  // Single contact endpoint
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

      const validChildTypes = contact.relationshipType
        ? getValidChildRelationshipTypes(contact.relationshipType as RelationshipType)
        : [];

      const relatedContacts = await db
        .select()
        .from(contacts)
        .where(
          or(
            eq(contacts.parentId, contact.id),
            contact.parentId ? eq(contacts.id, contact.parentId) : sql`false`
          )
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

  // Create contact endpoint
  app.post("/api/contacts", async (req, res) => {
    try {
      console.log('Creating new contact with data:', req.body);
      const validatedData = insertContactSchema.parse(req.body);

      // Geocode address if provided
      if (validatedData.street && validatedData.city) {
        try {
          const addressStr = `${validatedData.street}, ${validatedData.city}${validatedData.state ? `, ${validatedData.state}` : ''}${validatedData.country ? `, ${validatedData.country}` : ''}`;
          const [location] = await geocoder.geocode(addressStr);
          if (location) {
            validatedData.latitude = location.latitude;
            validatedData.longitude = location.longitude;
          }
        } catch (error) {
          console.error('Geocoding error:', error);
        }
      }

      const [newContact] = await db
        .insert(contacts)
        .values(validatedData)
        .returning();

      if (validatedData.parentId && validatedData.relationshipType) {
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

  // Update contact endpoint
  app.put("/api/contacts/:id", async (req, res) => {
    const { id } = req.params;

    try {
      const validatedData = insertContactSchema.parse(req.body);

      // Geocode new address if changed
      if (validatedData.street && validatedData.city) {
        try {
          const addressStr = `${validatedData.street}, ${validatedData.city}${validatedData.state ? `, ${validatedData.state}` : ''}${validatedData.country ? `, ${validatedData.country}` : ''}`;
          const [location] = await geocoder.geocode(addressStr);
          if (location) {
            validatedData.latitude = location.latitude;
            validatedData.longitude = location.longitude;
          }
        } catch (error) {
          console.error('Geocoding error:', error);
        }
      }

      const [updatedContact] = await db
        .update(contacts)
        .set({ 
          ...validatedData,
          updatedAt: new Date().toISOString()
        })
        .where(eq(contacts.id, parseInt(id)))
        .returning();

      if (validatedData.relationshipType) {
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

  // Delete contact endpoint
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