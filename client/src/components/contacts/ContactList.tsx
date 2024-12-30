import { useQuery } from "@tanstack/react-query";
import { ContactCard } from "./ContactCard";
import { type Contact } from "@/lib/types";
import { ScrollArea } from "@/components/ui/scroll-area";
import type { SearchFilters } from "./SearchBar";

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
    }
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

  // Helper function to build contact hierarchy
  const buildHierarchy = (contact: Contact): Contact => {
    // Get immediate children for this contact
    const children = contacts.filter(c => c.parentId === contact.id);

    // Process each child recursively
    const processedChildren = children.map(buildHierarchy);

    // Return contact with its processed children
    return {
      ...contact,
      children: processedChildren
    };
  };

  // Find personal contact (me) and direct contacts (contacts with no parent or where parent is me)
  const personalContact = contacts.find(c => c.isMe);
  const directContacts = contacts.filter(c => 
    (!c.parentId && !c.isMe) || 
    (personalContact && c.parentId === personalContact.id) 
  );

  // Process contacts into hierarchical structure
  const processedDirectContacts = directContacts.map(buildHierarchy);

  // For personal contact, process its hierarchy
  const personalHierarchy = personalContact ? buildHierarchy(personalContact) : null;

  // Categorize only direct contacts
  const categorizedContacts = categories.map(category => ({
    ...category,
    contacts: processedDirectContacts.filter(contact =>
      contact.relationshipType &&
      category.types.includes(contact.relationshipType)
    )
  }));

  // Handle uncategorized direct contacts
  const uncategorizedContacts = processedDirectContacts.filter(contact =>
    !contact.relationshipType ||
    !categories.some(cat => contact.relationshipType && cat.types.includes(contact.relationshipType))
  );

  return (
    <ScrollArea className="h-[calc(100vh-12rem)] pr-4">
      <div className="space-y-8">
        {/* Personal Contact Card */}
        {personalHierarchy && (
          <div>
            <h2 className="text-lg font-semibold mb-4 text-muted-foreground">Personal Card</h2>
            <ContactCard 
              contact={personalHierarchy} 
              children={personalHierarchy.children || []}
            />
          </div>
        )}

        {/* Categorized Contacts */}
        {categorizedContacts.map(category => (
          category.contacts.length > 0 && (
            <div key={category.title}>
              <h2 className="text-lg font-semibold mb-4 text-muted-foreground">{category.title}</h2>
              <div className="space-y-4">
                {category.contacts.map(contact => (
                  <ContactCard 
                    key={contact.id} 
                    contact={contact}
                    children={contact.children || []}
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
              {uncategorizedContacts.map(contact => (
                <ContactCard 
                  key={contact.id} 
                  contact={contact}
                  children={contact.children || []}
                />
              ))}
            </div>
          </div>
        )}
      </div>
    </ScrollArea>
  );
}