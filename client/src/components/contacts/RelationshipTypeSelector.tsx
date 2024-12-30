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

// Group types by category for better organization
const relationshipCategories = {
  family: ["mother", "father", "brother", "sibling", "child", "spouse"],
  friends: ["friend", "boyfriend/girlfriend"],
  professional: ["co-worker"]
} as const;

export function RelationshipTypeSelector({ 
  value, 
  onChange, 
  parentContact,
  validChildTypes 
}: RelationshipTypeSelectorProps) {
  // If we have valid child types from the parent, use those
  // Otherwise, show all types for root-level contacts
  const availableTypes = validChildTypes || Object.keys(relationshipIcons) as RelationshipType[];

  // Helper function to get the appropriate color class based on relationship type
  const getRelationshipColorClass = (type: RelationshipType, isSelected: boolean): string => {
    if (isSelected) {
      return "bg-primary text-primary-foreground border-primary";
    }

    if (relationshipCategories.family.includes(type)) {
      return "border-[hsl(var(--chart-1))] text-[hsl(var(--chart-1))] hover:bg-[hsl(var(--chart-1)/0.1)]";
    }
    if (relationshipCategories.friends.includes(type)) {
      return "border-[hsl(var(--chart-2))] text-[hsl(var(--chart-2))] hover:bg-[hsl(var(--chart-2)/0.1)]";
    }
    if (relationshipCategories.professional.includes(type)) {
      return "border-[hsl(var(--chart-3))] text-[hsl(var(--chart-3))] hover:bg-[hsl(var(--chart-3)/0.1)]";
    }

    return "border-muted text-muted-foreground hover:bg-muted/10";
  };

  return (
    <div className="space-y-4">
      {/* Family relationships */}
      {availableTypes.some(type => relationshipCategories.family.includes(type)) && (
        <div className="space-y-2">
          <h4 className="text-sm font-medium" style={{ color: 'hsl(var(--chart-1))' }}>Family</h4>
          <div className="flex flex-wrap gap-2">
            {availableTypes
              .filter(type => relationshipCategories.family.includes(type))
              .map((type) => {
                const Icon = relationshipIcons[type];
                const isSelected = value === type;
                return (
                  <Button
                    key={type}
                    type="button"
                    variant="outline"
                    size="sm"
                    className={cn(
                      "flex items-center gap-2 transition-all",
                      getRelationshipColorClass(type, isSelected)
                    )}
                    onClick={(e) => {
                      e.preventDefault();
                      onChange(type);
                    }}
                  >
                    <Icon className="h-4 w-4" />
                    <span>{relationshipLabels[type]}</span>
                  </Button>
                );
              })}
          </div>
        </div>
      )}

      {/* Friends relationships */}
      {availableTypes.some(type => relationshipCategories.friends.includes(type)) && (
        <div className="space-y-2">
          <h4 className="text-sm font-medium" style={{ color: 'hsl(var(--chart-2))' }}>Friends</h4>
          <div className="flex flex-wrap gap-2">
            {availableTypes
              .filter(type => relationshipCategories.friends.includes(type))
              .map((type) => {
                const Icon = relationshipIcons[type];
                const isSelected = value === type;
                return (
                  <Button
                    key={type}
                    type="button"
                    variant="outline"
                    size="sm"
                    className={cn(
                      "flex items-center gap-2 transition-all",
                      getRelationshipColorClass(type, isSelected)
                    )}
                    onClick={(e) => {
                      e.preventDefault();
                      onChange(type);
                    }}
                  >
                    <Icon className="h-4 w-4" />
                    <span>{relationshipLabels[type]}</span>
                  </Button>
                );
              })}
          </div>
        </div>
      )}

      {/* Professional relationships */}
      {availableTypes.some(type => relationshipCategories.professional.includes(type)) && (
        <div className="space-y-2">
          <h4 className="text-sm font-medium" style={{ color: 'hsl(var(--chart-3))' }}>Professional</h4>
          <div className="flex flex-wrap gap-2">
            {availableTypes
              .filter(type => relationshipCategories.professional.includes(type))
              .map((type) => {
                const Icon = relationshipIcons[type];
                const isSelected = value === type;
                return (
                  <Button
                    key={type}
                    type="button"
                    variant="outline"
                    size="sm"
                    className={cn(
                      "flex items-center gap-2 transition-all",
                      getRelationshipColorClass(type, isSelected)
                    )}
                    onClick={(e) => {
                      e.preventDefault();
                      onChange(type);
                    }}
                  >
                    <Icon className="h-4 w-4" />
                    <span>{relationshipLabels[type]}</span>
                  </Button>
                );
              })}
          </div>
        </div>
      )}
    </div>
  );
}