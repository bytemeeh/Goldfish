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

  // Enhance visual hierarchy with level-based styling
  const indentClass = level > 0 ? `ml-${Math.min(level * 24, 72)}` : '';
  const bgOpacity = Math.min((level + 1) * 3, 15); // Subtle background changes
  const borderOpacity = Math.max(85 - level * 10, 40); // Gradual border fading

  // Maximum depth is 4 levels (0-based index, so level 3 is the 4th layer)
  const isMaxDepth = level >= 3;

  return (
    <div className={`relative ${indentClass}`}>
      {level > 0 && (
        <>
          {/* Enhanced connection lines with refined gradients */}
          <div
            className="absolute -left-12 top-0 bottom-0 w-[1px]"
            style={{
              background: `linear-gradient(180deg, 
                hsl(var(--primary)/${Math.max(40 - level * 8, 20)}%) 0%,
                hsl(var(--primary)/${Math.max(30 - level * 8, 15)}%) 100%)`
            }}
          />
          <div
            className="absolute -left-12 top-8 w-12 h-[1px]"
            style={{
              background: `linear-gradient(90deg, 
                hsl(var(--primary)/${Math.max(40 - level * 8, 20)}%) 0%,
                hsl(var(--primary)/${Math.max(30 - level * 8, 15)}%) 100%)`
            }}
          />
          {/* Connection node with subtle animation */}
          <motion.div
            className="absolute -left-[50px] top-[29px] w-3 h-3 rounded-full border bg-background"
            style={{
              borderColor: `hsl(var(--primary)/${Math.max(40 - level * 8, 20)}%)`
            }}
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
            border-l-[3px]
            border-l-primary/${borderOpacity}
            hover:border-l-primary/${Math.min(borderOpacity + 20, 100)}
            transition-all duration-300 ease-in-out
            bg-background/[0.${bgOpacity}]
            backdrop-blur-sm
            rounded-lg
            ${level === 0 ? 'shadow-md' : `shadow-sm hover:shadow-md`}
            transform-gpu
            hover:translate-x-1
          `}
          style={{
            borderColor: `hsl(var(--border)/${Math.max(20 - level * 5, 8)}%)`
          }}
        >
          <CardHeader className="flex flex-row items-start space-x-4 pb-2">
            <motion.button
              className={`
                h-6 w-6 mt-1
                ${children.length > 0 ? 'text-primary/70 hover:text-primary' : 'text-muted-foreground'}
                transition-all duration-200
              `}
              onClick={() => setIsExpanded(!isExpanded)}
              whileTap={{ scale: 0.9 }}
              whileHover={{ scale: 1.1 }}
              animate={{ rotate: isExpanded ? 0 : -90 }}
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
                <h3
                  className={`
                    text-lg font-medium tracking-tight leading-none
                    ${level === 0
                      ? 'text-foreground'
                      : `text-foreground/[0.${Math.max(90 - level * 10, 60)}]`}
                  `}
                >
                  {contact.name}
                </h3>
                {contact.relationshipType && (
                  <Badge
                    variant="outline"
                    className={`
                      capitalize font-normal 
                      bg-primary/${Math.max(10 - level * 2, 5)}
                      text-primary/${Math.max(70 - level * 10, 40)}
                      border-0
                    `}
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
                  onClick={() => deleteContact.mutate()}
                >
                  Delete
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </CardHeader>

          <CardContent>
            {isMaxDepth ? (
              <div className="flex items-center justify-center p-4 bg-muted/20 rounded-lg backdrop-blur-sm border border-primary/10">
                <AlertCircle className="h-4 w-4 text-primary/40 mr-2" />
                <span className="text-sm text-muted-foreground/70 font-medium">
                  Maximum relationship depth reached
                </span>
              </div>
            ) : (
              <Button
                variant="outline"
                size="sm"
                className={`
                  w-full 
                  hover:bg-primary/5 
                  transition-colors 
                  rounded-lg 
                  border-primary/${Math.max(20 - level * 5, 10)}
                `}
                onClick={() => setIsAddingChild(true)}
              >
                <motion.div
                  className="w-6 h-6 rounded-full bg-primary/10 flex items-center justify-center mr-2"
                  whileHover={{ scale: 1.1 }}
                  whileTap={{ scale: 0.95 }}
                  transition={{
                    type: "spring",
                    stiffness: 400,
                    damping: 25
                  }}
                >
                  <Plus className="h-4 w-4 text-primary" />
                </motion.div>
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
            className="space-y-6 mt-6"
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