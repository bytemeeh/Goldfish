import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { type RelationshipType } from "@/lib/types";
import { Users, Heart, Baby, Briefcase, UserCircle2, UserMinus, UserPlus } from "lucide-react";

interface RelationshipTypeSelectorProps {
  value?: RelationshipType;
  onChange: (type: RelationshipType) => void;
}

const relationshipTypes: Array<{
  type: RelationshipType;
  icon: React.ComponentType<any>;
  label: string;
}> = [
  { type: "sibling", icon: Users, label: "Sibling" },
  { type: "mother", icon: Heart, label: "Mother" },
  { type: "father", icon: UserCircle2, label: "Father" },
  { type: "brother", icon: UserPlus, label: "Brother" },
  { type: "friend", icon: UserMinus, label: "Friend" },
  { type: "child", icon: Baby, label: "Child" },
  { type: "co-worker", icon: Briefcase, label: "Co-worker" }
];

export function RelationshipTypeSelector({ value, onChange }: RelationshipTypeSelectorProps) {
  return (
    <div className="flex flex-wrap gap-2">
      {relationshipTypes.map(({ type, icon: Icon, label }) => (
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