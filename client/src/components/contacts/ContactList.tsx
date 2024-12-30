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

  // Find personal contact (me)
  const personalContact = contacts.find(c => c.isMe);
  console.log('Personal contact:', personalContact);

  // Helper function to build hierarchy for a contact
  const buildHierarchy = (contactId: number | null = null, depth: number = 0): Contact[] => {
    if (depth >= 4) return []; // Limit to 4 layers deep

    // For the root level (personal contact's direct relationships)
    if (depth === 0 && contactId === personalContact?.id) {
      const directRelations = contacts.filter(c => 
        c.parentId === contactId || 
        (c.relationshipType === 'sibling' && !c.parentId)
      );
      return directRelations.map(child => ({
        ...child,
        children: buildHierarchy(child.id, 1)
      }));
    }

    const children = contacts.filter(c => c.parentId === contactId);
    console.log(`Building hierarchy at depth ${depth} for contact ${contactId}, found children:`,
      children.map(c => ({
        id: c.id,
        name: c.name,
        relationshipType: c.relationshipType
      }))
    );

    return children.map(child => ({
      ...child,
      children: buildHierarchy(child.id, depth + 1)
    }));
  };

  // Get root contacts (excluding personal contact)
  const rootContacts = contacts.filter(c => 
    !c.isMe && // Not personal contact
    !c.parentId // No parent
  );

  // Build hierarchies for root contacts
  const processedContacts = rootContacts.map(contact => ({
    ...contact,
    children: buildHierarchy(contact.id)
  }));

  // Build personal contact hierarchy
  let personalHierarchy = null;
  if (personalContact) {
    personalHierarchy = {
      ...personalContact,
      children: buildHierarchy(personalContact.id)
    };
    console.log('Personal hierarchy:', personalHierarchy);
  }

  // Categorize contacts
  const categorizedContacts = categories.map(category => ({
    ...category,
    contacts: processedContacts.filter(contact =>
      contact.relationshipType &&
      category.types.includes(contact.relationshipType)
    )
  }));

  // Get uncategorized contacts
  const uncategorizedContacts = processedContacts.filter(contact =>
    !contact.relationshipType ||
    !categories.some(cat => 
      contact.relationshipType && 
      cat.types.includes(contact.relationshipType)
    )
  );

  // Categorize root contacts by relationship type
  const categorizedContacts = categories.map(category => ({
    ...category,
    contacts: rootContacts.filter(contact =>
      contact.relationshipType &&
      category.types.includes(contact.relationshipType)
    ).map(contact => ({
      ...contact,
      children: buildHierarchy(contact.id)
    }))
  }));

  // Get uncategorized contacts
  const uncategorizedContacts = rootContacts
    .filter(contact =>
      !contact.relationshipType ||
      !categories.some(cat => 
        contact.relationshipType && 
        cat.types.includes(contact.relationshipType)
      )
    )
    .map(contact => ({
      ...contact,
      children: buildHierarchy(contact.id)
    }));

  return (
    <ScrollArea className="h-[calc(100vh-12rem)] pr-4">
      <div className="space-y-8">
        {/* Personal Contact Card with all relationships */}
        {personalHierarchy && (
          <div>
            <h2 className="text-lg font-semibold mb-4 text-muted-foreground">Personal Card</h2>
            <ContactCard 
              contact={personalHierarchy}
              children={personalHierarchy.children}
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
                    children={contact.children}
                  />
                ))}
              </div>
            </div>
          )
        ))}

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
              {uncategorizedContacts.map(contact => (
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