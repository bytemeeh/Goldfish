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
  PanOnScrollMode,
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
import { Undo2, RotateCcw, ChevronRight } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from '@/components/ui/dialog';
import 'reactflow/dist/style.css';
import { QuickFilter } from './QuickFilter';
import { CATEGORIES } from '@/lib/constants';

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
  onContactSelect?: (contactId: string) => void;
  onAddRelation?: (sourceId: string, type: 'child' | 'parent') => void;
}

function ContactFlowGraphInner({ contacts, onContactSelect, onAddRelation }: ContactFlowGraphProps) {
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const reactFlowInstance = useReactFlow();
  const [nodes, setNodes, onNodesChange] = useNodesState<Node>([]);
  const [edges, setEdges, onEdgesChange] = useEdgesState<Edge>([]);
  const [undoStack, setUndoStack] = useState<Array<{ child: string, parent: string | null, timestamp: number }>>([]);
  const [isReordering, setIsReordering] = useState(false);
  const [reorderTrigger, setReorderTrigger] = useState(0); // Add trigger for reordering
  const [voiceTranscription, setVoiceTranscription] = useState<string>("");
  const [relationshipFilter, setRelationshipFilter] = useState<string>("all");
  const [proximityFilter, setProximityFilter] = useState<{
    enabled: boolean;
    userLocation: { lat: number; lng: number } | null;
  }>({ enabled: false, userLocation: null });
  const [deleteContact, setDeleteContact] = useState<Contact | null>(null);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);

  // Calculate distance between two points in kilometers
  const calculateDistance = (lat1: number, lng1: number, lat2: number, lng2: number): number => {
    const R = 6371; // Earth's radius in kilometers
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLng = (lng2 - lng1) * Math.PI / 180;
    const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
      Math.sin(dLng / 2) * Math.sin(dLng / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
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
            typeof location.latitude === 'string' ? parseFloat(location.latitude) : location.latitude,
            typeof location.longitude === 'string' ? parseFloat(location.longitude) : location.longitude
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

  const handleDelete = (contactId: string) => {
    const contact = contacts.find(c => c.id === contactId);
    if (contact) {
      setDeleteContact(contact);
      setShowDeleteConfirm(true);
    }
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
        body: JSON.stringify({ parentId: parent }),
      });
      if (!response.ok) {
        const error = await response.json();
        throw new Error(error.message || 'Failed to reparent contact');
      }
      return response.json();
    },
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ['/api/contacts'] });

      // Add to undo stack
      setUndoStack(prev => [...prev, {
        child: variables.child,
        parent: variables.oldParent,
        timestamp: Date.now()
      }]);

      toast({
        title: "Relationship updated",
        description: "Contact moved successfully",
      });
    },
    onError: (error) => {
      console.error('Reparent error:', error);
      toast({
        title: "Error moving contact",
        description: error.message,
        variant: "destructive",
      });
    },
  });

  const deleteContactMutation = useMutation({
    mutationFn: async (contactId: string) => {
      const res = await fetch(`/api/contacts/${contactId}`, {
        method: "DELETE",
      });
      if (!res.ok) throw new Error("Failed to delete contact");
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["/api/contacts"] });
      toast({
        title: "Contact deleted",
        description: "The contact has been removed from your network",
      });
      setDeleteContact(null);
      setShowDeleteConfirm(false);
    },
    onError: (error) => {
      toast({
        title: "Error deleting contact",
        description: error.message,
        variant: "destructive",
      });
    },
  });

  const handleUndo = async (childId: string, oldParentId: string | null) => {
    try {
      const response = await fetch(`/api/contacts/${childId}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ parentId: oldParentId || null }),
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
    let filteredContacts = filterContactsByProximity(contacts);

    // Apply category filter
    if (relationshipFilter !== 'all') {
      const category = CATEGORIES.find(c => c.title.toLowerCase() === relationshipFilter);
      if (category) {
        filteredContacts = filteredContacts.filter(contact => {
          if (contact.isMe) return true;
          // Check direct relationship type
          if (contact.relationshipType && category.types.includes(contact.relationshipType.toLowerCase())) return true;
          // Check relationship to user
          if (contact.relationshipToUser && category.types.includes(contact.relationshipToUser.toLowerCase())) return true;
          return false;
        });
      }
    }

    console.log('🔄 Filtered contacts:', filteredContacts.length);

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
        onAddChild: (parentId: string) => onAddRelation?.(parentId, 'child'),
        onAddParent: (childId: string) => onAddRelation?.(childId, 'parent'),
        onDelete: handleDelete,
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
        animated: false, // Dynamic edges can be enabled if needed
        data: { hidden: false },
        style: {
          stroke: '#cbd5e1', // slate-300, much lighter
          strokeWidth: 1.5,
        },
      }));

    console.log('🔄 Created hierarchical nodes:', newNodes.length, 'edges:', newEdges.length);
    setNodes(newNodes);
    setEdges(newEdges);
  }, [contacts, setNodes, setEdges, proximityFilter, onAddRelation, reorderTrigger]); // Add reorderTrigger dependency

  // Drag start - establish drag context
  const onNodeDragStart = useCallback(
    (event: React.MouseEvent, node: Node) => {
      console.log('🚀 Drag start for node:', node.id);

      // Calculate subtree
      const subtreeIds = getSubtreeIds(contacts, node.id);

      // Find old parent edge
      const oldParentEdge = edges.find((e: Edge) => e.target === node.id) || null;

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
        setEdges((edges: Edge[]) => edges.map((e: Edge) =>
          e.id === oldParentEdge.id
            ? { ...e, data: { ...e.data, hidden: true }, style: { ...e.style, opacity: 0 } }
            : e
        ));
      }

      // Mark dragged nodes
      setNodes((nodes: Node[]) => nodes.map((n: Node) =>
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
      setNodes((nodes: Node[]) => nodes.map((n: Node) =>
        dragContext.subtree.has(n.id)
          ? { ...n, position: { x: n.position.x + dx, y: n.position.y + dy } }
          : n
      ));

      // Find snap targets
      const intersectingNodes = reactFlowInstance.getIntersectingNodes(node).filter((n: Node) =>
        !dragContext.subtree.has(n.id)
      );

      // Find closest valid target within 140px
      let closestTarget: Node | null = null;
      let closestDistance = 140;

      intersectingNodes.forEach((target: Node) => {
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
      const newSnapTarget = (closestTarget as any)?.id || null;
      if (newSnapTarget !== dragContext.snapTarget) {
        // Remove old snap target styling
        if (dragContext.snapTarget) {
          setNodes((nodes: Node[]) => nodes.map((n: Node) =>
            n.id === dragContext.snapTarget
              ? { ...n, data: { ...n.data, isSnapTarget: false } }
              : n
          ));
        }

        // Add new snap target styling
        if (newSnapTarget) {
          setNodes((nodes: Node[]) => nodes.map((n: Node) =>
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
      setNodes((nodes: Node[]) => nodes.map((n: Node) => ({
        ...n,
        data: { ...n.data, isDragged: false, isSnapTarget: false }
      })));

      // Restore old parent edge
      if (dragContext.oldParentEdge) {
        setEdges((edges: Edge[]) => edges.map((e: Edge) =>
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
        setEdges((edges: Edge[]) => {
          const filtered = edges.filter((e: Edge) => e.target !== dragContext.rootId);
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
        onContactSelect(node.id);
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
    setReorderTrigger(prev => prev + 1); // Trigger re-layout

    // Force a rebuild of the hierarchy
    setTimeout(() => {
      setIsReordering(false);
      toast({
        title: "Layout Reset",
        description: "Nodes returned to default positions",
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
        panOnScrollMode={PanOnScrollMode.Free}
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

      {/* Bottom-centered toolbar - Less intrusive and more integrated */}


      <div className="absolute top-4 left-1/2 transform -translate-x-1/2 z-50">
        <div className="flex items-center gap-2 bg-background/40 backdrop-blur-sm border border-border/30 rounded-md px-2 py-1 shadow-sm transition-all hover:bg-background/60">
          {/* Reset Layout button */}
          <Button
            onClick={handleReorder}
            variant="ghost"
            size="sm"
            disabled={isReordering}
            className="h-8 px-3 font-normal hover:bg-muted/30 text-sm touch-manipulation gap-2"
          >
            <RotateCcw className={`h-4 w-4 ${isReordering ? 'animate-spin' : ''}`} />
            {isReordering ? 'Resetting...' : 'Reset Layout'}
          </Button>

          <ChevronRight className="h-4 w-4 text-muted-foreground/30" />

          {/* Quick Filter */}
          <QuickFilter
            selectedFilter={relationshipFilter}
            onFilterChange={setRelationshipFilter}
            showToggle={false}
            className="scale-100"
          />

          <div className="w-px h-5 bg-border/40 mx-1" />

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
            placeholder="Add by Voice"
            mode="contact"
            className="h-8 px-3 font-normal hover:bg-muted/30 text-sm touch-manipulation"
          />

          <div className="w-px h-5 bg-border/40 mx-1" />

          {/* Proximity Filter */}
          <ProximityFilter
            onFilterChange={handleProximityFilterChange}
            className="h-8 px-3 font-normal hover:bg-muted/30 text-sm touch-manipulation"
          />
        </div>
      </div>

      {/* Delete Confirmation Dialog */}
      <Dialog open={showDeleteConfirm} onOpenChange={setShowDeleteConfirm}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Delete Contact</DialogTitle>
            <DialogDescription>
              Are you sure you want to delete <strong>{deleteContact?.name}</strong> from your network? This action cannot be undone.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter className="gap-2 sm:gap-0">
            <Button
              variant="outline"
              onClick={() => setShowDeleteConfirm(false)}
              disabled={deleteContactMutation.isPending}
            >
              Cancel
            </Button>
            <Button
              variant="destructive"
              onClick={() => {
                if (deleteContact) {
                  deleteContactMutation.mutate(deleteContact.id);
                }
              }}
              disabled={deleteContactMutation.isPending}
            >
              {deleteContactMutation.isPending ? 'Deleting...' : 'Delete'}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div >
  );
}

export default function ContactFlowGraph({ contacts, onContactSelect, onAddRelation }: ContactFlowGraphProps) {
  return (
    <ReactFlowProvider>
      <ContactFlowGraphInner contacts={contacts} onContactSelect={onContactSelect} onAddRelation={onAddRelation} />
    </ReactFlowProvider>
  );
}