import { Contact } from '@/lib/types';

export interface HierarchicalContact extends Contact {
  children: HierarchicalContact[];
  level: number;
  isRoot: boolean;
}

/**
 * Build a hierarchical tree from a flat array of contacts
 */
/**
 * Build a hierarchical tree from a flat array of contacts
 */
export function buildContactTree(contacts: Contact[]): HierarchicalContact[] {
  const contactMap = new Map<string, HierarchicalContact>();
  const roots: HierarchicalContact[] = [];

  // First pass: create all nodes
  contacts.forEach(contact => {
    contactMap.set(contact.id, {
      ...contact,
      children: [],
      level: 0,
      isRoot: !contact.parentId
    });
  });

  // Second pass: build parent-child relationships
  contacts.forEach(contact => {
    const node = contactMap.get(contact.id)!;

    if (contact.parentId) {
      const parent = contactMap.get(contact.parentId);
      if (parent) {
        parent.children.push(node);
        node.level = parent.level + 1;
      } else {
        // Parent doesn't exist, treat as root
        roots.push(node);
      }
    } else {
      roots.push(node);
    }
  });

  // Sort each level by relationship importance and name
  const sortContacts = (contacts: HierarchicalContact[]): HierarchicalContact[] => {
    return contacts.sort((a, b) => {
      // Prioritize "me" contact first
      if (a.isMe && !b.isMe) return -1;
      if (!a.isMe && b.isMe) return 1;

      // Then sort by relationship type importance
      const relationshipOrder = {
        'spouse': 1,
        'child': 2,
        'mother': 3,
        'father': 4,
        'sibling': 5,
        'brother': 6,
        'friend': 7,
        'co-worker': 8,
        'boyfriend/girlfriend': 9
      };

      const aOrder = relationshipOrder[a.relationshipType as keyof typeof relationshipOrder] || 10;
      const bOrder = relationshipOrder[b.relationshipType as keyof typeof relationshipOrder] || 10;

      if (aOrder !== bOrder) {
        return aOrder - bOrder;
      }

      // Finally sort by name
      return a.name.localeCompare(b.name);
    }).map(contact => ({
      ...contact,
      children: sortContacts(contact.children)
    }));
  };

  return sortContacts(roots);
}

/**
 * Flatten a hierarchical tree back to a list while preserving order
 */
export function flattenContactTree(tree: HierarchicalContact[]): HierarchicalContact[] {
  const result: HierarchicalContact[] = [];

  const traverse = (nodes: HierarchicalContact[]) => {
    nodes.forEach(node => {
      result.push(node);
      if (node.children.length > 0) {
        traverse(node.children);
      }
    });
  };

  traverse(tree);
  return result;
}

/**
 * Group contacts by family trees/networks
 */
export function groupByFamilyTrees(contacts: Contact[]): HierarchicalContact[][] {
  const tree = buildContactTree(contacts);
  const familyTrees: HierarchicalContact[][] = [];

  // Each root contact represents a family tree
  tree.forEach(root => {
    const familyMembers = flattenContactTree([root]);
    if (familyMembers.length > 0) {
      familyTrees.push(familyMembers);
    }
  });

  // Sort family trees by size (largest first) and then by "me" presence
  return familyTrees.sort((a, b) => {
    const aHasMe = a.some(contact => contact.isMe);
    const bHasMe = b.some(contact => contact.isMe);

    if (aHasMe && !bHasMe) return -1;
    if (!aHasMe && bHasMe) return 1;

    return b.length - a.length;
  });
}

/**
 * Calculate relationship levels for proximity-based sorting
 */
export function calculateRelationshipLevels(contacts: Contact[]): Map<string, number> {
  const levelMap = new Map<string, number>();
  const tree = buildContactTree(contacts);

  const assignLevels = (nodes: HierarchicalContact[], baseLevel: number = 0) => {
    nodes.forEach(node => {
      levelMap.set(node.id, baseLevel + node.level);
      assignLevels(node.children, baseLevel);
    });
  };

  assignLevels(tree);
  return levelMap;
}