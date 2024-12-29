import { useQuery } from "@tanstack/react-query";
import { ContactCard } from "./ContactCard";
import { type Contact } from "@/lib/types";
import { ScrollArea } from "@/components/ui/scroll-area";
import type { SearchFilters } from "./SearchBar";
import { useToast } from "@/hooks/use-toast";

interface ContactListProps {
  searchFilters: SearchFilters;
}

type ContactCategory = {
  title: string;
  types: string[];
  contacts: Contact[];
};

const categories: ContactCategory[] = [
  {
    title: "Family",
    types: ["mother", "father", "brother", "sibling", "child", "spouse"],
    contacts: [],
  },
  {
    title: "Friends",
    types: ["friend", "boyfriend/girlfriend"],
    contacts: [],
  },
  {
    title: "Professional",
    types: ["co-worker"],
    contacts: [],
  },
];

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

  // Separate personal contact and categorize other contacts
  const personalContact = contacts.find(c => c.isMe);
  const otherContacts = contacts.filter(c => !c.isMe && !c.parentId);
  const childContacts = contacts.filter(c => c.parentId);

  // Categorize contacts
  const categorizedContacts = categories.map(category => ({
    ...category,
    contacts: otherContacts.filter(contact => 
      contact.relationshipType && category.types.includes(contact.relationshipType)
    )
  }));

  // Add uncategorized contacts to a separate group
  const uncategorizedContacts = otherContacts.filter(contact => 
    !contact.relationshipType || 
    !categories.some(cat => cat.types.includes(contact.relationshipType!))
  );

  // Group contacts with their children
  const addChildrenToContacts = (parentContacts: Contact[]) => 
    parentContacts.map(contact => ({
      ...contact,
      children: childContacts.filter(child => child.parentId === contact.id)
    }));

  return (
    <ScrollArea className="h-[calc(100vh-12rem)] pr-4">
      <div className="space-y-8">
        {/* Personal Contact Card */}
        {personalContact && (
          <div>
            <h2 className="text-lg font-semibold mb-4 text-muted-foreground">Personal Card</h2>
            <ContactCard contact={personalContact} />
          </div>
        )}

        {/* Categorized Contacts */}
        {categorizedContacts.map(category => (
          category.contacts.length > 0 && (
            <div key={category.title}>
              <h2 className="text-lg font-semibold mb-4 text-muted-foreground">{category.title}</h2>
              <div className="space-y-4">
                {addChildrenToContacts(category.contacts).map(contact => (
                  <ContactCard 
                    key={contact.id} 
                    contact={contact} 
                    children={contact.children}
                  />
                ))}
              </div>
            </div>
          )
        ))}

        {/* Uncategorized Contacts */}
        {uncategorizedContacts.length > 0 && (
          <div>
            <h2 className="text-lg font-semibold mb-4 text-muted-foreground">Other Contacts</h2>
            <div className="space-y-4">
              {addChildrenToContacts(uncategorizedContacts).map(contact => (
                <ContactCard 
                  key={contact.id} 
                  contact={contact} 
                  children={contact.children}
                />
              ))}
            </div>
          </div>
        )}
      </div>
    </ScrollArea>
  );
}