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

  // Get category for styling
  const getTypeCategory = (type: RelationshipType): keyof typeof relationshipCategories | "other" => {
    for (const [category, types] of Object.entries(relationshipCategories)) {
      if (types.includes(type)) return category as keyof typeof relationshipCategories;
    }
    return "other";
  };

  // Get color variable based on category
  const getCategoryColor = (type: RelationshipType): string => {
    const category = getTypeCategory(type);
    switch(category) {
      case "family": return "--chart-1";
      case "friends": return "--chart-2";
      case "professional": return "--chart-3";
      default: return "--muted";
    }
  };

  return (
    <div className="space-y-4">
      {/* Family relationships */}
      {availableTypes.some(type => relationshipCategories.family.includes(type)) && (
        <div className="space-y-2">
          <h4 className="text-sm font-medium text-muted-foreground">Family</h4>
          <div className="flex flex-wrap gap-2">
            {availableTypes
              .filter(type => relationshipCategories.family.includes(type))
              .map((type) => {
                const Icon = relationshipIcons[type];
                const colorVar = getCategoryColor(type);
                return (
                  <Button
                    key={type}
                    type="button"
                    variant="outline"
                    size="sm"
                    className={cn(
                      "flex items-center gap-2 transition-all",
                      value === type 
                        ? "bg-primary text-primary-foreground border-primary" 
                        : `hover:bg-[hsl(var(${colorVar})/0.1)] border-[hsl(var(${colorVar})/0.2)]`
                    )}
                    onClick={(e) => {
                      e.preventDefault();
                      onChange(type);
                    }}
                  >
                    <Icon className={cn(
                      "h-4 w-4",
                      value === type 
                        ? "text-primary-foreground" 
                        : `text-[hsl(var(${colorVar})/0.8)]`
                    )} />
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
          <h4 className="text-sm font-medium text-muted-foreground">Friends</h4>
          <div className="flex flex-wrap gap-2">
            {availableTypes
              .filter(type => relationshipCategories.friends.includes(type))
              .map((type) => {
                const Icon = relationshipIcons[type];
                const colorVar = getCategoryColor(type);
                return (
                  <Button
                    key={type}
                    type="button"
                    variant="outline"
                    size="sm"
                    className={cn(
                      "flex items-center gap-2 transition-all",
                      value === type 
                        ? "bg-primary text-primary-foreground border-primary" 
                        : `hover:bg-[hsl(var(${colorVar})/0.1)] border-[hsl(var(${colorVar})/0.2)]`
                    )}
                    onClick={(e) => {
                      e.preventDefault();
                      onChange(type);
                    }}
                  >
                    <Icon className={cn(
                      "h-4 w-4",
                      value === type 
                        ? "text-primary-foreground" 
                        : `text-[hsl(var(${colorVar})/0.8)]`
                    )} />
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
          <h4 className="text-sm font-medium text-muted-foreground">Professional</h4>
          <div className="flex flex-wrap gap-2">
            {availableTypes
              .filter(type => relationshipCategories.professional.includes(type))
              .map((type) => {
                const Icon = relationshipIcons[type];
                const colorVar = getCategoryColor(type);
                return (
                  <Button
                    key={type}
                    type="button"
                    variant="outline"
                    size="sm"
                    className={cn(
                      "flex items-center gap-2 transition-all",
                      value === type 
                        ? "bg-primary text-primary-foreground border-primary" 
                        : `hover:bg-[hsl(var(${colorVar})/0.1)] border-[hsl(var(${colorVar})/0.2)]`
                    )}
                    onClick={(e) => {
                      e.preventDefault();
                      onChange(type);
                    }}
                  >
                    <Icon className={cn(
                      "h-4 w-4",
                      value === type 
                        ? "text-primary-foreground" 
                        : `text-[hsl(var(${colorVar})/0.8)]`
                    )} />
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