import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { type Contact } from "@/lib/types";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";
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
  ChevronRight,
} from "lucide-react";
import { format } from "date-fns";
import { motion, AnimatePresence } from "framer-motion";
import { ScrollArea } from "@/components/ui/scroll-area";

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

// Contact node component
interface ContactNodeProps {
  contact: Contact;
  level: number;
  onToggle: (contactId: number) => void;
  expandedNodes: Set<number>;
  onSelect: (contact: Contact) => void;
  selectedId: number | null;
  children?: Contact[];
}

function ContactNode({
  contact,
  level,
  onToggle,
  expandedNodes,
  onSelect,
  selectedId,
  children = []
}: ContactNodeProps) {
  const isExpanded = expandedNodes.has(contact.id);
  const isSelected = selectedId === contact.id;
  const hasChildren = children.length > 0;

  // Get color based on relationship type
  const getColor = () => {
    if (!contact.relationshipType) return "#64748b";
    const categories = {
      family: ["mother", "father", "brother", "sibling", "child", "spouse"],
      friends: ["friend", "boyfriend/girlfriend"],
      professional: ["co-worker"]
    };

    if (categories.family.includes(contact.relationshipType)) return "#22c55e";
    if (categories.friends.includes(contact.relationshipType)) return "#f97316";
    if (categories.professional.includes(contact.relationshipType)) return "#3b82f6";
    return "#64748b";
  };

  // Get icon based on relationship type
  const getIcon = () => {
    const icons: Record<string, typeof User> = {
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
    return contact.relationshipType ? icons[contact.relationshipType] || User : User;
  };

  const Icon = getIcon();
  const color = getColor();

  return (
    <div className={cn(
      "relative",
      level > 0 && "ml-12 mt-2",
      hasChildren && "before:absolute before:left-[-24px] before:top-[24px] before:h-[calc(100%-24px)] before:w-px before:bg-border"
    )}>
      <div className="relative">
        {level > 0 && (
          <div className="absolute left-[-24px] top-[24px] h-px w-6 bg-border" />
        )}

        <motion.div
          layoutId={`contact-${contact.id}`}
          className={cn(
            "relative flex items-center gap-3 rounded-lg border bg-card p-4 shadow-sm transition-colors",
            isSelected ? "border-primary ring-2 ring-primary ring-offset-2" : "hover:border-primary/50"
          )}
          onClick={() => onSelect(contact)}
        >
          <div
            className="flex h-8 w-8 items-center justify-center rounded-full"
            style={{ backgroundColor: `${color}20`, color }}
          >
            <Icon className="h-4 w-4" />
          </div>

          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2">
              <h3 className="font-medium leading-none truncate">{contact.name}</h3>
              {contact.relationshipType && (
                <Badge
                  variant="outline"
                  className="capitalize font-normal"
                  style={{ borderColor: `${color}40`, color }}
                >
                  {contact.relationshipType.replace("-", " ")}
                </Badge>
              )}
            </div>
          </div>

          {hasChildren && (
            <button
              onClick={(e) => {
                e.stopPropagation();
                onToggle(contact.id);
              }}
              className={cn(
                "flex h-6 w-6 items-center justify-center rounded-full hover:bg-accent",
                "transition-transform",
                isExpanded && "rotate-90"
              )}
            >
              <ChevronRight className="h-4 w-4" />
            </button>
          )}
        </motion.div>

        <AnimatePresence>
          {isExpanded && hasChildren && (
            <motion.div
              initial={{ height: 0, opacity: 0 }}
              animate={{ height: "auto", opacity: 1 }}
              exit={{ height: 0, opacity: 0 }}
              transition={{ duration: 0.2 }}
              className="overflow-hidden"
            >
              {children.map((child) => (
                <ContactNode
                  key={child.id}
                  contact={child}
                  children={child.children}
                  level={level + 1}
                  onToggle={onToggle}
                  expandedNodes={expandedNodes}
                  onSelect={onSelect}
                  selectedId={selectedId}
                />
              ))}
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </div>
  );
}

export function ContactGraph() {
  const [expandedNodes, setExpandedNodes] = useState<Set<number>>(new Set());
  const [selectedContact, setSelectedContact] = useState<Contact | null>(null);
  const { data: contacts, error } = useQuery<Contact[]>({
    queryKey: ["/api/contacts"],
  });

  // Error state
  if (error) {
    return (
      <div className="p-4 text-center text-destructive">
        Error loading contacts: {error instanceof Error ? error.message : "Unknown error"}
      </div>
    );
  }

  // Loading state
  if (!contacts) {
    return (
      <div className="p-4 text-center text-muted-foreground">
        Loading contacts...
      </div>
    );
  }

  // Find the root contact (me)
  const meContact = contacts.find(c => c.isMe);
  if (!meContact) {
    return (
      <div className="p-4 text-center text-muted-foreground">
        No personal contact found. Please set up your personal contact first.
      </div>
    );
  }

  // Build the contact tree
  const buildContactTree = (contact: Contact): Contact & { children: Contact[] } => {
    const children = contacts
      .filter(c => c.parentId === contact.id)
      .map(buildContactTree);
    return { ...contact, children };
  };

  const contactTree = buildContactTree(meContact);

  // Toggle node expansion
  const handleToggle = (contactId: number) => {
    setExpandedNodes(prev => {
      const next = new Set(prev);
      if (next.has(contactId)) {
        next.delete(contactId);
      } else {
        next.add(contactId);
      }
      return next;
    });
  };

  return (
    <div className="relative w-full h-[calc(100vh-12rem)] bg-card rounded-lg border overflow-hidden">
      {/* Selected Contact Details */}
      {selectedContact && (
        <Card className="absolute top-4 left-4 w-80 p-4 bg-card/95 backdrop-blur-sm z-10">
          <div className="space-y-4">
            <div className="flex items-center gap-2">
              <h3 className="font-semibold">{selectedContact.name}</h3>
            </div>
            <ContactDetails contact={selectedContact} />
          </div>
        </Card>
      )}

      {/* Contact Tree */}
      <ScrollArea className="h-full">
        <div className="p-8">
          <ContactNode
            contact={contactTree}
            children={contactTree.children}
            level={0}
            onToggle={handleToggle}
            expandedNodes={expandedNodes}
            onSelect={setSelectedContact}
            selectedId={selectedContact?.id || null}
          />
        </div>
      </ScrollArea>
    </div>
  );
}