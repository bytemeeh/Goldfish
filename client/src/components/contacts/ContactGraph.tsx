import { useState, useCallback, useEffect, useRef } from "react";
import { useQuery } from "@tanstack/react-query";
import { type Contact } from "@/lib/types";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Mail, Phone, Cake, MapPin } from "lucide-react";
import { format } from "date-fns";
import ForceGraph2D from "react-force-graph-2d";
import type { NodeObject, LinkObject } from "react-force-graph-2d";
import { motion, AnimatePresence } from "framer-motion";

// Color palette configuration for Apple-style design
const colorPalette = {
  family: {
    primary: "hsl(195, 100%, 45%)",  // Cyan Blue
    gradient: ["1, 0.5", "0.8, 0.3", "0.6, 0.15"]
  },
  friends: {
    primary: "hsl(330, 100%, 50%)",  // Bright Pink
    gradient: ["1, 0.5", "0.8, 0.3", "0.6, 0.15"]
  },
  professional: {
    primary: "hsl(30, 100%, 50%)",   // Orange
    gradient: ["1, 0.5", "0.8, 0.3", "0.6, 0.15"]
  },
  personal: {
    primary: "hsl(145, 100%, 35%)",  // Green
    gradient: ["1, 0.55", "0.8, 0.35", "0.6, 0.2"]
  },
  default: {
    primary: "hsl(215, 16%, 47%)",
    gradient: ["1, 0.4", "0.8, 0.25", "0.6, 0.1"]
  }
};

