import { useCallback, useState } from "react";
import { ForceGraph2D } from "react-force-graph";
import { useQuery } from "@tanstack/react-query";
import { type Contact, type RelationshipType } from "@/lib/types";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { format } from "date-fns";
import { Mail, Phone, Cake } from "lucide-react";

interface GraphData {
  nodes: Array<{
    id: string;
    name: string;
    val: number;
    color: string;
    contact: Contact;
  }>;
  links: Array<{
    source: string;
    target: string;
    label: string;
  }>;
}

interface NodeObject {
  id: string;
  name: string;
  color: string;
  x: number;
  y: number;
  contact: Contact;
}

// Color mapping for different relationship types
const relationshipColors: Record<RelationshipType, string> = {
  sibling: "#22c55e",    // Green
  mother: "#ec4899",     // Pink
  father: "#3b82f6",     // Blue
  brother: "#22c55e",    // Green
  friend: "#f97316",     // Orange
  child: "#a855f7",      // Purple
  "co-worker": "#78716c", // Warm Gray
  spouse: "#ec4899",      // Pink
  "boyfriend/girlfriend": "#f43f5e" // Rose
};

const defaultColor = "#94a3b8"; // Slate 400 for contacts without relationships

export function ContactGraph() {
  const [selectedNode, setSelectedNode] = useState<NodeObject | null>(null);
  const { data: contacts } = useQuery<Contact[]>({
    queryKey: ["/api/contacts"],
  });

  // Transform contacts data into graph format
  const graphData = useCallback((): GraphData => {
    if (!contacts) return { nodes: [], links: [] };

    const nodes = contacts.map(contact => ({
      id: contact.id.toString(),
      name: contact.name,
      val: contact.isMe ? 8 : 4, // Make the user's node larger
      color: contact.relationshipType 
        ? relationshipColors[contact.relationshipType]
        : defaultColor,
      contact,
    }));

    const links = contacts
      .filter(contact => contact.parentId)
      .map(contact => ({
        source: contact.parentId!.toString(),
        target: contact.id.toString(),
        label: contact.relationshipType || 'connected to'
      }));

    return { nodes, links };
  }, [contacts]);

  const handleNodeClick = useCallback((node: NodeObject) => {
    setSelectedNode(selectedNode?.id === node.id ? null : node);
  }, [selectedNode]);

  if (!contacts) return null;

  return (
    <div className="relative w-full h-[calc(100vh-12rem)]">
      {/* Selected Node Details */}
      {selectedNode && (
        <Card className="absolute top-4 left-4 w-80 z-10 p-4 bg-card/95 backdrop-blur-sm shadow-lg border-primary/20">
          <h3 className="text-lg font-semibold mb-2">{selectedNode.contact.name}</h3>
          {selectedNode.contact.relationshipType && (
            <Badge variant="relationship" className="mb-4 capitalize">
              {selectedNode.contact.relationshipType.replace('-', ' ')}
            </Badge>
          )}
          <div className="space-y-2 text-sm">
            {selectedNode.contact.email && (
              <div className="flex items-center text-muted-foreground">
                <Mail className="mr-2 h-4 w-4" />
                <a href={`mailto:${selectedNode.contact.email}`} className="hover:text-primary transition-colors">
                  {selectedNode.contact.email}
                </a>
              </div>
            )}
            {selectedNode.contact.phone && (
              <div className="flex items-center text-muted-foreground">
                <Phone className="mr-2 h-4 w-4" />
                <a href={`tel:${selectedNode.contact.phone}`} className="hover:text-primary transition-colors">
                  {selectedNode.contact.phone}
                </a>
              </div>
            )}
            {selectedNode.contact.birthday && (
              <div className="flex items-center text-muted-foreground">
                <Cake className="mr-2 h-4 w-4" />
                {format(new Date(selectedNode.contact.birthday), "PPP")}
              </div>
            )}
            {selectedNode.contact.notes && (
              <p className="text-muted-foreground mt-2 italic">
                {selectedNode.contact.notes}
              </p>
            )}
          </div>
        </Card>
      )}

      {/* Legend */}
      <Card className="absolute top-4 right-4 p-4 bg-card/95 backdrop-blur-sm z-10">
        <h3 className="font-semibold mb-2">Relationship Types</h3>
        <div className="space-y-1.5">
          {Object.entries(relationshipColors).map(([type, color]) => (
            <div key={type} className="flex items-center gap-2">
              <div 
                className="w-3 h-3 rounded-full" 
                style={{ backgroundColor: color }}
              />
              <span className="text-sm capitalize">{type.replace('-', ' ')}</span>
            </div>
          ))}
        </div>
      </Card>

      <div className="w-full h-full border rounded-lg bg-card overflow-hidden">
        <ForceGraph2D
          graphData={graphData()}
          nodeLabel="name"
          nodeRelSize={3}
          linkWidth={1.5}
          linkColor={() => "#cbd5e1"} // Slate 300
          nodeCanvasObject={(node: NodeObject, ctx: CanvasRenderingContext2D, globalScale: number) => {
            const label = node.name;
            const fontSize = 14/globalScale;
            ctx.font = `${fontSize}px Inter, sans-serif`;

            // Draw node
            ctx.beginPath();
            ctx.arc(node.x, node.y, node.val, 0, 2 * Math.PI);
            ctx.fillStyle = selectedNode?.id === node.id 
              ? "#020617" // Slate 950 for selected node
              : node.color;
            ctx.fill();

            // Draw border for selected node
            if (selectedNode?.id === node.id) {
              ctx.strokeStyle = node.color;
              ctx.lineWidth = 2;
              ctx.stroke();
            }

            // Draw label
            ctx.fillStyle = "#020617"; // Slate 950
            ctx.textAlign = "center";
            ctx.fillText(label, node.x, node.y + node.val + fontSize);
          }}
          linkCanvasObject={(link: any, ctx: CanvasRenderingContext2D, globalScale: number) => {
            const start = link.source;
            const end = link.target;

            // Draw line
            ctx.strokeStyle = "#cbd5e1"; // Slate 300
            ctx.lineWidth = 1.5;
            ctx.beginPath();
            ctx.moveTo(start.x, start.y);
            ctx.lineTo(end.x, end.y);
            ctx.stroke();

            // Draw relationship label
            const label = link.label;
            if (label && globalScale > 1.5) { // Only show labels when zoomed in
              const fontSize = 12/globalScale;
              ctx.font = `${fontSize}px Inter, sans-serif`;

              // Position label at midpoint
              const midX = (start.x + end.x) / 2;
              const midY = (start.y + end.y) / 2;

              // Add background for better readability
              const metrics = ctx.measureText(label);
              const padding = 4/globalScale;

              ctx.fillStyle = "rgba(255, 255, 255, 0.8)";
              ctx.fillRect(
                midX - metrics.width/2 - padding,
                midY - fontSize/2 - padding,
                metrics.width + padding * 2,
                fontSize + padding * 2
              );

              // Draw text
              ctx.fillStyle = "#475569"; // Slate 600
              ctx.textAlign = "center";
              ctx.textBaseline = "middle";
              ctx.fillText(label, midX, midY);
            }
          }}
          onNodeClick={handleNodeClick}
          cooldownTicks={100}
          enableZoomPanInteraction={true}
          enableNodeDrag={true}
        />
      </div>
    </div>
  );
}