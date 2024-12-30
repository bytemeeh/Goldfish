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

    const nodes = [];
    const links = [];
    const processedIds = new Set<number>();

    // Helper function to calculate node positions
    const calculateNodePosition = (
      level: number,
      index: number,
      totalInLevel: number,
      parentX?: number,
      parentY?: number
    ) => {
      const levelSpacing = 300; // Vertical spacing between levels
      const nodeSpacing = 200;  // Horizontal spacing between nodes

      const y = level * levelSpacing;
      let x;

      if (level === 0) {
        // Center the root node
        x = 0;
      } else if (parentX !== undefined && parentY !== undefined) {
        // Position relative to parent
        const spreadWidth = (totalInLevel - 1) * nodeSpacing;
        const startX = parentX - spreadWidth / 2;
        x = startX + (index * nodeSpacing);
      } else {
        // Position in level if no parent
        const spreadWidth = (totalInLevel - 1) * nodeSpacing;
        const startX = -spreadWidth / 2;
        x = startX + (index * nodeSpacing);
      }

      return { x, y };
    };

    // Add root node (me)
    const rootPos = calculateNodePosition(0, 0, 1);
    nodes.push({
      id: meContact.id.toString(),
      name: meContact.name,
      val: 24,
      color: defaultColor,
      icon: User,
      contact: meContact,
      ...rootPos,
      level: 0
    });
    processedIds.add(meContact.id);

    // Get direct connections (level 1)
    const directConnections = contacts.filter(c => 
      !c.isMe && 
      (!c.parentId || c.parentId === meContact.id)
    );

    // Add direct connections (level 1)
    directConnections.forEach((contact, index) => {
      if (!processedIds.has(contact.id)) {
        const pos = calculateNodePosition(1, index, directConnections.length);
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
          ...pos,
          level: 1
        });
        processedIds.add(contact.id);

        // Add link to root
        links.push({
          source: meContact.id.toString(),
          target: contact.id.toString(),
          value: 1,
          relationship: contact.relationshipType
        });

        // Process children of this contact (level 2)
        const children = contacts.filter(c => c.parentId === contact.id);
        children.forEach((child, childIndex) => {
          if (!processedIds.has(child.id)) {
            const childPos = calculateNodePosition(
              2, 
              childIndex, 
              children.length,
              pos.x,
              pos.y
            );
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
              ...childPos,
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
            if (globalScale > 1.5 && link.relationship) {
              const label = link.relationship;
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
          cooldownTicks={0}
          enablePanInteraction={true}
          enableZoomInteraction={true}
          enableNodeDrag={false}
          minZoom={0.5}
          maxZoom={3}
        />
      </div>
    </div>
  );
}