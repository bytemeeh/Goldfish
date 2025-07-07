import { z } from 'zod';

export const reparentSchema = z.object({
  parentId: z.number().int().positive().nullable(),
});

export type ReparentRequest = z.infer<typeof reparentSchema>;