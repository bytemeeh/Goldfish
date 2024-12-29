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
  createdAt: string;
  updatedAt: string;
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

export interface ContactWithChildren extends Contact {
  children?: Contact[];
}