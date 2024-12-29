import { useCallback, useState, useRef, useEffect } from "react";
import { ForceGraph2D } from "react-force-graph";
import { useQuery } from "@tanstack/react-query";
import { type Contact, type RelationshipType } from "@/lib/types";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { format } from "date-fns";
import { 
  Mail, 
  Phone, 
  Cake, 
  User, 
  Users, 
  Heart, 
  Baby, 
  Briefcase, 
  UserCircle2, 
  UserPlus, 
  HeartHandshake,
} from "lucide-react";

// Icon mapping for different relationship types
const relationshipIcons: Record<RelationshipType, typeof User> = {
  sibling: Users,
  mother: Heart,
  father: UserCircle2,
  brother: UserPlus,
  friend: Users,
  child: Baby,
  "co-worker": Briefcase,
  spouse: HeartHandshake,
  "boyfriend/girlfriend": Heart
};

// Category-based color scheme
const categoryColors = {
  family: "#22c55e",    // Green
  friends: "#f97316",   // Orange
  professional: "#3b82f6", // Blue
  romantic: "#ec4899",  // Pink
};

const relationshipCategories: Record<RelationshipType, keyof typeof categoryColors> = {
  sibling: "family",
  mother: "family",
  father: "family",
  brother: "family",
  friend: "friends",
  child: "family",
  "co-worker": "professional",
  spouse: "romantic",
  "boyfriend/girlfriend": "romantic"
};

const defaultColor = "#64748b"; // Slate 500 for better contrast

