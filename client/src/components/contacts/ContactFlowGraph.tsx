import React, { useCallback, useEffect, useRef, useState } from 'react';
import ReactFlow, {
  ReactFlowProvider,
  ConnectionLineType,
  useReactFlow,
  Edge,
  XYPosition,
  Node,
  Controls,
  MiniMap,
  Background,
  BackgroundVariant,
  useNodesState,
  useEdgesState,
} from 'reactflow';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { Contact } from '@/lib/types';
import { getContactColorClasses } from '@/lib/colors';
import { ContactNode } from './ContactNode';
import { RelationshipManager } from '@/components/ai/RelationshipManager';
import { VoiceInput } from '@/components/ai/VoiceInput';
import { ProximityFilter } from './ProximityFilter';
import { useToast } from '@/hooks/use-toast';
import { Button } from '@/components/ui/button';
import { Undo2, RotateCcw } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import 'reactflow/dist/style.css';

// Define nodeTypes outside component to avoid React Flow warning
const nodeTypes = {
  contact: ContactNode,
};

const NODE_SIZE = 160;

function isIntersect(a: XYPosition, b: XYPosition) {
  const threshold = NODE_SIZE * 0.6;
  return (
    Math.abs(a.x - b.x) < threshold &&
    Math.abs(a.y - b.y) < threshold
  );
}

function getSubtreeIds(contacts: Contact[], rootId: string): Set<string> {
  const subtreeIds = new Set<string>();
  
  function traverse(nodeId: string) {
    subtreeIds.add(nodeId);
    const children = contacts.filter(c => c.parentId?.toString() === nodeId);
    children.forEach(child => traverse(child.id.toString()));
  }
  
  traverse(rootId);
  return subtreeIds;
}

interface ContactFlowGraphProps {
  contacts: Contact[];
  onContactSelect?: (contactId: number) => void;
}

