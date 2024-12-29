import { pgTable, text, serial, date, timestamp } from "drizzle-orm/pg-core";
import { relations } from "drizzle-orm";
import { createInsertSchema, createSelectSchema } from "drizzle-zod";
import { z } from "zod";

export const contacts = pgTable("contacts", {
  id: serial("id").primaryKey(),
  name: text("name").notNull(),
  phone: text("phone"),
  email: text("email"),
  birthday: date("birthday", { mode: 'string' }),
  notes: text("notes"),
  parentId: serial("parent_id").references(() => contacts.id, { onDelete: "cascade" }),
  createdAt: timestamp("created_at").defaultNow().notNull(),
  updatedAt: timestamp("updated_at").defaultNow().notNull(),
});

export const relationships = pgTable("relationships", {
  id: serial("id").primaryKey(),
  parentId: serial("parent_id").references(() => contacts.id, { onDelete: "cascade" }).notNull(),
  childId: serial("child_id").references(() => contacts.id, { onDelete: "cascade" }).notNull(),
  label: text("label", { enum: ["friend", "spouse", "child", "sibling", "custom"] }).notNull(),
  createdAt: timestamp("created_at").defaultNow().notNull(),
});

// Define relations
export const contactRelations = relations(contacts, ({ one }) => ({
  parent: one(contacts, {
    fields: [contacts.parentId],
    references: [contacts.id],
  }),
}));

export const relationshipRelations = relations(relationships, ({ one }) => ({
  parent: one(contacts, {
    fields: [relationships.parentId],
    references: [contacts.id],
  }),
  child: one(contacts, {
    fields: [relationships.childId],
    references: [contacts.id],
  }),
}));

// Create schemas
export const insertContactSchema = createInsertSchema(contacts);
export const selectContactSchema = createSelectSchema(contacts);
export const insertRelationshipSchema = createInsertSchema(relationships);
export const selectRelationshipSchema = createSelectSchema(relationships);

// Export types
export type Contact = typeof contacts.$inferSelect;
export type NewContact = typeof contacts.$inferInsert;
export type Relationship = typeof relationships.$inferSelect;
export type NewRelationship = typeof relationships.$inferInsert;