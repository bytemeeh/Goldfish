import { useCallback, useState, useEffect } from "react";
import { ForceGraph2D } from "react-force-graph";
import { useQuery } from "@tanstack/react-query";
import { type Contact, type RelationshipType } from "@/lib/types";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { format } from "date-fns";
import { Mail, Phone, Cake } from "lucide-react";

// Simplified color mapping for different relationship types
const relationshipColors: Record<RelationshipType, string> = {
  sibling: "#22c55e",   // Green for family
  mother: "#22c55e",    // Green for family
  father: "#22c55e",    // Green for family
  brother: "#22c55e",   // Green for family
  friend: "#f97316",    // Orange for friends
  child: "#22c55e",     // Green for family
  "co-worker": "#3b82f6", // Blue for professional
  spouse: "#ec4899",     // Pink for romantic
  "boyfriend/girlfriend": "#ec4899" // Pink for romantic
};

const defaultColor = "#94a3b8"; // Slate 400 for contacts without relationships

export function ContactGraph() {
  const [selectedNode, setSelectedNode] = useState<any>(null);
  const { data: contacts } = useQuery<Contact[]>({
    queryKey: ["/api/contacts"],
  });

  // Transform contacts data into graph format
  const graphData = useCallback(() => {
    if (!contacts) return { nodes: [], links: [] };

    const meNode = contacts.find(c => c.isMe);
    if (!meNode) return { nodes: [], links: [] };

    const nodes = contacts.map(contact => ({
      id: contact.id.toString(),
      name: contact.name,
      val: contact.isMe ? 12 : 6, // Make personal card larger
      color: contact.relationshipType 
        ? relationshipColors[contact.relationshipType]
        : defaultColor,
      contact,
      fx: contact.isMe ? 0 : undefined, // Fix personal card at center
      fy: contact.isMe ? 0 : undefined,
    }));

    const links = contacts
      .filter(contact => contact.parentId || contact.isMe)
      .map(contact => {
        // If it's a connection to personal card
        if (contact.isMe) {
          return contacts
            .filter(c => c.parentId === contact.id)
            .map(child => ({
              source: contact.id.toString(),
              target: child.id.toString(),
              label: child.relationshipType || 'connected to'
            }));
        }
        // Regular parent-child connection
        return {
          source: (contact.parentId || meNode.id).toString(),
          target: contact.id.toString(),
          label: contact.relationshipType || 'connected to'
        };
      })
      .flat();

    return { nodes, links };
  }, [contacts]);

  const handleNodeClick = useCallback((node: any) => {
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
          </div>
        </Card>
      )}

      {/* Simplified Legend */}
      <Card className="absolute top-4 right-4 p-4 bg-card/95 backdrop-blur-sm z-10">
        <h3 className="font-semibold mb-2">Contact Types</h3>
        <div className="space-y-1.5">
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 rounded-full bg-[#22c55e]" />
            <span className="text-sm">Family</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 rounded-full bg-[#f97316]" />
            <span className="text-sm">Friend</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 rounded-full bg-[#3b82f6]" />
            <span className="text-sm">Professional</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 rounded-full bg-[#ec4899]" />
            <span className="text-sm">Romantic</span>
          </div>
        </div>
      </Card>

      <div className="w-full h-full border rounded-lg bg-card overflow-hidden">
        <ForceGraph2D
          graphData={graphData()}
          nodeLabel="name"
          nodeRelSize={4}
          linkWidth={1.5}
          linkColor={() => "#cbd5e1"}
          d3Force={(d3) => {
            // Center force for personal card
            d3.force('center', d3.forceCenter(0, 0));
            // Stronger repulsion between nodes
            d3.force('charge').strength(-200);
            // Shorter links
            d3.force('link').distance(100);
          }}
          nodeCanvasObject={(node: any, ctx: CanvasRenderingContext2D, globalScale: number) => {
            const label = node.name;
            const fontSize = node.contact.isMe ? 16/globalScale : 14/globalScale;
            ctx.font = `${fontSize}px Inter, sans-serif`;

            // Draw node
            ctx.beginPath();
            ctx.arc(node.x, node.y, node.val, 0, 2 * Math.PI);
            ctx.fillStyle = selectedNode?.id === node.id 
              ? "#020617"
              : node.color;
            ctx.fill();

            // Draw border for selected node or personal card
            if (selectedNode?.id === node.id || node.contact.isMe) {
              ctx.strokeStyle = node.color;
              ctx.lineWidth = 2;
              ctx.stroke();
            }

            // Draw label
            ctx.fillStyle = "#020617";
            ctx.textAlign = "center";
            ctx.fillText(label, node.x, node.y + node.val + fontSize);
          }}
          linkCanvasObject={(link: any, ctx: CanvasRenderingContext2D, globalScale: number) => {
            const start = link.source;
            const end = link.target;

            // Draw line
            ctx.strokeStyle = "#cbd5e1";
            ctx.lineWidth = 1.5;
            ctx.beginPath();
            ctx.moveTo(start.x, start.y);
            ctx.lineTo(end.x, end.y);
            ctx.stroke();

            // Draw relationship label when zoomed in
            if (globalScale > 1.5) {
              const label = link.label;
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
              ctx.fillStyle = "#475569";
              ctx.textAlign = "center";
              ctx.textBaseline = "middle";
              ctx.fillText(label, midX, midY);
            }
          }}
          onNodeClick={handleNodeClick}
          cooldownTicks={100}
          enableZoomPanInteraction={true}
          enableNodeDrag={true}
          minZoom={0.5}
          maxZoom={3}
        />
      </div>
    </div>
  );
}