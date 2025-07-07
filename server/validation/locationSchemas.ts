import { z } from 'zod';

export const locationSchema = z.object({
  id: z.string().uuid().optional(),
  contactId: z.string().uuid().optional(),
  type: z.enum(['home', 'work', 'other']),
  name: z.string().optional(),
  address: z.string().optional(),
  latitude: z.number().gte(-90).lte(90),
  longitude: z.number().gte(-180).lte(180),
  street: z.string().optional(),
  city: z.string().optional(),
  state: z.string().optional(),
  country: z.string().optional(),
  postalCode: z.string().optional(),
  isNew: z.boolean().optional(),
  isDeleted: z.boolean().optional(),
});

export const createLocationSchema = locationSchema.omit({ id: true });
export const updateLocationSchema = locationSchema.partial();