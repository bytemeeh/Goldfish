import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { type Contact, type RelationshipType } from "@/lib/types";
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

interface ContactNodeProps {
  contact: Contact;
  children?: Contact[];
  level: number;
  onToggle: (contactId: number) => void;
  expandedNodes: Set<number>;
  onSelectContact: (contact: Contact | null) => void;
  selectedContact: Contact | null;
}

function ContactNode({
  contact,
  children = [],
  level,
  onToggle,
  expandedNodes,
  onSelectContact,
  selectedContact
}: ContactNodeProps) {
  const isExpanded = expandedNodes.has(contact.id);
  const hasChildren = children.length > 0;
  const isSelected = selectedContact?.id === contact.id;
  const Icon = contact.relationshipType ? relationshipIcons[contact.relationshipType] : User;
  const color = contact.relationshipType
    ? categoryColors[relationshipCategories[contact.relationshipType]]
    : "#64748b";

  return (
    <div className={cn(
      "relative",
      level > 0 && "ml-12 mt-2",
      hasChildren && "before:absolute before:left-[-24px] before:top-[24px] before:h-[calc(100%-24px)] before:w-px before:bg-border",
      isSelected && "z-10"
    )}>
      <div className="relative">
        {/* Connection line to parent */}
        {level > 0 && (
          <div className="absolute left-[-24px] top-[24px] h-px w-6 bg-border" />
        )}

        {/* Node content */}
        <motion.div
          layoutId={`contact-${contact.id}`}
          className={cn(
            "relative flex items-center gap-3 rounded-lg border bg-card p-4 shadow-sm transition-colors",
            isSelected ? "border-primary ring-2 ring-primary ring-offset-2" : "hover:border-primary/50",
            "cursor-pointer"
          )}
          onClick={() => onSelectContact(isSelected ? null : contact)}
        >
          {/* Icon */}
          <div
            className="flex h-8 w-8 items-center justify-center rounded-full"
            style={{ backgroundColor: `${color}20`, color }}
          >
            <Icon className="h-4 w-4" />
          </div>

          {/* Contact info */}
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

          {/* Expand/collapse button */}
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

        {/* Children */}
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
                  onSelectContact={onSelectContact}
                  selectedContact={selectedContact}
                />
              ))}
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </div>
  );
}

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
        <p className="text-sm text-muted-foreground">
          {contact.notes}
        </p>
      )}
    </div>
  );
}

export function ContactGraph() {
  const [expandedNodes, setExpandedNodes] = useState<Set<number>>(new Set());
  const [selectedContact, setSelectedContact] = useState<Contact | null>(null);
  const { data: contacts } = useQuery<Contact[]>({
    queryKey: ["/api/contacts"],
  });

  if (!contacts) return null;

  // Find the root contact (me)
  const meContact = contacts.find(c => c.isMe);
  if (!meContact) return null;

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

      {/* Contact Details */}
      {selectedContact && (
        <Card className="absolute top-4 left-4 w-80 p-4 bg-card/95 backdrop-blur-sm z-10">
          <div className="space-y-4">
            <div className="flex items-center gap-2">
              {selectedContact.relationshipType && (
                <div
                  className="flex h-8 w-8 items-center justify-center rounded-full"
                  style={{
                    backgroundColor: `${categoryColors[relationshipCategories[selectedContact.relationshipType]]}20`,
                    color: categoryColors[relationshipCategories[selectedContact.relationshipType]]
                  }}
                >
                  {(() => {
                    const IconComponent = relationshipIcons[selectedContact.relationshipType];
                    return <IconComponent className="h-4 w-4" />;
                  })()}
                </div>
              )}
              <div>
                <h3 className="font-semibold">{selectedContact.name}</h3>
                {selectedContact.relationshipType && (
                  <Badge
                    variant="outline"
                    className="mt-1 capitalize"
                  >
                    {selectedContact.relationshipType.replace("-", " ")}
                  </Badge>
                )}
              </div>
            </div>
            <ContactDetails contact={selectedContact} />
          </div>
        </Card>
      )}

      {/* Contact Tree */}
      <div className="p-8 h-full overflow-auto">
        <ContactNode
          contact={contactTree}
          children={contactTree.children}
          level={0}
          onToggle={handleToggle}
          expandedNodes={expandedNodes}
          onSelectContact={setSelectedContact}
          selectedContact={selectedContact}
        />
      </div>
    </div>
  );
}