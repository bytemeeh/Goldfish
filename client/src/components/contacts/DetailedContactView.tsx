import React from "react";
import { useQuery } from "@tanstack/react-query";
import { ArrowLeft, Mail, Phone, Cake, MapPin, Edit } from "lucide-react";
import { format } from "date-fns";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { ContactForm } from "./ContactForm";
import { motion } from "framer-motion";
import type { Contact } from "@/lib/types";

interface DetailedContactViewProps {
  contactId: number;
  onBack: () => void;
}

export function DetailedContactView({ contactId, onBack }: DetailedContactViewProps) {
  const [isEditing, setIsEditing] = React.useState(false);
  
  // Fetch all contacts to find the selected one
  const { data: contacts, isLoading } = useQuery<Contact[]>({
    queryKey: ["/api/contacts"],
  });
  
  // Find the specific contact by ID
  const contact = contacts?.find(c => c.id === contactId);

  if (isLoading) {
    return (
      <div className="flex flex-col items-center justify-center min-h-[400px]">
        <div className="animate-pulse h-6 w-24 bg-muted rounded mb-4"></div>
        <div className="animate-pulse h-32 w-full max-w-md bg-muted rounded"></div>
      </div>
    );
  }

  if (!contact) {
    return (
      <div className="text-center py-12">
        <h3 className="text-lg font-medium mb-2">Contact not found</h3>
        <p className="text-muted-foreground mb-6">The requested contact could not be found.</p>
        <Button onClick={onBack}>Go Back</Button>
      </div>
    );
  }

  // Determine relationship type display
  const getRelationshipBadge = () => {
    if (!contact.relationshipType) return null;
    
    return (
      <Badge variant="outline" className="capitalize ml-2">
        {contact.relationshipType.replace("-", " ")}
      </Badge>
    );
  };

  return (
    <div className="space-y-6">
      {/* Header with back button */}
      <motion.div 
        className="flex items-center justify-between"
        initial={{ opacity: 0, y: -10 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.2 }}
      >
        <Button 
          variant="ghost" 
          size="sm" 
          className="flex items-center gap-1"
          onClick={onBack}
        >
          <ArrowLeft className="h-4 w-4" />
          <span>Back to Network</span>
        </Button>
        
        <Dialog open={isEditing} onOpenChange={setIsEditing}>
          <DialogTrigger asChild>
            <Button variant="outline" size="sm" className="flex items-center gap-1">
              <Edit className="h-4 w-4" />
              <span>Edit</span>
            </Button>
          </DialogTrigger>
          <DialogContent className="h-[80vh] max-w-3xl flex flex-col overflow-hidden">
            <DialogHeader>
              <DialogTitle>Edit Contact</DialogTitle>
            </DialogHeader>
            <div className="flex flex-1 overflow-hidden">
              <ContactForm 
                onSuccess={() => setIsEditing(false)} 
                initialData={contact}
              />
            </div>
          </DialogContent>
        </Dialog>
      </motion.div>

      {/* Contact Card */}
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.3, delay: 0.1 }}
      >
        <Card className="p-6 border shadow-sm">
          <div className="space-y-6">
            {/* Contact header */}
            <motion.div 
              className="space-y-1"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              transition={{ duration: 0.3, delay: 0.2 }}
            >
              <div className="flex items-center">
                <h2 className="text-2xl font-bold">{contact.name}</h2>
                {getRelationshipBadge()}
              </div>
              {contact.relationshipType && (
                <p className="text-muted-foreground">
                  {contact.relationshipType === "mother" ? "Your mother" : 
                   contact.relationshipType === "father" ? "Your father" :
                   contact.relationshipType === "brother" ? "Your brother" :
                   contact.relationshipType === "sibling" ? "Your sibling" : 
                   contact.relationshipType === "spouse" ? "Your spouse" :
                   contact.relationshipType === "child" ? "Your child" :
                   contact.relationshipType === "co-worker" ? "Your co-worker" :
                   contact.relationshipType === "friend" ? "Your friend" :
                   contact.relationshipType === "boyfriend/girlfriend" ? "Your partner" :
                   "Your contact"}
                </p>
              )}
            </motion.div>

            {/* Contact details */}
            <div className="space-y-4">
              {contact.email && (
                <motion.div 
                  className="flex items-center gap-3"
                  initial={{ opacity: 0, x: -10 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ duration: 0.3, delay: 0.3 }}
                >
                  <Mail className="h-5 w-5 text-muted-foreground" />
                  <div>
                    <p className="text-sm text-muted-foreground">Email</p>
                    <a 
                      href={`mailto:${contact.email}`} 
                      className="text-foreground hover:text-primary transition-colors"
                    >
                      {contact.email}
                    </a>
                  </div>
                </motion.div>
              )}

              {contact.phone && (
                <motion.div 
                  className="flex items-center gap-3"
                  initial={{ opacity: 0, x: -10 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ duration: 0.3, delay: 0.4 }}
                >
                  <Phone className="h-5 w-5 text-muted-foreground" />
                  <div>
                    <p className="text-sm text-muted-foreground">Phone</p>
                    <a 
                      href={`tel:${contact.phone}`} 
                      className="text-foreground hover:text-primary transition-colors"
                    >
                      {contact.phone}
                    </a>
                  </div>
                </motion.div>
              )}

              {contact.birthday && (
                <motion.div 
                  className="flex items-center gap-3"
                  initial={{ opacity: 0, x: -10 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ duration: 0.3, delay: 0.5 }}
                >
                  <Cake className="h-5 w-5 text-muted-foreground" />
                  <div>
                    <p className="text-sm text-muted-foreground">Birthday</p>
                    <p className="text-foreground">
                      {format(new Date(contact.birthday), "MMMM d, yyyy")}
                    </p>
                  </div>
                </motion.div>
              )}

              {/* Location display */}
              {(contact.locations && contact.locations.length > 0) ? (
                <motion.div 
                  className="space-y-3"
                  initial={{ opacity: 0, x: -10 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ duration: 0.3, delay: 0.6 }}
                >
                  <p className="text-sm font-medium">Locations</p>
                  {contact.locations.map((location, index) => (
                    <div key={location.id || index} className="flex items-start gap-3">
                      <MapPin className="h-5 w-5 text-muted-foreground mt-0.5" />
                      <div>
                        <p className="text-sm text-muted-foreground capitalize">{location.type}</p>
                        <p className="text-foreground">{location.name || location.address}</p>
                      </div>
                    </div>
                  ))}
                </motion.div>
              ) : (contact.street || contact.city || contact.state || contact.country) && (
                <motion.div 
                  className="flex items-start gap-3"
                  initial={{ opacity: 0, x: -10 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ duration: 0.3, delay: 0.6 }}
                >
                  <MapPin className="h-5 w-5 text-muted-foreground mt-0.5" />
                  <div>
                    <p className="text-sm text-muted-foreground">Address</p>
                    <div className="text-foreground">
                      {contact.street && <p>{contact.street}</p>}
                      <p>
                        {[contact.city, contact.state, contact.postalCode]
                          .filter(Boolean)
                          .join(", ")}
                      </p>
                      {contact.country && <p>{contact.country}</p>}
                    </div>
                  </div>
                </motion.div>
              )}

              {/* Notes */}
              {contact.notes && (
                <motion.div 
                  className="mt-6 pt-4 border-t"
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  transition={{ duration: 0.3, delay: 0.7 }}
                >
                  <p className="text-sm font-medium mb-2">Notes</p>
                  <p className="text-muted-foreground whitespace-pre-line">
                    {contact.notes}
                  </p>
                </motion.div>
              )}
            </div>
          </div>
        </Card>
      </motion.div>
    </div>
  );
}