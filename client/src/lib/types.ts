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
  shareToken?: string;
  shareDepth?: number;
  shareableUntil?: string;
  // Location fields
  street?: string;
  city?: string;
  state?: string;
  country?: string;
  postalCode?: string;
  latitude?: string;
  longitude?: string;
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