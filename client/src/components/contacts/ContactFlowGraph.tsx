
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

const NODE_SIZE = 160;

function isIntersect(a: XYPosition, b: XYPosition) {
  return (
    Math.abs(a.x - b.x) < NODE_SIZE * 0.5 &&
    Math.abs(a.y - b.y) < NODE_SIZE * 0.5
  );
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
    mutationFn: ({ child, parent }: { child: string; parent: string }) =>
      fetch(`/api/contacts/${child}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ parentId: parent }),
      }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['contacts'] }),
  });

  // Convert contacts to nodes and edges
  useEffect(() => {
    const newNodes: Node[] = contacts.map((contact, index) => ({
      id: contact.id.toString(),
      position: { 
        x: (index % 5) * 200, 
        y: Math.floor(index / 5) * 180 
      },
      data: { 
        label: contact.name,
        contact,
        drop: false,
      },
      type: 'contactNode',
      draggable: true,
    }));

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
      const targets = getNodes().filter(
        (n) => n.id !== dragged.id && isIntersect(dragged.position, n.position),
      );
      setNodes((ns) =>
        ns.map((n) =>
          targets.some((t) => t.id === n.id)
            ? { ...n, data: { ...n.data, drop: true } }
            : { ...n, data: { ...n.data, drop: false } },
        ),
      );
    }, 80),
    [getNodes, setNodes],
  );

  const onDragStop = useCallback(
    (_e, dragged) => {
      const target = getNodes().find(
        (n) => n.data.drop && isIntersect(dragged.position, n.position),
      );
      
      // Clear drop highlighting
      setNodes((ns) =>
        ns.map((n) => ({ ...n, data: { ...n.data, drop: false } })),
      );
      
      if (!target) return;

      reparent.mutate({ child: dragged.id, parent: target.id });

      // Optimistically update the UI
      const subs = subtree(getEdges(), dragged.id);
      setNodes((ns) =>
        ns.map((n) =>
          [dragged.id, ...subs].includes(n.id)
            ? { ...n, parentNode: target.id }
            : n,
        ),
      );
    },
    [getNodes, getEdges, setNodes, reparent],
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

const nodeTypes = {
  contactNode: ContactNode,
};

export default function ContactFlowGraph({ contacts, onContactSelect }: ContactFlowGraphProps) {
  return (
    <ReactFlowProvider>
      <ContactFlowGraphInner contacts={contacts} onContactSelect={onContactSelect} />
    </ReactFlowProvider>
  );
}
