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

// Helper function to get computed RGB color from CSS variable
function getRGBColor(variable: string, opacity: number = 1): string {
  const root = document.documentElement;
  const computedStyle = getComputedStyle(root);
  const hsl = computedStyle.getPropertyValue(variable).trim();

  // Create temporary element to convert HSL to RGB
  const temp = document.createElement('div');
  temp.style.color = `hsl(${hsl})`;
  document.body.appendChild(temp);
  const rgb = getComputedStyle(temp).color;
  document.body.removeChild(temp);

  // Extract RGB values and return with opacity
  const [r, g, b] = rgb.match(/\d+/g)?.map(Number) || [0, 0, 0];
  return `rgba(${r}, ${g}, ${b}, ${opacity})`;
}

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
        <p className="text-sm text-muted-foreground mt-2">{contact.notes}</p>
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
  ringColor?: string;
}

interface GraphLink extends LinkObject {
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
  const graphRef = useRef<any>(null);
  const [selectedContact, setSelectedContact] = useState<Contact | null>(null);
  const [dimensions, setDimensions] = useState({ width: 800, height: 600 });
  const [graphData, setGraphData] = useState<GraphData>({ nodes: [], links: [] });

  const { data: contacts } = useQuery<Contact[]>({
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

      const getNodeColors = (contact: Contact): { color: string, ringColor?: string } => {
        if (contact.isMe) {
          return {
            color: getRGBColor('--primary'),
            ringColor: getRGBColor('--primary', 0.3)
          };
        }

        if (!contact.relationshipType) {
          return {
            color: getRGBColor('--muted'),
            ringColor: getRGBColor('--muted', 0.3)
          };
        }

        const categories = {
          family: ["mother", "father", "brother", "sibling", "child", "spouse"],
          friends: ["friend", "boyfriend/girlfriend"],
          professional: ["co-worker"]
        };

        if (categories.family.includes(contact.relationshipType)) {
          return {
            color: getRGBColor('--chart-1'),
            ringColor: getRGBColor('--chart-1', 0.3)
          };
        }
        if (categories.friends.includes(contact.relationshipType)) {
          return {
            color: getRGBColor('--chart-2'),
            ringColor: getRGBColor('--chart-2', 0.3)
          };
        }
        if (categories.professional.includes(contact.relationshipType)) {
          return {
            color: getRGBColor('--chart-3'),
            ringColor: getRGBColor('--chart-3', 0.3)
          };
        }

        return {
          color: getRGBColor('--muted'),
          ringColor: getRGBColor('--muted', 0.3)
        };
      };

      const nodes: GraphNode[] = contacts.map(contact => {
        const colors = getNodeColors(contact);
        return {
          id: contact.id,
          name: contact.name,
          relationshipType: contact.relationshipType,
          isMe: contact.isMe,
          color: colors.color,
          ringColor: colors.ringColor,
          x: Math.random() * 100,
          y: Math.random() * 100,
          vx: 0,
          vy: 0
        };
      });

      const links: GraphLink[] = [];

      contacts.forEach(contact => {
        if (!contact.parentId) return;

        const sourceNode = nodes.find(n => n.id === contact.parentId);
        const targetNode = nodes.find(n => n.id === contact.id);

        if (sourceNode && targetNode) {
          links.push({
            source: sourceNode,
            target: targetNode,
            type: contact.relationshipType || "undefined"
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
              type: contact.relationshipType || "undefined"
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

  if (!contacts) {
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
                  style={{ backgroundColor: getRGBColor(color) }}
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
        nodeCanvasObject={(node: GraphNode, ctx, globalScale) => {
          const label = node.name;
          const fontSize = Math.max(14/globalScale, 8);
          const nodeSize = node.isMe ? 8 : 6;

          ctx.font = `${fontSize}px -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif`;
          ctx.textAlign = 'center';
          ctx.textBaseline = 'middle';

          // Draw outer glow
          if (node.ringColor) {
            const gradient = ctx.createRadialGradient(
              node.x!, node.y!, nodeSize * 0.5,
              node.x!, node.y!, nodeSize * 2
            );
            gradient.addColorStop(0, node.ringColor);
            gradient.addColorStop(1, 'rgba(0, 0, 0, 0)');
            ctx.fillStyle = gradient;
            ctx.beginPath();
            ctx.arc(node.x!, node.y!, nodeSize * 2, 0, 2 * Math.PI);
            ctx.fill();
          }

          // Draw node shadow
          ctx.shadowColor = 'rgba(0, 0, 0, 0.2)';
          ctx.shadowBlur = 5;
          ctx.shadowOffsetY = 2;

          // Draw node
          ctx.fillStyle = node.color;
          ctx.beginPath();
          ctx.arc(node.x!, node.y!, nodeSize, 0, 2 * Math.PI);
          ctx.fill();

          // Draw highlight
          ctx.shadowColor = 'transparent';
          const highlightGradient = ctx.createLinearGradient(
            node.x!, node.y! - nodeSize,
            node.x!, node.y! + nodeSize
          );
          highlightGradient.addColorStop(0, 'rgba(255, 255, 255, 0.2)');
          highlightGradient.addColorStop(1, 'rgba(255, 255, 255, 0)');
          ctx.fillStyle = highlightGradient;
          ctx.beginPath();
          ctx.arc(node.x!, node.y!, nodeSize, 0, 2 * Math.PI);
          ctx.fill();

          // Draw text background
          const textWidth = ctx.measureText(label).width;
          const bgHeight = fontSize * 1.5;
          const bgWidth = textWidth + 16;
          const bgY = node.y! + nodeSize * 2;

          ctx.fillStyle = 'rgba(255, 255, 255, 0.9)';
          ctx.shadowColor = 'rgba(0, 0, 0, 0.1)';
          ctx.shadowBlur = 4;
          ctx.beginPath();
          ctx.roundRect(node.x! - bgWidth/2, bgY - bgHeight/2, bgWidth, bgHeight, 4);
          ctx.fill();

          // Draw text
          ctx.shadowColor = 'transparent';
          ctx.fillStyle = getRGBColor('--foreground');
          ctx.fillText(label, node.x!, bgY);
        }}
        linkColor={() => getRGBColor('--border', 0.15)}
        linkWidth={1}
        linkDirectionalParticles={4}
        linkDirectionalParticleWidth={2}
        linkDirectionalParticleSpeed={0.003}
        linkDirectionalParticleColor={() => getRGBColor('--primary', 0.3)}
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