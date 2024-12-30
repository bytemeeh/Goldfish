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

  console.log('Processing contacts for list view:', contacts);

  // Find personal contact (me)
  const personalContact = contacts.find(c => c.isMe);
  console.log('Found personal contact:', personalContact);

  // Find all top-level contacts (those without parents or direct children of personal contact)
  const rootContacts = contacts.filter(c => 
    !c.parentId || // No parent
    (personalContact && c.parentId === personalContact.id) // Direct child of personal contact
  );
  console.log('Found root contacts:', rootContacts);

  // Helper function to build contact hierarchy
  const buildHierarchy = (contacts: Contact[], parentId: number | null = null): Contact[] => {
    // Get immediate children for this parent
    const immediateChildren = contacts.filter(c => c.parentId === parentId);
    console.log(`Found ${immediateChildren.length} immediate children for parent ${parentId}:`, immediateChildren);

    // Process each child recursively
    return immediateChildren.map(child => ({
      ...child,
      children: buildHierarchy(contacts, child.id)
    }));
  };

  // Build hierarchies for each root contact
  const processedContacts = rootContacts.map(contact => ({
    ...contact,
    children: buildHierarchy(contacts, contact.id)
  }));
  console.log('Processed contacts with hierarchy:', processedContacts);

  // Categorize contacts (excluding personal contact and its direct relations)
  const categorizedContacts = categories.map(category => ({
    ...category,
    contacts: processedContacts.filter(contact =>
      !contact.isMe && // Not the personal contact
      !(personalContact && contact.parentId === personalContact.id) && // Not a direct relation of personal contact
      contact.relationshipType &&
      category.types.includes(contact.relationshipType)
    )
  }));

  // Get uncategorized contacts
  const uncategorizedContacts = processedContacts.filter(contact =>
    !contact.isMe && // Not the personal contact
    !(personalContact && contact.parentId === personalContact.id) && // Not a direct relation of personal contact
    (!contact.relationshipType || // No relationship type
    !categories.some(cat => contact.relationshipType && cat.types.includes(contact.relationshipType)))
  );

  return (
    <ScrollArea className="h-[calc(100vh-12rem)] pr-4">
      <div className="space-y-8">
        {/* Personal Contact Card with direct relations */}
        {personalContact && (
          <div>
            <h2 className="text-lg font-semibold mb-4 text-muted-foreground">Personal Card</h2>
            <ContactCard 
              contact={personalContact} 
              children={buildHierarchy(contacts, personalContact.id)}
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