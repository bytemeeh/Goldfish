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
  DialogTrigger,
} from "@/components/ui/dialog";
import { Badge } from "@/components/ui/badge";
import { ContactForm } from "./ContactForm";
import { type Contact } from "@/lib/types";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { format } from "date-fns";

interface ContactCardProps {
  contact: Contact;
  children?: Contact[];
}

export function ContactCard({ contact, children = [] }: ContactCardProps) {
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

  return (
    <Card className="relative border-l-4 border-l-primary/20 hover:border-l-primary/40 transition-colors">
      <CardHeader className="flex flex-row items-start space-x-4 pb-2">
        <Button
          variant="ghost"
          size="icon"
          className="h-6 w-6 mt-1"
          onClick={() => setIsExpanded(!isExpanded)}
        >
          {children.length > 0 ? (
            isExpanded ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />
          ) : (
            <User className="h-4 w-4 text-muted-foreground" />
          )}
        </Button>

        <div className="flex-1 space-y-1">
          <div className="flex items-center gap-2">
            <h3 className="text-lg font-semibold leading-none">{contact.name}</h3>
            {contact.relationshipType && (
              <Badge
                variant="relationship"
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

        {isExpanded && children.length > 0 && (
          <div className="mt-4 space-y-4">
            {children.map((child) => (
              <ContactCard key={child.id} contact={child} />
            ))}
          </div>
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

        <Button
          variant="outline"
          size="sm"
          className="mt-4 w-full hover:bg-primary/5"
          onClick={() => setIsAddingChild(true)}
        >
          <Plus className="mr-2 h-4 w-4" />
          Add Related Contact
        </Button>
      </CardContent>
    </Card>
  );
}