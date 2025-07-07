
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
import 'reactflow/dist/style.css';

// Define nodeTypes outside component to avoid React Flow warning
const nodeTypes = {
  contactNode: ContactNode,
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
      acc.push(e.target);
      subtree(edgeList, e.target, acc);
    });
  return acc;
}

interface ContactFlowGraphProps {
  contacts: Contact[];
  onContactSelect?: (contactId: number) => void;
}

function ContactFlowGraphInner({ contacts, onContactSelect }: ContactFlowGraphProps) {
  const queryClient = useQueryClient();
  const { setNodes, getNodes, getEdges, setEdges } = useReactFlow();
  const [nodes, setNodeState] = useState<Node[]>([]);
  const [edges, setEdgeState] = useState<Edge[]>([]);

  const reparent = useMutation({
    mutationFn: async ({ child, parent }: { child: string; parent: string }) => {
      console.log('🔄 Attempting to reparent:', { child, parent });
      const response = await fetch(`/api/contacts/${child}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ parentId: parseInt(parent, 10) }),
      });
      
      if (!response.ok) {
        const error = await response.text();
        console.error('❌ Reparent failed:', error);
        throw new Error(`Failed to reparent: ${error}`);
      }
      
      console.log('✅ Reparent successful');
      return response.json();
    },
    onSuccess: () => {
      console.log('🔄 Invalidating contacts query');
      queryClient.invalidateQueries({ queryKey: ['/api/contacts'] });
    },
    onError: (error) => {
      console.error('❌ Mutation error:', error);
    },
  });

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
        id: contact.id.toString(),
        position,
        data: { 
          label: contact.name,
          contact,
          drop: false,
        },
        type: 'contactNode',
        draggable: true,
      };
    });

    const newEdges: Edge[] = contacts
      .filter(contact => contact.parentId)
      .map(contact => ({
        id: `${contact.parentId}-${contact.id}`,
        source: contact.parentId!.toString(),
        target: contact.id.toString(),
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
      const target = allNodes.find(
        (n) => n.data.drop && isIntersect(dragged.position, n.position),
      );
      
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

      console.log('🚀 Initiating reparent mutation');
      reparent.mutate({ child: dragged.id, parent: target.id });
    },
    [getNodes, setNodes, reparent],
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
