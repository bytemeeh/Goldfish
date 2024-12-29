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

export const contacts = pgTable("contacts", {
  id: serial("id").primaryKey(),
  name: text("name").notNull(),
  phone: text("phone"),
  email: text("email"),
  birthday: date("birthday", { mode: 'string' }),
  notes: text("notes"),
  parentId: integer("parent_id").references(() => contacts.id, { onDelete: "cascade" }),
  relationshipType: text("relationship_type"),
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

// Create Zod schemas with proper validation
export const insertContactSchema = createInsertSchema(contacts, {
  name: z.string().min(1, "Name is required"),
  email: z.string().email("Invalid email").nullable().optional().or(z.literal('')),
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
export type RelationshipType = typeof relationshipTypes[number];