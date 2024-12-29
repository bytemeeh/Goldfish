import { pgTable, text, serial, date, timestamp } from "drizzle-orm/pg-core";
import { relations, sql } from "drizzle-orm";
import { createInsertSchema, createSelectSchema } from "drizzle-zod";

export const contacts = pgTable("contacts", {
  id: serial("id").primaryKey(),
  name: text("name").notNull(),
  phone: text("phone"),
  email: text("email"),
  birthday: date("birthday", { mode: 'string' }),
  notes: text("notes"),
  parentId: serial("parent_id").references(() => contacts.id, { onDelete: "cascade" }),
  createdAt: timestamp("created_at").default(sql`CURRENT_TIMESTAMP`).notNull(),
  updatedAt: timestamp("updated_at").default(sql`CURRENT_TIMESTAMP`).notNull(),
});

// Define relations for the self-referential relationship
export const contactsRelations = relations(contacts, ({ one, many }) => ({
  parent: one(contacts, {
    fields: [contacts.parentId],
    references: [contacts.id],
  }),
  children: many(contacts),
}));

// Create schemas
export const insertContactSchema = createInsertSchema(contacts);
export const selectContactSchema = createSelectSchema(contacts);

// Export types
export type Contact = typeof contacts.$inferSelect;
export type NewContact = typeof contacts.$inferInsert;