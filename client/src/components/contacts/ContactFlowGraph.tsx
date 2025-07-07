
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
      
      // Show undo toast
      const contact = contacts.find(c => c.id.toString() === variables.child);
      const targetContact = contacts.find(c => c.id.toString() === variables.parent);
      
      toast({
        title: "Relationship changed",
        description: `${contact?.name} is now connected to ${targetContact?.name}`,
        action: (
          <button 
            onClick={() => handleUndo(variables.child, variables.oldParent)}
            className="px-2 py-1 bg-primary text-primary-foreground rounded text-sm"
          >
            Undo
          </button>
        ),
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
        animated: true,
      }));

    setNodeState(newNodes);
    setEdgeState(newEdges);
    setNodes(newNodes);
    setEdges(newEdges);
  }, [contacts, setNodes, setEdges]);

  const onDrag = useCallback(
    throttle((_e, dragged) => {
      console.log('🔄 Dragging node:', dragged.id, 'at position:', dragged.position);
      
      const allNodes = getNodes();
      const targets = allNodes.filter(
        (n) => n.id !== dragged.id && isIntersect(dragged.position, n.position),
      );
      
      console.log('🎯 Found targets for drop:', targets.map(t => t.id));
      
      setNodes((ns) =>
        ns.map((n) =>
          targets.some((t) => t.id === n.id)
            ? { ...n, data: { ...n.data, drop: true } }
            : { ...n, data: { ...n.data, drop: false } },
        ),
      );
    }, 100),
    [getNodes, setNodes],
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
      
      // Clear drop highlighting
      setNodes((ns) =>
        ns.map((n) => ({ ...n, data: { ...n.data, drop: false } })),
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

  return (
    <div style={{ height: '600px', width: '100%' }}>
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
