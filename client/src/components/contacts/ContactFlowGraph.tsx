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
  NodeProps,
  Handle,
} from 'reactflow';
import 'reactflow/dist/style.css';

// We'll define the ContactNode component directly in this file
// until we resolve the import issues
import { memo } from 'react';
import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import { Badge } from '@/components/ui/badge';

// Color theme for different relationship types with higher contrast
const relationshipNodeColors = {
  family: {
    bg: 'bg-[#00ACE6]/25',
    border: 'border-[#00ACE6]',
    text: 'text-[#00ACE6]'
  },
  friends: {
    bg: 'bg-[#FF0080]/25',
    border: 'border-[#FF0080]',
    text: 'text-[#FF0080]'
  },
  professional: {
    bg: 'bg-[#FF8000]/25',
    border: 'border-[#FF8000]',
    text: 'text-[#FF8000]'
  },
  personal: {
    bg: 'bg-[#00B359]/25',
    border: 'border-[#00B359]',
    text: 'text-[#00B359]'
  },
  default: {
    bg: 'bg-gray-200',
    border: 'border-gray-400',
    text: 'text-gray-700'
  }
};

// ContactNode component
export const ContactNode = memo(({ data }: NodeProps<ContactNodeData>) => {
  const { contact, level, isSelected } = data;
  
  // Determine style based on relationship type
  const getNodeStyle = () => {
    if (contact.isMe) {
      return relationshipNodeColors.personal;
    }
    
    const relType = contact.relationshipType || 'default';
    
    const categories = {
      family: ['mother', 'father', 'brother', 'sibling', 'child', 'spouse'],
      friends: ['friend', 'boyfriend/girlfriend'],
      professional: ['co-worker']
    };
    
    if (categories.family.includes(relType)) {
      return relationshipNodeColors.family;
    } else if (categories.friends.includes(relType)) {
      return relationshipNodeColors.friends;
    } else if (categories.professional.includes(relType)) {
      return relationshipNodeColors.professional;
    }
    
    return relationshipNodeColors.default;
  };
  
  const nodeStyle = getNodeStyle();
  
  // Generate initials for avatar
  const getInitials = (name: string) => {
    return name
      .split(' ')
      .map(part => part[0])
      .join('')
      .toUpperCase()
      .substring(0, 2);
  };
  
  return (
    <div
      className={`
        group relative w-36 rounded-md border-2 p-3 transition-all duration-200
        ${nodeStyle.bg} ${nodeStyle.border} bg-white
        ${isSelected ? 'border-primary shadow-lg border-[3px] scale-110' : 'shadow-md hover:shadow-lg'}
        cursor-pointer hover:scale-105
      `}
    >
      <Handle type="target" position={Position.Top} className="!bg-muted-foreground" />
      
      <div className="flex flex-col items-center gap-1">
        <Avatar className={`w-12 h-12 ${isSelected ? 'ring-2 ring-primary' : 'ring-1 ring-gray-300'} shadow-sm`}>
          <AvatarFallback className={`text-base font-semibold ${nodeStyle.text} bg-white`}>
            {getInitials(contact.name)}
          </AvatarFallback>
        </Avatar>
        
        <div className="text-center mt-1">
          <h3 className="font-medium text-foreground truncate max-w-full">
            {contact.name}
          </h3>
          
          {contact.relationshipType && (
            <Badge 
              variant="outline" 
              className={`mt-1 text-xs ${nodeStyle.text} ${nodeStyle.border}`}
            >
              {contact.relationshipType}
            </Badge>
          )}
          
          {contact.isMe && (
            <Badge 
              variant="outline" 
              className="mt-1 text-xs bg-primary/10 border-primary text-primary"
            >
              You
            </Badge>
          )}
          
          <div className="text-xs text-muted-foreground mt-1">
            Level {level}
          </div>
        </div>
      </div>
      
      <Handle type="source" position={Position.Bottom} className="!bg-muted-foreground" />
    </div>
  );
});

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

// Memoize node types to avoid React warning
const nodeTypes = {
  contactNode: ContactNode as any,
};