export function ContactGraph() {
  const [selectedNode, setSelectedNode] = useState<any>(null);
  const graphRef = useRef<any>();
  const { data: contacts } = useQuery<Contact[]>({
    queryKey: ["/api/contacts"],
  });

  // Transform contacts data into graph format with hierarchical layout
  const graphData = useCallback(() => {
    if (!contacts) return { nodes: [], links: [] };

    const meNode = contacts.find(c => c.isMe);
    if (!meNode) return { nodes: [], links: [] };

    const nodes = contacts.map(contact => ({
      id: contact.id.toString(),
      name: contact.name,
      val: contact.isMe ? 24 : 16,
      color: contact.relationshipType 
        ? categoryColors[relationshipCategories[contact.relationshipType]]
        : defaultColor,
      icon: contact.relationshipType 
        ? relationshipIcons[contact.relationshipType]
        : User,
      contact,
      // Position personal card at center
      fx: contact.isMe ? 0 : undefined,
      fy: contact.isMe ? 0 : undefined,
      // Add category for layout calculations
      category: contact.relationshipType 
        ? relationshipCategories[contact.relationshipType]
        : "other"
    }));

    const links = contacts
      .filter(contact => contact.parentId || contact.isMe)
      .map(contact => {
        if (contact.isMe) {
          return contacts
            .filter(c => c.parentId === contact.id)
            .map(child => ({
              source: contact.id.toString(),
              target: child.id.toString(),
              label: child.relationshipType || 'connected to'
            }));
        }
        return {
          source: (contact.parentId || meNode.id).toString(),
          target: contact.id.toString(),
          label: contact.relationshipType || 'connected to'
        };
      })
      .flat();

    return { nodes, links };
  }, [contacts]);

  // Apply force layout adjustments
  useEffect(() => {
    if (graphRef.current) {
      const fg = graphRef.current;
      fg.d3Force('charge').strength(-800); // Stronger repulsion
      fg.d3Force('link').distance(200); // Longer links

      // Add radial force to organize nodes by category
      const radialForce = (alpha: number) => {
        const centerX = 0;
        const centerY = 0;
        const radius = 300; // Radius for category arrangement

        fg.graphData().nodes.forEach((node: any) => {
          if (node.contact.isMe) return; // Skip personal card (center)

          // Calculate angle based on category
          let angle = 0;
          switch (node.category) {
            case 'family':
              angle = Math.PI / 2; // Top
              break;
            case 'friends':
              angle = Math.PI; // Right
              break;
            case 'professional':
              angle = -Math.PI / 2; // Bottom
              break;
            case 'romantic':
              angle = 0; // Left
              break;
            default:
              angle = Math.random() * 2 * Math.PI; // Random for uncategorized
          }

          // Calculate target position
          const targetX = centerX + radius * Math.cos(angle);
          const targetY = centerY + radius * Math.sin(angle);

          // Move node towards target
          node.vx = (node.vx || 0) + (targetX - node.x) * alpha;
          node.vy = (node.vy || 0) + (targetY - node.y) * alpha;
        });
      };

      fg.d3Force('radial', radialForce);
    }
  }, []);

  const handleNodeClick = useCallback((node: any) => {
    setSelectedNode(selectedNode?.id === node.id ? null : node);
  }, [selectedNode]);

  if (!contacts) return null;

  return (
    <div className="relative w-full h-[calc(100vh-12rem)]">
      {/* Selected Node Details */}
      {selectedNode && (
        <Card className="absolute top-4 left-4 w-80 z-10 p-4 bg-card/95 backdrop-blur-sm shadow-lg border-primary/20">
          <div className="flex items-center gap-2 mb-2">
            {selectedNode.icon && (
              <selectedNode.icon className="h-5 w-5" style={{ color: selectedNode.color }} />
            )}
            <h3 className="text-lg font-semibold">{selectedNode.contact.name}</h3>
          </div>
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

      {/* Legend */}
      <Card className="absolute top-4 right-4 p-4 bg-card/95 backdrop-blur-sm z-10">
        <h3 className="font-semibold mb-2">Categories</h3>
        <div className="space-y-2">
          <div className="flex items-center gap-2">
            <Users className="h-4 w-4" style={{ color: categoryColors.family }} />
            <span className="text-sm">Family</span>
          </div>
          <div className="flex items-center gap-2">
            <Users className="h-4 w-4" style={{ color: categoryColors.friends }} />
            <span className="text-sm">Friends</span>
          </div>
          <div className="flex items-center gap-2">
            <Briefcase className="h-4 w-4" style={{ color: categoryColors.professional }} />
            <span className="text-sm">Professional</span>
          </div>
          <div className="flex items-center gap-2">
            <Heart className="h-4 w-4" style={{ color: categoryColors.romantic }} />
            <span className="text-sm">Romantic</span>
          </div>
        </div>
      </Card>

      <div className="w-full h-full border rounded-lg bg-card overflow-hidden">
        <ForceGraph2D
          ref={graphRef}
          graphData={graphData()}
          nodeLabel="name"
          nodeRelSize={6}
          linkWidth={1.5}
          linkColor={() => "#e2e8f0"}
          nodeCanvasObject={(node: any, ctx: CanvasRenderingContext2D, globalScale: number) => {
            const Icon = node.icon;
            const size = node.val;
            const iconSize = size * 1.5;

            // Draw icon background
            ctx.beginPath();
            ctx.arc(node.x, node.y, size, 0, 2 * Math.PI);
            ctx.fillStyle = selectedNode?.id === node.id 
              ? "#ffffff"
              : "rgba(255, 255, 255, 0.9)";
            ctx.fill();

            // Draw icon border
            ctx.strokeStyle = node.color;
            ctx.lineWidth = selectedNode?.id === node.id || node.contact.isMe ? 3 : 2;
            ctx.stroke();

            // Draw icon path
            ctx.save();
            ctx.translate(node.x - iconSize/2, node.y - iconSize/2);
            ctx.scale(iconSize/24, iconSize/24);

            const path = new Path2D('M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z');
            ctx.fillStyle = node.color;
            ctx.fill(path);
            ctx.restore();

            // Draw label
            const label = node.name;
            const fontSize = node.contact.isMe ? 16/globalScale : 14/globalScale;
            ctx.font = `${fontSize}px Inter, sans-serif`;
            ctx.fillStyle = "#020617";
            ctx.textAlign = "center";
            ctx.fillText(label, node.x, node.y + size + fontSize);
          }}
          linkCanvasObject={(link: any, ctx: CanvasRenderingContext2D, globalScale: number) => {
            const start = link.source;
            const end = link.target;

            // Draw line
            ctx.strokeStyle = "#e2e8f0";
            ctx.lineWidth = 2;
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

              ctx.fillStyle = "rgba(255, 255, 255, 0.9)";
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