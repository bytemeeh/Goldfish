
import React, { useCallback } from 'react';
import ReactFlow, {
  ReactFlowProvider,
  NodeMouseHandler,
  ConnectionLineType,
  useReactFlow,
  Edge,
  XYPosition,
} from 'reactflow';
import { throttle } from 'lodash-es';
import { useMutation, useQueryClient } from '@tanstack/react-query';

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

export default function ContactFlowGraph() {
  const queryClient = useQueryClient();
  const { setNodes, getNodes, getEdges } = useReactFlow();

  const reparent = useMutation({
    mutationFn: ({ child, parent }: { child: string; parent: string }) =>
      fetch(`/api/contacts/${child}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ parentId: parent }),
      }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['contacts'] }),
  });

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
    [],
  );

  const onDragStop = useCallback(
    (_e, dragged) => {
      const target = getNodes().find(
        (n) => n.data.drop && isIntersect(dragged.position, n.position),
      );
      if (!target) return;

      reparent.mutate({ child: dragged.id, parent: target.id });

      const subs = subtree(getEdges(), dragged.id);
      setNodes((ns) =>
        ns.map((n) =>
          [dragged.id, ...subs].includes(n.id)
            ? { ...n, parentNode: target.id }
            : n,
        ),
      );
    },
    [],
  );

  return (
    <div style={{ height: '600px', width: '100%' }}>
      <ReactFlow
        onNodeDrag={onDrag}
        onNodeDragStop={onDragStop}
        connectionLineType={ConnectionLineType.SmoothStep}
        fitView
      />
    </div>
  );
}
