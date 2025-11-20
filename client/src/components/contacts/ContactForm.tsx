import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import {
  Form,
  FormControl,
  FormField,
  FormItem,
  FormLabel,
  FormMessage,
} from "@/components/ui/form";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Loader2, Map, Sparkles, UserCircle2, PawPrint, Trash2 } from "lucide-react";
import { VoiceInput } from "@/components/ai/VoiceInput";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
  DialogFooter,
} from "@/components/ui/dialog";
import { Textarea } from "@/components/ui/textarea";
import { type Contact, type RelationshipType, type Location } from "@/lib/types";
import { useState, useEffect } from "react";
import { useMutation, useQueryClient, useQuery } from "@tanstack/react-query";
import { useToast } from "@/hooks/use-toast";
import { RelationshipTypeSelector } from "./RelationshipTypeSelector";
import { LocationList } from "./LocationList";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { ColorPicker } from "@/components/ui/color-picker";
import { PhotoUpload } from "@/components/ui/PhotoUpload";
import { PermissionPrimingDialog } from "@/components/ui/PermissionPrimingDialog";

const contactSchema = z.object({
  name: z.string().min(1, "Name is required"),
  type: z.enum(['person', 'pet']).default('person'),
  contextNotes: z.string().optional().nullable(),
  email: z.string().email("Invalid email").optional().or(z.literal('')),
  phone: z.string().optional().or(z.literal('')),
  birthday: z.string().optional().or(z.literal('')),
  notes: z.string().optional().or(z.literal('')),
  parentId: z.string().optional().nullable(),
  relationshipType: z.string().optional().nullable(), // Relaxed validation for custom types
  relationshipToUser: z.string().optional().nullable(),
  isMe: z.boolean().optional(),
  color: z.string().optional(),
  photo: z.string().optional().nullable(),
  // Legacy location fields
  street: z.string().optional().nullable(),
  city: z.string().optional().nullable(),
  state: z.string().optional().nullable(),
  country: z.string().optional().nullable(),
  postalCode: z.string().optional().nullable(),
  latitude: z.string().optional().nullable(),
  longitude: z.string().optional().nullable(),
});

interface ContactFormProps {
  onSuccess?: () => void;
  initialData?: Partial<Contact>;
  parentId?: string;
  isPersonalCard?: boolean;
}