// Helper function to convert HSL to RGB
function hslToRgb(hslString: string, opacity: number = 1): string {
  // Create temporary element to convert HSL to RGB
  const temp = document.createElement('div');
  temp.style.color = hslString;
  document.body.appendChild(temp);
  const rgb = getComputedStyle(temp).color;
  document.body.removeChild(temp);

  // Extract RGB values
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
      {(contact.street || contact.city || contact.state || contact.country) && (
        <div className="flex items-start text-sm text-muted-foreground">
          <MapPin className="mr-2 h-4 w-4 mt-0.5 flex-shrink-0" />
          <div>
            {contact.street && <div>{contact.street}</div>}
            <div>
              {[contact.city, contact.state, contact.postalCode]
                .filter(Boolean)
                .join(", ")}
            </div>
            {contact.country && <div>{contact.country}</div>}
          </div>
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
  gradientColors: string[];
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

interface ContactGraphProps {
  onContactSelect?: (contactId: number) => void;
}

export function ContactGraph({ onContactSelect }: ContactGraphProps) {
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

      const getNodeStyle = (contact: Contact): { color: string, gradientColors: string[] } => {
        let palette;

        if (contact.isMe) {
          palette = colorPalette.personal;
        } else if (!contact.relationshipType) {
          palette = colorPalette.default;
        } else {
          const categories = {
            family: ["mother", "father", "brother", "sibling", "child", "spouse"],
            friends: ["friend", "boyfriend/girlfriend"],
            professional: ["co-worker"]
          };

          if (categories.family.includes(contact.relationshipType)) {
            palette = colorPalette.family;
          } else if (categories.friends.includes(contact.relationshipType)) {
            palette = colorPalette.friends;
          } else if (categories.professional.includes(contact.relationshipType)) {
            palette = colorPalette.professional;
          } else {
            palette = colorPalette.default;
          }
        }

        return {
          color: palette.primary,
          gradientColors: palette.gradient.map(g => {
            const [_, opacity] = g.split(', ');
            return hslToRgb(palette.primary, parseFloat(opacity));
          })
        };
      };

      const nodes: GraphNode[] = contacts.map(contact => {
        const style = getNodeStyle(contact);
        return {
          id: contact.id,
          name: contact.name,
          relationshipType: contact.relationshipType,
          isMe: contact.isMe,
          color: style.color,
          gradientColors: style.gradientColors,
          x: Math.random() * 100,
          y: Math.random() * 100,
          vx: 0,
          vy: 0,
          // Use undefined instead of null for TypeScript compatibility
          fx: undefined,
          fy: undefined
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

  // Enhanced node click handler with better node ID extraction
  const handleNodeClick = useCallback((node: any) => {
    console.log('🚨 Node clicked:', node);
    
    try {
      if (!contacts) {
        console.log('❌ No contacts available');
        return;
      }
      
      if (!node) {
        console.log('❌ Node is null');
        return;
      }
      
      // Extract node ID from various possible structures
      // based on react-force-graph implementation details
      let nodeId: number | undefined;
      
      if (typeof node.id === 'number') {
        // Direct ID from the node
        nodeId = node.id;
        console.log('📌 Using direct node.id:', nodeId);
      } else if (node.__data__ && typeof node.__data__.id === 'number') {
        // ID from internal data structure
        nodeId = node.__data__.id;
        console.log('📌 Using node.__data__.id:', nodeId);
      } else if (node.id && typeof node.id._value === 'number') {
        // ID might be wrapped in an observable
        nodeId = node.id._value;
        console.log('📌 Using observable node.id._value:', nodeId);
      } else {
        // Try to extract ID as string and convert to number
        const strId = String(node.id || node.__data__?.id || '');
        if (strId && !isNaN(parseInt(strId, 10))) {
          nodeId = parseInt(strId, 10);
          console.log('📌 Converted string ID to number:', nodeId);
        } else {
          console.log('❌ Could not find valid node ID in any format', node);
          return;
        }
      }
      
      // Find the contact based on the extracted ID
      const contactMatch = contacts.find(c => c.id === nodeId);
      console.log('💾 Contact match result:', contactMatch ? contactMatch.name : 'Not found');
      
      if (contactMatch) {
        console.log('✅ Setting selected contact:', contactMatch.name, 'ID:', contactMatch.id);
        
        // Update local state
        setSelectedContact(contactMatch);
        
        // Navigate to list view if handler exists
        if (typeof onContactSelect === 'function') {
          console.log('🔄 Calling onContactSelect with ID:', contactMatch.id);
          // Use setTimeout to ensure this happens outside of this render cycle
          setTimeout(() => {
            onContactSelect(contactMatch.id);
          }, 0);
        } else {
          console.log('❌ onContactSelect prop is not provided');
        }
      } else {
        console.log('❌ Could not find contact with ID:', nodeId);
        console.log('❌ Available contact IDs:', contacts.map(c => c.id));
      }
    } catch (error) {
      console.error('❌ Error in handleNodeClick:', error);
    }
  }, [contacts, onContactSelect]);

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
              { label: "Family", color: colorPalette.family.primary },
              { label: "Friends", color: colorPalette.friends.primary },
              { label: "Professional", color: colorPalette.professional.primary },
              { label: "Personal Card", color: colorPalette.personal.primary }
            ].map(({ label, color }) => (
              <div key={label} className="flex items-center gap-2">
                <div 
                  className="w-3 h-3 rounded-full" 
                  style={{ backgroundColor: hslToRgb(color) }}
                />
                <span className="text-sm text-muted-foreground">{label}</span>
              </div>
            ))}
          </div>
        </Card>
      </motion.div>

      {/* @ts-ignore ForceGraph2D has typings issues but works as expected */}
      <ForceGraph2D
        ref={graphRef}
        graphData={graphData}
        nodeLabel={node => node.name}
        nodeAutoColorBy="relationshipType"
        warmupTicks={100}
        cooldownTime={3000}
        nodeCanvasObject={(node: GraphNode, ctx, globalScale) => {
          // Remove any fixed positions without changing type
          if (node.fx !== undefined) node.fx = undefined;
          if (node.fy !== undefined) node.fy = undefined;
          const label = node.name;
          const fontSize = Math.max(12/globalScale, 6); //Reduced font size
          const nodeSize = node.isMe ? 8 : 6;

          ctx.font = `${fontSize}px -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif`;
          ctx.textAlign = 'center';
          ctx.textBaseline = 'middle';

          // Draw multi-layered glow effect with reduced intensity
          node.gradientColors.forEach((color, index) => {
            const radius = nodeSize * (2 - index * 0.5);
            const gradient = ctx.createRadialGradient(
              node.x!, node.y!, radius * 0.3,
              node.x!, node.y!, radius
            );
            // Better opacity management - brighter when hovered or selected
            const isSelectedNode = selectedContact && selectedContact.id === node.id;
            const baseOpacity = isSelectedNode ? 0.08 : 0.02;
            gradient.addColorStop(0, color.replace(/[\d.]+\)$/, `${baseOpacity})`));
            gradient.addColorStop(1, 'rgba(0, 0, 0, 0)');
            ctx.fillStyle = gradient;
            ctx.beginPath();
            ctx.arc(node.x!, node.y!, radius, 0, 2 * Math.PI);
            ctx.fill();
          });

          ctx.shadowColor = 'rgba(0, 0, 0, 0.02)';
          ctx.shadowBlur = 2;
          ctx.shadowOffsetY = 1;

          // Node base
          ctx.fillStyle = node.color;
          ctx.beginPath();
          ctx.arc(node.x!, node.y!, nodeSize, 0, 2 * Math.PI);
          ctx.fill();

          ctx.shadowColor = 'transparent';
          const highlightGradient = ctx.createLinearGradient(
            node.x!, node.y! - nodeSize,
            node.x!, node.y! + nodeSize
          );
          highlightGradient.addColorStop(0, 'rgba(255, 255, 255, 0.3)');
          highlightGradient.addColorStop(1, 'rgba(255, 255, 255, 0)');
          ctx.fillStyle = highlightGradient;
          ctx.beginPath();
          ctx.arc(node.x!, node.y!, nodeSize, 0, 2 * Math.PI);
          ctx.fill();

          // Determine if this node should show its label
          const isSelectedNode = selectedContact && selectedContact.id === node.id;
          // Safely check for hover state
          let isGraphNodeHovered = false;
          try {
            isGraphNodeHovered = !!(graphRef.current?.state && 
                               graphRef.current.state.hoverNode && 
                               graphRef.current.state.hoverNode.id === node.id);
          } catch (e) {
            // Ignore any errors from accessing hoverNode
          }
          const shouldShowFullLabel = isSelectedNode || isGraphNodeHovered || globalScale > 1.5;

          if (shouldShowFullLabel) {
            // Full label display with background for highlighted nodes
            const textWidth = ctx.measureText(label).width;
            const bgHeight = fontSize * 1.8;
            const bgWidth = textWidth + 24;
            const bgY = node.y! + nodeSize * 3;

            // Enhanced background with animation effect
            ctx.fillStyle = 'rgba(255, 255, 255, 0.95)';
            ctx.shadowColor = 'rgba(0, 0, 0, 0.12)';
            ctx.shadowBlur = 8;
            ctx.beginPath();
            ctx.roundRect(node.x! - bgWidth/2, bgY - bgHeight/2, bgWidth, bgHeight, 6);
            ctx.fill();

            // Text with better contrast
            ctx.shadowColor = 'transparent';
            ctx.fillStyle = "hsl(240, 10%, 15%)";
            ctx.font = `500 ${fontSize}px -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif`;
            ctx.fillText(label, node.x!, bgY);
          } else if (label.length > 0) {
            // Simplified mini-label for non-highlighted nodes (just initials)
            const initials = label.split(' ').map(word => word[0]).join('').substring(0, 2).toUpperCase();
            const miniLabelY = node.y! + nodeSize * 2;
            
            ctx.fillStyle = 'rgba(255, 255, 255, 0.8)';
            ctx.shadowColor = 'rgba(0, 0, 0, 0.1)';
            ctx.shadowBlur = 4;
            ctx.beginPath();
            ctx.arc(node.x!, miniLabelY, fontSize/2 + 2, 0, 2 * Math.PI);
            ctx.fill();
            
            ctx.shadowColor = 'transparent';
            ctx.fillStyle = "hsl(240, 10%, 25%)";
            ctx.font = `500 ${fontSize * 0.8}px -apple-system, sans-serif`;
            ctx.fillText(initials, node.x!, miniLabelY + fontSize * 0.25);
          }
        }}
        linkColor={() => "rgba(0, 0, 0, 0.08)"}
        linkWidth={1.5}
        linkDirectionalParticles={3}
        linkDirectionalParticleWidth={1.5}
        linkDirectionalParticleSpeed={0.002}
        linkDirectionalParticleColor={() => "rgba(0, 0, 0, 0.15)"}
        d3VelocityDecay={0.4}
        d3AlphaMin={0.05}
        cooldownTicks={100}
        nodeRelSize={6}
        //@ts-ignore - d3Force property exists but has type issues
      d3Force={(d3: any) => {
          const simulation = d3;
          
          simulation.forceCenter(dimensions.width / 2, dimensions.height / 2)
            .strength(0.05);

          simulation.forceManyBody()
            .strength(-1000);

          simulation.forceLink()
            .id((d: any) => d.id)
            .distance(100);

          const forceX = simulation.forceX((d: any) => {
            if (!d.relationshipType) return dimensions.width / 2;
            const types = {
              'spouse': -200,
              'child': 0,
              'friend': 200,
              'co-worker': 400,
              'mother': -300,
              'father': -300,
              'brother': -100,
              'sibling': -100,
              'boyfriend/girlfriend': 300
            };
            return (dimensions.width / 2) + (types[d.relationshipType as keyof typeof types] || 0);
          }).strength(0.5);

          const forceY = simulation.forceY((d: any) => {
            if (!d.relationshipType) return dimensions.height / 2;
            const types = {
              'spouse': -100,
              'child': 200,
              'friend': -100,
              'co-worker': 100,
              'mother': -200,
              'father': -200,
              'brother': 0,
              'sibling': 0,
              'boyfriend/girlfriend': 0
            };
            return (dimensions.height / 2) + (types[d.relationshipType as keyof typeof types] || 0);
          }).strength(0.3);

          return simulation;
        }}
        backgroundColor="transparent"
        onNodeClick={handleNodeClick}
        width={dimensions.width}
        height={dimensions.height}
        d3AlphaDecay={0.01}
        onEngineStop={() => {
          if (graphRef.current) {
            graphRef.current.zoomToFit(400, 50);
          }
        }}
      />
    </div>
  );
}