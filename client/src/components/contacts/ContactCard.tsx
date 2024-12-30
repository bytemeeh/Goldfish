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
  ChevronRight,
  Plus,
  User,
  AlertCircle,
  Calendar,
  Clock,
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
  const [isHovered, setIsHovered] = useState(false);
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

      <motion.div
        initial={false}
        animate={{
          scale: isHovered ? 1.02 : 1,
          y: isHovered ? -4 : 0,
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
            transform-gpu
          `}
        >
          <CardHeader className="flex flex-row items-start space-x-4 pb-2">
            <motion.button
              className={`
                h-6 w-6 mt-1
                ${children.length > 0 ? 'text-primary hover:text-primary/80' : 'text-muted-foreground'}
                transition-transform duration-200
                ${isExpanded ? 'rotate-0' : '-rotate-90'}
              `}
              onClick={() => setIsExpanded(!isExpanded)}
              whileTap={{ scale: 0.9 }}
              whileHover={{ scale: 1.1 }}
            >
              {children.length > 0 ? (
                <ChevronDown className="h-5 w-5" />
              ) : (
                <User className="h-4 w-4" />
              )}
            </motion.button>

            <div className="flex-1 space-y-2">
              <motion.div 
                className="flex items-center gap-2"
                animate={{ opacity: 1 }}
                initial={{ opacity: 0 }}
                transition={{ duration: 0.2 }}
              >
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
              </motion.div>

              <AnimatePresence>
                {isHovered && (
                  <motion.div
                    initial={{ opacity: 0, height: 0 }}
                    animate={{ opacity: 1, height: "auto" }}
                    exit={{ opacity: 0, height: 0 }}
                    className="space-y-2 overflow-hidden"
                  >
                    {contact.email && (
                      <motion.div 
                        className="flex items-center text-sm text-muted-foreground"
                        initial={{ x: -20, opacity: 0 }}
                        animate={{ x: 0, opacity: 1 }}
                        transition={{ delay: 0.1 }}
                      >
                        <Mail className="mr-2 h-4 w-4" />
                        <a href={`mailto:${contact.email}`} className="hover:text-primary transition-colors">
                          {contact.email}
                        </a>
                      </motion.div>
                    )}
                    {contact.phone && (
                      <motion.div 
                        className="flex items-center text-sm text-muted-foreground"
                        initial={{ x: -20, opacity: 0 }}
                        animate={{ x: 0, opacity: 1 }}
                        transition={{ delay: 0.2 }}
                      >
                        <Phone className="mr-2 h-4 w-4" />
                        <a href={`tel:${contact.phone}`} className="hover:text-primary transition-colors">
                          {contact.phone}
                        </a>
                      </motion.div>
                    )}
                    {contact.birthday && (
                      <motion.div 
                        className="flex items-center text-sm text-muted-foreground"
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
                        className="text-sm text-muted-foreground mt-2 pl-6 border-l-2 border-primary/20"
                        initial={{ y: -10, opacity: 0 }}
                        animate={{ y: 0, opacity: 1 }}
                        transition={{ delay: 0.4 }}
                      >
                        {contact.notes}
                      </motion.p>
                    )}
                    {(contact.createdAt || contact.updatedAt) && (
                      <motion.div 
                        className="flex flex-col gap-1 text-xs text-muted-foreground/60 mt-3"
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
                  onClick={() => deleteContact.mutate()}
                >
                  Delete
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </CardHeader>

          <CardContent>
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
      </motion.div>

      <AnimatePresence>
        {isExpanded && children.length > 0 && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: "auto" }}
            exit={{ opacity: 0, height: 0 }}
            className="space-y-8 mt-8"
          >
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