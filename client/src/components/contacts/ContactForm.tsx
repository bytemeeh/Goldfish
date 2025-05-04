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
import { type Contact, type RelationshipType } from "@/lib/types";
import { useMutation, useQueryClient, useQuery } from "@tanstack/react-query";
import { useToast } from "@/hooks/use-toast";
import { RelationshipTypeSelector } from "./RelationshipTypeSelector";
import { LocationPicker } from "./LocationPicker";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";

const contactSchema = z.object({
  name: z.string().min(1, "Name is required"),
  email: z.string().email("Invalid email").optional().or(z.literal('')),
  phone: z.string().optional().or(z.literal('')),
  birthday: z.string().optional().or(z.literal('')),
  notes: z.string().optional().or(z.literal('')),
  parentId: z.number().optional().nullable(),
  relationshipType: z.enum(['sibling', 'mother', 'father', 'brother', 'friend', 'child', 'co-worker', 'spouse', 'boyfriend/girlfriend'] as const).optional().nullable(),
  isMe: z.boolean().optional(),
  // Location fields
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
    mutationFn: async (data: z.infer<typeof contactSchema>) => {
      const cleanedData = {
        ...data,
        email: data.email || null,
        phone: data.phone || null,
        birthday: data.birthday || null,
        notes: data.notes || null,
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
    mutate({
      ...data,
      relationshipType: data.relationshipType || null,
    });
  });

  return (
    <Form {...form}>
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
          <Tabs defaultValue="map" className="w-full">
            <TabsList className="mb-4 w-full justify-start">
              <TabsTrigger value="map" className="flex items-center gap-2">
                <Map className="h-4 w-4" />
                Map
              </TabsTrigger>
              <TabsTrigger value="address" className="flex items-center gap-2">
                Address Details
              </TabsTrigger>
            </TabsList>
            <TabsContent value="map" className="p-1">
              <div className="mb-2 text-sm text-muted-foreground">
                Select a location by clicking on the map or searching for an address.
              </div>
              <div className="flex gap-4 items-start flex-wrap space-y-0">
                <LocationPicker
                  value={{
                    address: `${form.watch('street') || ''} ${form.watch('city') || ''} ${form.watch('state') || ''} ${form.watch('country') || ''}`.trim(),
                    latitude: form.watch('latitude'),
                    longitude: form.watch('longitude'),
                  }}
                  onChange={(location) => {
                    if (location.address) {
                      // Parse address components from formatted address
                      const addressParts = location.address.split(',').map(part => part.trim());
                      
                      if (addressParts.length >= 3) {
                        form.setValue('street', addressParts[0]);
                        form.setValue('city', addressParts[1]);
                        
                        // Last part might be country or state + postal + country
                        const lastPart = addressParts[addressParts.length-1];
                        form.setValue('country', lastPart);
                        
                        // If we have a state/postal part
                        if (addressParts.length > 3) {
                          const statePostal = addressParts[addressParts.length-2];
                          const statePostalParts = statePostal.split(' ');
                          
                          if (statePostalParts.length > 1) {
                            form.setValue('state', statePostalParts[0]);
                            form.setValue('postalCode', statePostalParts[1]);
                          } else {
                            form.setValue('state', statePostal);
                          }
                        }
                      }
                    }
                    
                    if (location.latitude) form.setValue('latitude', location.latitude);
                    if (location.longitude) form.setValue('longitude', location.longitude);
                  }}
                />
              </div>
            </TabsContent>
            <TabsContent value="address" className="p-1 space-y-4">
              <FormField
                control={form.control}
                name="street"
                render={({ field }) => (
                  <FormItem>
                    <FormLabel>Street Address</FormLabel>
                    <FormControl>
                      <Input {...field} placeholder="123 Main St" />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />
              
              <div className="grid gap-4 grid-cols-2">
                <FormField
                  control={form.control}
                  name="city"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>City</FormLabel>
                      <FormControl>
                        <Input {...field} />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
                
                <FormField
                  control={form.control}
                  name="state"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>State/Province</FormLabel>
                      <FormControl>
                        <Input {...field} />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
              </div>
              
              <div className="grid gap-4 grid-cols-2">
                <FormField
                  control={form.control}
                  name="postalCode"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Postal Code</FormLabel>
                      <FormControl>
                        <Input {...field} />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
                
                <FormField
                  control={form.control}
                  name="country"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Country</FormLabel>
                      <FormControl>
                        <Input {...field} />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
              </div>
              
              <div className="grid gap-4 grid-cols-2">
                <FormField
                  control={form.control}
                  name="latitude"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Latitude</FormLabel>
                      <FormControl>
                        <Input {...field} readOnly className="bg-muted/40" />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
                
                <FormField
                  control={form.control}
                  name="longitude"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>Longitude</FormLabel>
                      <FormControl>
                        <Input {...field} readOnly className="bg-muted/40" />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
              </div>
            </TabsContent>
          </Tabs>
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
    </Form>
  );
}