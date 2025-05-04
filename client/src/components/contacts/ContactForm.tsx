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
import { Loader2, Map } from "lucide-react";
import { Textarea } from "@/components/ui/textarea";
import { type Contact, type RelationshipType, type Location } from "@/lib/types";
import { useState } from "react";
import { useMutation, useQueryClient, useQuery } from "@tanstack/react-query";
import { useToast } from "@/hooks/use-toast";
import { RelationshipTypeSelector } from "./RelationshipTypeSelector";
import { LocationList } from "./LocationList";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { ScrollArea } from "@/components/ui/scroll-area";

const contactSchema = z.object({
  name: z.string().min(1, "Name is required"),
  email: z.string().email("Invalid email").optional().or(z.literal('')),
  phone: z.string().optional().or(z.literal('')),
  birthday: z.string().optional().or(z.literal('')),
  notes: z.string().optional().or(z.literal('')),
  parentId: z.number().optional().nullable(),
  relationshipType: z.enum(['sibling', 'mother', 'father', 'brother', 'friend', 'child', 'co-worker', 'spouse', 'boyfriend/girlfriend'] as const).optional().nullable(),
  isMe: z.boolean().optional(),
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
    <Form {...form}>
      <ScrollArea className="h-[calc(100vh-120px)] pr-4">
        <form onSubmit={onSubmit} className="space-y-4">
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
            <p className="text-sm text-muted-foreground">Add multiple locations where you might meet this contact</p>
          </div>
          <LocationList
            locations={locations}
            onChange={setLocations}
          />
        </div>

        <div className="flex justify-end gap-3">
          <Button 
            type="button" 
            variant="outline" 
            onClick={() => onSuccess?.()} 
            disabled={isPending}
          >
            Cancel
          </Button>
          <Button type="submit" disabled={isPending} className="flex items-center gap-2">
            {isPending && <Loader2 className="h-4 w-4 animate-spin" />}
            {isPending ? "Saving..." : initialData?.id ? "Update Contact" : "Add Contact"}
          </Button>
        </div>
      </form>
      </ScrollArea>
    </Form>
  );
}