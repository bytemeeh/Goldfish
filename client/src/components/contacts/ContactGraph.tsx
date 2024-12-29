import { useCallback } from "react";
import { ForceGraph2D } from "react-force-graph";
import { useQuery } from "@tanstack/react-query";
import { type Contact } from "@/lib/types";

interface GraphData {
  nodes: Array<{
    id: string;
    name: string;
    val: number;
    color: string;
  }>;
  links: Array<{
    source: string;
    target: string;
    value: number;
  }>;
}

interface NodeObject {
  id: string;
  name: string;
  color: string;
  x: number;
  y: number;
}

export function ContactGraph() {
  const { data: contacts } = useQuery<Contact[]>({
    queryKey: ["/api/contacts"],
  });

  // Transform contacts data into graph format
  const graphData = useCallback((): GraphData => {
    if (!contacts) return { nodes: [], links: [] };

    const nodes = contacts.map(contact => ({
      id: contact.id.toString(),
      name: contact.name,
      val: 1,
      color: contact.parentId ? '#69b3a2' : '#ff9999',  // Different colors for parents and children
    }));

    const links = contacts
      .filter(contact => contact.parentId)
      .map(contact => ({
        source: contact.parentId!.toString(),
        target: contact.id.toString(),
        value: 1,
      }));

    return { nodes, links };
  }, [contacts]);

  if (!contacts) return null;

  return (
    <div className="w-full h-[calc(100vh-12rem)] border rounded-lg bg-card">
      <ForceGraph2D
        graphData={graphData()}
        nodeLabel="name"
        nodeRelSize={8}
        linkWidth={2}
        linkColor={() => "#999"}
        nodeCanvasObject={(node: NodeObject, ctx: CanvasRenderingContext2D, globalScale: number) => {
          const label = node.name;
          const fontSize = 16/globalScale;
          ctx.font = `${fontSize}px Sans-Serif`;
          ctx.fillStyle = node.color;
          ctx.beginPath();
          ctx.arc(node.x, node.y, 5, 0, 2 * Math.PI, false);
          ctx.fill();

          // Draw label
          ctx.fillStyle = "black";
          ctx.textAlign = "center";
          ctx.fillText(label, node.x, node.y + 10);
        }}
        enableZoomPanInteraction={true}
        enableNodeDrag={true}
        cooldownTicks={100}
      />
    </div>
  );
}