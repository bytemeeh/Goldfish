import { useState, useCallback, useEffect, useRef } from "react";
import { useQuery } from "@tanstack/react-query";
import { type Contact } from "@/lib/types";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Mail, Phone, Cake } from "lucide-react";
import { format } from "date-fns";
import ForceGraph2D from "react-force-graph-2d";
import type { NodeObject, LinkObject } from "react-force-graph-2d";
import { motion, AnimatePresence } from "framer-motion";

// Helper function to convert CSS HSL variable to rgba
function hslToRgba(variable: string, alpha: number = 1): string {
  const div = document.createElement('div');
  div.style.color = `hsl(var(${variable}))`;
  document.body.appendChild(div);
  const color = window.getComputedStyle(div).color;
  document.body.removeChild(div);
  const rgb = color.match(/\d+/g)?.map(Number) || [0, 0, 0];
  return `rgba(${rgb[0]}, ${rgb[1]}, ${rgb[2]}, ${alpha})`;
}

// Ambient animation frame counter
let animationFrame = 0;

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

interface GraphNode extends NodeObject {
  id: number;
  name: string;
  relationshipType?: string;
  isMe?: boolean;
  color: string;
  pulsePhase?: number;
}

interface GraphLink extends LinkObject {
  source: GraphNode;
  target: GraphNode;
  type: string;
  particleSpeed?: number;
}

interface GraphData {
  nodes: GraphNode[];
  links: GraphLink[];
}