function ContactFlowGraphInner({ contacts, onContactSelect }: ContactFlowGraphProps) {
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const reactFlowInstance = useReactFlow();
  const [nodes, setNodes, onNodesChange] = useNodesState([]);
  const [edges, setEdges, onEdgesChange] = useEdgesState([]);
  const [undoStack, setUndoStack] = useState<Array<{child: string, parent: string | null, timestamp: number}>>([]);
  const [isReordering, setIsReordering] = useState(false);
  const [voiceTranscription, setVoiceTranscription] = useState<string>("");
  const [proximityFilter, setProximityFilter] = useState<{
    enabled: boolean;
    userLocation: { lat: number; lng: number } | null;
  }>({ enabled: false, userLocation: null });

  // Calculate distance between two points in kilometers
  const calculateDistance = (lat1: number, lng1: number, lat2: number, lng2: number): number => {
    const R = 6371; // Earth's radius in kilometers
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLng = (lng2 - lng1) * Math.PI / 180;
    const a = Math.sin(dLat/2) * Math.sin(dLat/2) +
              Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
              Math.sin(dLng/2) * Math.sin(dLng/2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
    return R * c;
  };

  // Filter contacts based on proximity
  const filterContactsByProximity = (contacts: Contact[]): Contact[] => {
    if (!proximityFilter.enabled || !proximityFilter.userLocation) {
      return contacts;
    }

    return contacts.filter(contact => {
      // Always show "me" contact
      if (contact.isMe) return true;

      // Check if contact has location data
      const hasLocation = contact.locations && contact.locations.length > 0;
      const hasLegacyLocation = contact.latitude && contact.longitude;

      if (!hasLocation && !hasLegacyLocation) return false;

      // Check distance for each location
      if (hasLocation) {
        return contact.locations!.some(location => {
          const distance = calculateDistance(
            proximityFilter.userLocation!.lat,
            proximityFilter.userLocation!.lng,
            parseFloat(location.latitude.toString()),
            parseFloat(location.longitude.toString())
          );
          return distance <= 1; // Within 1km
        });
      }

      // Check legacy location
      if (hasLegacyLocation) {
        const distance = calculateDistance(
          proximityFilter.userLocation!.lat,
          proximityFilter.userLocation!.lng,
          parseFloat(contact.latitude!),
          parseFloat(contact.longitude!)
        );
        return distance <= 1; // Within 1km
      }

      return false;
    });
  };

  const handleProximityFilterChange = (enabled: boolean, userLocation?: { lat: number; lng: number }) => {
    setProximityFilter({ enabled, userLocation: userLocation || null });
  };
  
  // Ephemeral drag context stored in ref to avoid re-renders
  const dragContextRef = useRef<{
    rootId: string;
    subtree: Set<string>;
    prevPos: XYPosition;
    oldParentEdge: Edge | null;
    snapTarget: string | null;
  } | null>(null);

  const reparent = useMutation({
    mutationFn: async ({ child, parent, oldParent }: { child: string; parent: string; oldParent: string | null }) => {
      console.log('🔄 Attempting to reparent:', { child, parent, oldParent });
      const response = await fetch(`/api/contacts/${child}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ parentId: parseInt(parent, 10) }),
      });
      if (!response.ok) {
        throw new Error('Failed to reparent contact');
      }
      return response.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['/api/contacts'] });
      toast({
        title: "Relationship updated",
        description: "The contact hierarchy has been updated successfully",
      });
    },
    onError: (error: Error) => {
      console.error('❌ Reparent mutation failed:', error);
      toast({
        title: "Failed to update relationship",
        description: "Please try again or check for circular relationships",
        variant: "destructive",
      });
    },
  });

  const handleUndo = async (childId: string, oldParentId: string | null) => {
    try {
      const response = await fetch(`/api/contacts/${childId}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ parentId: oldParentId ? parseInt(oldParentId, 10) : null }),
      });
      
      if (!response.ok) {
        throw new Error('Failed to undo');
      }
      
      queryClient.invalidateQueries({ queryKey: ['/api/contacts'] });
      toast({
        title: "Relationship restored",
        description: "The change has been undone",
      });
    } catch (error) {
      toast({
        title: "Failed to undo",
        description: "Could not restore the previous relationship",
        variant: "destructive",
      });
    }
  };

  // Convert contacts to hierarchical tree nodes and edges
  useEffect(() => {
    console.log('🔄 Building hierarchical tree structure from contacts:', contacts.length);
    
    // Apply proximity filter first
    const filteredContacts = filterContactsByProximity(contacts);
    console.log('🔄 Filtered contacts by proximity:', filteredContacts.length);
    
    const contactMap = new Map(filteredContacts.map(c => [c.id, c]));
    const rootContacts = filteredContacts.filter(c => !c.parentId || !contactMap.has(c.parentId));
    
    const buildHierarchy = (contact: Contact, level: number = 0, parentX: number = 600, parentY: number = 200): { contact: Contact; position: XYPosition; level: number }[] => {
      const result: { contact: Contact; position: XYPosition; level: number }[] = [];
      
      const NODE_WIDTH = 160;
      const NODE_HEIGHT = 120;
      const HORIZONTAL_GAP = 120; // Increased for better spacing
      const VERTICAL_GAP = 150;   // Increased for better vertical spacing
      const MIN_X = 50;           // Start closer to edge for more space
      
      let position: XYPosition;
      
      if (contact.isMe) {
        position = { x: 600, y: 100 }; // Centered in larger canvas
      } else if (level === 0) {
        const rootIndex = rootContacts.indexOf(contact);
        const spacing = NODE_WIDTH + HORIZONTAL_GAP;
        const totalWidth = Math.max(800, rootContacts.length * spacing);
        const startX = Math.max(MIN_X, 600 - totalWidth / 2);
        
        position = { 
          x: startX + rootIndex * spacing, 
          y: 300 // More space below "me" contact
        };
      } else {
        const siblings = contacts.filter(c => c.parentId === contact.parentId);
        const childIndex = siblings.indexOf(contact);
        const spacing = NODE_WIDTH + HORIZONTAL_GAP;
        const totalWidth = Math.max(400, siblings.length * spacing);
        const startX = Math.max(MIN_X, parentX - totalWidth / 2);
        
        position = {
          x: startX + childIndex * spacing,
          y: parentY + NODE_HEIGHT + VERTICAL_GAP
        };
      }
      
      result.push({ contact, position, level });
      
      const children = filteredContacts.filter(c => c.parentId === contact.id);
      children.forEach(child => {
        result.push(...buildHierarchy(child, level + 1, position.x, position.y));
      });
      
      return result;
    };
    
    const hierarchyData: { contact: Contact; position: XYPosition; level: number }[] = [];
    rootContacts.forEach(rootContact => {
      hierarchyData.push(...buildHierarchy(rootContact));
    });
    
    // Create nodes
    const newNodes: Node[] = hierarchyData.map(({ contact, position, level }) => ({
      id: String(contact.id),
      position,
      data: { 
        label: contact.name,
        contact,
        level,
        isDragged: false,
        isSnapTarget: false,
      },
      type: 'contact',
      draggable: true,
      style: {
        zIndex: contact.isMe ? 1000 : (100 - level * 10),
      }
    }));

    const newEdges: Edge[] = filteredContacts
      .filter(contact => contact.parentId)
      .map(contact => ({
        id: `${contact.parentId}-${contact.id}`,
        source: String(contact.parentId!),
        target: String(contact.id),
        type: 'smoothstep',
        animated: false,
        data: { hidden: false },
        style: {
          stroke: '#64748b',
          strokeWidth: 2,
        },
      }));

    console.log('🔄 Created hierarchical nodes:', newNodes.length, 'edges:', newEdges.length);
    setNodes(newNodes);
    setEdges(newEdges);
  }, [contacts, setNodes, setEdges, proximityFilter]);

  // Drag start - establish drag context
  const onNodeDragStart = useCallback(
    (event: React.MouseEvent, node: Node) => {
      console.log('🚀 Drag start for node:', node.id);
      
      // Calculate subtree
      const subtreeIds = getSubtreeIds(contacts, node.id);
      
      // Find old parent edge
      const oldParentEdge = edges.find(e => e.target === node.id) || null;
      
      // Set drag context
      dragContextRef.current = {
        rootId: node.id,
        subtree: subtreeIds,
        prevPos: node.position,
        oldParentEdge,
        snapTarget: null,
      };
      
      // Hide old parent edge
      if (oldParentEdge) {
        setEdges(edges => edges.map(e => 
          e.id === oldParentEdge.id 
            ? { ...e, data: { ...e.data, hidden: true }, style: { ...e.style, opacity: 0 } }
            : e
        ));
      }
      
      // Mark dragged nodes
      setNodes(nodes => nodes.map(n => 
        subtreeIds.has(n.id) 
          ? { ...n, data: { ...n.data, isDragged: true } }
          : n
      ));
    },
    [contacts, edges, setNodes, setEdges]
  );

  // Drag - move subtree and handle snap targets
  const onNodeDrag = useCallback(
    (event: React.MouseEvent, node: Node) => {
      const dragContext = dragContextRef.current;
      if (!dragContext) return;
      
      // Calculate movement delta
      const dx = node.position.x - dragContext.prevPos.x;
      const dy = node.position.y - dragContext.prevPos.y;
      dragContext.prevPos = node.position;
      
      // Move entire subtree
      setNodes(nodes => nodes.map(n => 
        dragContext.subtree.has(n.id)
          ? { ...n, position: { x: n.position.x + dx, y: n.position.y + dy } }
          : n
      ));
      
      // Find snap targets
      const intersectingNodes = reactFlowInstance.getIntersectingNodes(node).filter(n => 
        !dragContext.subtree.has(n.id)
      );
      
      // Find closest valid target within 140px
      let closestTarget: Node | null = null;
      let closestDistance = 140;
      
      intersectingNodes.forEach(target => {
        const distance = Math.sqrt(
          Math.pow(target.position.x - node.position.x, 2) + 
          Math.pow(target.position.y - node.position.y, 2)
        );
        if (distance < closestDistance) {
          closestTarget = target;
          closestDistance = distance;
        }
      });
      
      // Update snap target
      const newSnapTarget = closestTarget?.id || null;
      if (newSnapTarget !== dragContext.snapTarget) {
        // Remove old snap target styling
        if (dragContext.snapTarget) {
          setNodes(nodes => nodes.map(n => 
            n.id === dragContext.snapTarget 
              ? { ...n, data: { ...n.data, isSnapTarget: false } }
              : n
          ));
        }
        
        // Add new snap target styling
        if (newSnapTarget) {
          setNodes(nodes => nodes.map(n => 
            n.id === newSnapTarget 
              ? { ...n, data: { ...n.data, isSnapTarget: true } }
              : n
          ));
        }
        
        dragContext.snapTarget = newSnapTarget;
      }
    },
    [reactFlowInstance, setNodes]
  );

  // Drag stop - commit changes
  const onNodeDragStop = useCallback(
    (event: React.MouseEvent, node: Node) => {
      const dragContext = dragContextRef.current;
      if (!dragContext) return;
      
      console.log('🏁 Drag stop for node:', node.id, 'snap target:', dragContext.snapTarget);
      
      // Clean up node states
      setNodes(nodes => nodes.map(n => ({
        ...n,
        data: { ...n.data, isDragged: false, isSnapTarget: false }
      })));
      
      // Restore old parent edge
      if (dragContext.oldParentEdge) {
        setEdges(edges => edges.map(e => 
          e.id === dragContext.oldParentEdge!.id 
            ? { ...e, data: { ...e.data, hidden: false }, style: { ...e.style, opacity: 1 } }
            : e
        ));
      }
      
      // If we have a snap target, reparent
      if (dragContext.snapTarget) {
        const oldParentId = dragContext.oldParentEdge?.source || null;
        
        // Add to undo stack
        setUndoStack(prev => [...prev, {
          child: dragContext.rootId,
          parent: oldParentId,
          timestamp: Date.now(),
        }]);
        
        // Remove old parent edge and add new one
        setEdges(edges => {
          const filtered = edges.filter(e => e.target !== dragContext.rootId);
          return [...filtered, {
            id: `${dragContext.snapTarget}-${dragContext.rootId}`,
            source: dragContext.snapTarget!,
            target: dragContext.rootId,
            type: 'smoothstep',
            animated: false,
            data: { hidden: false },
            style: {
              stroke: '#64748b',
              strokeWidth: 2,
            },
          }];
        });
        
        // Commit to database
        reparent.mutate({
          child: dragContext.rootId,
          parent: dragContext.snapTarget,
          oldParent: oldParentId,
        });
      }
      
      // Clear drag context
      dragContextRef.current = null;
    },
    [setNodes, setEdges, setUndoStack, reparent]
  );

  const onNodeClick = useCallback(
    (event: React.MouseEvent, node: Node) => {
      if (onContactSelect) {
        onContactSelect(parseInt(node.id));
      }
    },
    [onContactSelect]
  );

  const handleUndoAction = () => {
    if (undoStack.length === 0) return;
    
    const lastAction = undoStack[undoStack.length - 1];
    setUndoStack(prev => prev.slice(0, -1));
    
    handleUndo(lastAction.child, lastAction.parent);
  };

  const handleReorder = () => {
    setIsReordering(true);
    
    // Force a rebuild of the hierarchy with better spacing
    setTimeout(() => {
      setIsReordering(false);
      toast({
        title: "Contacts reordered",
        description: "Hierarchy layout has been optimized",
      });
    }, 500);
  };

  return (
    <div style={{ height: '100vh', width: '100%', position: 'relative' }}>
      
      <ReactFlow
        nodes={nodes}
        edges={edges}
        nodeTypes={nodeTypes}
        onNodesChange={onNodesChange}
        onEdgesChange={onEdgesChange}
        onNodeDragStart={onNodeDragStart}
        onNodeDrag={onNodeDrag}
        onNodeDragStop={onNodeDragStop}
        onNodeClick={onNodeClick}
        connectionLineType={ConnectionLineType.SmoothStep}
        nodesDraggable={true}
        edgesFocusable={false}
        nodesFocusable={false}
        snapToGrid={false}
        preventScrolling={false}
        nodeOrigin={[0.5, 0.5]}
        panOnDrag={true}
        selectNodesOnDrag={false}
        zoomOnScroll={true}
        zoomOnPinch={true}
        zoomOnDoubleClick={true}
        panOnScrollMode="free"
        minZoom={0.1}
        maxZoom={2}
        defaultViewport={{ x: 0, y: 0, zoom: 0.8 }}
        fitView
        fitViewOptions={{ 
          padding: 0.3,
          includeHiddenNodes: false,
          minZoom: 0.3,
          maxZoom: 1.2
        }}
      >
        <Background 
          variant={BackgroundVariant.Dots}
          gap={20}
          size={1}
          color="#e2e8f0"
        />
        <Controls 
          position="bottom-left"
          showZoom={true}
          showFitView={true}
          showInteractive={true}
        />
        <MiniMap 
          nodeColor={(node) => {
            const contact = node.data.contact;
            if (contact.isMe) return '#10b981';
            return getContactColorClasses(contact.color || 'blue').hex;
          }}
          nodeStrokeWidth={2}
          nodeBorderRadius={8}
          pannable={true}
          zoomable={true}
          position="bottom-right"
          style={{
            backgroundColor: 'rgba(255, 255, 255, 0.9)',
            border: '1px solid #e2e8f0'
          }}
        />
      </ReactFlow>
      
      {/* Control Panel - Redesigned with better hierarchy and spacing */}
      <div className="absolute top-6 right-6 z-50 flex flex-col gap-3">
        {/* Primary Action: Undo */}
        <AnimatePresence>
          {undoStack.length > 0 && (
            <motion.div
              initial={{ opacity: 0, y: -10 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -10 }}
              transition={{ duration: 0.2 }}
            >
              <Button
                onClick={handleUndoAction}
                variant="default"
                size="sm"
                className="shadow-lg bg-primary text-primary-foreground hover:bg-primary/90 min-w-[120px] justify-start"
              >
                <Undo2 className="h-4 w-4 mr-2" />
                Undo ({undoStack.length})
              </Button>
            </motion.div>
          )}
        </AnimatePresence>
        
        {/* Secondary Actions Panel */}
        <div className="bg-background/95 backdrop-blur-sm border border-border/50 rounded-lg p-2 shadow-lg">
          <div className="flex flex-col gap-2">
            <Button
              onClick={handleReorder}
              variant="outline"
              size="sm"
              disabled={isReordering}
              className="justify-start min-w-[120px] h-9"
            >
              <RotateCcw className={`h-4 w-4 mr-2 ${isReordering ? 'animate-spin' : ''}`} />
              {isReordering ? 'Reordering...' : 'Reorder'}
            </Button>
            
            {/* Voice Input */}
            <VoiceInput 
              onTranscription={setVoiceTranscription}
              onProcessingComplete={(result) => {
                if (result.type === 'contact_created') {
                  queryClient.invalidateQueries({ queryKey: ['/api/contacts'] });
                  toast({
                    title: "Contact created",
                    description: `${result.contact.name} has been added to your contacts`
                  });
                }
              }}
              placeholder="Voice Input"
              mode="contact"
              className="justify-start min-w-[120px] h-9"
            />
            
            {/* Proximity Filter */}
            <ProximityFilter 
              onFilterChange={handleProximityFilterChange}
              className="justify-start min-w-[120px] h-9"
            />
          </div>
        </div>
      </div>
    </div>
  );
}

export default function ContactFlowGraph({ contacts, onContactSelect }: ContactFlowGraphProps) {
  return (
    <ReactFlowProvider>
      <ContactFlowGraphInner contacts={contacts} onContactSelect={onContactSelect} />
    </ReactFlowProvider>
  );
}