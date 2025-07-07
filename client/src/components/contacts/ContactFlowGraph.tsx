
import React, { useCallback, useEffect, useState } from 'react';
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
} from 'reactflow';
import { throttle } from 'lodash-es';
import { useMutation, useQueryClient, useQuery } from '@tanstack/react-query';
import { Contact } from '@/lib/types';
import { ContactNode } from './ContactNode';
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
  const threshold = NODE_SIZE * 0.6; // Make it easier to drop
  const intersects = (
    Math.abs(a.x - b.x) < threshold &&
    Math.abs(a.y - b.y) < threshold
  );
  
  if (intersects) {
    console.log('🎯 Intersection detected:', { a, b, threshold });
  }
  
  return intersects;
}

function subtree(edgeList: Edge[], root: string, acc: string[] = []) {
  edgeList
    .filter((e) => e.source === root)
    .forEach((e) => {
      acc.push(String(e.target));
      subtree(edgeList, String(e.target), acc);
    });
  return acc;
}

interface ContactFlowGraphProps {
  contacts: Contact[];
  onContactSelect?: (contactId: number) => void;
}



function ContactFlowGraphInner({ contacts, onContactSelect }: ContactFlowGraphProps) {
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const { setNodes, getNodes, getEdges, setEdges } = useReactFlow();
  const [nodes, setNodeState] = useState<Node[]>([]);
  const [edges, setEdgeState] = useState<Edge[]>([]);
  const [isDragging, setIsDragging] = useState(false);
  const [draggedNode, setDraggedNode] = useState<string | null>(null);
  const [undoStack, setUndoStack] = useState<Array<{child: string, parent: string | null, timestamp: number}>>([]);
  const [dragTrail, setDragTrail] = useState<Array<{x: number, y: number, timestamp: number}>>([]);

  const reparent = useMutation({
    mutationFn: async ({ child, parent, oldParent }: { child: string; parent: string; oldParent: string | null }) => {
      console.log('🔄 Attempting to reparent:', { child, parent, oldParent });
      const response = await fetch(`/api/contacts/${child}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ parentId: parseInt(parent, 10) }),
      });
      
      if (!response.ok) {
        const error = await response.text();
        console.error('API error', response.status, error);
        throw new Error('API fail');
      }
      
      console.log('✅ Reparent successful');
      return { response: response.json(), oldParent };
    },
    onSuccess: (data, variables) => {
      console.log('🔄 Invalidating contacts query');
      queryClient.invalidateQueries({ queryKey: ['/api/contacts'] });
      
      // Add to undo stack
      setUndoStack(prev => [...prev.slice(-4), {
        child: variables.child,
        parent: variables.oldParent,
        timestamp: Date.now()
      }]);
      
      // Show success toast
      const contact = contacts.find(c => c.id.toString() === variables.child);
      const targetContact = contacts.find(c => c.id.toString() === variables.parent);
      
      toast({
        title: "Relationship changed",
        description: `${contact?.name} is now connected to ${targetContact?.name}`,
        duration: 3000,
      });
    },
    onError: (error) => {
      console.error('❌ Mutation error:', error);
      toast({
        title: "Failed to update relationship",
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
    
    // Build hierarchical structure
    const contactMap = new Map(contacts.map(c => [c.id, c]));
    const rootContacts = contacts.filter(c => !c.parentId || !contactMap.has(c.parentId));
    
    const buildHierarchy = (contact: Contact, level: number = 0, parentX: number = 400, parentY: number = 150): { contact: Contact; position: XYPosition; level: number }[] => {
      const result: { contact: Contact; position: XYPosition; level: number }[] = [];
      
      // Position calculation based on hierarchy level
      let position: XYPosition;
      
      if (contact.isMe) {
        // "Me" contact at center-top
        position = { x: 400, y: 100 };
      } else if (level === 0) {
        // Root level contacts spread horizontally
        const rootIndex = rootContacts.indexOf(contact);
        const spacing = Math.min(300, 800 / Math.max(rootContacts.length, 1));
        position = { 
          x: 400 - ((rootContacts.length - 1) * spacing) / 2 + (rootIndex * spacing), 
          y: 200 
        };
      } else {
        // Child contacts positioned below parent
        const siblings = contacts.filter(c => c.parentId === contact.parentId);
        const childIndex = siblings.indexOf(contact);
        const spacing = Math.min(200, 600 / Math.max(siblings.length, 1));
        
        position = {
          x: parentX - ((siblings.length - 1) * spacing) / 2 + (childIndex * spacing),
          y: parentY + 150
        };
      }
      
      result.push({ contact, position, level });
      
      // Process children
      const children = contacts.filter(c => c.parentId === contact.id);
      children.forEach(child => {
        result.push(...buildHierarchy(child, level + 1, position.x, position.y));
      });
      
      return result;
    };
    
    // Build all hierarchies
    const hierarchyData: { contact: Contact; position: XYPosition; level: number }[] = [];
    
    rootContacts.forEach(rootContact => {
      hierarchyData.push(...buildHierarchy(rootContact));
    });
    
    // Create nodes with hierarchical positioning
    const newNodes: Node[] = hierarchyData.map(({ contact, position, level }) => ({
      id: String(contact.id),
      position,
      data: { 
        label: contact.name,
        contact,
        level,
        drop: false,
      },
      type: 'contact',
      draggable: true,
      style: {
        zIndex: contact.isMe ? 1000 : (100 - level * 10),
      }
    }));

    const newEdges: Edge[] = contacts
      .filter(contact => contact.parentId)
      .map(contact => ({
        id: `${contact.parentId}-${contact.id}`,
        source: String(contact.parentId!),
        target: String(contact.id),
        type: 'smoothstep',
        animated: !isDragging,
        style: {
          stroke: isDragging && (draggedNode === String(contact.id) || draggedNode === String(contact.parentId)) 
            ? '#ef4444' 
            : '#64748b',
          strokeWidth: isDragging && (draggedNode === String(contact.id) || draggedNode === String(contact.parentId))
            ? 3
            : 2,
          strokeDasharray: isDragging && draggedNode === String(contact.id) ? '5,5' : 'none',
        },
      }));

    console.log('🔄 Created hierarchical nodes:', newNodes.length, 'edges:', newEdges.length);
    setNodeState(newNodes);
    setEdgeState(newEdges);
    setNodes(newNodes);
    setEdges(newEdges);
  }, [contacts, setNodes, setEdges, isDragging, draggedNode]);

  const onDrag = useCallback(
    throttle((_e, dragged) => {
      console.log('🔄 Dragging node:', dragged.id, 'at position:', dragged.position);
      
      if (!isDragging) {
        setIsDragging(true);
        setDraggedNode(dragged.id);
      }
      
      const allNodes = getNodes();
      const targets = allNodes.filter(
        (n) => n.id !== dragged.id && isIntersect(dragged.position, n.position),
      );
      
      console.log('🎯 Found targets for drop:', targets.map(t => t.id));
      
      // Add current position to drag trail
      if (draggedNode === dragged.id) {
        setDragTrail(prev => [
          ...prev.slice(-10), // Keep last 10 positions for trail effect
          { x: dragged.position.x, y: dragged.position.y, timestamp: Date.now() }
        ]);
      }
      
      setNodes((ns) =>
        ns.map((n) => {
          const isTarget = targets.some((t) => t.id === n.id);
          const isDraggedNode = n.id === dragged.id;
          
          return {
            ...n,
            position: isDraggedNode ? dragged.position : n.position,
            data: { 
              ...n.data, 
              drop: isTarget,
              isDragging: isDraggedNode,
            }
          };
        }),
      );
      
      // Update edges with animation effects
      setEdges((edges) =>
        edges.map((edge) => ({
          ...edge,
          animated: !isDragging,
          style: {
            ...edge.style,
            stroke: edge.source === dragged.id || edge.target === dragged.id 
              ? '#ef4444' 
              : '#64748b',
            strokeWidth: edge.source === dragged.id || edge.target === dragged.id ? 3 : 2,
            strokeDasharray: edge.source === dragged.id ? '5,5' : 'none',
            opacity: edge.source === dragged.id || edge.target === dragged.id ? 0.6 : 1,
          },
        }))
      );
    }, 50),
    [getNodes, setNodes, setEdges, isDragging],
  );

  const onDragStop = useCallback(
    (_e, dragged) => {
      console.log('🛑 Drag stopped for node:', dragged.id, 'at position:', dragged.position);
      
      const allNodes = getNodes();
      
      // Find intersecting nodes based on current positions
      const intersectingNodes = allNodes.filter(
        (n) => n.id !== dragged.id && isIntersect(dragged.position, n.position),
      );
      
      console.log('🎯 Intersecting nodes at drop:', intersectingNodes.map(n => n.id));
      
      // Use the first intersecting node as target
      const target = intersectingNodes.length > 0 ? intersectingNodes[0] : null;
      
      console.log('🎯 Target found:', target ? target.id : 'none');
      
      // Reset drag state and clear visual effects
      setIsDragging(false);
      setDraggedNode(null);
      setDragTrail([]);
      
      // Clear drop highlighting
      setNodes((ns) =>
        ns.map((n) => ({ 
          ...n, 
          data: { ...n.data, drop: false, isDragging: false }
        })),
      );
      
      // Reset edges
      setEdges((edges) =>
        edges.map((edge) => ({
          ...edge,
          animated: true,
          style: {
            ...edge.style,
            stroke: '#64748b',
            strokeWidth: 2,
            strokeDasharray: 'none',
            opacity: 1,
          },
        }))
      );
      
      if (!target) {
        console.log('❌ No valid target found, aborting reparent');
        return;
      }

      // Prevent self-parenting and circular references
      if (target.id === dragged.id) {
        console.log('❌ Cannot parent to self');
        return;
      }

      // Get the old parent before reparenting
      const currentContact = contacts.find(c => c.id.toString() === dragged.id);
      const oldParent = currentContact?.parentId?.toString() || null;
      
      console.log('🚀 Initiating reparent mutation');
      reparent.mutate({ child: String(dragged.id), parent: String(target.id), oldParent });
    },
    [getNodes, setNodes, reparent, contacts],
  );

  const onNodeClick = useCallback(
    (_event, node) => {
      if (onContactSelect) {
        onContactSelect(parseInt(node.id));
      }
    },
    [onContactSelect],
  );

  const handleUndoAction = () => {
    if (undoStack.length === 0) return;
    
    const lastAction = undoStack[undoStack.length - 1];
    setUndoStack(prev => prev.slice(0, -1));
    
    handleUndo(lastAction.child, lastAction.parent);
  };

  return (
    <div style={{ height: '600px', width: '100%', position: 'relative' }}>
      <ReactFlow
        nodes={nodes}
        edges={edges}
        nodeTypes={nodeTypes}
        onNodeDrag={onDrag}
        onNodeDragStop={onDragStop}
        onNodeClick={onNodeClick}
        connectionLineType={ConnectionLineType.SmoothStep}
        fitView
        fitViewOptions={{ padding: 0.2 }}
      >
        <Background variant={BackgroundVariant.Dots} />
        <Controls />
        <MiniMap />
      </ReactFlow>
      
      {/* Undo Button */}
      <AnimatePresence>
        {undoStack.length > 0 && (
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: 20 }}
            className="absolute top-4 right-4 z-50"
          >
            <Button
              onClick={handleUndoAction}
              variant="secondary"
              size="sm"
              className="shadow-lg bg-white/90 backdrop-blur-sm border border-gray-200 hover:bg-white"
            >
              <Undo2 className="h-4 w-4 mr-2" />
              Undo ({undoStack.length})
            </Button>
          </motion.div>
        )}
      </AnimatePresence>
      
      {/* Dragging Status Indicator */}
      <AnimatePresence>
        {isDragging && (
          <motion.div
            initial={{ opacity: 0, scale: 0.8 }}
            animate={{ opacity: 1, scale: 1 }}
            exit={{ opacity: 0, scale: 0.8 }}
            className="absolute top-4 left-4 z-50"
          >
            <div className="bg-blue-100 border border-blue-300 rounded-lg px-3 py-2 text-sm text-blue-800 shadow-lg">
              <RotateCcw className="h-4 w-4 inline mr-2 animate-spin" />
              Drag to reconnect relationship
            </div>
          </motion.div>
        )}
      </AnimatePresence>
      
      {/* Drag Trail Effect */}
      <AnimatePresence>
        {isDragging && dragTrail.length > 0 && (
          <div className="absolute inset-0 pointer-events-none z-10">
            {dragTrail.map((point, index) => (
              <motion.div
                key={`${point.timestamp}-${index}`}
                initial={{ opacity: 0.8, scale: 0.8 }}
                animate={{ opacity: 0, scale: 1.2 }}
                exit={{ opacity: 0 }}
                transition={{ duration: 0.6 }}
                className="absolute w-3 h-3 bg-blue-400 rounded-full shadow-lg"
                style={{
                  left: point.x - 6,
                  top: point.y - 6,
                  opacity: Math.max(0, (index / dragTrail.length) * 0.6),
                }}
              />
            ))}
          </div>
        )}
      </AnimatePresence>
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
