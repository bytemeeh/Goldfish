export type LocationType = 'home' | 'work' | 'other';

export interface Location {
  id?: string;
  contactId?: string;
  type: LocationType;
  name?: string;
  address?: string;
  latitude: string | number;
  longitude: string | number;
  street?: string;
  city?: string;
  state?: string;
  country?: string;
  postalCode?: string;
  isNew?: boolean;
  isDeleted?: boolean;
}

export interface Contact {
  id: string;
  name: string;
  type?: 'person' | 'pet';
  contextNotes?: string;
  phone?: string;
  email?: string;
  birthday?: string;
  notes?: string;
  parentId: string | null;
  relationshipType: RelationshipType | string | null;
  relationshipToUser?: string | null;
  isMe: boolean;
  color?: string;
  photo?: string;
  shareToken?: string;
  shareDepth?: number;
  shareableUntil?: string;
  // Single location fields (legacy support)
  street?: string;
  city?: string;
  state?: string;
  country?: string;
  postalCode?: string;
  latitude?: string;
  longitude?: string;
  // Multiple locations
  locations?: Location[];
  createdAt: string;
  updatedAt: string;
  children?: Contact[];
}

export type RelationshipType =
  | "sibling"
  | "mother"
  | "father"
  | "brother"
  | "friend"
  | "child"
  | "co-worker"
  | "spouse"
  | "boyfriend/girlfriend"
  | "pet";