export function ContactFlowGraph({ onContactSelect }: ContactFlowGraphProps) {
  const [nodes, setNodes, onNodesChange] = useNodesState([]);
  const [edges, setEdges, onEdgesChange] = useEdgesState([]);
  const [selectedContactId, setSelectedContactId] = useState<number | null>(null);

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
        // Calculate horizontal spacing based on the deepest subtree
        // This prevents nodes in deeper levels from overlapping
        const calculateMaxDepth = (contactId: number, currentDepth = 0): number => {
          const childContacts = contacts.filter(c => c.parentId === contactId);
          if (childContacts.length === 0) return currentDepth;
          
          return Math.max(...childContacts.map(c => 
            calculateMaxDepth(c.id, currentDepth + 1)
          ));
        };
        
        // Get the maximum depth of each child's subtree
        const maxDepths = children.map(child => calculateMaxDepth(child.id));
        const maxDepth = Math.max(...maxDepths, 1);
        
        // Increase spacing based on the depth of the subtree and number of children
        const baseSpacing = 400; // Increased base spacing
        const depthFactor = 150; // Increased additional spacing per depth level
        const childFactor = 30; // Additional spacing per child in this level
        const spacing = baseSpacing + (maxDepth * depthFactor) + (childCount * childFactor);
        
        const totalWidth = (childCount - 1) * spacing;
        const startX = x - totalWidth / 2;
        
        // Sort children to place those with more descendants in the middle
        const sortedChildren = [...children].sort((a, b) => {
          const aChildCount = contacts.filter(c => c.parentId === a.id).length;
          const bChildCount = contacts.filter(c => c.parentId === b.id).length;
          
          // If both have children or neither has children, keep original order
          if ((aChildCount > 0 && bChildCount > 0) || (aChildCount === 0 && bChildCount === 0)) {
            return 0;
          }
          
          // Place nodes with children in the middle
          return bChildCount - aChildCount;
        });
        
        // Stagger positions to avoid vertical alignment
        sortedChildren.forEach((child, index) => {
          // Apply alternating offsets based on level
          const levelOffset = level % 2 === 0 ? 0 : spacing / 3;
          
          // Add a small random offset to prevent perfect alignment
          const jitterOffset = ((child.id * 17) % 50) - 25; // Deterministic "random" offset
          
          const childX = startX + (index * spacing) + levelOffset + jitterOffset;
          const childY = y + 300; // Significant vertical spacing
          
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
        // More spacing for top-level contacts based on how many children they have
        const topLevelSpacing = 500; // Much larger spacing for top-level contacts
        const offsetPerChild = 50; // Additional offset per child
        
        // Sort top-level contacts to spread them more efficiently
        const sortedTopLevelContacts = [...otherTopLevelContacts].sort((a, b) => {
          const aChildCount = contacts.filter(c => c.parentId === a.id).length;
          const bChildCount = contacts.filter(c => c.parentId === b.id).length;
          // Put contacts with more children to the outer edges
          return aChildCount - bChildCount;
        });
        
        const totalWidth = (sortedTopLevelContacts.length - 1) * topLevelSpacing;
        const startX = -totalWidth / 2;
        
        sortedTopLevelContacts.forEach((contact, index) => {
          // Calculate how many children this contact has for additional spacing
          const childCount = contacts.filter(c => c.parentId === contact.id).length;
          const additionalOffset = childCount * offsetPerChild;
          
          // Position contacts with wider offsets and staggered vertical positions
          const x = startX + (index * topLevelSpacing) + additionalOffset;
          const y = -350 - (index % 2 * 100); // Staggered vertical spacing from "me" contact
          processContact(contact, 0, x, y);
          
          // Add edge from "me" to this top-level contact (now solid lines)
          newEdges.push({
            id: `${meContact.id}-${contact.id}`,
            source: meContact.id.toString(),
            target: contact.id.toString(),
            animated: false,
            style: {
              stroke: getRelationshipColor(contact.relationshipType),
              strokeWidth: 2 // Solid line with consistent width
            }
          });
        });
      }
    } else {
      // No "me" contact, process all top-level contacts
      const topLevelContacts = contacts.filter(c => !c.parentId);
      
      // Use same enhanced spacing as for other top-level contacts
      const topLevelSpacing = 500; // Larger spacing
      const offsetPerChild = 50; // Additional offset per child
      const totalWidth = (topLevelContacts.length - 1) * topLevelSpacing;
      const startX = -totalWidth / 2;
      
      // Sort top-level contacts to spread them more efficiently
      const sortedTopLevelContacts = [...topLevelContacts].sort((a, b) => {
        const aChildCount = contacts.filter(c => c.parentId === a.id).length;
        const bChildCount = contacts.filter(c => c.parentId === b.id).length;
        // Put contacts with more children to the outer edges
        return aChildCount - bChildCount;
      });
      
      sortedTopLevelContacts.forEach((contact, index) => {
        // Calculate how many children this contact has for additional spacing
        const childCount = contacts.filter(c => c.parentId === contact.id).length;
        const additionalOffset = childCount * offsetPerChild;
        
        // Position with staggered layout
        const x = startX + (index * topLevelSpacing) + additionalOffset;
        const y = (index % 2) * -100; // Alternating vertical positions
        
        processContact(contact, 0, x, y);
      });
    }
    
    setNodes(newNodes);
    setEdges(newEdges);
  }, [contacts, selectedContactId]);

  // Handle node click
  const onNodeClick: NodeMouseHandler = useCallback((event, node) => {
    event.preventDefault();
    event.stopPropagation();
    
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
        defaultEdgeOptions={{
          type: 'smoothstep', // Use curved edges for better routing
          style: {
            strokeWidth: 2,
            // Ensure no dashed lines anywhere
            strokeDasharray: undefined 
          },
        }}
        minZoom={0.2} // Allow zooming out further to see the entire network
        maxZoom={1.5} // Limit max zoom to prevent excessive detail
      >
        <Controls />
        <MiniMap 
          zoomable 
          pannable
          nodeStrokeWidth={3}
          nodeBorderRadius={2}
        />
        <Background
          color="#999"
          gap={20}
          size={1}
          variant="dots"
        />
      </ReactFlow>
    </div>
  );
}