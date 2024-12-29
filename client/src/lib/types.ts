export interface Contact {
  id: number;
  name: string;
  phone?: string;
  email?: string;
  birthday?: string;
  notes?: string;
  parentId?: number;
  relationshipType?: RelationshipType;
  createdAt: string;
  updatedAt: string;
}

export interface Relationship {
  id: number;
  parentId: number;
  childId: number;
  label: RelationshipLabel;
  createdAt: string;
}

export type RelationshipLabel = "friend" | "spouse" | "child" | "sibling" | "custom";
export type RelationshipType = "sibling" | "mother" | "father" | "brother" | "friend" | "child" | "co-worker";

export interface ContactWithChildren extends Contact {
  children?: Contact[];
}