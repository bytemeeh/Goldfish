import { pgTable, text, serial, date, timestamp, integer, boolean, jsonb, decimal, primaryKey } from "drizzle-orm/pg-core";
import { relations } from "drizzle-orm";
import { createInsertSchema, createSelectSchema } from "drizzle-zod";
import { z } from "zod";
import type { PgTableFn } from 'drizzle-orm/pg-core';

// Define relationship types first to avoid circular reference
export const relationshipTypes = [
  "sibling",
  "mother",
  "father",
  "brother",
  "friend",
  "child",
  "co-worker",
  "spouse",
  "boyfriend/girlfriend"
] as const;

export type RelationshipType = typeof relationshipTypes[number];

// Define relationship cascading rules
export type RelationshipCascadeRule = {
  parentType: RelationshipType;
  validChildTypes: RelationshipType[];
  cascadeUpdates?: {
    [K in RelationshipType]?: RelationshipType;
  };
};

export const relationshipCascadeRules: RelationshipCascadeRule[] = [
  {
    parentType: "spouse",
    validChildTypes: ["child"],
    cascadeUpdates: {
      child: "child"
    }
  },
  {
    parentType: "boyfriend/girlfriend",
    validChildTypes: ["child"],
    cascadeUpdates: {
      child: "child"
    }
  },
  {
    parentType: "mother",
    validChildTypes: ["sibling", "spouse"],
    cascadeUpdates: {
      sibling: "sibling",
      spouse: "father"
    }
  },
  {
    parentType: "father",
    validChildTypes: ["sibling", "spouse"],
    cascadeUpdates: {
      sibling: "sibling",
      spouse: "mother"
    }
  },
  {
    parentType: "sibling",
    validChildTypes: ["spouse", "child"],
  },
  {
    parentType: "friend",
    validChildTypes: ["spouse", "child", "friend"],
  },
  {
    parentType: "child",
    validChildTypes: ["spouse", "child"],
  },
  {
    parentType: "co-worker",
    validChildTypes: ["spouse", "child"],
  }
];

// Define the contacts table
export const contacts = pgTable("contacts", {
  id: serial("id").primaryKey(),
  name: text("name").notNull(),
  phone: text("phone"),
  email: text("email"),
  birthday: date("birthday", { mode: 'string' }),
  notes: text("notes"),
  parentId: integer("parent_id").references(() => contacts.id, { onDelete: "cascade" }),
  relationshipType: text("relationship_type", { enum: relationshipTypes }),
  isMe: boolean("is_me").default(false),
  shareToken: text("share_token").unique(),
  shareDepth: integer("share_depth"),
  shareableUntil: timestamp("shareable_until", { mode: "string" }),
  // Address and location fields
  street: text("street"),
  city: text("city"),
  state: text("state"),
  country: text("country"),
  postalCode: text("postal_code"),
  latitude: text("latitude"),
  longitude: text("longitude"),
  // Import fields
  importSource: text("import_source"),
  externalId: text("external_id"),
  createdAt: timestamp("created_at", { mode: "string" }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { mode: "string" }).notNull().defaultNow(),
});

// Define relations for the self-referential relationship
export const contactsRelations = relations(contacts, ({ one, many }) => ({
  parent: one(contacts, {
    fields: [contacts.parentId],
    references: [contacts.id],
  }),
  children: many(contacts),
}));

// Helper function to get valid child relationship types for a given parent type
export function getValidChildRelationshipTypes(parentType: RelationshipType | null | undefined): RelationshipType[] {
  if (!parentType) {
    return [...relationshipTypes];
  }

  const rule = relationshipCascadeRules.find(r => r.parentType === parentType);
  return rule?.validChildTypes ?? [];
}

// Helper function to get cascaded relationship type
export function getCascadedRelationshipType(
  parentType: RelationshipType,
  childType: RelationshipType
): RelationshipType | undefined {
  const rule = relationshipCascadeRules.find(r => r.parentType === parentType);
  return rule?.cascadeUpdates?.[childType];
}

// Create Zod schemas with proper validation
export const insertContactSchema = createInsertSchema(contacts, {
  name: z.string().min(1, "Name is required"),
  email: z.string().email("Invalid email").nullable().optional(),
  phone: z.string().optional().nullable(),
  birthday: z.string().optional().nullable(),
  notes: z.string().optional().nullable(),
  parentId: z.number().optional().nullable(),
  relationshipType: z.enum(relationshipTypes).optional().nullable(),
  isMe: z.boolean().optional(),
  shareToken: z.string().optional().nullable(),
  shareDepth: z.number().optional().nullable(),
  shareableUntil: z.string().optional().nullable(),
});

export const selectContactSchema = createSelectSchema(contacts);

// Define the location types
export const locationTypes = [
  "home",
  "work",
  "other"
] as const;

export type LocationType = typeof locationTypes[number];

// Define the locations table
export const locations = pgTable("locations", {
  id: serial("id").primaryKey(),
  contactId: integer("contact_id").notNull().references(() => contacts.id, { onDelete: "cascade" }),
  type: text("type", { enum: locationTypes }).notNull().default("other"),
  name: text("name"),
  address: text("address"),
  latitude: decimal("latitude", { precision: 10, scale: 7 }),
  longitude: decimal("longitude", { precision: 10, scale: 7 }),
  createdAt: timestamp("created_at", { mode: "string" }).notNull().defaultNow(),
  updatedAt: timestamp("updated_at", { mode: "string" }).notNull().defaultNow(),
});

// Define relations for locations
export const locationsRelations = relations(locations, ({ one }) => ({
  contact: one(contacts, {
    fields: [locations.contactId],
    references: [contacts.id],
  }),
}));

// Add locations relation to contacts
export const contactsRelationsWithLocations = relations(contacts, ({ one, many }) => ({
  parent: one(contacts, {
    fields: [contacts.parentId],
    references: [contacts.id],
  }),
  children: many(contacts),
  locations: many(locations),
}));

// Create Zod schemas for locations
export const insertLocationSchema = createInsertSchema(locations, {
  type: z.enum(locationTypes).default("other"),
  name: z.string().optional().nullable(),
  address: z.string().optional().nullable(),
  latitude: z.number().min(-90).max(90).optional().nullable(),
  longitude: z.number().min(-180).max(180).optional().nullable(),
});

export const selectLocationSchema = createSelectSchema(locations);

// Export types
export type Contact = typeof contacts.$inferSelect;
export type NewContact = typeof contacts.$inferInsert;
export type Location = typeof locations.$inferSelect;
export type NewLocation = typeof locations.$inferInsert;