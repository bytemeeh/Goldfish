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
  AlertCircle,
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

  const indentClass = level > 0 ? `ml-${Math.min(level * 16, 64)}` : '';
  const borderOpacity = Math.max(90 - level * 15, 40);
  const borderColor = `border-primary opacity-${borderOpacity}`;
  const bgOpacity = Math.min((level + 1) * 8, 25);

  // Maximum depth is 4 levels (0-based index, so level 3 is the 4th layer)
  const isMaxDepth = level >= 3;

  return (
    <div className={`relative ${indentClass}`}>
      {level > 0 && (
        <>
          {/* Enhanced connection lines with gradients */}
          <div className="absolute -left-8 top-0 bottom-0 w-[2px] bg-gradient-to-b from-primary/50 to-primary/20" />
          <div className="absolute -left-8 top-8 w-8 h-[2px] bg-gradient-to-r from-primary/50 to-primary/20" />
          {/* Connection node indicator */}
          <div className="absolute -left-[35px] top-[29px] w-4 h-4 rounded-full border-2 border-primary/40 bg-background/80 backdrop-blur-sm" />
        </>
      )}

      <Card
        className={`
          relative
          border-l-4 
          ${borderColor}
          hover:border-l-primary/90 
          transition-all duration-300 ease-in-out
          bg-background/[0.${bgOpacity}]
          ${level > 0 ? 'shadow-sm hover:shadow-md' : 'shadow-md'}
          backdrop-blur-sm
          rounded-xl
          hover:translate-x-1.5
          hover:bg-background/[0.${bgOpacity + 5}]
        `}
      >
        <CardHeader className="flex flex-row items-start space-x-4 pb-2">
          <Button
            variant="ghost"
            size="icon"
            className={`
              h-6 w-6 mt-1
              ${children.length > 0 ? 'text-primary hover:text-primary/80' : 'text-muted-foreground'}
              transition-transform duration-200
              ${isExpanded ? 'rotate-0' : '-rotate-90'}
            `}
            onClick={() => setIsExpanded(!isExpanded)}
          >
            {children.length > 0 ? (
              <ChevronDown className="h-5 w-5" />
            ) : (
              <User className="h-4 w-4" />
            )}
          </Button>

          <div className="flex-1 space-y-2">
            <div className="flex items-center gap-2">
              <h3 className={`text-lg font-medium tracking-tight leading-none ${level === 0 ? 'text-foreground' : `text-foreground/[0.${90 - level * 10}]`}`}>
                {contact.name}
              </h3>
              {contact.relationshipType && (
                <Badge
                  variant="outline"
                  className="capitalize font-normal bg-primary/5 text-primary border-0"
                >
                  {contact.relationshipType.replace("-", " ")}
                </Badge>
              )}
            </div>
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
            </div>
          </div>

          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button
                variant="ghost"
                size="icon"
                className="h-8 w-8 hover:bg-primary/5 transition-colors"
              >
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
            <p className="text-sm text-muted-foreground mb-6 leading-relaxed">
              {contact.notes}
            </p>
          )}

          {isMaxDepth ? (
            <div className="flex items-center justify-center p-4 bg-muted/40 rounded-xl backdrop-blur-sm border border-primary/10">
              <AlertCircle className="h-4 w-4 text-primary/60 mr-2" />
              <span className="text-sm text-muted-foreground font-medium">
                Maximum relationship depth reached
              </span>
            </div>
          ) : (
            <Button
              variant="outline"
              size="sm"
              className="w-full hover:bg-primary/5 transition-colors rounded-lg border-primary/20"
              onClick={() => setIsAddingChild(true)}
            >
              <div className="w-5 h-5 rounded-full bg-primary/10 flex items-center justify-center mr-2">
                <Plus className="h-3.5 w-3.5 text-primary" />
              </div>
              Add Related Contact
            </Button>
          )}

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

      {isExpanded && children.length > 0 && (
        <div className="space-y-8 mt-8">
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