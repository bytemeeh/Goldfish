import React from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { ArrowLeft, Mail, Phone, Cake, MapPin, Edit, Calendar, StickyNote, User, Heart, Users, Sparkles, Trash2 } from "lucide-react";
import { format } from "date-fns";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog";
import { ContactForm } from "./ContactForm";
import { motion } from "framer-motion";
import type { Contact } from "@/lib/types";
import { ProfilePhoto } from "@/components/ui/ProfilePhoto";
import { getContactColorClasses } from "@/lib/colors";
import { clsx } from "clsx";

interface DetailedContactViewProps {
  contactId: string;
  onBack: () => void;
}

export function DetailedContactView({ contactId, onBack }: DetailedContactViewProps) {
  const [isEditing, setIsEditing] = React.useState(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = React.useState(false);
  const queryClient = useQueryClient();

  // Fetch all contacts to find the selected one
  const { data: contacts, isLoading } = useQuery<Contact[]>({
    queryKey: ["/api/contacts"],
  });

  // Find the specific contact by ID
  const contact = contacts?.find(c => c.id === contactId);

  if (isLoading) {
    return (
      <div className="flex flex-col items-center justify-center min-h-[400px]">
        <div className="animate-pulse h-32 w-32 bg-muted rounded-full mb-6"></div>
        <div className="animate-pulse h-8 w-48 bg-muted rounded mb-4"></div>
        <div className="animate-pulse h-4 w-64 bg-muted rounded mb-8"></div>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-6 w-full max-w-4xl">
          <div className="animate-pulse h-40 bg-muted rounded-xl"></div>
          <div className="animate-pulse h-40 bg-muted rounded-xl"></div>
        </div>
      </div>
    );
  }

  const deleteContact = useMutation({
    mutationFn: async () => {
      const res = await fetch(`/api/contacts/${contactId}`, {
        method: "DELETE",
      });
      if (!res.ok) throw new Error("Failed to delete contact");
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["/api/contacts"] });
      onBack(); // Navigate back after successful delete
    },
  });

  if (!contact) {
    return (
      <div className="text-center py-12">
        <h3 className="text-lg font-medium mb-2">Contact not found</h3>
        <p className="text-muted-foreground mb-6">The requested contact could not be found.</p>
        <Button onClick={onBack}>Go Back</Button>
      </div>
    );
  }

  const colorClasses = getContactColorClasses(contact.color || 'blue');

  return (
    <div className="max-w-4xl mx-auto pb-10">
      {/* Header with back button */}
      <motion.div
        className="flex items-center justify-between mb-6"
        initial={{ opacity: 0, y: -10 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.2 }}
      >
        <Button
          variant="ghost"
          size="sm"
          className="flex items-center gap-2 hover:bg-white/20 hover:text-primary -ml-2"
          onClick={onBack}
        >
          <ArrowLeft className="h-5 w-5" />
          <span className="font-medium">Back to Network</span>
        </Button>

        <div className="flex items-center gap-2">
          {!contact.isMe && (
            <Button
              variant="outline"
              className="flex items-center gap-2 bg-red-50/50 backdrop-blur-sm border-red-200/40 hover:bg-red-100/80 text-red-600 hover:text-red-700"
              onClick={() => setShowDeleteConfirm(true)}
            >
              <Trash2 className="h-4 w-4" />
              <span>Delete</span>
            </Button>
          )}
          <Dialog open={isEditing} onOpenChange={setIsEditing}>
            <DialogTrigger asChild>
              <Button variant="outline" className="flex items-center gap-2 bg-white/50 backdrop-blur-sm border-white/40 hover:bg-white/80">
                <Edit className="h-4 w-4" />
                <span>Edit Profile</span>
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
        </div>
      </motion.div>

      {/* Hero Section - Simplified & Personal */}
      <motion.div
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        transition={{ duration: 0.4 }}
        className="relative mb-8"
      >
        <div className={clsx(
          "absolute inset-0 rounded-3xl opacity-20 blur-3xl",
          contact.color === 'purple' ? 'bg-purple-400' :
            contact.color === 'green' ? 'bg-emerald-400' :
              contact.color === 'pink' ? 'bg-pink-400' :
                'bg-blue-400'
        )} />

        <div className="relative bg-white/40 dark:bg-slate-900/40 backdrop-blur-xl border border-white/50 dark:border-slate-700/50 rounded-3xl p-8 shadow-xl overflow-hidden">
          <div className="flex flex-col md:flex-row items-center gap-8">
            <motion.div
              initial={{ scale: 0.8, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              transition={{ delay: 0.2, type: "spring" }}
              className="relative group"
            >
              <div className={clsx(
                "absolute -inset-1 rounded-full blur opacity-40 group-hover:opacity-60 transition-opacity duration-500",
                contact.color === 'purple' ? 'bg-purple-400' :
                  contact.color === 'green' ? 'bg-emerald-400' :
                    contact.color === 'pink' ? 'bg-pink-400' :
                      'bg-blue-400'
              )} />
              <ProfilePhoto
                photo={contact.photo}
                name={contact.name}
                type={contact.type}
                size="xl"
                className="relative ring-4 ring-white/80 shadow-2xl w-32 h-32 md:w-40 md:h-40 text-3xl"
              />
            </motion.div>

            <div className="flex-1 text-center md:text-left space-y-2">
              <div className="flex flex-col md:flex-row items-center md:items-start gap-3 justify-center md:justify-start">
                <h1 className="text-3xl md:text-4xl font-bold text-slate-900 dark:text-white tracking-tight">
                  {contact.name}
                </h1>
                {contact.relationshipType && (
                  <Badge variant="secondary" className={clsx(
                    "capitalize px-3 py-1 text-sm font-medium border shadow-sm mt-1",
                    colorClasses.bg, colorClasses.text, colorClasses.border
                  )}>
                    {contact.relationshipType}
                  </Badge>
                )}
              </div>

              <p className="text-lg text-muted-foreground max-w-2xl">
                {contact.relationshipType === "mother" ? "Your mother" :
                  contact.relationshipType === "father" ? "Your father" :
                    contact.relationshipType === "brother" ? "Your brother" :
                      contact.relationshipType === "sibling" ? "Your sibling" :
                        contact.relationshipType === "spouse" ? "Your spouse" :
                          contact.relationshipType === "child" ? "Your child" :
                            contact.relationshipType === "co-worker" ? "Your co-worker" :
                              contact.relationshipType === "friend" ? "Your friend" :
                                contact.relationshipType === "boyfriend/girlfriend" ? "Your partner" :
                                  "Part of your network"}
              </p>
            </div>
          </div>
        </div>
      </motion.div>

      {/* Content Tabs */}
      <Tabs defaultValue="context" className="w-full">
        <TabsList className="grid w-full grid-cols-2 mb-6 bg-white/40 backdrop-blur-sm p-1 h-12 rounded-xl">
          <TabsTrigger value="context" className="rounded-lg text-sm font-medium data-[state=active]:bg-white data-[state=active]:shadow-sm">
            <Sparkles className="w-4 h-4 mr-2" />
            Social Context
          </TabsTrigger>
          <TabsTrigger value="info" className="rounded-lg text-sm font-medium data-[state=active]:bg-white data-[state=active]:shadow-sm">
            <User className="w-4 h-4 mr-2" />
            Contact Info
          </TabsTrigger>
        </TabsList>

        <TabsContent value="context" className="space-y-6">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            {/* Left Column: Relationships & Birthday */}
            <div className="space-y-6">
              {/* Relationships Card */}
              <Card className="p-6 border-0 shadow-lg bg-white/60 backdrop-blur-md ring-1 ring-black/5">
                <h3 className="text-lg font-semibold mb-4 flex items-center gap-2 text-slate-800">
                  <Users className="h-5 w-5 text-indigo-500" />
                  Relationships
                </h3>
                <div className="space-y-4">
                  {/* Parent */}
                  {contact.parentId && (
                    <div className="space-y-2">
                      <p className="text-xs font-medium text-muted-foreground uppercase tracking-wider">Reports To / Parent</p>
                      {(() => {
                        const parent = contacts?.find(c => c.id === contact.parentId);
                        return parent ? (
                          <div className="flex items-center gap-3 p-3 rounded-xl bg-white/50 hover:bg-white/80 transition-all cursor-pointer border border-transparent hover:border-indigo-100 group">
                            <ProfilePhoto photo={parent.photo} name={parent.name} type={parent.type} size="sm" />
                            <div>
                              <p className="font-medium text-sm group-hover:text-indigo-700 transition-colors">{parent.name}</p>
                              <Badge variant="outline" className="text-[10px] h-5 px-1.5 bg-white/50">
                                {parent.relationshipType || 'Parent'}
                              </Badge>
                            </div>
                          </div>
                        ) : (
                          <p className="text-sm text-muted-foreground italic">Unknown Parent</p>
                        );
                      })()}
                    </div>
                  )}

                  {/* Children */}
                  {(() => {
                    const children = contacts?.filter(c => c.parentId === contact.id) || [];
                    return children.length > 0 ? (
                      <div className="space-y-2">
                        <p className="text-xs font-medium text-muted-foreground uppercase tracking-wider">
                          Children & Connections ({children.length})
                        </p>
                        <div className="space-y-2">
                          {children.map(child => (
                            <div key={child.id} className="flex items-center gap-3 p-3 rounded-xl bg-white/50 hover:bg-white/80 transition-all cursor-pointer border border-transparent hover:border-indigo-100 group">
                              <ProfilePhoto photo={child.photo} name={child.name} type={child.type} size="sm" />
                              <div>
                                <p className="font-medium text-sm group-hover:text-indigo-700 transition-colors">{child.name}</p>
                                <Badge variant="outline" className="text-[10px] h-5 px-1.5 bg-white/50">
                                  {child.relationshipType || 'Child'}
                                </Badge>
                              </div>
                            </div>
                          ))}
                        </div>
                      </div>
                    ) : null;
                  })()}

                  {!contact.parentId && (!contacts?.some(c => c.parentId === contact.id)) && (
                    <div className="text-sm text-muted-foreground italic p-4 bg-slate-50 rounded-xl text-center">
                      No relationships defined yet.
                      <br />
                      <span className="text-xs">Add connections in the Graph View!</span>
                    </div>
                  )}
                </div>
              </Card>

              {/* Birthday Card - Contextual Importance */}
              {contact.birthday && (
                <Card className="p-6 border-0 shadow-lg bg-gradient-to-br from-pink-50 to-white backdrop-blur-md ring-1 ring-black/5">
                  <h3 className="text-lg font-semibold mb-4 flex items-center gap-2 text-pink-900">
                    <Cake className="h-5 w-5 text-pink-500" />
                    Special Dates
                  </h3>
                  <div className="flex items-center gap-4">
                    <div className="p-3 bg-white text-pink-600 rounded-full shadow-sm">
                      <Calendar className="h-6 w-6" />
                    </div>
                    <div>
                      <p className="text-xs font-medium text-pink-600 uppercase tracking-wider mb-0.5">Birthday</p>
                      <p className="text-lg font-semibold text-slate-900">{format(new Date(contact.birthday), "MMMM d")}</p>
                      <p className="text-sm text-muted-foreground">{format(new Date(contact.birthday), "yyyy")}</p>
                    </div>
                  </div>
                </Card>
              )}
            </div>

            {/* Right Column: Notes & Locations */}
            <div className="space-y-6">
              <Card className="p-6 border-0 shadow-lg bg-yellow-50/80 backdrop-blur-md ring-1 ring-yellow-500/10 h-full">
                <h3 className="text-lg font-semibold mb-4 flex items-center gap-2 text-yellow-900">
                  <StickyNote className="h-5 w-5 text-yellow-600" />
                  Context Notes
                </h3>

                <div className="bg-white/60 border border-yellow-200/50 rounded-xl p-5 min-h-[200px] shadow-sm">
                  {contact.notes ? (
                    <p className="text-slate-800 whitespace-pre-line leading-relaxed font-medium">
                      {contact.notes}
                    </p>
                  ) : (
                    <div className="flex flex-col items-center justify-center h-32 text-center">
                      <p className="text-yellow-700/50 italic text-sm mb-2">No notes added yet...</p>
                      <Button variant="ghost" size="sm" className="text-yellow-700 hover:text-yellow-900 hover:bg-yellow-100" onClick={() => setIsEditing(true)}>
                        Add a note
                      </Button>
                    </div>
                  )}
                </div>
              </Card>
            </div>
          </div>
        </TabsContent>

        <TabsContent value="info">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
            <Card className="p-6 border-0 shadow-lg bg-white/60 backdrop-blur-md ring-1 ring-black/5">
              <h3 className="text-lg font-semibold mb-4 flex items-center gap-2">
                <User className="h-5 w-5 text-slate-400" />
                Contact Details
              </h3>
              <div className="space-y-4">
                <div className="flex items-center gap-3 p-3 rounded-lg bg-white/50">
                  <div className="p-2 bg-slate-100 text-slate-600 rounded-full">
                    <Mail className="h-4 w-4" />
                  </div>
                  <div className="flex-1">
                    <p className="text-xs font-medium text-muted-foreground uppercase tracking-wider">Email</p>
                    {contact.email ? (
                      <a href={`mailto:${contact.email}`} className="font-medium text-blue-600 hover:underline block truncate">
                        {contact.email}
                      </a>
                    ) : (
                      <p className="text-sm text-muted-foreground italic">Not set</p>
                    )}
                  </div>
                </div>

                <div className="flex items-center gap-3 p-3 rounded-lg bg-white/50">
                  <div className="p-2 bg-slate-100 text-slate-600 rounded-full">
                    <Phone className="h-4 w-4" />
                  </div>
                  <div className="flex-1">
                    <p className="text-xs font-medium text-muted-foreground uppercase tracking-wider">Phone</p>
                    {contact.phone ? (
                      <a href={`tel:${contact.phone}`} className="font-medium text-blue-600 hover:underline block">
                        {contact.phone}
                      </a>
                    ) : (
                      <p className="text-sm text-muted-foreground italic">Not set</p>
                    )}
                  </div>
                </div>
              </div>
            </Card>

            <Card className="p-6 border-0 shadow-lg bg-white/60 backdrop-blur-md ring-1 ring-black/5">
              <h3 className="text-lg font-semibold mb-4 flex items-center gap-2">
                <MapPin className="h-5 w-5 text-slate-400" />
                Locations
              </h3>

              <div className="space-y-3">
                {(contact.locations && contact.locations.length > 0) ? (
                  contact.locations.map((location, index) => (
                    <div key={location.id || index} className="flex items-start gap-3 p-3 rounded-lg bg-white/50 hover:bg-white/80 transition-colors">
                      <div className="p-2 bg-emerald-100 text-emerald-600 rounded-full mt-1">
                        <MapPin className="h-4 w-4" />
                      </div>
                      <div>
                        <Badge variant="secondary" className="mb-1 text-[10px] uppercase tracking-wider">{location.type}</Badge>
                        <p className="font-medium text-slate-900">{location.name || location.address}</p>
                        {(location.city || location.state) && (
                          <p className="text-sm text-muted-foreground">
                            {[location.city, location.state, location.country].filter(Boolean).join(", ")}
                          </p>
                        )}
                      </div>
                    </div>
                  ))
                ) : (contact.street || contact.city || contact.state || contact.country) ? (
                  <div className="flex items-start gap-3 p-3 rounded-lg bg-white/50">
                    <div className="p-2 bg-emerald-100 text-emerald-600 rounded-full mt-1">
                      <MapPin className="h-4 w-4" />
                    </div>
                    <div>
                      <p className="font-medium text-slate-900">{contact.street}</p>
                      <p className="text-sm text-muted-foreground">
                        {[contact.city, contact.state, contact.postalCode, contact.country]
                          .filter(Boolean)
                          .join(", ")}
                      </p>
                    </div>
                  </div>
                ) : (
                  <div className="text-sm text-muted-foreground italic p-2">No locations added</div>
                )}
              </div>
            </Card>
          </div>
        </TabsContent>
      </Tabs>

      {/* Delete Confirmation Dialog */}
      <Dialog open={showDeleteConfirm} onOpenChange={setShowDeleteConfirm}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Delete Contact</DialogTitle>
            <DialogDescription>
              Are you sure you want to delete <strong>{contact.name}</strong>? This action cannot be undone.
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
    </div>
  );
}