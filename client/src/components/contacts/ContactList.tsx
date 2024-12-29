import { useQuery } from "@tanstack/react-query";
import { ContactCard } from "./ContactCard";
import { type Contact } from "@/lib/types";
import { ScrollArea } from "@/components/ui/scroll-area";
import type { SearchFilters } from "./SearchBar";

interface ContactListProps {
  searchFilters: SearchFilters;
}

export function ContactList({ searchFilters }: ContactListProps) {
  const { data: contacts, isLoading } = useQuery<Contact[]>({
    queryKey: ["/api/contacts", searchFilters],
    queryFn: async () => {
      const params = new URLSearchParams();
      Object.entries(searchFilters).forEach(([key, value]) => {
        if (value) params.append(key, value);
      });

      const url = `/api/contacts${params.toString() ? `?${params.toString()}` : ''}`;
      const res = await fetch(url);
      if (!res.ok) throw new Error("Failed to fetch contacts");
      return res.json();
    },
  });

  if (isLoading) {
    return <div className="p-4">Loading contacts...</div>;
  }

  if (!contacts?.length) {
    return (
      <div className="p-4 text-center text-muted-foreground">
        No contacts found
      </div>
    );
  }

  // Group contacts by parent/child relationships
  const rootContacts = contacts.filter(c => !c.parentId);
  const childContacts = contacts.filter(c => c.parentId);

  const contactsWithChildren = rootContacts.map(contact => ({
    ...contact,
    children: childContacts.filter(child => child.parentId === contact.id)
  }));

  return (
    <ScrollArea className="h-[calc(100vh-12rem)] pr-4">
      <div className="space-y-4">
        {contactsWithChildren.map(contact => (
          <ContactCard 
            key={contact.id} 
            contact={contact} 
            children={contact.children}
          />
        ))}
      </div>
    </ScrollArea>
  );
}