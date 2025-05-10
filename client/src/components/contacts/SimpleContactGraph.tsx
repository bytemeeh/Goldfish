import { useState, useCallback, useEffect, useRef } from "react";
import { useQuery } from "@tanstack/react-query";
import { type Contact } from "@/lib/types";
import ForceGraph2D from "react-force-graph-2d";
import type { NodeObject, LinkObject } from "react-force-graph-2d";
import { motion } from "framer-motion";

// Simple node and link types
interface SimpleNode extends NodeObject {
  id: number;
  name: string;
}

interface SimpleLink extends LinkObject {
  source: SimpleNode;
  target: SimpleNode;
}

interface SimpleContactGraphProps {
  onContactSelect?: (contactId: number) => void;
}

export function SimpleContactGraph({ onContactSelect }: SimpleContactGraphProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const graphRef = useRef<any>(null);
  const [dimensions, setDimensions] = useState({ width: 800, height: 600 });

  // Fetch contacts
  const { data: contacts } = useQuery<Contact[]>({
    queryKey: ["/api/contacts"],
  });

  // Update dimensions on resize
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

  // Simple node click handler
  const handleNodeClick = useCallback((node: any) => {
    console.log("Node clicked:", node);
    
    if (node && node.id && typeof node.id === 'number') {
      // If onContactSelect is provided, call it with the node id
      if (onContactSelect) {
        onContactSelect(node.id);
      }
    }
  }, [onContactSelect]);

  if (!contacts) {
    return <div>Loading contacts...</div>;
  }

  // Create simple graph data
  const nodes = contacts.map(contact => ({
    id: contact.id,
    name: contact.name,
  }));

  const links = contacts
    .filter(contact => contact.parentId)
    .map(contact => ({
      source: contact.parentId as number,
      target: contact.id
    }));

  return (
    <div 
      ref={containerRef} 
      className="w-full h-[calc(100vh-12rem)] rounded-lg border shadow-sm overflow-hidden"
    >
      <ForceGraph2D
        ref={graphRef}
        graphData={{ nodes, links }}
        nodeLabel={node => (node as SimpleNode).name}
        width={dimensions.width}
        height={dimensions.height}
        onNodeClick={handleNodeClick}
      />
    </div>
  );
}