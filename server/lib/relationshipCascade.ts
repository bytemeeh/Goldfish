
import { sql } from "drizzle-orm";
import type { DrizzleTransaction } from "@/db";

export async function cascadeRelationship(tx: DrizzleTransaction, startingId: string) {
  await tx.execute(sql`
    WITH RECURSIVE d AS (
      SELECT id, parent_id, relationship FROM contacts WHERE id = ${startingId}
      UNION ALL
      SELECT c.id, c.parent_id, c.relationship
        FROM contacts c JOIN d ON c.parent_id = d.id
    )
    UPDATE contacts AS c
      SET relationship = rules.new_type,
          updated_at   = now()
      FROM relationship_cascade_rules AS rules,
           d
      WHERE c.id = d.id
        AND rules.parent_type = d.relationship
        AND rules.child_type  = c.relationship
        AND c.id <> ${startingId};
  `);
}
