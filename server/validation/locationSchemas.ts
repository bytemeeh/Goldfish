
import { z } from "zod";

export const insertLocationSchema = z.object({
  label: z.string().max(30),
  address: z.string().max(255),
  latitude: z.number().gte(-90).lte(90),
  longitude: z.number().gte(-180).lte(180),
});

export const updateLocationSchema = insertLocationSchema.partial();

export type InsertLocationData = z.infer<typeof insertLocationSchema>;
export type UpdateLocationData = z.infer<typeof updateLocationSchema>;
