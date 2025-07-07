import type { Express } from "express";
import { createServer, type Server } from "http";
import { db } from "@db";
import { contacts, locations, insertContactSchema, insertLocationSchema, getCascadedRelationshipType, getValidChildRelationshipTypes, type RelationshipType, type Location } from "@db/schema";
import { and, or, eq, ilike, sql, inArray } from "drizzle-orm";

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
      
      // First get all contacts matching the filters
      const contactsResult = await db
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
          // Legacy location fields
          street: contacts.street,
          city: contacts.city,
          state: contacts.state,
          country: contacts.country,
          postalCode: contacts.postalCode,
          latitude: contacts.latitude,
          longitude: contacts.longitude,
          createdAt: contacts.createdAt,
          updatedAt: contacts.updatedAt,
        })
        .from(contacts)
        .orderBy(contacts.name);

      console.log('Found contacts:', contactsResult.length);
      console.log('Contact hierarchy:', contactsResult.map(c => ({
        id: c.id,
        name: c.name,
        parentId: c.parentId,
        relationshipType: c.relationshipType
      })));
      
      // If we have contacts, get their locations
      if (contactsResult.length > 0) {
        // Get all locations for all contacts in one query
        const contactIds = contactsResult.map(c => c.id);
        
        // Need to use parameterized queries instead of string concatenation
        let allLocations: Location[] = [];
        if (contactIds.length > 0) {
          // Process in batches of 10 to avoid query parameter issues
          for (let i = 0; i < contactIds.length; i += 10) {
            const batchIds = contactIds.slice(i, i + 10);
            const batchLocations = await Promise.all(
              batchIds.map(contactId => 
                db
                  .select()
                  .from(locations)
                  .where(eq(locations.contactId, contactId))
              )
            );
            
            // Flatten the results
            allLocations = [
              ...allLocations,
              ...batchLocations.flat()
            ];
          }
          
          console.log(`Found ${allLocations.length} total locations for ${contactIds.length} contacts`);
        }
        
        // Group locations by contact ID
        const locationsByContactId: Record<number, Location[]> = {};
        allLocations.forEach(loc => {
          if (!locationsByContactId[loc.contactId]) {
            locationsByContactId[loc.contactId] = [];
          }
          locationsByContactId[loc.contactId].push(loc);
        });
        
        // Add locations to each contact
        const contactsWithLocations = contactsResult.map(contact => ({
          ...contact,
          locations: locationsByContactId[contact.id] || [],
        }));
        
        res.json(contactsWithLocations);
      } else {
        res.json(contactsResult); // Return empty array if no contacts found
      }
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

      // Get locations for this contact
      const contactLocations = await db
        .select()
        .from(locations)
        .where(eq(locations.contactId, parseInt(id)));

      console.log(`Found ${contactLocations.length} locations for contact ${contact.name}`);

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
        locations: contactLocations,
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

      // Extract locations from request body
      const { locations: locationData, ...contactData } = req.body;
      
      // Validate the contact data
      const validatedContactData = insertContactSchema.parse(contactData);
      console.log('Validated contact data:', validatedContactData);

      // Insert the contact first
      const [newContact] = await db
        .insert(contacts)
        .values({
          ...validatedContactData,
        })
        .returning();

      console.log('Created new contact:', newContact);

      // Now handle the locations if any
      if (locationData && Array.isArray(locationData) && locationData.length > 0) {
        console.log(`Adding ${locationData.length} locations for new contact`);
        
        // Process each location individually to avoid type issues
        for (const location of locationData) {
          const preparedLocation = {
            ...location,
            contactId: newContact.id,
            createdAt: new Date().toISOString(),
            updatedAt: new Date().toISOString(),
            // Remove client-side flags if any
            isNew: undefined,
            isDeleted: undefined
          };
          
          await db
            .insert(locations)
            .values(preparedLocation);
        }
          
        console.log(`Added ${locationData.length} locations for contact`);
      }

      if (validatedContactData.parentId && validatedContactData.relationshipType) {
        console.log('Initiating cascade update for new contact');
        // Trigger cascading updates if this is a child contact
        await updateRelationshipsCascading(
          newContact.id,
          validatedContactData.parentId,
          validatedContactData.relationshipType as RelationshipType
        );
      }

      // Return the contact with locations
      const contactLocations = await db
        .select()
        .from(locations)
        .where(eq(locations.contactId, newContact.id));
        
      res.json({
        ...newContact,
        locations: contactLocations
      });
    } catch (error) {
      console.error('Error creating contact:', error);
      res.status(400).json({ 
        message: error instanceof Error ? error.message : "Failed to create contact" 
      });
    }
  });

  app.put("/api/contacts/:id", async (req, res) => {
    const { id } = req.params;
    const contactId = parseInt(id);

    try {
      console.log(`Updating contact with ID ${id}, Data: `, req.body);
      
      // Extract locations from request body
      const { locations: locationData, ...contactData } = req.body;
      
      // Validate the contact data
      const validatedContactData = insertContactSchema.parse(contactData);
      console.log('Validated contact data:', validatedContactData);

      // Update the contact
      const [updatedContact] = await db
        .update(contacts)
        .set({ 
          ...validatedContactData,
          updatedAt: new Date().toISOString()
        })
        .where(eq(contacts.id, contactId))
        .returning();

      console.log('Updated contact:', updatedContact);
      
      // Handle locations if they're provided
      if (locationData && Array.isArray(locationData) && locationData.length > 0) {
        console.log(`Processing ${locationData.length} locations for contact ${id}`);
        
        // Group locations into new, updated, and deleted
        const newLocations = locationData.filter(loc => !loc.id || (loc.id && loc.id < 0));
        const existingLocations = locationData.filter(loc => loc.id && loc.id > 0 && !loc.isDeleted);
        const deletedLocationIds = locationData
          .filter(loc => loc.id && loc.id > 0 && loc.isDeleted)
          .map(loc => loc.id);
          
        console.log(`Locations breakdown - New: ${newLocations.length}, Updated: ${existingLocations.length}, Deleted: ${deletedLocationIds.length}`);
        
        // Delete locations that are marked for deletion
        if (deletedLocationIds.length > 0) {
          // Delete in batches to avoid SQL issues
          for (let i = 0; i < deletedLocationIds.length; i++) {
            const locationId = deletedLocationIds[i];
            await db
              .delete(locations)
              .where(eq(locations.id, locationId));
          }
          console.log(`Deleted ${deletedLocationIds.length} locations`);
        }
        
        // Update existing locations
        for (const location of existingLocations) {
          // Process latitude and longitude appropriately
          let latitude = null;
          let longitude = null;
          
          if (location.latitude && location.latitude.toString().trim() !== '') {
            latitude = Number(location.latitude);
            if (isNaN(latitude)) latitude = null;
          }
          
          if (location.longitude && location.longitude.toString().trim() !== '') {
            longitude = Number(location.longitude);
            if (isNaN(longitude)) longitude = null;
          }
          
          await db
            .update(locations)
            .set({
              ...location,
              contactId, // Ensure correct contact ID
              latitude,
              longitude,
              updatedAt: new Date().toISOString(),
              // Remove client-side flags
              isNew: undefined,
              isDeleted: undefined
            })
            .where(eq(locations.id, location.id));
        }
        console.log(`Updated ${existingLocations.length} existing locations`);
        
        // Insert new locations
        if (newLocations.length > 0) {
          // Process each new location individually
          for (const location of newLocations) {
            // Process latitude and longitude appropriately
            let latitude = null;
            let longitude = null;
            
            if (location.latitude && location.latitude.toString().trim() !== '') {
              latitude = Number(location.latitude);
              if (isNaN(latitude)) latitude = null;
            }
            
            if (location.longitude && location.longitude.toString().trim() !== '') {
              longitude = Number(location.longitude);
              if (isNaN(longitude)) longitude = null;
            }

            const preparedLocation = {
              ...location,
              id: undefined, // Remove any temporary ID
              contactId,
              latitude,
              longitude,
              createdAt: new Date().toISOString(),
              updatedAt: new Date().toISOString(),
              // Remove client-side flags
              isNew: undefined,
              isDeleted: undefined
            };
            
            await db
              .insert(locations)
              .values(preparedLocation);
          }
            
          console.log(`Inserted ${newLocations.length} new locations`);
        }
      }

      // Trigger cascading updates if relationship type changed
      if (validatedContactData.relationshipType) {
        console.log('Initiating cascade update for updated contact');
        await updateRelationshipsCascading(
          contactId,
          validatedContactData.parentId,
          validatedContactData.relationshipType as RelationshipType
        );
      }

      // Return the updated contact with locations
      const contactLocations = await db
        .select()
        .from(locations)
        .where(eq(locations.contactId, contactId));
        
      res.json({
        ...updatedContact,
        locations: contactLocations
      });
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