export function ContactForm({ onSuccess, initialData, parentId, isPersonalCard }: ContactFormProps) {
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const [locations, setLocations] = useState<Location[]>(initialData?.locations || []);
  const [isVoiceProcessing, setIsVoiceProcessing] = useState(false);
  const [voiceTranscription, setVoiceTranscription] = useState<string>("");
  const [isVoiceActive, setIsVoiceActive] = useState(false);
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [showLocationPermissionDialog, setShowLocationPermissionDialog] = useState(false);

  const form = useForm<z.infer<typeof contactSchema>>({
    resolver: zodResolver(contactSchema),
    defaultValues: {
      name: initialData?.name || "",
      type: initialData?.type || "person",
      contextNotes: initialData?.contextNotes || "",
      email: initialData?.email || "",
      phone: initialData?.phone || "",
      birthday: initialData?.birthday || "",
      notes: initialData?.notes || "",
      parentId: parentId || initialData?.parentId || null,
      relationshipType: initialData?.relationshipType || null,
      relationshipToUser: initialData?.relationshipToUser || null,
      isMe: isPersonalCard || initialData?.isMe || false,
      color: initialData?.color || "blue",
      photo: initialData?.photo || null,
      // Location fields
      street: initialData?.street || "",
      city: initialData?.city || "",
      state: initialData?.state || "",
      country: initialData?.country || "",
      postalCode: initialData?.postalCode || "",
      latitude: initialData?.latitude || null,
      longitude: initialData?.longitude || null,
    },
  });

  // Auto-set type based on relationship
  useEffect(() => {
    const subscription = form.watch((value, { name }) => {
      if (name === 'relationshipType') {
        if (value.relationshipType === 'pet') {
          form.setValue('type', 'pet');
        } else {
          form.setValue('type', 'person');
        }
      }
    });
    return () => subscription.unsubscribe();
  }, [form]);

  // For personal card, automatically use current location
  // For personal card, automatically prompt for location if none exists
  useEffect(() => {
    // Only do this for personal card and when no locations exist
    if (isPersonalCard && locations.length === 0) {
      // Instead of immediately asking, show the priming dialog
      setShowLocationPermissionDialog(true);
    }
  }, [isPersonalCard, locations.length]);

  const handleLocationPermissionContinue = () => {
    setShowLocationPermissionDialog(false);
    // Check if browser supports geolocation
    if (navigator.geolocation) {
      navigator.geolocation.getCurrentPosition(
        (position) => {
          // Create a new location with current coordinates
          const currentLocation: Location = {
            type: 'home',
            name: 'My Location',
            address: 'Current Location',
            latitude: position.coords.latitude.toString(),
            longitude: position.coords.longitude.toString(),
            isNew: true
          };

          // Add to locations
          setLocations([currentLocation]);

          toast({
            title: "Location detected",
            description: "Your current location has been set as the default.",
          });
        },
        (error) => {
          console.error("Error getting location:", error);
          toast({
            title: "Location Error",
            description: "Could not get your current location. You can add it manually.",
            variant: "destructive"
          });
        }
      );
    }
  };

  // Fetch parent contact if parentId is provided
  const { data: parentContact } = useQuery<Contact & { validChildTypes: RelationshipType[] }>({
    queryKey: [`/api/contacts/${parentId}`],
    enabled: !!parentId,
  });

  // Voice processing handlers
  const handleVoiceTranscription = (text: string) => {
    setVoiceTranscription(text);
  };

  const handleVoiceProcessingComplete = (result: any) => {
    if (result.type === 'contact_created') {
      // The contact was created on the server, refresh the data
      queryClient.invalidateQueries({ queryKey: ['/api/contacts'] });
      onSuccess?.();
      toast({
        title: "Contact created via voice",
        description: `${result.contact.name} has been added to your contacts.`
      });
    } else if (result.type === 'contact_extracted') {
      // Fill the form with extracted data
      const contact = result.contact;
      form.setValue('name', contact.name || '');
      form.setValue('phone', contact.phone || '');
      form.setValue('email', contact.email || '');
      form.setValue('birthday', contact.birthday || '');
      form.setValue('notes', contact.notes || '');
      form.setValue('color', contact.color || 'blue');
      if (contact.relationshipType) {
        form.setValue('relationshipType', contact.relationshipType);
      }

      toast({
        title: "Contact details extracted",
        description: "Voice input has been processed and form fields filled."
      });
    }
    setIsVoiceProcessing(false);
  };

  const { mutate, isPending } = useMutation({
    mutationFn: async (data: any) => {
      // Clean the form data - type is 'any' to accommodate for locations array
      const cleanedData = {
        ...data,
        type: data.type || 'person',
        contextNotes: data.contextNotes || null,
        email: data.email || null,
        phone: data.phone || null,
        birthday: data.birthday || null,
        notes: data.notes || null,
        // Legacy location fields
        street: data.street || null,
        city: data.city || null,
        state: data.state || null,
        postalCode: data.postalCode || null,
        country: data.country || null,
        latitude: data.latitude || null,
        longitude: data.longitude || null,
        // Ensure locations data is properly formatted
        locations: data.locations?.map((loc: Location) => ({
          ...loc,
          contactId: initialData?.id || undefined,
          // Convert latitude/longitude to strings if they're numbers
          latitude: loc.latitude?.toString() || "",
          longitude: loc.longitude?.toString() || "",
        })),
      };

      const url = initialData?.id
        ? `/api/contacts/${initialData.id}`
        : "/api/contacts";

      const res = await fetch(url, {
        method: initialData?.id ? "PUT" : "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(cleanedData),
        credentials: 'include',
      });

      if (!res.ok) {
        const errorData = await res.json();
        throw new Error(errorData.message || "Failed to save contact");
      }

      return res.json();
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["/api/contacts"] });
      toast({
        title: "Success",
        description: initialData?.id ? "Contact updated" : "Contact created",
      });
      onSuccess?.();
    },
    onError: (error: Error) => {
      console.error('Form submission error:', error);
      toast({
        title: "Error",
        description: error.message,
        variant: "destructive",
      });
    },
  });

  const deleteContact = useMutation({
    mutationFn: async () => {
      if (!initialData?.id) throw new Error("No contact ID");
      const res = await fetch(`/api/contacts/${initialData.id}`, {
        method: "DELETE",
      });
      if (!res.ok) throw new Error("Failed to delete contact");
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ["/api/contacts"] });
      toast({
        title: "Success",
        description: "Contact deleted",
      });
      onSuccess?.();
    },
    onError: (error: Error) => {
      toast({
        title: "Error",
        description: error.message,
        variant: "destructive",
      });
    },
  });

  const onSubmit = form.handleSubmit((data) => {
    // Prepare form data for submission
    const formData = {
      ...data,
      relationshipType: data.relationshipType || null,
      relationshipToUser: data.relationshipToUser || null,
      // Include legacy location fields for backward compatibility
      street: data.street || null,
      city: data.city || null,
      state: data.state || null,
      postalCode: data.postalCode || null,
      country: data.country || null,
      latitude: data.latitude || null,
      longitude: data.longitude || null,
    };

    // Process locations separately (avoiding type errors with Zod schema)
    const submissionData = {
      ...formData,
      locations: locations.filter(loc => !loc.isDeleted), // Only submit non-deleted locations
    };

    mutate(submissionData as any); // Type cast to avoid TypeScript errors
  });

  return (
    <div className="relative flex flex-col h-full">
      <Form {...form}>
        <form id="contact-form" onSubmit={onSubmit} className="space-y-5 pr-2 pt-2 pb-2 overflow-y-auto px-1 flex-1 min-h-0">
          {/* Header / Name Input */}
          <div className="space-y-4">
            <div className="flex items-start gap-4">
              <div className="flex-shrink-0 mt-1">
                <FormField
                  control={form.control}
                  name="photo"
                  render={({ field }) => (
                    <FormItem>
                      <FormControl>
                        <PhotoUpload
                          currentPhoto={field.value || undefined}
                          onPhotoChange={field.onChange}
                          className="w-16 h-16"
                        />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
              </div>
              <div className="flex-grow space-y-2">
                <FormField
                  control={form.control}
                  name="name"
                  render={({ field }) => (
                    <FormItem className="space-y-0">
                      <FormControl>
                        <Input
                          {...field}
                          className="text-lg font-medium border-0 border-b border-input rounded-none px-0 focus-visible:ring-0 focus-visible:border-primary placeholder:text-muted-foreground/50"
                          placeholder="Name"
                        />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />

                {/* Voice Input Toggle - HIDDEN FOR INITIAL RELEASE
                {!isVoiceActive ? (
                  <button
                    type="button"
                    onClick={() => setIsVoiceActive(true)}
                    className="flex items-center gap-1.5 text-xs text-muted-foreground hover:text-primary transition-colors"
                  >
                    <Sparkles className="w-3 h-3" />
                    <span>Fill with AI Voice</span>
                  </button>
                ) : (
                  <div className="bg-blue-50/50 rounded-lg p-2 border border-blue-100 animate-in fade-in slide-in-from-top-2">
                    <div className="flex items-center justify-between mb-2">
                      <span className="text-xs font-medium text-blue-700 flex items-center gap-1">
                        <Sparkles className="w-3 h-3" /> Voice Input
                      </span>
                      <button
                        onClick={() => setIsVoiceActive(false)}
                        className="text-[10px] text-blue-500 hover:text-blue-700"
                      >
                        Close
                      </button>
                    </div>
                    <VoiceInput
                      onTranscription={handleVoiceTranscription}
                      onProcessingComplete={handleVoiceProcessingComplete}
                      placeholder="Speak details..."
                      mode="contact"
                      isProcessing={isVoiceProcessing}
                      className="text-xs"
                    />
                    {voiceTranscription && (
                      <p className="text-[10px] text-muted-foreground mt-1 italic">"{voiceTranscription}"</p>
                    )}
                  </div>
                )}
                */}
              </div>
            </div>
          </div>

          {/* Relationship Section */}
          {!isPersonalCard && (
            <div className="space-y-3 bg-slate-50/50 p-3 rounded-xl border border-slate-100">
              {/* Relationship to Parent (if exists) */}
              {parentId && (
                <FormField
                  control={form.control}
                  name="relationshipType"
                  render={({ field }) => (
                    <FormItem className="space-y-2">
                      <FormLabel className="text-xs uppercase tracking-wider text-muted-foreground font-semibold">
                        Relationship to {parentContact?.name || 'parent'}
                      </FormLabel>
                      <FormControl>
                        <RelationshipTypeSelector
                          value={field.value as RelationshipType}
                          onChange={field.onChange}
                          parentContact={parentContact}
                          validChildTypes={parentContact?.validChildTypes}
                        />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
              )}

              {/* Relationship to User (Always shown for non-personal cards) */}
              <FormField
                control={form.control}
                name="relationshipToUser"
                render={({ field }) => (
                  <FormItem className="space-y-2">
                    <FormLabel className="text-xs uppercase tracking-wider text-muted-foreground font-semibold">
                      Relationship to You
                    </FormLabel>
                    <FormControl>
                      <RelationshipTypeSelector
                        value={field.value as RelationshipType}
                        onChange={field.onChange}
                      // For direct relationship to user, we don't restrict types based on parent
                      />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />

              <FormField
                control={form.control}
                name="contextNotes"
                render={({ field }) => (
                  <FormItem className="space-y-1">
                    <FormControl>
                      <Input
                        placeholder={parentId ? `Context (e.g. "Met at ${parentContact?.name}'s wedding")` : 'Context (e.g. "College roommate")'}
                        {...field}
                        value={field.value || ''}
                        className="bg-white border-slate-200 text-sm h-8"
                      />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />
            </div>
          )}

          {/* Details Tabs */}
          <Tabs defaultValue="details" className="w-full">
            <TabsList className="grid w-full grid-cols-2 h-8">
              <TabsTrigger value="details" className="text-xs">Contact Details</TabsTrigger>
              <TabsTrigger value="notes" className="text-xs">Notes & More</TabsTrigger>
            </TabsList>

            <TabsContent value="details" className="space-y-3 pt-2">
              <div className="grid grid-cols-2 gap-3">
                <FormField
                  control={form.control}
                  name="email"
                  render={({ field }) => (
                    <FormItem className="space-y-1">
                      <FormLabel className="text-xs">Email</FormLabel>
                      <FormControl>
                        <Input type="email" {...field} className="h-8" />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />

                <FormField
                  control={form.control}
                  name="phone"
                  render={({ field }) => (
                    <FormItem className="space-y-1">
                      <FormLabel className="text-xs">Phone</FormLabel>
                      <FormControl>
                        <Input {...field} className="h-8" />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
              </div>

              <div className="space-y-1">
                <div className="flex items-center justify-between">
                  <h3 className="text-xs font-medium">Locations</h3>
                  {isPersonalCard && (
                    <span className="text-[10px] text-muted-foreground">Current location used by default</span>
                  )}
                </div>
                <LocationList
                  locations={locations}
                  onChange={setLocations}
                  disabled={isPersonalCard && locations.length > 0}
                />
              </div>
            </TabsContent>

            <TabsContent value="notes" className="space-y-3 pt-2">
              <div className="grid grid-cols-2 gap-3">
                <FormField
                  control={form.control}
                  name="birthday"
                  render={({ field }) => (
                    <FormItem className="space-y-1">
                      <FormLabel className="text-xs">Birthday</FormLabel>
                      <FormControl>
                        <Input type="date" {...field} className="h-8" />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />

                <FormField
                  control={form.control}
                  name="color"
                  render={({ field }) => (
                    <FormItem className="space-y-1">
                      <FormLabel className="text-xs">Card Color</FormLabel>
                      <FormControl>
                        <ColorPicker
                          value={field.value}
                          onValueChange={field.onChange}
                        />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
              </div>

              <FormField
                control={form.control}
                name="notes"
                render={({ field }) => (
                  <FormItem className="space-y-1">
                    <FormLabel className="text-xs">Detailed Notes</FormLabel>
                    <FormControl>
                      <Textarea {...field} className="min-h-[80px] resize-none" />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />
            </TabsContent>
          </Tabs>

          <div className="h-14"></div>
        </form>
      </Form>

      <div className="flex justify-between gap-2 py-3 px-4 border-t bg-background/80 backdrop-blur-sm sticky bottom-0 left-0 right-0">
        {/* Delete button on the left - only show when editing existing contact */}
        {initialData?.id && !initialData.isMe ? (
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={() => setShowDeleteConfirm(true)}
            disabled={isPending || deleteContact.isPending}
            className="text-red-600 hover:text-red-700 hover:bg-red-50"
          >
            <Trash2 className="h-3 w-3 mr-1.5" />
            Delete
          </Button>
        ) : (
          <div></div>
        )}

        {/* Right side buttons */}
        <div className="flex gap-2">
          <Button
            type="button"
            variant="ghost"
            size="sm"
            onClick={() => onSuccess?.()}
            disabled={isPending || deleteContact.isPending}
          >
            Cancel
          </Button>
          <Button
            onClick={onSubmit}
            disabled={isPending || deleteContact.isPending}
            size="sm"
            className="flex items-center gap-2"
          >
            {isPending && <Loader2 className="h-3 w-3 animate-spin" />}
            {isPending ? "Saving..." : initialData?.id ? "Update" : "Add Contact"}
          </Button>
        </div>
      </div>

      {/* Delete Confirmation Dialog */}
      <Dialog open={showDeleteConfirm} onOpenChange={setShowDeleteConfirm}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Delete Contact</DialogTitle>
            <DialogDescription>
              Are you sure you want to delete <strong>{initialData?.name}</strong>? This action cannot be undone.
            </DialogDescription>
          </DialogHeader>
          <DialogFooter className="gap-2 sm:gap-0">
            <Button
              variant="outline"
              onClick={() => setShowDeleteConfirm(false)}
              disabled={deleteContact.isPending}
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

      <PermissionPrimingDialog
        open={showLocationPermissionDialog}
        onOpenChange={setShowLocationPermissionDialog}
        permissionType="location"
        onContinue={handleLocationPermissionContinue}
        onCancel={() => setShowLocationPermissionDialog(false)}
      />
    </div>
  );
}