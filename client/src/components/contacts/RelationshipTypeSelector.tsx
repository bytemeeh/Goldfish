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
  validChildTypes?: RelationshipType[];
}

// Icon mapping for different relationship types
const relationshipIcons: Record<RelationshipType, React.ComponentType<any>> = {
  sibling: Users,
  mother: Heart,
  father: UserCircle2,
  brother: UserPlus,
  friend: Users,
  child: Baby,
  "co-worker": Briefcase,
  spouse: HeartHandshake,
  "boyfriend/girlfriend": Heart,
};

// Labels for relationship types
const relationshipLabels: Record<RelationshipType, string> = {
  sibling: "Sibling",
  mother: "Mother",
  father: "Father",
  brother: "Brother",
  friend: "Friend",
  child: "Child",
  "co-worker": "Co-worker",
  spouse: "Spouse",
  "boyfriend/girlfriend": "Boyfriend/Girlfriend",
};

export function RelationshipTypeSelector({ 
  value, 
  onChange, 
  parentContact,
  validChildTypes 
}: RelationshipTypeSelectorProps) {
  // If we have valid child types from the parent, use those
  // Otherwise, show all types for root-level contacts
  const availableTypes = validChildTypes || Object.keys(relationshipIcons) as RelationshipType[];

  const handleTypeSelect = (e: React.MouseEvent, type: RelationshipType) => {
    e.preventDefault(); // Prevent form submission
    e.stopPropagation(); // Stop event bubbling
    onChange(type);
  };

  return (
    <div className="flex flex-wrap gap-2">
      {availableTypes.map((type) => {
        const Icon = relationshipIcons[type];
        return (
          <Button
            key={type}
            type="button" // Explicitly set type to prevent form submission
            variant="outline"
            size="sm"
            className={cn(
              "flex items-center gap-2 transition-all",
              value === type 
                ? "bg-primary text-primary-foreground border-primary" 
                : "hover:bg-secondary"
            )}
            onClick={(e) => handleTypeSelect(e, type)}
          >
            <Icon className="h-4 w-4" />
            <span>{relationshipLabels[type]}</span>
          </Button>
        );
      })}
    </div>
  );
}