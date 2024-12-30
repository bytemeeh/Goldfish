import { useState, useCallback, useEffect, useRef } from "react";
import { useQuery } from "@tanstack/react-query";
import { type Contact } from "@/lib/types";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import {
  Mail,
  Phone,
  Cake,
} from "lucide-react";
import { format } from "date-fns";
import ForceGraph2D, { type ForceGraphMethods } from "react-force-graph-2d";

// Contact details component
function ContactDetails({ contact }: { contact: Contact }) {
  return (
    <div className="space-y-2">
      {contact.email && (
        <div className="flex items-center text-sm text-muted-foreground">
          <Mail className="mr-2 h-4 w-4" />
          <a href={`mailto:${contact.email}`} className="hover:text-primary transition-colors">
            {contact.email}
          </a>
        </div>
      )}
      {contact.phone && (
        <div className="flex items-center text-sm text-muted-foreground">
          <Phone className="mr-2 h-4 w-4" />
          <a href={`tel:${contact.phone}`} className="hover:text-primary transition-colors">
            {contact.phone}
          </a>
        </div>
      )}
      {contact.birthday && (
        <div className="flex items-center text-sm text-muted-foreground">
          <Cake className="mr-2 h-4 w-4" />
          {format(new Date(contact.birthday), "PPP")}
        </div>
      )}
      {contact.notes && (
        <p className="text-sm text-muted-foreground">{contact.notes}</p>
      )}
    </div>
  );
}

interface GraphNode {
  id: number;
  name: string;
  relationshipType?: string;
  isMe?: boolean;
  color: string;
  // Required by force-graph
  x?: number;
  y?: number;
  vx?: number;
  vy?: number;
}

interface GraphLink {
  source: GraphNode;
  target: GraphNode;
  type: string;
}

interface GraphData {
  nodes: GraphNode[];
  links: GraphLink[];
}

