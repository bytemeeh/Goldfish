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
  PawPrint,
  Sparkles
} from "lucide-react";
import { useQuery } from "@tanstack/react-query";

interface RelationshipTypeSelectorProps {
  value: string | null;
  onChange: (value: string) => void;
  parentContact?: Contact & { validChildTypes?: string[] };
  validChildTypes?: string[];
}

// Core icons mapping
const coreIcons: Record<string, React.ComponentType<any>> = {
  sibling: Users,
  mother: Heart,
  father: UserCircle2,
  brother: UserPlus,
  friend: Users,
  child: Baby,
  "co-worker": Briefcase,
  spouse: HeartHandshake,
  "boyfriend/girlfriend": Heart,
  pet: PawPrint,
};

// Default labels for core types
const coreLabels: Record<string, string> = {
  sibling: "Sibling",
  mother: "Mother",
  father: "Father",
  brother: "Brother",
  friend: "Friend",
  child: "Child",
  "co-worker": "Co-worker",
  spouse: "Spouse",
  "boyfriend/girlfriend": "BF/GF",
  pet: "Pet",
};

// Default categories
const defaultCategories: Record<string, string[]> = {
  family: ["mother", "father", "brother", "sibling", "child", "spouse", "pet"],
  friends: ["friend", "boyfriend/girlfriend"],
  professional: ["co-worker"]
};

export function RelationshipTypeSelector({
  value,
  onChange,
  parentContact,
  validChildTypes
}: RelationshipTypeSelectorProps) {
  // Fetch dynamic relationship definitions
  const { data: customDefinitions = [] } = useQuery({
    queryKey: ['/api/contacts/relationships/definitions'],
    queryFn: async () => {
      const res = await fetch('/api/contacts/relationships/definitions');
      if (!res.ok) throw new Error('Failed to fetch definitions');
      return res.json();
    }
  });

  // Merge core and custom types
  // For now, we'll use the hardcoded lists as the base, and append any custom ones
  // In a full implementation, we'd rely entirely on the DB

  // Helper to determine category
  const getCategory = (type: string): string => {
    for (const [cat, types] of Object.entries(defaultCategories)) {
      if (types.includes(type)) return cat;
    }
    // Check custom definitions
    const custom = customDefinitions.find((d: any) => d.name === type);
    if (custom) return custom.category;

    return 'other';
  };

  // Helper to get label
  const getLabel = (type: string): string => {
    if (coreLabels[type]) return coreLabels[type];
    const custom = customDefinitions.find((d: any) => d.name === type);
    return custom ? custom.name : type; // Fallback to type string
  };

  // Helper to get icon
  const getIcon = (type: string) => {
    if (coreIcons[type]) return coreIcons[type];
    return Sparkles; // Default icon for custom types
  };

  // Determine available types
  let availableTypes: string[] = [];

  if (validChildTypes && validChildTypes.length > 0) {
    availableTypes = validChildTypes;
  } else {
    // Default set + custom ones
    const coreTypes = Object.keys(coreIcons);
    const customTypeNames = customDefinitions.map((d: any) => d.name);
    availableTypes = [...new Set([...coreTypes, ...customTypeNames])];
  }

  // Group by category
  const groupedTypes: Record<string, string[]> = {
    family: [],
    friends: [],
    professional: [],
    other: []
  };

  availableTypes.forEach(type => {
    const cat = getCategory(type);
    if (groupedTypes[cat]) {
      groupedTypes[cat].push(type);
    } else {
      // If category doesn't exist in our predefined groups, add to 'other' or create new?
      // For simplicity, map unknown categories to 'other' or dynamically create
      if (!groupedTypes[cat]) groupedTypes[cat] = [];
      groupedTypes[cat].push(type);
    }
  });

  const renderCategory = (category: string, colorVar: string, label: string) => {
    const types = groupedTypes[category];
    if (!types || types.length === 0) return null;

    return (
      <div className="space-y-1.5">
        <h3 className="text-sm font-medium capitalize" style={{ color: `hsl(var(${colorVar}))` }}>{label}</h3>
        <div className="flex flex-wrap gap-1.5 max-w-full">
          {types.map(type => {
            const Icon = getIcon(type);
            const isSelected = value === type;

            // Dynamic color class based on category
            let colorClass = "border-muted text-muted-foreground hover:bg-muted/10";
            if (isSelected) {
              colorClass = "bg-primary text-primary-foreground border-primary";
            } else {
              colorClass = `border-[hsl(var(${colorVar}))] text-[hsl(var(${colorVar}))] hover:bg-[hsl(var(${colorVar})/0.1)]`;
            }

            return (
              <Button
                key={type}
                type="button"
                variant="outline"
                size="sm"
                className={cn(
                  "flex items-center gap-1 transition-all flex-shrink-0 overflow-hidden h-7 px-2 py-0 text-xs rounded-md",
                  colorClass
                )}
                onClick={(e) => {
                  e.preventDefault();
                  onChange(type);
                }}
              >
                <Icon className="h-3.5 w-3.5 flex-shrink-0" />
                <span className="truncate">{getLabel(type)}</span>
              </Button>
            );
          })}
        </div>
      </div>
    );
  };

  return (
    <div className="space-y-3 max-w-full">
      {renderCategory('family', '--chart-1', 'Family')}
      {renderCategory('friends', '--chart-2', 'Friends')}
      {renderCategory('professional', '--chart-3', 'Professional')}
      {renderCategory('other', '--muted-foreground', 'Other')}
    </div>
  );
}