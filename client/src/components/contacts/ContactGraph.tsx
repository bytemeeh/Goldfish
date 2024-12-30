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

const defaultColor = "#64748b"; // Slate 500 for better contrast

export function ContactGraph() {
  const [selectedNode, setSelectedNode] = useState<any>(null);
  const graphRef = useRef<any>();
  const { data: contacts } = useQuery<Contact[]>({
    queryKey: ["/api/contacts"],
  });

  const graphData = useCallback(() => {
    if (!contacts) return { nodes: [], links: [] };

    // Find the personal contact (me)
    const meContact = contacts.find(c => c.isMe);
    if (!meContact) return { nodes: [], links: [] };

    // Create a map for quick contact lookup
    const contactMap = new Map(contacts.map(c => [c.id, c]));

    // Function to check if a contact should be connected directly to 'me'
    const isDirectConnection = (contact: Contact) => {
      if (contact.isMe) return false;
      if (!contact.parentId) return true; // Root level contacts
      return contact.parentId === meContact.id; // Direct children of me
    };

    // Create nodes for direct connections and their immediate relationships
    const nodes = [];
    const links = [];
    const processedIds = new Set<number>();

    // Add 'me' node
    nodes.push({
      id: meContact.id.toString(),
      name: meContact.name,
      val: 24,
      color: defaultColor,
      icon: User,
      contact: meContact,
      fx: 0,
      fy: 0,
      level: 0
    });
    processedIds.add(meContact.id);

    // Process direct connections first
    contacts.forEach(contact => {
      if (isDirectConnection(contact) && !processedIds.has(contact.id)) {
        // Add node for direct connection
        nodes.push({
          id: contact.id.toString(),
          name: contact.name,
          val: 16,
          color: contact.relationshipType
            ? categoryColors[relationshipCategories[contact.relationshipType]]
            : defaultColor,
          icon: contact.relationshipType
            ? relationshipIcons[contact.relationshipType]
            : User,
          contact,
          level: 1
        });
        processedIds.add(contact.id);

        // Add link to 'me' if it's a direct connection
        if (!contact.parentId) {
          links.push({
            source: meContact.id.toString(),
            target: contact.id.toString(),
            value: 1,
            relationship: contact.relationshipType
          });
        }

        // Process immediate children/relationships of direct connections
        const children = contacts.filter(c => c.parentId === contact.id);
        children.forEach(child => {
          if (!processedIds.has(child.id)) {
            // Add node for the child
            nodes.push({
              id: child.id.toString(),
              name: child.name,
              val: 12,
              color: child.relationshipType
                ? categoryColors[relationshipCategories[child.relationshipType]]
                : defaultColor,
              icon: child.relationshipType
                ? relationshipIcons[child.relationshipType]
                : User,
              contact: child,
              level: 2
            });
            processedIds.add(child.id);

            // Add link to parent
            links.push({
              source: contact.id.toString(),
              target: child.id.toString(),
              value: 1,
              relationship: child.relationshipType
            });
          }
        });
      }
    });

    return { nodes, links };
  }, [contacts]);

  useEffect(() => {
    if (graphRef.current) {
      const fg = graphRef.current;

      // Configure force simulation
      fg.d3Force('charge')?.strength(-1200);
      fg.d3Force('link')?.distance(d => {
        return d.source.level === 0 ? 200 : 150;
      });

      // Add hierarchical force
      const simulation = fg.d3Force();
      if (simulation) {
        simulation.force('radial', function(alpha: number) {
          const nodes = fg.graphData().nodes;
          const radius = 250;

          nodes.forEach((node: any) => {
            if (node.contact.isMe) return;

            let angle = 0;
            const parentNode = nodes.find((n: any) => 
              n.id === node.contact.parentId?.toString()
            );

            if (parentNode) {
              // Child nodes orbit around their parent
              angle = parentNode.x ? Math.atan2(parentNode.y, parentNode.x) : 0;
              const distance = radius * (node.level === 1 ? 0.6 : 0.8);
              const targetX = parentNode.x + distance * Math.cos(angle);
              const targetY = parentNode.y + distance * Math.sin(angle);
              node.vx = (node.vx || 0) + (targetX - node.x) * alpha;
              node.vy = (node.vy || 0) + (targetY - node.y) * alpha;
            } else {
              // Root nodes positioned by category
              switch (node.contact.relationshipType) {
                case 'mother':
                case 'father':
                case 'brother':
                case 'sibling':
                  angle = Math.PI / 2; // Family at top
                  break;
                case 'friend':
                case 'boyfriend/girlfriend':
                  angle = Math.PI; // Friends at right
                  break;
                case 'co-worker':
                  angle = -Math.PI / 2; // Professional at bottom
                  break;
                case 'spouse':
                  angle = 0; // Spouse at left
                  break;
                default:
                  angle = Math.random() * 2 * Math.PI;
              }
              const targetX = radius * Math.cos(angle);
              const targetY = radius * Math.sin(angle);
              node.vx = (node.vx || 0) + (targetX - node.x) * alpha;
              node.vy = (node.vy || 0) + (targetY - node.y) * alpha;
            }
          });
        });
      }
    }
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
          <div className="flex items-center gap-2 mb-2">
            {selectedNode.icon && (
              <selectedNode.icon className="h-5 w-5" style={{ color: selectedNode.color }} />
            )}
            <h3 className="text-lg font-semibold">{selectedNode.contact.name}</h3>
          </div>
          {selectedNode.contact.relationshipType && (
            <Badge
              variant="relationship"
              className="mb-4 capitalize"
            >
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
            const size = node.val;

            // Draw node background
            ctx.beginPath();
            ctx.arc(node.x, node.y, size, 0, 2 * Math.PI);
            ctx.fillStyle = selectedNode?.id === node.id
              ? "#ffffff"
              : "rgba(255, 255, 255, 0.9)";
            ctx.fill();

            // Draw node border
            ctx.strokeStyle = node.color;
            ctx.lineWidth = selectedNode?.id === node.id || node.contact.isMe ? 3 : 2;
            ctx.stroke();

            // Draw simple icon (circle with initial)
            ctx.fillStyle = node.color;
            ctx.textAlign = 'center';
            ctx.textBaseline = 'middle';
            ctx.font = `${size}px Inter`;
            ctx.fillText(node.name[0], node.x, node.y);

            // Draw label below node
            const label = node.name;
            const fontSize = node.contact.isMe ? 16 / globalScale : 14 / globalScale;
            ctx.font = `${fontSize}px Inter, sans-serif`;
            ctx.fillStyle = "#020617";
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
              const label = link.relationship || '';
              const fontSize = 12 / globalScale;
              ctx.font = `${fontSize}px Inter, sans-serif`;

              // Position label at midpoint
              const midX = (start.x + end.x) / 2;
              const midY = (start.y + end.y) / 2;

              // Add background for better readability
              const metrics = ctx.measureText(label);
              const padding = 4 / globalScale;

              ctx.fillStyle = "rgba(255, 255, 255, 0.9)";
              ctx.fillRect(
                midX - metrics.width / 2 - padding,
                midY - fontSize / 2 - padding,
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
          enablePanInteraction={true}
          enableZoomInteraction={true}
          enableNodeDrag={true}
          minZoom={0.5}
          maxZoom={3}
        />
      </div>
    </div>
  );
}