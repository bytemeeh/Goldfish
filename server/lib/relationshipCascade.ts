import { db } from "../../db";
import { contacts, type RelationshipType, getCascadedRelationshipType } from "../../db/schema";
import { sql } from "drizzle-orm";

export async function cascadeRelationship(tx: any, startingId: string) {
  // Use a single WITH RECURSIVE UPDATE to handle relationship cascading
  await tx.execute(sql`
    WITH RECURSIVE relationship_tree AS (
      -- Base case: start with the given contact
      SELECT id, parent_id, relationship_type, 0 as level
      FROM contacts 
      WHERE id = ${startingId}
      
      UNION ALL
      
      -- Recursive case: find all descendants
      SELECT c.id, c.parent_id, c.relationship_type, rt.level + 1
      FROM contacts c
      INNER JOIN relationship_tree rt ON c.parent_id = rt.id
    ),
    updated_relationships AS (
      UPDATE contacts 
      SET relationship_type = CASE 
        WHEN rt.level = 0 THEN contacts.relationship_type -- Keep original for starting contact
        WHEN rt.level = 1 THEN 'child' -- Direct children
        WHEN rt.level = 2 THEN 'child' -- Grandchildren also become children
        ELSE 'other' -- Great-grandchildren and beyond
      END
      FROM relationship_tree rt
      WHERE contacts.id = rt.id AND rt.level > 0
      RETURNING contacts.id, contacts.relationship_type
    )
    SELECT * FROM updated_relationships;
  `);
}