export function ContactGraph() {
  const containerRef = useRef<HTMLDivElement>(null);
  const graphRef = useRef<any>();
  const [selectedContact, setSelectedContact] = useState<Contact | null>(null);
  const [dimensions, setDimensions] = useState({ width: 800, height: 600 });
  const [graphData, setGraphData] = useState<GraphData>({ nodes: [], links: [] });

  const { data: contacts, isLoading, error } = useQuery<Contact[]>({
    queryKey: ["/api/contacts"],
  });

  useEffect(() => {
    const updateDimensions = () => {
      if (containerRef.current) {
        const { offsetWidth, offsetHeight } = containerRef.current;
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

  useEffect(() => {
    if (!contacts?.length) return;

    try {
      const meContact = contacts.find(c => c.isMe);

      // Get color based on relationship type
      const getNodeColor = (contact: Contact): string => {
        if (contact.isMe) return hslToRgba('--primary');
        if (!contact.relationshipType) return hslToRgba('--muted');

        const categories = {
          family: ["mother", "father", "brother", "sibling", "child", "spouse"],
          friends: ["friend", "boyfriend/girlfriend"],
          professional: ["co-worker"]
        };

        if (categories.family.includes(contact.relationshipType)) return hslToRgba('--chart-1');
        if (categories.friends.includes(contact.relationshipType)) return hslToRgba('--chart-2');
        if (categories.professional.includes(contact.relationshipType)) return hslToRgba('--chart-3');
        return hslToRgba('--muted');
      };

      const nodes: GraphNode[] = contacts.map(contact => ({
        id: contact.id,
        name: contact.name,
        relationshipType: contact.relationshipType,
        isMe: contact.isMe,
        color: getNodeColor(contact),
        pulsePhase: Math.random() * Math.PI * 2,
        x: 0,
        y: 0,
        vx: 0,
        vy: 0
      }));

      const links: GraphLink[] = [];

      contacts.forEach(contact => {
        if (!contact.parentId) return;

        const sourceNode = nodes.find(n => n.id === contact.parentId);
        const targetNode = nodes.find(n => n.id === contact.id);

        if (sourceNode && targetNode) {
          links.push({
            source: sourceNode,
            target: targetNode,
            type: contact.relationshipType || "undefined",
            particleSpeed: 0.002 + Math.random() * 0.003
          });
        }
      });

      if (meContact) {
        contacts.forEach(contact => {
          if (contact.id === meContact.id || contact.parentId) return;

          const meNode = nodes.find(n => n.id === meContact.id);
          const contactNode = nodes.find(n => n.id === contact.id);

          if (meNode && contactNode) {
            links.push({
              source: meNode,
              target: contactNode,
              type: contact.relationshipType || "undefined",
              particleSpeed: 0.002 + Math.random() * 0.003
            });
          }
        });
      }

      setGraphData({ nodes, links });

      if (graphRef.current) {
        setTimeout(() => {
          graphRef.current?.zoomToFit(400, 50);
        }, 500);
      }
    } catch (error) {
      console.error('Error processing graph data:', error);
    }
  }, [contacts]);

  const handleNodeClick = useCallback((node: GraphNode | null) => {
    if (!contacts || !node) return;
    const contact = contacts.find(c => c.id === node.id);
    if (contact) {
      setSelectedContact(prev => prev?.id === contact.id ? null : contact);
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
      className="relative w-full h-[calc(100vh-12rem)] bg-card rounded-lg border shadow-sm overflow-hidden"
    >
      <AnimatePresence>
        {selectedContact && (
          <motion.div
            initial={{ opacity: 0, x: -20 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: -20 }}
            transition={{ type: "spring", stiffness: 300, damping: 25 }}
          >
            <Card className="absolute top-4 left-4 w-80 p-4 bg-card/95 backdrop-blur-sm z-10 border-primary/10">
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
          </motion.div>
        )}
      </AnimatePresence>

      <motion.div
        initial={{ opacity: 0, y: -20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.2 }}
      >
        <Card className="absolute top-4 right-4 p-4 bg-card/95 backdrop-blur-sm z-10 border-primary/10">
          <h3 className="font-semibold mb-3 text-sm">Relationship Types</h3>
          <div className="space-y-2.5">
            {[
              { label: "Family", color: "--chart-1" },
              { label: "Friends", color: "--chart-2" },
              { label: "Professional", color: "--chart-3" },
              { label: "Personal Card", color: "--primary" }
            ].map(({ label, color }) => (
              <div key={label} className="flex items-center gap-2">
                <div 
                  className="w-3 h-3 rounded-full" 
                  style={{ backgroundColor: `hsl(var(${color}))` }}
                />
                <span className="text-sm text-muted-foreground">{label}</span>
              </div>
            ))}
          </div>
        </Card>
      </motion.div>

      <ForceGraph2D
        ref={graphRef}
        graphData={graphData}
        nodeLabel={node => node.name}
        nodeColor={node => node.color}
        nodeCanvasObject={(node, ctx, globalScale) => {
          const label = node.name;
          const fontSize = Math.max(14/globalScale, 8);
          const nodeSize = node.isMe ? 8 : 6;

          ctx.font = `${fontSize}px -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif`;
          ctx.textAlign = 'center';
          ctx.textBaseline = 'middle';

          // Calculate pulse effect
          const pulseNode = node as GraphNode;
          const pulsePhase = pulseNode.pulsePhase || 0;
          const pulseIntensity = Math.sin(animationFrame * 0.02 + pulsePhase) * 0.2 + 0.8;

          // Draw ambient glow
          const gradient = ctx.createRadialGradient(node.x!, node.y!, 0, node.x!, node.y!, nodeSize * 3);
          const glowColor = (node as GraphNode).color;
          gradient.addColorStop(0, glowColor.replace('1)', `${0.4 * pulseIntensity})`));
          gradient.addColorStop(0.5, glowColor.replace('1)', `${0.2 * pulseIntensity})`));
          gradient.addColorStop(1, 'transparent');
          ctx.fillStyle = gradient;
          ctx.beginPath();
          ctx.arc(node.x!, node.y!, nodeSize * 3, 0, 2 * Math.PI);
          ctx.fill();

          // Draw node
          ctx.shadowColor = 'rgba(0, 0, 0, 0.15)';
          ctx.shadowBlur = 8 * pulseIntensity;
          ctx.shadowOffsetY = 2;
          ctx.fillStyle = (node as GraphNode).color;
          ctx.beginPath();
          ctx.arc(node.x!, node.y!, nodeSize * pulseIntensity, 0, 2 * Math.PI);
          ctx.fill();

          // Reset shadow for text
          ctx.shadowColor = 'transparent';

          // Draw text with frosted glass effect background
          const textWidth = ctx.measureText(label).width;
          const bgHeight = fontSize * 1.5;
          const bgWidth = textWidth + 16;
          const bgY = node.y! + nodeSize * 2;

          ctx.fillStyle = 'rgba(255, 255, 255, 0.85)';
          ctx.shadowColor = 'rgba(0, 0, 0, 0.1)';
          ctx.shadowBlur = 4;
          ctx.beginPath();
          ctx.roundRect(node.x! - bgWidth/2, bgY - bgHeight/2, bgWidth, bgHeight, 4);
          ctx.fill();

          ctx.shadowColor = 'transparent';
          ctx.fillStyle = 'hsl(var(--foreground))';
          ctx.fillText(label, node.x!, bgY);

          // Update animation frame
          animationFrame++;
        }}
        linkColor={() => "rgba(0, 0, 0, 0.1)"}
        linkWidth={1}
        linkDirectionalParticles={6}
        linkDirectionalParticleWidth={2}
        linkDirectionalParticleSpeed={d => (d as GraphLink).particleSpeed || 0.003}
        linkDirectionalParticleColor={() => {
          const phase = Math.sin(animationFrame * 0.02) * 0.2 + 0.8;
          return hslToRgba('--primary', 0.3 * phase);
        }}
        backgroundColor="transparent"
        onNodeClick={handleNodeClick}
        width={dimensions.width}
        height={dimensions.height}
        d3AlphaDecay={0.01}
        d3VelocityDecay={0.4}
        cooldownTicks={100}
        onEngineStop={() => {
          if (graphRef.current) {
            graphRef.current.zoomToFit(400, 50);
          }
        }}
      />
    </div>
  );
}