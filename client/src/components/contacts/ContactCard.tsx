import { useState } from "react";
import { Card, CardHeader, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { motion, AnimatePresence, Reorder } from "framer-motion";
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
  Calendar,
  Clock,
  Heart,
  Users,
  Baby,
  Briefcase,
  UserCircle2,
  UserPlus,
  HeartHandshake,
  MapPin,
  GripVertical,
  EyeOff,
  Pencil,
  Trash2,
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
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog";
import { Badge } from "@/components/ui/badge";
import { ContactForm } from "./ContactForm";
import { type Contact, type RelationshipType } from "@/lib/types";
import { getContactColorClasses, type ContactColor } from "@/lib/colors";
import { ProfilePhoto } from "@/components/ui/ProfilePhoto";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { format } from "date-fns";
import cn from 'classnames';

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

interface ContactCardProps {
  contact: Contact;
  children?: Contact[];
  level?: number;
  relationshipLevel?: number;
  manualSortMode?: boolean;
  onChildrenReorder?: (children: Contact[]) => void;
  isSelected?: boolean;
}

export function ContactCard({ contact, children = [], level = 0, relationshipLevel, manualSortMode = false, onChildrenReorder, isSelected = false }: ContactCardProps) {
  // Auto-expand first level contacts
  const [isExpanded, setIsExpanded] = useState(level === 0 && children.length > 0);
  const [isAddingChild, setIsAddingChild] = useState(false);
  const [isEditing, setIsEditing] = useState(false);
  // Removed hover state to implement click-to-expand instead
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
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

  // Enhanced visual hierarchy with level-based styling
  const indentClass = level > 0 ? `ml-${Math.min(level * 24, 72)}` : '';

  // Maximum depth is 4 levels (0-based index, so level 3 is the 4th layer)
  // Level 0 is the master contact (you), level 1 is direct contacts, level 2+ are subsequent levels
  const isMaxDepth = level >= 3;

  // Get relationship icon if available
  const RelationshipIcon = contact.relationshipType ? relationshipIcons[contact.relationshipType] : null;

  // Relationship categories for styling
  const relationshipCategories = {
    family: ["mother", "father", "sibling", "brother", "child", "spouse"],
    friends: ["friend", "boyfriend/girlfriend"],
    professional: ["co-worker"],
  };

  // Get color classes for the contact
  const colorClasses = getContactColorClasses(contact.color || 'blue');

  return (
    <div className={`relative ${indentClass} group`}>
      
      {level > 0 && (
        <>
          {/* Connection line with level-based styling */}
          <div
            className={`absolute -left-12 top-0 bottom-0 w-[1px] ${level === 1 ? 'bg-primary/30' : level === 2 ? 'bg-primary/20' : 'bg-border/20'}`}
          />
          <div
            className={`absolute -left-12 top-10 w-12 h-[1px] ${level === 1 ? 'bg-primary/30' : level === 2 ? 'bg-primary/20' : 'bg-border/20'}`}
          />
          {/* Connection node with level-based styling */}
          <motion.div
            className={`absolute -left-[50px] top-[37px] w-2 h-2 rounded-full ${level === 1 ? 'bg-primary/60' : level === 2 ? 'bg-primary/40' : 'bg-border/40'}`}
            whileHover={{ scale: 1.2 }}
            transition={{ type: "spring", stiffness: 400, damping: 25 }}
          />
        </>
      )}
      
      {/* Grip handle for manual sort mode - ONLY shown in the main card, not in the header */}
      {manualSortMode && level === 0 && (
        <div className="absolute -left-6 top-10 transform opacity-40 hover:opacity-100 transition-opacity cursor-move">
          <GripVertical className="w-4 h-4 text-muted-foreground" />
        </div>
      )}

      <motion.div
        initial={false}
        transition={{
          type: "spring",
          stiffness: 400,
          damping: 25,
        }}
        onClick={() => setIsExpanded(!isExpanded)}
      >
        <Card
          className={`
            relative
            ${colorClasses.border}
            ${colorClasses.bg}
            rounded-xl
            border-2
            ${level === 0 ? 'shadow-lg' : 'shadow-md'}
            ${isSelected ? `ring-2 ${colorClasses.ring} ring-opacity-70 shadow-xl` : ''}
            transition-all
            duration-300
            ease-in-out
            transform-gpu
            cursor-pointer
            hover:shadow-xl
            hover:border-border
          `}
        >
          {/* Level indicator */}
          {level > 0 && (
            <div className="absolute -left-6 top-1/2 -translate-y-1/2 flex items-center">
              <div className="flex items-center gap-1">
                {Array.from({ length: level }).map((_, index) => (
                  <div
                    key={index}
                    className={`w-1 h-3 rounded-full ${index === 0 ? 'bg-primary/70' : index === 1 ? 'bg-primary/40' : 'bg-primary/20'}`}
                  />
                ))}
              </div>
            </div>
          )}

          <CardHeader className="flex flex-row items-start space-x-2 pb-1 pt-2 px-3 sm:px-3">
            <motion.div
              className={`
                h-7 w-7 mt-0.5 flex items-center justify-center
                ${children.length > 0 ? 'text-primary/70' : 'text-muted-foreground/40'}
                transition-all duration-200
                rounded-full
              `}
              animate={{ opacity: 1 }}
            >
              {children.length > 0 ? (
                isExpanded ? (
                  <ChevronDown className="h-5 w-5" />
                ) : (
                  <ChevronRight className="h-5 w-5" />
                )
              ) : (
                <div className="mr-1">
                  <ProfilePhoto 
                    photo={contact.photo}
                    name={contact.name}
                    size="sm"
                  />
                </div>
              )}
            </motion.div>

            <div className="flex-1 space-y-2">
              <motion.div
                className="flex items-center gap-3"
                animate={{ opacity: 1 }}
                initial={{ opacity: 0 }}
                transition={{ duration: 0.2 }}
              >
                <div className="flex flex-col">
                  <div className="flex items-center gap-2">
                    <h3 className={`
                      ${level === 0 ? 'text-base sm:text-lg font-semibold' : 'text-sm sm:text-base font-medium'}
                      tracking-tight
                      text-foreground
                      leading-tight
                    `}>
                      {contact.name}
                    </h3>
                    {/* Level badges based on actual relationship level, not UI nesting */}
                    {relationshipLevel === 1 && (
                      <span className="inline-flex items-center justify-center w-6 h-6 text-xs font-medium text-primary ml-2">
                        L1
                      </span>
                    )}
                    {relationshipLevel === 2 && (
                      <span className="inline-flex items-center justify-center w-6 h-6 text-xs font-medium text-primary ml-2">
                        L2
                      </span>
                    )}
                    {relationshipLevel === 3 && (
                      <span className="inline-flex items-center justify-center w-6 h-6 text-xs font-medium text-primary ml-2">
                        L3
                      </span>
                    )}
                    {relationshipLevel === 4 && (
                      <span className="inline-flex items-center justify-center w-6 h-6 text-xs font-medium text-primary ml-2">
                        L4
                      </span>
                    )}
                  </div>
                  {contact.relationshipType && (
                    <div className="flex items-center gap-2 mt-1.5">
                      {RelationshipIcon && (
                        <RelationshipIcon
                          className={cn(
                            "h-3.5 w-3.5",
                            relationshipCategories.family.includes(contact.relationshipType)
                              ? "text-[hsl(var(--chart-1))]"
                              : relationshipCategories.friends.includes(contact.relationshipType)
                              ? "text-[hsl(var(--chart-2))]"
                              : relationshipCategories.professional.includes(contact.relationshipType)
                              ? "text-[hsl(var(--chart-3))]"
                              : "text-muted-foreground"
                          )}
                        />
                      )}
                      <Badge
                        variant="outline"
                        className={cn(
                          "capitalize font-normal text-xs border-0 px-2 py-0",
                          relationshipCategories.family.includes(contact.relationshipType)
                            ? "bg-[hsl(var(--chart-1)/0.1)] text-[hsl(var(--chart-1))]"
                            : relationshipCategories.friends.includes(contact.relationshipType)
                            ? "bg-[hsl(var(--chart-2)/0.1)] text-[hsl(var(--chart-2))]"
                            : relationshipCategories.professional.includes(contact.relationshipType)
                            ? "bg-[hsl(var(--chart-3)/0.1)] text-[hsl(var(--chart-3))]"
                            : "bg-muted/20 text-muted-foreground"
                        )}
                      >
                        {contact.relationshipType.replace("-", " ")}
                      </Badge>
                    </div>
                  )}
                </div>
              </motion.div>

              <AnimatePresence>
                {isExpanded && (
                  <motion.div
                    initial={{ opacity: 0, height: 0 }}
                    animate={{ opacity: 1, height: "auto" }}
                    exit={{ opacity: 0, height: 0 }}
                    className="space-y-2.5 overflow-hidden mt-2"
                  >
                    {contact.email && (
                      <motion.div
                        className="flex items-center text-xs text-muted-foreground/90"
                        initial={{ x: -20, opacity: 0 }}
                        animate={{ x: 0, opacity: 1 }}
                        transition={{ delay: 0.1 }}
                      >
                        <Mail className="mr-1.5 h-3.5 w-3.5" />
                        <a
                          href={`mailto:${contact.email}`}
                          className="hover:text-primary transition-colors"
                        >
                          {contact.email}
                        </a>
                      </motion.div>
                    )}
                    {contact.phone && (
                      <motion.div
                        className="flex items-center text-xs text-muted-foreground/90"
                        initial={{ x: -20, opacity: 0 }}
                        animate={{ x: 0, opacity: 1 }}
                        transition={{ delay: 0.2 }}
                      >
                        <Phone className="mr-1.5 h-3.5 w-3.5" />
                        <a
                          href={`tel:${contact.phone}`}
                          className="hover:text-primary transition-colors"
                        >
                          {contact.phone}
                        </a>
                      </motion.div>
                    )}
                    {contact.birthday && (
                      <motion.div
                        className="flex items-center text-xs text-muted-foreground/90"
                        initial={{ x: -20, opacity: 0 }}
                        animate={{ x: 0, opacity: 1 }}
                        transition={{ delay: 0.3 }}
                      >
                        <Cake className="mr-1.5 h-3.5 w-3.5" />
                        {format(new Date(contact.birthday), "PPP")}
                      </motion.div>
                    )}
                    
                    {/* Location information display */}
                    {/* Display multiple locations if available */}
                    {contact.locations && contact.locations.length > 0 ? (
                      <motion.div
                        className="flex items-start text-xs text-muted-foreground/90"
                        initial={{ x: -20, opacity: 0 }}
                        animate={{ x: 0, opacity: 1 }}
                        transition={{ delay: 0.35 }}
                      >
                        <MapPin className="mr-1.5 h-3.5 w-3.5 mt-0.5 flex-shrink-0" />
                        <div className="space-y-1.5">
                          {contact.isMe ? (
                            // For personal card, only show address with no additional details
                            <div className="pb-1">
                              {contact.locations[0]?.address && <div>{contact.locations[0].address}</div>}
                            </div>
                          ) : (
                            // For regular contacts, show full location information
                            contact.locations.map((location, index) => (
                              <div key={location.id || index} className="pb-1">
                                {location.type && (
                                  <div className="text-xs font-medium text-primary/70 mb-0.5 capitalize">
                                    {location.type} {location.name && `- ${location.name}`}
                                  </div>
                                )}
                                {location.address && <div>{location.address}</div>}
                                <div className="text-xs opacity-90">
                                  {location.latitude && location.longitude && (
                                    <div className="text-muted-foreground/70">
                                      GPS: {parseFloat(location.latitude as string).toFixed(4)}, 
                                      {parseFloat(location.longitude as string).toFixed(4)}
                                    </div>
                                  )}
                                </div>
                              </div>
                            ))
                          )}
                        </div>
                      </motion.div>
                    ) : 
                    /* Fallback to legacy location fields */
                    (contact.street || contact.city || contact.state || contact.country) && (
                      <motion.div
                        className="flex items-start text-xs text-muted-foreground/90"
                        initial={{ x: -20, opacity: 0 }}
                        animate={{ x: 0, opacity: 1 }}
                        transition={{ delay: 0.35 }}
                      >
                        <MapPin className="mr-1.5 h-3.5 w-3.5 mt-0.5 flex-shrink-0" />
                        <div>
                          {contact.street && <div>{contact.street}</div>}
                          <div>
                            {[contact.city, contact.state, contact.postalCode]
                              .filter(Boolean)
                              .join(", ")}
                          </div>
                          {contact.country && <div>{contact.country}</div>}
                        </div>
                      </motion.div>
                    )}
                    {contact.notes && (
                      <motion.p
                        className={`
                          text-xs text-muted-foreground/80 
                          mt-1.5 pl-3 
                          border-l border-primary/${Math.max(20 - level * 5, 10)}
                        `}
                        initial={{ y: -10, opacity: 0 }}
                        animate={{ y: 0, opacity: 1 }}
                        transition={{ delay: 0.4 }}
                      >
                        {contact.notes}
                      </motion.p>
                    )}
                    {(contact.createdAt || contact.updatedAt) && (
                      <motion.div
                        className="flex flex-col gap-1 text-xs text-muted-foreground/50 mt-3"
                        initial={{ y: -10, opacity: 0 }}
                        animate={{ y: 0, opacity: 1 }}
                        transition={{ delay: 0.5 }}
                      >
                        {contact.createdAt && (
                          <div className="flex items-center">
                            <Calendar className="mr-1 h-3 w-3" />
                            Created: {format(new Date(contact.createdAt), "PP")}
                          </div>
                        )}
                        {contact.updatedAt && (
                          <div className="flex items-center">
                            <Clock className="mr-1 h-3 w-3" />
                            Updated: {format(new Date(contact.updatedAt), "PP")}
                          </div>
                        )}
                      </motion.div>
                    )}
                  </motion.div>
                )}
              </AnimatePresence>
            </div>

            <div className="flex items-center">
              {/* Hide button moved to dropdown menu */}
              
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
                  <DropdownMenuItem 
                    onClick={(e) => {
                      e.stopPropagation();
                      setIsEditing(true);
                    }}
                    className="flex items-center justify-start"
                  >
                    <Pencil className="h-4 w-4 mr-2" />
                    Edit
                  </DropdownMenuItem>
                  {!isMaxDepth && (
                    <DropdownMenuItem 
                      onClick={(e) => {
                        e.stopPropagation();
                        setIsAddingChild(true);
                      }}
                      className="flex items-center justify-start"
                    >
                      <UserPlus className="h-4 w-4 mr-2" />
                      Add Related Contact
                    </DropdownMenuItem>
                  )}
                  {/* Hide option */}
                  {!contact.isMe && (
                    <DropdownMenuItem
                      onClick={(e) => {
                        e.stopPropagation();
                        // Emit hide event through custom event
                        if (window.dispatchEvent) {
                          const hideEvent = new CustomEvent('contact:hide', { detail: { contactId: contact.id } });
                          window.dispatchEvent(hideEvent);
                        }
                      }}
                      className="flex items-center justify-start"
                    >
                      <EyeOff className="h-4 w-4 mr-2" />
                      Hide
                    </DropdownMenuItem>
                  )}
                  <DropdownMenuItem
                    className="text-destructive flex items-center justify-start"
                    onClick={(e) => {
                      e.stopPropagation();
                      setShowDeleteConfirm(true);
                    }}
                  >
                    <Trash2 className="h-4 w-4 mr-2" />
                    Delete
                  </DropdownMenuItem>
                </DropdownMenuContent>
              </DropdownMenu>
            </div>
          </CardHeader>

          <CardContent className="p-3 pt-0">
            {isMaxDepth ? (
              <div className="flex items-center justify-center p-4 bg-muted/20 rounded-lg border border-primary/10">
                <AlertCircle className="h-4 w-4 text-primary/40 mr-2" />
                <span className="text-sm text-muted-foreground/70 font-medium">
                  Maximum relationship depth reached
                </span>
              </div>
            ) : (
              <Button
                variant="outline"
                size="sm"
                className="w-full h-7 py-0 text-xs hover:bg-primary/5 transition-colors rounded-md group"
                onClick={() => setIsAddingChild(true)}
              >
                <div className="w-4 h-4 rounded-full bg-primary/10 flex items-center justify-center mr-1 group-hover:bg-primary/20 transition-colors">
                  <Plus className="h-3 w-3 text-primary" />
                </div>
                Add Related
              </Button>
            )}

            <Dialog open={isEditing} onOpenChange={setIsEditing}>
              <DialogContent>
                <DialogHeader>
                  <DialogTitle>Edit Contact</DialogTitle>
                  <DialogDescription>Update the contact information</DialogDescription>
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
                  <DialogDescription>Create a new contact connected to {contact.name}</DialogDescription>
                </DialogHeader>
                <ContactForm
                  parentId={contact.id}
                  onSuccess={() => setIsAddingChild(false)}
                />
              </DialogContent>
            </Dialog>

            <Dialog open={showDeleteConfirm} onOpenChange={setShowDeleteConfirm}>
              <DialogContent>
                <DialogHeader>
                  <DialogTitle>Delete Contact</DialogTitle>
                  <DialogDescription>
                    Are you sure you want to delete <strong>{contact.name}</strong>?
                    {children.length > 0 && (
                      <div className="mt-2 text-destructive">
                        Warning: This will also delete {children.length} related contact{children.length !== 1 ? 's' : ''}.
                      </div>
                    )}
                  </DialogDescription>
                </DialogHeader>
                <DialogFooter className="gap-2 sm:gap-0">
                  <Button 
                    variant="outline" 
                    onClick={() => setShowDeleteConfirm(false)}
                  >
                    Cancel
                  </Button>
                  <Button 
                    variant="destructive" 
                    onClick={() => {
                      deleteContact.mutate();
                      setShowDeleteConfirm(false);
                    }}
                    disabled={deleteContact.isPending}
                  >
                    {deleteContact.isPending ? 'Deleting...' : 'Delete'}
                  </Button>
                </DialogFooter>
              </DialogContent>
            </Dialog>
          </CardContent>
        </Card>
      </motion.div>

      <AnimatePresence>
        {isExpanded && children.length > 0 && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: "auto" }}
            exit={{ opacity: 0, height: 0 }}
            className="space-y-4 mt-4"
          >
            {/* Level headings have been removed as requested */}
            {manualSortMode ? (
              <Reorder.Group
                axis="y"
                values={children}
                onReorder={onChildrenReorder || (() => {})}
                className="space-y-4"
              >
                {children.map((child) => (
                  <Reorder.Item
                    key={child.id}
                    value={child}
                    className="relative cursor-move"
                  >
                    <div className="absolute -left-4 top-6 transform opacity-40 hover:opacity-100 transition-opacity">
                      <GripVertical className="w-4 h-4 text-muted-foreground" />
                    </div>
                    <ContactCard
                      key={child.id}
                      contact={child}
                      children={child.children}
                      level={level + 1}
                      relationshipLevel={relationshipLevel ? relationshipLevel + 1 : undefined}
                      manualSortMode={manualSortMode}
                      onChildrenReorder={(newChildren) => {
                        // Update this specific child's children
                        if (child.children) {
                          // Find the child in the children array and update its children
                          const updatedChildren = children.map(c => 
                            c.id === child.id ? { ...c, children: newChildren } : c
                          );
                          onChildrenReorder?.(updatedChildren);
                        }
                      }}
                    />
                  </Reorder.Item>
                ))}
              </Reorder.Group>
            ) : (
              // Regular non-draggable mode
              children.map((child) => (
                <ContactCard
                  key={child.id}
                  contact={child}
                  children={child.children}
                  level={level + 1}
                  relationshipLevel={relationshipLevel ? relationshipLevel + 1 : undefined}
                  manualSortMode={manualSortMode}
                />
              ))
            )}
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}