export function ContactGraph() {
  const containerRef = useRef<HTMLDivElement>(null);
  const graphRef = useRef<ForceGraphMethods<GraphNode, GraphLink>>(null);
  const [selectedContact, setSelectedContact] = useState<Contact | null>(null);
  const [dimensions, setDimensions] = useState({ width: 800, height: 600 });
  const [graphData, setGraphData] = useState<GraphData>({ nodes: [], links: [] });

  const { data: contacts, isLoading, error } = useQuery<Contact[]>({
    queryKey: ["/api/contacts"],
  });

  // Update dimensions on resize
  useEffect(() => {
    const updateDimensions = () => {
      if (containerRef.current) {
        const { offsetWidth, offsetHeight } = containerRef.current;
        console.log('Updating dimensions:', { width: offsetWidth, height: offsetHeight });
        setDimensions({
          width: offsetWidth,
          height: offsetHeight
        });
      }
    };

    window.addEventListener('resize', updateDimensions);
    updateDimensions();

    return () => window.removeEventListener('resize', updateDimensions);
  }, []);

  // Transform contacts data into graph format
  useEffect(() => {
    if (!contacts?.length) return;

    try {
      console.log('Processing contacts for graph:', contacts.length, 'contacts');
      const meContact = contacts.find(c => c.isMe);
      console.log('Found personal contact:', meContact);

      // Get color based on relationship type
      const getNodeColor = (contact: Contact): string => {
        if (contact.isMe) return "#6366f1"; // Indigo for personal contact
        if (!contact.relationshipType) return "#94a3b8"; // Slate for undefined

        const categories = {
          family: ["mother", "father", "brother", "sibling", "child", "spouse"],
          friends: ["friend", "boyfriend/girlfriend"],
          professional: ["co-worker"]
        };

        if (categories.family.includes(contact.relationshipType)) return "#22c55e";
        if (categories.friends.includes(contact.relationshipType)) return "#f97316";
        if (categories.professional.includes(contact.relationshipType)) return "#3b82f6";
        return "#94a3b8";
      };

      // Create nodes first
      const nodes: GraphNode[] = contacts.map(contact => ({
        id: contact.id,
        name: contact.name,
        relationshipType: contact.relationshipType,
        isMe: contact.isMe,
        color: getNodeColor(contact)
      }));

      console.log('Created nodes:', nodes);

      // Then create links using the nodes
      const links: GraphLink[] = [];

      // First, handle explicit parent-child relationships
      contacts.forEach(contact => {
        if (!contact.parentId) return;

        const sourceNode = nodes.find(n => n.id === contact.parentId);
        const targetNode = nodes.find(n => n.id === contact.id);

        if (!sourceNode || !targetNode) {
          console.warn('Missing nodes for parent-child link:', { contactId: contact.id, parentId: contact.parentId });
          return;
        }

        links.push({
          source: sourceNode,
          target: targetNode,
          type: contact.relationshipType || "undefined"
        });
      });

      // Then, handle root-level relationships with personal contact
      if (meContact) {
        contacts.forEach(contact => {
          if (contact.id === meContact.id || contact.parentId) return; // Skip self and children

          const meNode = nodes.find(n => n.id === meContact.id);
          const contactNode = nodes.find(n => n.id === contact.id);

          if (!meNode || !contactNode) {
            console.warn('Missing nodes for personal contact link:', { contactId: contact.id });
            return;
          }

          links.push({
            source: meNode,
            target: contactNode,
            type: contact.relationshipType || "undefined"
          });
        });
      }

      console.log('Created links:', links);

      setGraphData({ nodes, links });
    } catch (error) {
      console.error('Error processing graph data:', error);
    }
  }, [contacts]);

  // Handle node click
  const handleNodeClick = useCallback((node: GraphNode | undefined) => {
    if (!contacts || !node) {
      console.log('Node click: Invalid node or no contacts available');
      return;
    }

    console.log('Node clicked:', node);
    const contact = contacts.find(c => c.id === node.id);

    if (contact) {
      console.log('Selected contact:', contact);
      setSelectedContact(prev => prev?.id === contact.id ? null : contact);
    } else {
      console.warn('Could not find contact for node:', node);
    }
  }, [contacts]);

  if (error) {
    return (
      <div className="p-4 text-center text-destructive">
        Error loading contacts: {error instanceof Error ? error.message : "Unknown error"}
      </div>
    );
  }

  if (isLoading) {
    return (
      <div className="p-4 text-center text-muted-foreground">
        Loading contacts...
      </div>
    );
  }

  return (
    <div 
      ref={containerRef} 
      className="relative w-full h-[calc(100vh-12rem)] bg-card rounded-lg border overflow-hidden"
    >
      {/* Selected Contact Details */}
      {selectedContact && (
        <Card className="absolute top-4 left-4 w-80 p-4 bg-card/95 backdrop-blur-sm z-10">
          <div className="space-y-4">
            <div className="flex items-center gap-2">
              <h3 className="font-semibold">{selectedContact.name}</h3>
              {selectedContact.relationshipType && (
                <Badge variant="outline" className="capitalize">
                  {selectedContact.relationshipType.replace("-", " ")}
                </Badge>
              )}
            </div>
            <ContactDetails contact={selectedContact} />
          </div>
        </Card>
      )}

      {/* Graph Legend */}
      <Card className="absolute top-4 right-4 p-4 bg-card/95 backdrop-blur-sm z-10">
        <h3 className="font-semibold mb-2">Categories</h3>
        <div className="space-y-2">
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 rounded-full" style={{ backgroundColor: "#22c55e" }} />
            <span className="text-sm">Family</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 rounded-full" style={{ backgroundColor: "#f97316" }} />
            <span className="text-sm">Friends</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 rounded-full" style={{ backgroundColor: "#3b82f6" }} />
            <span className="text-sm">Professional</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-3 h-3 rounded-full" style={{ backgroundColor: "#6366f1" }} />
            <span className="text-sm">Personal Card</span>
          </div>
        </div>
      </Card>

      {/* Force Graph */}
      <ForceGraph2D
        ref={graphRef}
        graphData={graphData}
        nodeLabel={node => (node as GraphNode).name}
        nodeColor={node => (node as GraphNode).color}
        nodeCanvasObject={(node, ctx, globalScale) => {
          const n = node as GraphNode;
          const label = n.name;
          const fontSize = 12/globalScale;
          ctx.font = `${fontSize}px Sans-Serif`;
          ctx.textAlign = 'center';
          ctx.textBaseline = 'middle';
          ctx.fillStyle = n.color;

          // Draw node circle
          ctx.beginPath();
          ctx.arc(node.x!, node.y!, 5, 0, 2 * Math.PI);
          ctx.fill();

          // Draw text
          ctx.fillStyle = '#64748b';
          ctx.fillText(label, node.x!, node.y! + 10);
        }}
        nodeRelSize={8}
        linkDirectionalParticles={2}
        linkDirectionalParticleSpeed={0.005}
        linkColor={() => "#94a3b8"}
        backgroundColor="transparent"
        onNodeClick={handleNodeClick}
        width={dimensions.width}
        height={dimensions.height}
        d3AlphaDecay={0.02}
        d3VelocityDecay={0.3}
        cooldownTicks={100}
        onEngineStop={() => {
          if (graphRef.current) {
            graphRef.current.zoomToFit(400);
          }
        }}
      />
    </div>
  );
}