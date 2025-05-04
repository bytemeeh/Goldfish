import { useState } from "react";
import { Card, CardHeader, CardContent } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { motion, AnimatePresence } from "framer-motion";
import {
  MoreVertical,
  Mail,
  Phone,
  Cake,
  ChevronDown,
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
}

export function ContactCard({ contact, children = [], level = 0 }: ContactCardProps) {
  // Auto-expand first level contacts
  const [isExpanded, setIsExpanded] = useState(level === 0 && children.length > 0);
  const [isAddingChild, setIsAddingChild] = useState(false);
  const [isEditing, setIsEditing] = useState(false);
  const [isHovered, setIsHovered] = useState(false);
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
  const isMaxDepth = level >= 3;

  // Get relationship icon if available
  const RelationshipIcon = contact.relationshipType ? relationshipIcons[contact.relationshipType] : null;

  // Relationship categories for styling
  const relationshipCategories = {
    family: ["mother", "father", "sibling", "brother", "child", "spouse"],
    friends: ["friend", "boyfriend/girlfriend"],
    professional: ["co-worker"],
  };

  return (
    <div className={`relative ${indentClass} group`}>
      
      {level > 0 && (
        <>
          {/* Connection line with refined styling */}
          <div
            className="absolute -left-12 top-0 bottom-0 w-[1px] bg-border/20"
          />
          <div
            className="absolute -left-12 top-10 w-12 h-[1px] bg-border/20"
          />
          {/* Connection node with subtle styling */}
          <motion.div
            className="absolute -left-[50px] top-[37px] w-2 h-2 rounded-full bg-border/40"
            whileHover={{ scale: 1.2 }}
            transition={{ type: "spring", stiffness: 400, damping: 25 }}
          />
        </>
      )}

      <motion.div
        initial={false}
        animate={{
          scale: isHovered ? 1.01 : 1,
          y: isHovered ? -2 : 0,
        }}
        transition={{
          type: "spring",
          stiffness: 400,
          damping: 25,
        }}
        onHoverStart={() => setIsHovered(true)}
        onHoverEnd={() => setIsHovered(false)}
      >
        <Card
          className={`
            relative
            border
            rounded-lg
            ${level === 0 ? 'shadow-md' : 'shadow-sm hover:shadow-md'}
            transition-all
            duration-300
            ease-in-out
            hover:bg-accent/5
            transform-gpu
            hover:translate-x-1
          `}
        >
          {/* Level indicator */}
          {level > 0 && (
            <div className="absolute -left-6 top-1/2 -translate-y-1/2 flex items-center">
              <div className="flex items-center gap-1">
                {Array.from({ length: level }).map((_, index) => (
                  <div
                    key={index}
                    className="w-1 h-3 rounded-full bg-primary/20"
                  />
                ))}
              </div>
            </div>
          )}

          <CardHeader className="flex flex-row items-start space-x-4 pb-2">
            <motion.button
              className={`
                h-8 w-8 mt-1 flex items-center justify-center
                ${children.length > 0 ? 'text-primary/70 hover:text-primary' : 'text-muted-foreground'}
                transition-all duration-200
                rounded-full
                hover:bg-primary/5
              `}
              onClick={() => setIsExpanded(!isExpanded)}
              whileTap={{ scale: 0.9 }}
              whileHover={{ scale: 1.1 }}
              animate={children.length > 0 ? { rotate: isExpanded ? 0 : -90 } : {}}
            >
              {children.length > 0 ? (
                <ChevronDown className="h-5 w-5" />
              ) : (
                <User className="h-4 w-4" />
              )}
            </motion.button>

            <div className="flex-1 space-y-3">
              <motion.div
                className="flex items-center gap-3"
                animate={{ opacity: 1 }}
                initial={{ opacity: 0 }}
                transition={{ duration: 0.2 }}
              >
                <div className="flex flex-col">
                  <div className="flex items-center gap-2">
                    <h3 className={`
                      ${level === 0 ? 'text-xl font-semibold' : 'text-lg font-medium'}
                      tracking-tight
                      text-foreground
                      leading-none
                    `}>
                      {contact.name}
                    </h3>
                    {level > 0 && (
                      <span className="inline-flex items-center justify-center w-5 h-5 text-xs font-medium bg-primary/10 text-primary rounded-full">
                        L{level}
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
                {isHovered && (
                  <motion.div
                    initial={{ opacity: 0, height: 0 }}
                    animate={{ opacity: 1, height: "auto" }}
                    exit={{ opacity: 0, height: 0 }}
                    className="space-y-2.5 overflow-hidden"
                  >
                    {contact.email && (
                      <motion.div
                        className="flex items-center text-sm text-muted-foreground/90"
                        initial={{ x: -20, opacity: 0 }}
                        animate={{ x: 0, opacity: 1 }}
                        transition={{ delay: 0.1 }}
                      >
                        <Mail className="mr-2 h-4 w-4" />
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
                        className="flex items-center text-sm text-muted-foreground/90"
                        initial={{ x: -20, opacity: 0 }}
                        animate={{ x: 0, opacity: 1 }}
                        transition={{ delay: 0.2 }}
                      >
                        <Phone className="mr-2 h-4 w-4" />
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
                        className="flex items-center text-sm text-muted-foreground/90"
                        initial={{ x: -20, opacity: 0 }}
                        animate={{ x: 0, opacity: 1 }}
                        transition={{ delay: 0.3 }}
                      >
                        <Cake className="mr-2 h-4 w-4" />
                        {format(new Date(contact.birthday), "PPP")}
                      </motion.div>
                    )}
                    {contact.notes && (
                      <motion.p
                        className={`
                          text-sm text-muted-foreground/80 
                          mt-2 pl-4 
                          border-l-2 border-primary/${Math.max(20 - level * 5, 10)}
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
                  onClick={() => setShowDeleteConfirm(true)}
                >
                  Delete
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </CardHeader>

          <CardContent>
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
                className="w-full hover:bg-primary/5 transition-colors rounded-lg group"
                onClick={() => setIsAddingChild(true)}
              >
                <div className="w-6 h-6 rounded-full bg-primary/10 flex items-center justify-center mr-2 group-hover:bg-primary/20 transition-colors">
                  <Plus className="h-4 w-4 text-primary" />
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
            className="space-y-6 mt-6"
          >
            {children.length > 0 && level === 0 && (
              <div className="text-xs font-medium text-muted-foreground/60 uppercase tracking-wider ml-12 mb-2">
                Related Contacts
              </div>
            )}
            {children.map((child) => (
              <ContactCard
                key={child.id}
                contact={child}
                children={child.children}
                level={level + 1}
              />
            ))}
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}