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
import { Textarea } from "@/components/ui/textarea";
import { type Contact } from "@/lib/types";
import { useMutation, useQueryClient } from "@tanstack/react-query";
import { useToast } from "@/hooks/use-toast";
import { RelationshipTypeSelector } from "./RelationshipTypeSelector";

const contactSchema = z.object({
  name: z.string().min(1, "Name is required"),
  email: z.string().email("Invalid email").optional().or(z.literal('')),
  phone: z.string().optional().or(z.literal('')),
  birthday: z.string().optional().or(z.literal('')),
  notes: z.string().optional().or(z.literal('')),
  parentId: z.number().optional().nullable(),
  relationshipType: z.string().optional().nullable(),
});

interface ContactFormProps {
  onSuccess?: () => void;
  initialData?: Partial<Contact>;
  parentId?: number;
}

export function ContactForm({ onSuccess, initialData, parentId }: ContactFormProps) {
  const queryClient = useQueryClient();
  const { toast } = useToast();

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
    console.log('Submitting form data:', data);
    mutate(data);
  });

  return (
    <Form {...form}>
      <form onSubmit={onSubmit} className="space-y-4">
        <FormField
          control={form.control}
          name="name"
          render={({ field }) => (
            <FormItem>
              <FormLabel>Name *</FormLabel>
              <FormControl>
                <Input {...field} />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />

        {parentId && (
          <FormField
            control={form.control}
            name="relationshipType"
            render={({ field }) => (
              <FormItem>
                <FormLabel>Relationship Type</FormLabel>
                <FormControl>
                  <RelationshipTypeSelector 
                    value={field.value as any} 
                    onChange={field.onChange}
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
              <FormLabel>Email (optional)</FormLabel>
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
              <FormLabel>Phone (optional)</FormLabel>
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
              <FormLabel>Birthday (optional)</FormLabel>
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
              <FormLabel>Notes (optional)</FormLabel>
              <FormControl>
                <Textarea {...field} />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />

        <Button type="submit" disabled={isPending}>
          {isPending ? "Saving..." : initialData?.id ? "Update Contact" : "Add Contact"}
        </Button>
      </form>
    </Form>
  );
}