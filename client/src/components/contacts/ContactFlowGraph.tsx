import { useCallback, useEffect, useState, useMemo } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Contact } from '@/lib/types';
import { useToast } from '@/hooks/use-toast';

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
  OnNodesChange,
  OnConnect,
  Connection,
  addEdge,
  NodeDragHandler,
  ConnectionMode,
  OnConnectStart,
  OnConnectEnd,
  ReactFlowInstance,
  useReactFlow,
} from 'reactflow';
import 'reactflow/dist/style.css';
import { ReactFlowProvider } from 'reactflow';

import { memo } from 'react';
import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { 
  Users, 
  Heart, 
  Baby, 
  Briefcase, 
  UserCircle2, 
  UserPlus, 
  HeartHandshake,
  Link,
  Unlink,
  RotateCcw
} from 'lucide-react';

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

// Relationship icons
const relationshipIcons = {
  sibling: Users,
  mother: Heart,
  father: UserCircle2,
  brother: UserPlus,
  friend: Users,
  child: Baby,
  "co-worker": Briefcase,
  spouse: HeartHandshake,
  "boyfriend/girlfriend": Heart,
};

// ContactNode component with enhanced connection UI
export const ContactNode = memo(({ data, selected }: NodeProps<ContactNodeData>) => {
  const { contact, level, isSelected, isConnecting, canConnect, onStartConnection, onEndConnection } = data;
  const [isHovered, setIsHovered] = useState(false);

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
        group relative w-40 rounded-md border-2 p-3 transition-all duration-200
        ${nodeStyle.bg} ${nodeStyle.border} bg-white
        ${isSelected ? 'border-primary shadow-lg border-[3px] scale-110' : 'shadow-md hover:shadow-lg'}
        ${isConnecting ? 'ring-2 ring-blue-400 ring-opacity-50' : ''}
        ${canConnect ? 'ring-2 ring-green-400 ring-opacity-50 bg-green-50' : ''}
        cursor-pointer hover:scale-105
      `}
      onMouseEnter={() => setIsHovered(true)}
      onMouseLeave={() => setIsHovered(false)}
    >
      <Handle 
        type="target" 
        position={Position.Top} 
        className="!bg-muted-foreground opacity-0 group-hover:opacity-100 transition-opacity" 
      />

      <div className="flex flex-col items-center gap-1">
        <Avatar className={`w-12 h-12 ${isSelected ? 'ring-2 ring-primary' : 'ring-1 ring-gray-300'} shadow-sm`}>
          <AvatarFallback className={`text-base font-semibold ${nodeStyle.text} bg-white`}>
            {getInitials(contact.name)}
          </AvatarFallback>
        </Avatar>

        <div className="text-center mt-1">
          <h3 className="font-medium text-foreground truncate max-w-full text-sm">
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

        {/* Connection Controls - only show on hover */}
        {isHovered && !contact.isMe && (
          <div className="absolute -bottom-2 left-1/2 transform -translate-x-1/2 flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
            <Button
              size="sm"
              variant="outline"
              className="h-6 w-6 p-0 bg-white shadow-md hover:bg-blue-50"
              onClick={(e) => {
                e.stopPropagation();
                onStartConnection?.(contact.id);
              }}
              title="Connect to another contact"
            >
              <Link className="h-3 w-3" />
            </Button>
            {contact.parentId && (
              <Button
                size="sm"
                variant="outline"
                className="h-6 w-6 p-0 bg-white shadow-md hover:bg-red-50"
                onClick={(e) => {
                  e.stopPropagation();
                  onEndConnection?.(contact.id, null);
                }}
                title="Disconnect from parent"
              >
                <Unlink className="h-3 w-3" />
              </Button>
            )}
          </div>
        )}
      </div>

      <Handle 
        type="source" 
        position={Position.Bottom} 
        className="!bg-muted-foreground opacity-0 group-hover:opacity-100 transition-opacity" 
      />
    </div>
  );
});

// Define node data interface
interface ContactNodeData {
  contact: Contact;
  level: number;
  isSelected: boolean;
  isConnecting?: boolean;
  canConnect?: boolean;
  onStartConnection?: (contactId: number) => void;
  onEndConnection?: (contactId: number, parentId: number | null) => void;
}

interface ContactFlowGraphProps {
  onContactSelect?: (contactId: number) => void;
}

// Color theme for different relationship types
const relationshipColors = {
  family: '#00ACE6',
  friends: '#FF0080',
  professional: '#FF8000',
  personal: '#00B359',
  default: '#6B7280'
};

export function ContactFlowGraphInner({ onContactSelect }: ContactFlowGraphProps) {
  const [nodes, setNodes, onNodesChange] = useNodesState([]);
  const [edges, setEdges, onEdgesChange] = useEdgesState([]);
  const [selectedContactId, setSelectedContactId] = useState<number | null>(null);
  const [connectingFromId, setConnectingFromId] = useState<number | null>(null);
  const [reactFlowInstance, setReactFlowInstance] = useState<ReactFlowInstance | null>(null);

  const { toast } = useToast();
  const queryClient = useQueryClient();

  // Memoize nodeTypes to avoid React Flow warning
  const nodeTypes = useMemo(() => ({
    contactNode: ContactNode as any,
  }), []);

  // Get contacts data
  const { data: contacts } = useQuery<Contact[]>({
    queryKey: ['/api/contacts'],
  });

  // Mutation for updating contact relationships
  const updateRelationshipMutation = useMutation({
    mutationFn: async ({ contactId, parentId }: { contactId: number; parentId: number | null }) => {
      const response = await fetch(`/api/contacts/${contactId}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ parentId }),
      });
      if (!response.ok) throw new Error('Failed to update relationship');
      return response.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['/api/contacts'] });
      toast({
        title: "Connection Updated",
        description: "Contact relationship has been updated successfully.",
      });
    },
    onError: (error) => {
      toast({
        title: "Connection Failed",
        description: error.message || "Failed to update contact relationship.",
        variant: "destructive",
      });
    },
  });

  // Grid snapping function
  const snapToGrid = (x: number, y: number) => {
    const gridSize = 50;
    return {
      x: Math.round(x / gridSize) * gridSize,
      y: Math.round(y / gridSize) * gridSize,
    };
  };

  // Handle node drag end to snap to grid
  const handleNodeDragStop: NodeDragHandler = useCallback((event, node, nodes) => {
    const snappedPosition = snapToGrid(node.position.x, node.position.y);

    setNodes((nds) =>
      nds.map((n) =>
        n.id === node.id
          ? { ...n, position: snappedPosition }
          : n
      )
    );
  }, [setNodes]);

  // Start connection mode
  const handleStartConnection = useCallback((contactId: number) => {
    setConnectingFromId(contactId);
    toast({
      title: "Connection Mode",
      description: "Click on another contact to create a connection, or click elsewhere to cancel.",
    });
  }, [toast]);

  // End connection (connect or disconnect)
  const handleEndConnection = useCallback((contactId: number, parentId: number | null) => {
    if (connectingFromId && connectingFromId !== contactId) {
      // Connecting two contacts
      updateRelationshipMutation.mutate({
        contactId: connectingFromId,
        parentId: contactId,
      });
    } else if (parentId === null) {
      // Disconnecting
      updateRelationshipMutation.mutate({
        contactId,
        parentId: null,
      });
    }

    setConnectingFromId(null);
  }, [connectingFromId, updateRelationshipMutation]);

  // Handle clicking on empty space to cancel connection
  const handlePaneClick = useCallback(() => {
    if (connectingFromId) {
      setConnectingFromId(null);
      toast({
        title: "Connection Cancelled",
        description: "Connection mode has been cancelled.",
      });
    }
  }, [connectingFromId, toast]);

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
          isSelected: contact.id === selectedContactId,
          isConnecting: connectingFromId === contact.id,
          canConnect: connectingFromId !== null && connectingFromId !== contact.id && contact.id !== meContact?.id,
          onStartConnection: handleStartConnection,
          onEndConnection: handleEndConnection,
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
          animated: connectingFromId === parentId || connectingFromId === contact.id,
          style: {
            stroke: getRelationshipColor(contact.relationshipType),
            strokeWidth: connectingFromId === parentId || connectingFromId === contact.id ? 3 : 2,
            strokeDasharray: connectingFromId === parentId || connectingFromId === contact.id ? '5,5' : undefined,
          }
        });
      }

      // Process children
      const children = contacts.filter(c => c.parentId === contact.id);
      if (children.length > 0) {
        const spacing = 200;
        const totalWidth = (children.length - 1) * spacing;
        const startX = x - totalWidth / 2;

        children.forEach((child, index) => {
          const childX = startX + (index * spacing);
          const childY = y + 250;
          processContact(child, level + 1, childX, childY, contact.id);
        });
      }
    };

    // Start processing from "me" contact or find a suitable root
    if (meContact) {
      processContact(meContact, 0, 0, 0);
    } else {
      // Find top-level contacts (no parent)
      const topLevelContacts = contacts.filter(c => !c.parentId);
      if (topLevelContacts.length > 0) {
        processContact(topLevelContacts[0], 0, 0, 0);
      }
    }

    // Process any remaining unconnected contacts
    const remainingContacts = contacts.filter(c => !processedContacts.has(c.id));
    remainingContacts.forEach((contact, index) => {
      processContact(contact, 0, 300 + (index * 200), 400);
    });

    setNodes(newNodes);
    setEdges(newEdges);
  }, [contacts, selectedContactId, connectingFromId, handleStartConnection, handleEndConnection]);

  // Handle node click
  const onNodeClick: NodeMouseHandler = useCallback((event, node) => {
    event.preventDefault();
    event.stopPropagation();

    const contactId = parseInt(node.id);

    if (connectingFromId && connectingFromId !== contactId) {
      // Complete connection
      handleEndConnection(contactId, contactId);
    } else {
      // Regular node selection
      if (!isNaN(contactId)) {
        setSelectedContactId(contactId);
        if (onContactSelect) {
          onContactSelect(contactId);
        }
      }
    }
  }, [connectingFromId, handleEndConnection, onContactSelect]);

  if (!contacts) {
    return (
      <div className="p-4 text-center text-muted-foreground">
        Loading contacts...
      </div>
    );
  }

  return (
    <div className="w-full h-[calc(100vh-12rem)] bg-card rounded-lg border shadow-sm overflow-hidden relative">
      {/* Connection status indicator */}
      {connectingFromId && (
        <div className="absolute top-4 left-4 z-10 bg-blue-100 border border-blue-300 rounded-lg p-3 shadow-lg">
          <div className="flex items-center gap-2">
            <Link className="h-4 w-4 text-blue-600" />
            <span className="text-sm font-medium text-blue-800">
              Connecting from {contacts.find(c => c.id === connectingFromId)?.name}
            </span>
            <Button
              size="sm"
              variant="ghost"
              onClick={() => setConnectingFromId(null)}
              className="h-6 w-6 p-0 hover:bg-blue-200"
            >
              <RotateCcw className="h-3 w-3" />
            </Button>
          </div>
          <p className="text-xs text-blue-600 mt-1">Click on another contact to connect</p>
        </div>
      )}

      <ReactFlow
        nodes={nodes}
        edges={edges}
        onNodesChange={onNodesChange}
        onEdgesChange={onEdgesChange}
        onNodeClick={onNodeClick}
        onNodeDragStop={handleNodeDragStop}
        onPaneClick={handlePaneClick}
        onInit={setReactFlowInstance}
        nodeTypes={nodeTypes as NodeTypes}
        proOptions={{ hideAttribution: true }}
        fitView
        snapToGrid={true}
        snapGrid={[50, 50]}
        connectionMode={ConnectionMode.Loose}
        defaultEdgeOptions={{
          type: 'smoothstep',
          style: {
            strokeWidth: 2,
          },
        }}
        minZoom={0.2}
        maxZoom={1.5}
        nodesDraggable={true}
        nodesConnectable={false} // We handle connections manually
        elementsSelectable={true}
      >
        <Controls />
        <MiniMap 
          zoomable 
          pannable
          nodeStrokeWidth={3}
          nodeBorderRadius={2}
        />
        <Background
          color="#aaa"
          gap={50}
          size={2}
          variant="dots"
        />
      </ReactFlow>
    </div>
  );
}

export function ContactFlowGraph({ onContactSelect }: ContactFlowGraphProps) {
  return (
    <ReactFlowProvider>
      <ContactFlowGraphInner onContactSelect={onContactSelect} />
    </ReactFlowProvider>
  );
}