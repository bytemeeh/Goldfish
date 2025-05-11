import { useCallback, useEffect, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Contact } from '@/lib/types';

import ReactFlow, {
  Node,
  Edge,
  Controls,
  Background,
  MiniMap,
  NodeMouseHandler,
  useNodesState,
  useEdgesState,
  Position,
} from 'reactflow';
import 'reactflow/dist/style.css';

// Custom node types
import { ContactNode } from './flow-nodes/ContactNode';

// Define node data interface
interface ContactNodeData {
  contact: Contact;
  level: number;
  isSelected: boolean;
}

interface ContactFlowGraphProps {
  onContactSelect?: (contactId: number) => void;
}

// Color theme for different relationship types
const relationshipColors = {
  family: '#00ACE6',       // Cyan Blue (family: mother, father, brother, sibling, child, spouse)
  friends: '#FF0080',      // Bright Pink (friend, boyfriend/girlfriend)
  professional: '#FF8000', // Orange (co-worker)
  personal: '#00B359',     // Green (personal/me)
  default: '#6B7280'       // Default gray
};

export function ContactFlowGraph({ onContactSelect }: ContactFlowGraphProps) {
  const [nodes, setNodes, onNodesChange] = useNodesState([]);
  const [edges, setEdges, onEdgesChange] = useEdgesState([]);
  const [selectedContactId, setSelectedContactId] = useState<number | null>(null);

  // Define the node types mapping
  const nodeTypes = {
    contactNode: ContactNode,
  };

  // Get contacts data
  const { data: contacts } = useQuery<Contact[]>({
    queryKey: ['/api/contacts'],
  });

  // Determine relationship type color
  const getRelationshipColor = (relationshipType?: string) => {
    if (!relationshipType) return relationshipColors.default;
    
    const categories = {
      family: ['mother', 'father', 'brother', 'sibling', 'child', 'spouse'],
      friends: ['friend', 'boyfriend/girlfriend'],
      professional: ['co-worker']
    };
    
    if (categories.family.includes(relationshipType)) {
      return relationshipColors.family;
    } else if (categories.friends.includes(relationshipType)) {
      return relationshipColors.friends;
    } else if (categories.professional.includes(relationshipType)) {
      return relationshipColors.professional;
    }
    
    return relationshipColors.default;
  };

  // Transform contacts data to nodes and edges
  useEffect(() => {
    if (!contacts?.length) return;

    // Find the "me" contact
    const meContact = contacts.find(c => c.isMe);
    
    // Track processed contacts to avoid duplicates
    const processedContacts = new Set<number>();
    
    // Create nodes and edges arrays
    const newNodes: Node<ContactNodeData>[] = [];
    const newEdges: Edge[] = [];
    
    // Process contact hierarchy recursively
    const processContact = (
      contact: Contact, 
      level: number = 0,
      x: number = 0,
      y: number = 0,
      parentId?: number
    ) => {
      if (processedContacts.has(contact.id)) return;
      processedContacts.add(contact.id);
      
      // Create node for this contact
      const node: Node<ContactNodeData> = {
        id: contact.id.toString(),
        type: 'contactNode',
        data: {
          contact,
          level,
          isSelected: contact.id === selectedContactId
        },
        position: { x, y },
        sourcePosition: Position.Bottom,
        targetPosition: Position.Top,
      };
      
      newNodes.push(node);
      
      // Create edge if there's a parent
      if (parentId !== undefined) {
        newEdges.push({
          id: `${parentId}-${contact.id}`,
          source: parentId.toString(),
          target: contact.id.toString(),
          animated: false,
          style: {
            stroke: getRelationshipColor(contact.relationshipType),
            strokeWidth: 2
          }
        });
      }
      
      // Process children
      const children = contacts.filter(c => c.parentId === contact.id);
      const childCount = children.length;
      
      if (childCount > 0) {
        const spacing = 150;
        const totalWidth = (childCount - 1) * spacing;
        const startX = x - totalWidth / 2;
        
        children.forEach((child, index) => {
          const childX = startX + index * spacing;
          const childY = y + 120; // Vertical spacing
          processContact(child, level + 1, childX, childY, contact.id);
        });
      }
    };
    
    // Start processing from "me" contact or top-level contacts
    if (meContact) {
      processContact(meContact, 0, 0, 0);
      
      // Process any other top-level contacts (not connected to "me")
      const otherTopLevelContacts = contacts.filter(c => 
        !c.isMe && !c.parentId && !processedContacts.has(c.id)
      );
      
      if (otherTopLevelContacts.length > 0) {
        const spacing = 250;
        const totalWidth = (otherTopLevelContacts.length - 1) * spacing;
        const startX = -totalWidth / 2;
        
        otherTopLevelContacts.forEach((contact, index) => {
          const x = startX + index * spacing;
          const y = -200; // Position above the "me" contact
          processContact(contact, 0, x, y);
          
          // Add edge from "me" to this top-level contact
          newEdges.push({
            id: `${meContact.id}-${contact.id}`,
            source: meContact.id.toString(),
            target: contact.id.toString(),
            animated: false,
            style: {
              stroke: getRelationshipColor(contact.relationshipType),
              strokeWidth: 1.5,
              strokeDasharray: '5,5' // Dashed line for indirect connections
            }
          });
        });
      }
    } else {
      // No "me" contact, process all top-level contacts
      const topLevelContacts = contacts.filter(c => !c.parentId);
      const spacing = 200;
      const totalWidth = (topLevelContacts.length - 1) * spacing;
      const startX = -totalWidth / 2;
      
      topLevelContacts.forEach((contact, index) => {
        const x = startX + index * spacing;
        processContact(contact, 0, x, 0);
      });
    }
    
    setNodes(newNodes);
    setEdges(newEdges);
  }, [contacts, selectedContactId]);

  // Handle node click
  const onNodeClick: NodeMouseHandler = useCallback((_, node) => {
    const contactId = parseInt(node.id);
    
    if (!isNaN(contactId)) {
      setSelectedContactId(contactId);
      
      if (onContactSelect) {
        console.log('🔄 ContactFlowGraph - Node clicked, calling onContactSelect with ID:', contactId);
        onContactSelect(contactId);
      }
    }
  }, [onContactSelect]);

  if (!contacts) {
    return (
      <div className="p-4 text-center text-muted-foreground">
        Loading contacts...
      </div>
    );
  }

  return (
    <div className="w-full h-[calc(100vh-12rem)] bg-card rounded-lg border shadow-sm overflow-hidden">
      <ReactFlow
        nodes={nodes}
        edges={edges}
        onNodesChange={onNodesChange}
        onEdgesChange={onEdgesChange}
        onNodeClick={onNodeClick}
        nodeTypes={nodeTypes}
        proOptions={{ hideAttribution: true }}
        fitView
      >
        <Controls />
        <MiniMap zoomable pannable />
        <Background color="#aaa" gap={16} />
      </ReactFlow>
    </div>
  );
}