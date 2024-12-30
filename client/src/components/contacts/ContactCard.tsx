import { useState } from "react";
import { Card, CardHeader, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import {
  MoreVertical,
  Mail,
  Phone,
  Cake,
  ChevronDown,
  ChevronRight,
  Plus,
  User,
} from "lucide-react";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Badge } from "@/components/ui/badge";
import { ContactForm } from "./ContactForm";
import { type Contact } from "@/lib/types";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { format } from "date-fns";

interface ContactCardProps {
  contact: Contact;
  children?: Contact[];
  level?: number;
}

export function ContactCard({ contact, children = [], level = 0 }: ContactCardProps) {
  const [isExpanded, setIsExpanded] = useState(true);
  const [isAddingChild, setIsAddingChild] = useState(false);
  const [isEditing, setIsEditing] = useState(false);
  const queryClient = useQueryClient();

  const deleteContact = useMutation({
    mutationFn: async () => {
      const res = await fetch(`/api/contacts/${contact.id}`, {
        method: "DELETE",
      });
      if (!res.ok) throw new Error("Failed to delete contact");
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["/api/contacts"] });
    },
  });

  // Calculate indentation and nested styles based on level
  const indentClass = level > 0 ? `ml-${Math.min(level * 6, 24)}` : '';
  const levelBackgroundClass = level > 0 ? `bg-background/[0.${Math.min(level * 2, 8)}]` : '';
  const borderColor = level === 0 ? 'primary' : `primary/[0.${Math.max(8 - level * 2, 3)}]`;

  return (
    <div className={`relative ${indentClass}`}>
      {/* Connection line for nested items */}
      {level > 0 && (
        <div className="absolute -left-4 top-0 bottom-0 w-px bg-primary/20" />
      )}

      <Card className={`relative border-l-4 border-l-${borderColor} hover:border-l-primary/60 transition-colors ${levelBackgroundClass}`}>
        <CardHeader className="flex flex-row items-start space-x-4 pb-2">
          <Button
            variant="ghost"
            size="icon"
            className={`h-6 w-6 mt-1 ${children.length > 0 ? 'text-primary hover:text-primary/80' : 'text-muted-foreground'}`}
            onClick={() => setIsExpanded(!isExpanded)}
          >
            {children.length > 0 ? (
              isExpanded ? <ChevronDown className="h-5 w-5" /> : <ChevronRight className="h-5 w-5" />
            ) : (
              <User className="h-4 w-4" />
            )}
          </Button>

          <div className="flex-1 space-y-1">
            <div className="flex items-center gap-2">
              <h3 className="text-lg font-semibold leading-none">{contact.name}</h3>
              {contact.relationshipType && (
                <Badge
                  variant="outline"
                  className="capitalize font-normal cursor-default"
                >
                  {contact.relationshipType.replace("-", " ")}
                </Badge>
              )}
            </div>
            <div className="space-y-1">
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
            </div>
          </div>

          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="ghost" size="icon" className="h-8 w-8">
                <MoreVertical className="h-4 w-4" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <DropdownMenuItem onClick={() => setIsEditing(true)}>
                Edit
              </DropdownMenuItem>
              <DropdownMenuItem
                className="text-destructive"
                onClick={() => deleteContact.mutate()}
              >
                Delete
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </CardHeader>

        <CardContent>
          {contact.notes && (
            <p className="text-sm text-muted-foreground mb-4">
              {contact.notes}
            </p>
          )}

          <Button
            variant="outline"
            size="sm"
            className="w-full hover:bg-primary/5"
            onClick={() => setIsAddingChild(true)}
          >
            <Plus className="mr-2 h-4 w-4" />
            Add Related Contact
          </Button>

          <Dialog open={isEditing} onOpenChange={setIsEditing}>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>Edit Contact</DialogTitle>
              </DialogHeader>
              <ContactForm
                initialData={contact}
                onSuccess={() => setIsEditing(false)}
              />
            </DialogContent>
          </Dialog>

          <Dialog open={isAddingChild} onOpenChange={setIsAddingChild}>
            <DialogContent>
              <DialogHeader>
                <DialogTitle>Add Related Contact</DialogTitle>
              </DialogHeader>
              <ContactForm
                parentId={contact.id}
                onSuccess={() => setIsAddingChild(false)}
              />
            </DialogContent>
          </Dialog>
        </CardContent>
      </Card>

      {/* Render children with increased nesting level */}
      {isExpanded && children.length > 0 && (
        <div className="space-y-4 mt-4">
          {children.map((child) => (
            <ContactCard 
              key={child.id} 
              contact={child}
              children={child.children}
              level={level + 1}
            />
          ))}
        </div>
      )}
    </div>
  );
}