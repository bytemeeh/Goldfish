import { useQuery } from "@tanstack/react-query";
import { ContactCard } from "./ContactCard";
import { type Contact } from "@/lib/types";
import { ScrollArea } from "@/components/ui/scroll-area";
import type { SearchFilters } from "./SearchBar";
import { useToast } from "@/hooks/use-toast";
import { Card } from "@/components/ui/card";

interface ContactListProps {
  searchFilters: SearchFilters;
}

export function ContactList({ searchFilters }: ContactListProps) {
  const { toast } = useToast();

  const { data: contacts, isLoading, error } = useQuery<Contact[]>({
    queryKey: ["/api/contacts", searchFilters],
    queryFn: async () => {
      const params = new URLSearchParams();
      Object.entries(searchFilters).forEach(([key, value]) => {
        if (value) params.append(key, value.trim());
      });

      const url = `/api/contacts${params.toString() ? `?${params}` : ''}`;
      const res = await fetch(url);

      if (!res.ok) {
        const error = await res.text();
        throw new Error(error);
      }

      return res.json();
    },
    onError: (error) => {
      toast({
        title: "Error",
        description: error instanceof Error ? error.message : "Failed to fetch contacts",
        variant: "destructive",
      });
    },
  });

  if (isLoading) {
    return (
      <div className="p-4 text-center text-muted-foreground">
        Loading contacts...
      </div>
    );
  }

  if (error) {
    return (
      <div className="p-4 text-center text-destructive">
        Error: {error instanceof Error ? error.message : "Failed to fetch contacts"}
      </div>
    );
  }

  if (!contacts?.length) {
    return (
      <div className="p-4 text-center text-muted-foreground">
        No contacts found
      </div>
    );
  }

  // Separate personal contact and other contacts
  const personalContact = contacts.find(c => c.isMe);
  const otherContacts = contacts.filter(c => !c.isMe && !c.parentId);
  const childContacts = contacts.filter(c => c.parentId);

  // Group contacts by parent/child relationships
  const contactsWithChildren = otherContacts.map(contact => ({
    ...contact,
    children: childContacts.filter(child => child.parentId === contact.id)
  }));

  return (
    <ScrollArea className="h-[calc(100vh-12rem)] pr-4">
      <div className="space-y-4">
        {/* Personal Contact Card */}
        {personalContact && (
          <div className="mb-8">
            <h2 className="text-lg font-semibold mb-4 text-muted-foreground">Personal Card</h2>
            <ContactCard contact={personalContact} />
          </div>
        )}

        {/* Other Contacts */}
        {contactsWithChildren.length > 0 && (
          <>
            <h2 className="text-lg font-semibold mb-4 text-muted-foreground">Contacts</h2>
            {contactsWithChildren.map(contact => (
              <ContactCard 
                key={contact.id} 
                contact={contact} 
                children={contact.children}
              />
            ))}
          </>
        )}
      </div>
    </ScrollArea>
  );
}