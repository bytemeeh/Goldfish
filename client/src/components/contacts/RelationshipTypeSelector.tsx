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
    <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
      {relationshipTypes.map(({ type, icon: Icon, label }) => (
        <Button
          key={type}
          variant="outline"
          size="lg"
          className={cn(
            "h-auto py-4 flex flex-col gap-2 items-center justify-center transition-all",
            value === type && "bg-primary text-primary-foreground border-primary"
          )}
          onClick={() => onChange(type)}
        >
          <Icon className="h-5 w-5" />
          <span>{label}</span>
        </Button>
      ))}
    </div>
  );
}