export type LocationType = 'home' | 'work' | 'other';

export interface Location {
  id?: number;
  contactId?: number;
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
  id: number;
  name: string;
  phone?: string;
  email?: string;
  birthday?: string;
  notes?: string;
  parentId?: number;
  relationshipType?: RelationshipType;
  isMe?: boolean;
  color?: string;
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
  | "boyfriend/girlfriend";