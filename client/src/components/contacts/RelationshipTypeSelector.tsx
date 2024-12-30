import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { type RelationshipType, type Contact } from "@/lib/types";
import { 
  Users, 
  Heart, 
  Baby, 
  Briefcase, 
  UserCircle2, 
  UserPlus, 
  HeartHandshake,
} from "lucide-react";

interface RelationshipTypeSelectorProps {
  value?: RelationshipType;
  onChange: (type: RelationshipType) => void;
  parentContact?: Contact;
}

// Define available relationship types based on parent context
function getAvailableRelationships(parentContact?: Contact): Array<{
  type: RelationshipType;
  icon: React.ComponentType<any>;
  label: string;
}> {
  // If no parent (root level), show all relationships relative to "me"
  if (!parentContact) {
    return [
      { type: "sibling", icon: Users, label: "Sibling" },
      { type: "mother", icon: Heart, label: "Mother" },
      { type: "father", icon: UserCircle2, label: "Father" },
      { type: "brother", icon: UserPlus, label: "Brother" },
      { type: "friend", icon: Users, label: "Friend" },
      { type: "child", icon: Baby, label: "Child" },
      { type: "co-worker", icon: Briefcase, label: "Co-worker" },
      { type: "spouse", icon: HeartHandshake, label: "Spouse" },
      { type: "boyfriend/girlfriend", icon: Heart, label: "Boyfriend/Girlfriend" }
    ];
  }

  // Based on parent's relationship type, return appropriate options
  switch (parentContact.relationshipType) {
    case "spouse":
    case "boyfriend/girlfriend":
      return [
        { type: "child", icon: Baby, label: "Child" }
      ];
    case "friend":
      return [
        { type: "spouse", icon: HeartHandshake, label: "Spouse" },
        { type: "child", icon: Baby, label: "Child" },
        { type: "friend", icon: Users, label: "Friend" }
      ];
    case "sibling":
      return [
        { type: "spouse", icon: HeartHandshake, label: "Spouse" },
        { type: "child", icon: Baby, label: "Child" }
      ];
    case "mother":
    case "father":
      return [
        { type: "sibling", icon: Users, label: "Sibling" }
      ];
    case "child":
      return [
        { type: "spouse", icon: HeartHandshake, label: "Spouse" },
        { type: "child", icon: Baby, label: "Child" }
      ];
    default:
      return [
        { type: "spouse", icon: HeartHandshake, label: "Spouse" },
        { type: "child", icon: Baby, label: "Child" },
        { type: "friend", icon: Users, label: "Friend" }
      ];
  }
}

export function RelationshipTypeSelector({ value, onChange, parentContact }: RelationshipTypeSelectorProps) {
  const availableRelationships = getAvailableRelationships(parentContact);

  return (
    <div className="flex flex-wrap gap-2">
      {availableRelationships.map(({ type, icon: Icon, label }) => (
        <Button
          key={type}
          variant="outline"
          size="sm"
          className={cn(
            "flex items-center gap-2 transition-all",
            value === type 
              ? "bg-primary text-primary-foreground border-primary" 
              : "hover:bg-secondary"
          )}
          onClick={() => onChange(type)}
        >
          <Icon className="h-4 w-4" />
          <span>{label}</span>
        </Button>
      ))}
    </div>
  );
}