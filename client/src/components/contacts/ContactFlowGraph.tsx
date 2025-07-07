
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

  // Convert contacts to nodes and edges
  useEffect(() => {
    const newNodes: Node[] = contacts.map((contact, index) => {
      // Place "me" contact in center, others around it
      let position;
      if (contact.isMe) {
        position = { x: 400, y: 300 }; // Center position
      } else {
        // Arrange other contacts in a circle around the center
        const nonMeIndex = contacts.filter(c => !c.isMe).findIndex(c => c.id === contact.id);
        const angle = (nonMeIndex * 2 * Math.PI) / Math.max(contacts.length - 1, 1);
        const radius = 250;
        position = {
          x: 400 + radius * Math.cos(angle),
          y: 300 + radius * Math.sin(angle)
        };
      }

      return {
        id: String(contact.id),
        position,
        data: { 
          label: contact.name,
          contact,
          drop: false,
        },
        type: 'contact',
        draggable: true,
      };
    });

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

    setNodeState(newNodes);
    setEdgeState(newEdges);
    setNodes(newNodes);
    setEdges(newEdges);
  }, [contacts, setNodes, setEdges]);

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
      
      setNodes((ns) =>
        ns.map((n) => {
          const isTarget = targets.some((t) => t.id === n.id);
          const isDraggedNode = n.id === dragged.id;
          
          return {
            ...n,
            data: { 
              ...n.data, 
              drop: isTarget,
              isDragging: isDraggedNode,
            },
            style: {
              ...n.style,
              opacity: isDraggedNode ? 0.8 : (isTarget ? 1 : 0.7),
              transform: isDraggedNode ? 'scale(1.1)' : (isTarget ? 'scale(1.05)' : 'scale(1)'),
              transition: 'all 0.2s ease-in-out',
              zIndex: isDraggedNode ? 1000 : (isTarget ? 100 : 1),
              filter: isDraggedNode ? 'drop-shadow(0 8px 16px rgba(0,0,0,0.3))' : 'none',
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
      
      // Clear drop highlighting with animation
      setNodes((ns) =>
        ns.map((n) => ({ 
          ...n, 
          data: { ...n.data, drop: false, isDragging: false },
          style: {
            ...n.style,
            opacity: 1,
            transform: 'scale(1)',
            transition: 'all 0.3s ease-out',
            zIndex: 1,
            filter: 'none',
          }
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
