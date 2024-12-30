import { pgTable, text, serial, date, timestamp, integer, boolean } from "drizzle-orm/pg-core";
import { relations } from "drizzle-orm";
import { createInsertSchema, createSelectSchema } from "drizzle-zod";
import { z } from "zod";

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

export type RelationshipType = (typeof relationshipTypes)[number];

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
      child: "child" // Children of a spouse are also your children
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
    validChildTypes: ["sibling"],
    cascadeUpdates: {
      sibling: "sibling" // Siblings of your mother are your aunts/uncles (simplified as sibling for now)
    }
  },
  {
    parentType: "father",
    validChildTypes: ["sibling"],
    cascadeUpdates: {
      sibling: "sibling"
    }
  },
  {
    parentType: "sibling",
    validChildTypes: ["spouse", "child"],
    cascadeUpdates: {
      child: "child" // Children of your sibling are your nieces/nephews (simplified as child for now)
    }
  },
  {
    parentType: "friend",
    validChildTypes: ["spouse", "child", "friend"],
    cascadeUpdates: {
      child: "child",
      friend: "friend"
    }
  },
  {
    parentType: "child",
    validChildTypes: ["spouse", "child"],
    cascadeUpdates: {
      child: "child" // Children of your child are your grandchildren (simplified as child for now)
    }
  }
];

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
  shareDepth: integer("share_depth"), // How many levels deep to share (null means all)
  shareableUntil: timestamp("shareable_until", { mode: "string" }),
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
  console.log('Getting valid child types for parent type:', parentType);

  if (!parentType) {
    console.log('No parent type, returning all relationship types');
    return relationshipTypes;
  }

  const rule = relationshipCascadeRules.find(r => r.parentType === parentType);
  console.log('Found cascade rule:', rule);

  const validTypes = rule?.validChildTypes ?? [];
  console.log('Valid child types:', validTypes);

  return validTypes;
}

// Helper function to get cascaded relationship type
export function getCascadedRelationshipType(
  parentType: RelationshipType,
  childType: RelationshipType
): RelationshipType | undefined {
  console.log('Getting cascaded relationship type:', { parentType, childType });

  const rule = relationshipCascadeRules.find(r => r.parentType === parentType);
  console.log('Found cascade rule:', rule);

  const cascadedType = rule?.cascadeUpdates?.[childType];
  console.log('Cascaded type:', cascadedType);

  return cascadedType;
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

// Export types
export type Contact = typeof contacts.$inferSelect;
export type NewContact = typeof contacts.$inferInsert;