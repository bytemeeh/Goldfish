import { useCallback } from "react";
import { ForceGraph2D } from "react-force-graph";
import { useQuery } from "@tanstack/react-query";
import { type Contact, type RelationshipType } from "@/lib/types";

interface GraphData {
  nodes: Array<{
    id: string;
    name: string;
    val: number;
    color: string;
    relationshipType?: RelationshipType;
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

// Color mapping for different relationship types
const relationshipColors: Record<RelationshipType, string> = {
  sibling: "#4CAF50",    // Green
  mother: "#E91E63",     // Pink
  father: "#2196F3",     // Blue
  brother: "#4CAF50",    // Green
  friend: "#FF9800",     // Orange
  child: "#9C27B0",      // Purple
  "co-worker": "#795548" // Brown
};

const defaultColor = "#999999"; // Gray for contacts without relationships

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
      relationshipType: contact.relationshipType,
      color: contact.relationshipType 
        ? relationshipColors[contact.relationshipType]
        : defaultColor,
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
    <div className="relative w-full h-[calc(100vh-12rem)]">
      <div className="absolute top-4 right-4 bg-card p-4 rounded-lg shadow-md z-10">
        <h3 className="font-semibold mb-2">Relationship Types</h3>
        <div className="space-y-2">
          {Object.entries(relationshipColors).map(([type, color]) => (
            <div key={type} className="flex items-center gap-2">
              <div 
                className="w-4 h-4 rounded-full" 
                style={{ backgroundColor: color }}
              />
              <span className="text-sm capitalize">{type}</span>
            </div>
          ))}
        </div>
      </div>

      <div className="w-full h-full border rounded-lg bg-card">
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
    </div>
  );
}