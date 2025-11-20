import { z } from 'zod';

export const reparentSchema = z.object({
  parentId: z.string().uuid().nullable(),
});

export type ReparentRequest = z.infer<typeof reparentSchema>;