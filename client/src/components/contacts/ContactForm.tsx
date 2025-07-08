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
import { Loader2, Map, Sparkles } from "lucide-react";
import { VoiceInput } from "@/components/ai/VoiceInput";
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

const contactSchema = z.object({
  name: z.string().min(1, "Name is required"),
  email: z.string().email("Invalid email").optional().or(z.literal('')),
  phone: z.string().optional().or(z.literal('')),
  birthday: z.string().optional().or(z.literal('')),
  notes: z.string().optional().or(z.literal('')),
  parentId: z.number().optional().nullable(),
  relationshipType: z.enum(['sibling', 'mother', 'father', 'brother', 'friend', 'child', 'co-worker', 'spouse', 'boyfriend/girlfriend'] as const).optional().nullable(),
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
  parentId?: number;
  isPersonalCard?: boolean;
}

export function ContactForm({ onSuccess, initialData, parentId, isPersonalCard }: ContactFormProps) {
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const [locations, setLocations] = useState<Location[]>(initialData?.locations || []);
  const [isVoiceProcessing, setIsVoiceProcessing] = useState(false);
  const [voiceTranscription, setVoiceTranscription] = useState<string>("");
  
  // For personal card, automatically use current location
  useEffect(() => {
    // Only do this for personal card and when no locations exist
    if (isPersonalCard && locations.length === 0) {
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
    }
  }, [isPersonalCard, locations.length, toast]);

  // Fetch parent contact if parentId is provided
  const { data: parentContact } = useQuery<Contact & { validChildTypes: RelationshipType[] }>({
    queryKey: ['/api/contacts', parentId],
    enabled: !!parentId,
  });

  const form = useForm<z.infer<typeof contactSchema>>({
    resolver: zodResolver(contactSchema),
    defaultValues: {
      name: initialData?.name || "",
      email: initialData?.email || "",
      phone: initialData?.phone || "",
      birthday: initialData?.birthday || "",
      notes: initialData?.notes || "",
      parentId: parentId || initialData?.parentId || null,
      relationshipType: initialData?.relationshipType || null,
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

  const onSubmit = form.handleSubmit((data) => {
    // Prepare form data for submission
    const formData = {
      ...data,
      relationshipType: data.relationshipType || null,
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
    <div className="relative flex flex-col max-h-[70vh]">
      <Form {...form}>
        <form id="contact-form" onSubmit={onSubmit} className="space-y-4 pr-2 pb-2 overflow-y-auto">
          
          {/* Voice Input Section */}
          <div className="bg-gradient-to-r from-blue-50 to-purple-50 rounded-lg p-4 border border-blue-200">
            <div className="flex items-center justify-between mb-3">
              <div className="flex items-center space-x-2">
                <Sparkles className="h-5 w-5 text-blue-600" />
                <h3 className="text-sm font-medium text-blue-900">AI Voice Input</h3>
              </div>
              <VoiceInput 
                onTranscription={handleVoiceTranscription}
                onProcessingComplete={handleVoiceProcessingComplete}
                placeholder="Speak contact details..."
                mode="contact"
                isProcessing={isVoiceProcessing}
                className="text-xs"
              />
            </div>
            {voiceTranscription && (
              <div className="text-xs text-gray-600 bg-white p-2 rounded border">
                <strong>Transcription:</strong> "{voiceTranscription}"
              </div>
            )}
          </div>

          <FormField
            control={form.control}
            name="name"
            render={({ field }) => (
              <FormItem>
                <FormLabel>Name {isPersonalCard ? "(You)" : "*"}</FormLabel>
                <FormControl>
                  <Input {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />

          {!isPersonalCard && (
            <FormField
              control={form.control}
              name="relationshipType"
              render={({ field }) => (
                <FormItem>
                  <FormLabel>
                    Relationship Type {parentId ? `(to ${parentContact?.name || 'parent contact'})` : "(to you)"}
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

          <FormField
            control={form.control}
            name="color"
            render={({ field }) => (
              <FormItem>
                <FormLabel>Card Color</FormLabel>
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

          <FormField
            control={form.control}
            name="photo"
            render={({ field }) => (
              <FormItem>
                <FormLabel>Profile Photo</FormLabel>
                <FormControl>
                  <PhotoUpload
                    currentPhoto={field.value || undefined}
                    onPhotoChange={field.onChange}
                  />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />

          <FormField
            control={form.control}
            name="email"
            render={({ field }) => (
              <FormItem>
                <FormLabel>Email</FormLabel>
                <FormControl>
                  <Input type="email" {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />

          <FormField
            control={form.control}
            name="phone"
            render={({ field }) => (
              <FormItem>
                <FormLabel>Phone</FormLabel>
                <FormControl>
                  <Input {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />

          <FormField
            control={form.control}
            name="birthday"
            render={({ field }) => (
              <FormItem>
                <FormLabel>Birthday</FormLabel>
                <FormControl>
                  <Input type="date" {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />

          <FormField
            control={form.control}
            name="notes"
            render={({ field }) => (
              <FormItem>
                <FormLabel>Notes</FormLabel>
                <FormControl>
                  <Textarea {...field} />
                </FormControl>
                <FormMessage />
              </FormItem>
            )}
          />

          <div className="pt-2">
            <div className="pb-2 border-b mb-4">
              <h3 className="text-base font-medium">Locations</h3>
              {isPersonalCard ? (
                <p className="text-sm text-muted-foreground">
                  Your current location will be used by default
                </p>
              ) : (
                <p className="text-sm text-muted-foreground">
                  Add multiple locations where you might meet this contact
                </p>
              )}
            </div>
            <LocationList
              locations={locations}
              onChange={setLocations}
              disabled={isPersonalCard && locations.length > 0} // Disable adding multiple locations for personal card
            />
          </div>

          <div className="h-14"></div> {/* Spacer to ensure content isn't hidden behind the fixed button row */}
        </form>
      </Form>
      
      <div className="flex justify-end gap-3 py-3 px-4 border-t bg-background/80 backdrop-blur-sm sticky bottom-0 left-0 right-0">
        <Button 
          type="button" 
          variant="outline" 
          onClick={() => onSuccess?.()} 
          disabled={isPending}
        >
          Cancel
        </Button>
        <Button 
          onClick={onSubmit}
          disabled={isPending} 
          className="flex items-center gap-2"
        >
          {isPending && <Loader2 className="h-4 w-4 animate-spin" />}
          {isPending ? "Saving..." : initialData?.id ? "Update Contact" : "Add Contact"}
        </Button>
      </div>
    </div>
  );
}