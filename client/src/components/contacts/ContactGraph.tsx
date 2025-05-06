import { useQuery } from "@tanstack/react-query";
import { useRef, useState, useEffect, useCallback } from "react";
import ForceGraph2D from "react-force-graph-2d";
import { NodeObject, LinkObject } from "react-force-graph-2d";
import { Contact } from "@/lib/types";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { motion, AnimatePresence } from "framer-motion";

// Convert HSL string to RGB for gradients
function hslToRgb(hslString: string, opacity: number = 1): string {
  // Parse the HSL values from the string
  const match = hslString.match(/hsl\(var\(--(.+)\)\)/);
  if (!match) return `rgba(100, 100, 100, ${opacity})`;
  
  // For simplicity, we'll map specific color variables to RGB values
  const colorMap: Record<string, string> = {
    "chart-1": "rgba(83, 100, 233, $opacity)",
    "chart-2": "rgba(233, 100, 133, $opacity)",
    "chart-3": "rgba(100, 183, 233, $opacity)",
    "chart-4": "rgba(233, 193, 100, $opacity)",
    "chart-5": "rgba(143, 233, 100, $opacity)",
    "primary": "rgba(100, 120, 233, $opacity)",
    // Add more mappings as needed
  };
  
  const color = match[1];
  return (colorMap[color] || `rgba(100, 100, 100, ${opacity})`).replace("$opacity", opacity.toString());
}

const colorPalette = {
  family: {
    primary: "hsl(var(--chart-1))",
    secondary: "hsl(var(--chart-1) / 0.8)",
  },
  friends: {
    primary: "hsl(var(--chart-2))",
    secondary: "hsl(var(--chart-2) / 0.8)",
  },
  professional: {
    primary: "hsl(var(--chart-3))",
    secondary: "hsl(var(--chart-3) / 0.8)",
  },
  personal: {
    primary: "hsl(var(--chart-4))",
    secondary: "hsl(var(--chart-4) / 0.8)",
  },
  default: {
    primary: "hsl(var(--chart-5))",
    secondary: "hsl(var(--chart-5) / 0.8)",
  }
};

function ContactDetails({ contact }: { contact: Contact }) {
  return (
    <div className="space-y-2 text-sm text-muted-foreground">
      {contact.email && (
        <div>
          <span className="font-medium">Email:</span> {contact.email}
        </div>
      )}
      {contact.phone && (
        <div>
          <span className="font-medium">Phone:</span> {contact.phone}
        </div>
      )}
      {contact.birthday && (
        <div>
          <span className="font-medium">Birthday:</span> {new Date(contact.birthday).toLocaleDateString()}
        </div>
      )}
      {contact.notes && (
        <div>
          <span className="font-medium">Notes:</span> {contact.notes}
        </div>
      )}
      {contact.locations && contact.locations.length > 0 && (
        <div>
          <span className="font-medium">Locations:</span>
          <ul className="mt-1 space-y-1">
            {contact.locations.map((location, index) => (
              <li key={index} className="pl-2 text-xs">
                {location.name || location.address || "Unnamed location"}
              </li>
            ))}
          </ul>
        </div>
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
          gradientColors: [
            hslToRgb(palette.primary, 0.2),
            hslToRgb(palette.secondary, 0.1)
          ]
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
    } catch (error) {
      console.error('Error building graph data:', error);
    }
  }, [contacts]);

  // New handleNodeClick implementation focusing on name-based matching
  const handleNodeClick = useCallback((node: any) => {
    console.log('🚨 Graph: Node clicked:', node);
    
    if (!contacts || !contacts.length) {
      console.log('❌ No contacts available');
      return;
    }
    
    if (!node) {
      console.log('❌ Node is null');
      return;
    }
    
    try {
      // Print all properties for debugging
      console.log('🔍 Node object properties:');
      for (const prop in node) {
        try {
          console.log(`  - ${prop}: ${typeof node[prop] === 'object' ? 'Object' : node[prop]}`);
        } catch (err) {
          console.log(`  - ${prop}: [Cannot display]`);
        }
      }
      
      // Extract node info - focus on both ID and name
      let nodeId: number | undefined;
      let nodeName: string = '';
      
      // ID extraction
      if (typeof node.id === 'number') {
        nodeId = node.id;
      } else if (node.__data__ && typeof node.__data__.id === 'number') {
        nodeId = node.__data__.id;
      }
      
      // Name extraction
      if (typeof node.name === 'string') {
        nodeName = node.name.toLowerCase();
      } else if (node.__data__ && typeof node.__data__.name === 'string') {
        nodeName = node.__data__.name.toLowerCase();
      }
      
      console.log('🔍 Extracted node info:', { nodeId, nodeName });
      
      // Find matching contact - prioritize ID, then fall back to name
      let targetContact: Contact | undefined;
      
      // 1. Try direct ID match
      if (nodeId !== undefined) {
        targetContact = contacts.find(c => c.id === nodeId);
        if (targetContact) {
          console.log('✅ Found contact by ID:', targetContact.id, targetContact.name);
        }
      }
      
      // 2. Try special contact names that were known to work
      if (!targetContact && nodeName) {
        const specialNames = ['christoph', 'angelina', 'test'];
        const isSpecial = specialNames.includes(nodeName);
        
        if (isSpecial) {
          targetContact = contacts.find(c => 
            c.name.toLowerCase() === nodeName
          );
          
          if (targetContact) {
            console.log('✅ Found special contact by name:', targetContact.id, targetContact.name);
          }
        }
      }
      
      // 3. Try exact name match for any contact
      if (!targetContact && nodeName) {
        targetContact = contacts.find(c => 
          c.name.toLowerCase() === nodeName
        );
        
        if (targetContact) {
          console.log('✅ Found contact by exact name match:', targetContact.id, targetContact.name);
        }
      }
      
      // 4. Try fuzzy name matching as last resort
      if (!targetContact && nodeName) {
        for (const contact of contacts) {
          const contactName = contact.name.toLowerCase();
          
          if (contactName.includes(nodeName) || nodeName.includes(contactName)) {
            targetContact = contact;
            console.log('✅ Found contact by fuzzy name match:', contact.id, contact.name);
            break;
          }
        }
      }
      
      // If we found a match, update the UI and call the selection handler
      if (targetContact) {
        setSelectedContact(targetContact);
        
        if (typeof onContactSelect === 'function') {
          console.log('🔄 Calling onContactSelect with ID:', targetContact.id);
          
          // We need a slight delay to ensure the component has time to update
          setTimeout(() => {
            onContactSelect(targetContact!.id);
          }, 0);
        }
      } else {
        console.log('❌ Could not find any matching contact');
        console.log('Available contacts:', contacts.map(c => ({ id: c.id, name: c.name })));
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
