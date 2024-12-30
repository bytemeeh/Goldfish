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

  console.log('Initial contacts:', contacts.map(c => ({
    id: c.id,
    name: c.name,
    parentId: c.parentId,
    relationshipType: c.relationshipType
  })));

  // Find personal contact (me)
  const personalContact = contacts.find(c => c.isMe);
  console.log('Personal contact:', personalContact);

  // Helper function to build contact hierarchy
  const buildHierarchy = (contactId: number | null = null, visited = new Set<number>()): Contact[] => {
    // Get children for this contact
    const children = contacts.filter(c => c.parentId === contactId);
    console.log(`Building hierarchy for contact ${contactId}, found children:`, 
      children.map(c => ({
        id: c.id,
        name: c.name,
        relationshipType: c.relationshipType
      }))
    );

    return children.map(child => {
      // Prevent infinite recursion
      if (visited.has(child.id)) {
        console.log(`Preventing circular reference for contact ${child.id}`);
        return child;
      }

      const newVisited = new Set(visited);
      newVisited.add(child.id);

      // Get this child's children
      const childrenOfChild = buildHierarchy(child.id, newVisited);
      console.log(`Built hierarchy for ${child.name}:`, childrenOfChild);

      return {
        ...child,
        children: childrenOfChild
      };
    });
  };

  // Process all contacts into hierarchical structure
  const rootContacts = contacts.filter(c => 
    !c.isMe && // Not personal contact
    !c.parentId // No parent
  );
  console.log('Root contacts:', rootContacts);

  const processedContacts = rootContacts.map(contact => ({
    ...contact,
    children: buildHierarchy(contact.id)
  }));

  // Build personal contact hierarchy
  let personalHierarchy = null;
  if (personalContact) {
    // Get direct relationships for personal contact
    personalHierarchy = {
      ...personalContact,
      children: buildHierarchy(personalContact.id)
    };
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