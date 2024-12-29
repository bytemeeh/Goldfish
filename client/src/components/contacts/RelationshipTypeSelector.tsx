import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { type RelationshipType } from "@/lib/types";

interface RelationshipTypeSelectorProps {
  value?: RelationshipType;
  onChange: (type: RelationshipType) => void;
}

const relationshipTypes: RelationshipType[] = [
  "sibling",
  "mother",
  "father",
  "brother",
  "friend",
  "child",
  "co-worker"
];

export function RelationshipTypeSelector({ value, onChange }: RelationshipTypeSelectorProps) {
  return (
    <div className="flex flex-wrap gap-2">
      {relationshipTypes.map((type) => (
        <Button
          key={type}
          variant="secondary"
          size="sm"
          className={cn(
            "capitalize",
            value === type && "bg-primary text-primary-foreground"
          )}
          onClick={() => onChange(type)}
        >
          {type}
        </Button>
      ))}
    </div>
  );
}
