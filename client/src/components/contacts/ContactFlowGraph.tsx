import { useCallback, useEffect, useState, useMemo } from 'react';
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
  NodeTypes,
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

// Memoize node types to avoid React warning - must be inside the component
// Will move this into the component function

export function ContactFlowGraph({ onContactSelect }: ContactFlowGraphProps) {
  const [nodes, setNodes, onNodesChange] = useNodesState([]);
  const [edges, setEdges, onEdgesChange] = useEdgesState([]);
  const [selectedContactId, setSelectedContactId] = useState<number | null>(null);
  
  // Memoize nodeTypes to avoid React Flow warning
  const nodeTypes = useMemo(() => ({
    contactNode: ContactNode as any,
  }), []);

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
        
        // Sort children by relationship type and name for a more logical layout
        const sortedChildren = [...children].sort((a, b) => {
          // Group by relationship type category first
          const relationshipCategories = {
            family: ['mother', 'father', 'brother', 'sister', 'sibling', 'child', 'spouse'],
            romantic: ['boyfriend/girlfriend', 'spouse'],
            friends: ['friend'],
            professional: ['co-worker']
          };
          
          // Helper function to get category for a relationship type
          const getCategory = (relType?: string) => {
            if (!relType) return 'other';
            
            for (const [category, types] of Object.entries(relationshipCategories)) {
              if (types.includes(relType)) return category;
            }
            return 'other';
          };
          
          const aCategory = getCategory(a.relationshipType);
          const bCategory = getCategory(b.relationshipType);
          
          // First sort by category - family first, then romantic, etc.
          const categoryOrder = ['family', 'romantic', 'friends', 'professional', 'other'];
          const categoryCompare = categoryOrder.indexOf(aCategory) - categoryOrder.indexOf(bCategory);
          
          if (categoryCompare !== 0) return categoryCompare;
          
          // Within same category, show family members with children closer to parent
          const aChildCount = contacts.filter(c => c.parentId === a.id).length;
          const bChildCount = contacts.filter(c => c.parentId === b.id).length;
          
          if (aCategory === 'family' && bChildCount !== aChildCount) {
            return bChildCount - aChildCount; // More children = closer to parent
          }
          
          // Otherwise alphabetical by name
          return a.name.localeCompare(b.name);
        });
        
        // Position children in a more intuitive way based on their relationship
        sortedChildren.forEach((child, index) => {
          // Get the position in the layout
          const position = index / (childCount - 1 || 1); // 0 to 1 range
          
          // Calculate horizontal position with weighted distribution
          // Center positions (0.5) get more emphasis, edges (0, 1) get less
          const horizontalWeight = 1 - Math.abs(position - 0.5) * 0.5;
          const weightedOffset = position * totalWidth;
          
          // Add small offset based on relationship type
          // Family members should be closer to parent
          const isFamily = ['mother', 'father', 'brother', 'sister', 'sibling', 'child', 'spouse'].includes(child.relationshipType || '');
          const relationshipOffset = isFamily ? -30 : 0;
          
          // Vertical positioning should vary by relationship type too
          const verticalOffset = (() => {
            if (child.relationshipType === 'child') return 20; // Children slightly lower
            if (child.relationshipType === 'spouse') return -30; // Spouses slightly higher
            if (child.relationshipType === 'sibling') return -10; // Siblings slightly higher
            return 0;
          })();
          
          // Add a small deterministic offset to prevent perfect alignment
          const jitterOffset = ((child.id * 13) % 30) - 15; // Smaller jitter
          
          const childX = startX + weightedOffset + jitterOffset + relationshipOffset;
          const childY = y + 250 + verticalOffset; // Base vertical spacing with offsets
          
          processContact(child, level + 1, childX, childY, contact.id);
        });
      }
    };
    
    // Start processing from "me" contact or top-level contacts
    if (meContact) {
      processContact(meContact, 0, 0, 0);
      
      // Get all level 1 contacts - both direct children of "me" and orphaned top-level contacts
      const level1Contacts = contacts.filter(c => 
        !c.isMe && (!c.parentId || c.parentId === meContact.id) && !processedContacts.has(c.id)
      );
      
      if (level1Contacts.length > 0) {
        // Sort contacts by relationship type and name for more logical grouping
        const sortedLevel1Contacts = [...level1Contacts].sort((a, b) => {
          // Priority order by relationship type
          const typeOrder = {
            'sibling': 10,
            'brother': 10,
            'sister': 10,
            'spouse': 20,
            'child': 30,
            'boyfriend/girlfriend': 40,
            'friend': 50,
            'co-worker': 60
          };
          
          const getTypeOrder = (type: string | null | undefined): number => {
            if (!type) return 999;
            return (typeOrder as any)[type] || 999;
          };
          
          // First compare by relationship type
          const typeComparison = getTypeOrder(a.relationshipType) - getTypeOrder(b.relationshipType);
          if (typeComparison !== 0) return typeComparison;
          
          // Then by name (alphabetically)
          return a.name.localeCompare(b.name);
        });
        
        // Layout all level 1 contacts in a single row under "me"
        const nodeSpacing = 200; // Fixed spacing between same-level nodes
        const rowWidth = (sortedLevel1Contacts.length - 1) * nodeSpacing;
        const rowStart = -rowWidth / 2; // Center the row
        const level1Y = 200; // Fixed Y position for level 1
        
        // Position each contact in a simple row
        sortedLevel1Contacts.forEach((contact, index) => {
          const x = rowStart + (index * nodeSpacing);
          processContact(contact, 1, x, level1Y);
          
          // Only add an edge if this is not already a direct child of "me"
          // This avoids duplicate edges
          if (!contact.parentId) {
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
          }
        });
      }
    } else {
      // No "me" contact, find the most important contact to use as root
      const topLevelContacts = contacts.filter(c => !c.parentId);
      
      if (topLevelContacts.length > 0) {
        // Sort contacts to find the most connected one (likely main contact)
        const sortedByImportance = [...topLevelContacts].sort((a, b) => {
          // First by number of children (most important = most connections)
          const aChildCount = contacts.filter(c => c.parentId === a.id).length;
          const bChildCount = contacts.filter(c => c.parentId === b.id).length;
          
          if (aChildCount !== bChildCount) {
            return bChildCount - aChildCount; // Most children first
          }
          
          // Then by relationship type
          const typeOrder = {
            'sibling': 10,
            'brother': 10,
            'sister': 10,
            'spouse': 20,
            'child': 30,
            'boyfriend/girlfriend': 40,
            'friend': 50,
            'co-worker': 60
          };
          
          const getTypeOrder = (type: string | null | undefined): number => {
            if (!type) return 999;
            return (typeOrder as any)[type] || 999;
          };
          
          const typeCompare = getTypeOrder(a.relationshipType) - getTypeOrder(b.relationshipType);
          if (typeCompare !== 0) return typeCompare;
          
          // Finally alphabetically
          return a.name.localeCompare(b.name);
        });
        
        // Treat the most important contact as root
        const rootContact = sortedByImportance[0];
        processContact(rootContact, 0, 0, 0);
        
        // All other top-level contacts go in a row below
        const otherTopLevel = topLevelContacts.filter(c => c.id !== rootContact.id);
        
        if (otherTopLevel.length > 0) {
          // Sort the other top level contacts
          const sortedOthers = [...otherTopLevel].sort((a, b) => {
            // First by relationship type to the root (if any)
            const typeOrder = {
              'sibling': 10,
              'brother': 10,
              'sister': 10,
              'spouse': 20,
              'child': 30,
              'boyfriend/girlfriend': 40,
              'friend': 50,
              'co-worker': 60
            };
            
            const getTypeOrder = (type: string | null | undefined): number => {
              if (!type) return 999;
              return (typeOrder as any)[type] || 999;
            };
            
            const typeCompare = getTypeOrder(a.relationshipType) - getTypeOrder(b.relationshipType);
            if (typeCompare !== 0) return typeCompare;
            
            // Then alphabetically
            return a.name.localeCompare(b.name);
          });
          
          // Position them in a row
          const nodeSpacing = 200;
          const rowWidth = (sortedOthers.length - 1) * nodeSpacing;
          const rowStart = -rowWidth / 2;
          const level1Y = 200; // Fixed Y position
          
          sortedOthers.forEach((contact, index) => {
            const x = rowStart + (index * nodeSpacing);
            processContact(contact, 1, x, level1Y);
            
            // Add edge from root to this contact
            newEdges.push({
              id: `${rootContact.id}-${contact.id}`,
              source: rootContact.id.toString(),
              target: contact.id.toString(),
              animated: false,
              style: {
                stroke: getRelationshipColor(contact.relationshipType),
                strokeWidth: 2
              }
            });
          });
        }
      } else {
        // No contacts at all, nothing to do
        console.log("No contacts to display");
      }
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
        nodeTypes={nodeTypes as NodeTypes}
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
        />
      </ReactFlow>
    </div>
  );
}