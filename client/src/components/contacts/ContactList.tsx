import { useQuery } from "@tanstack/react-query";
import { ContactCard } from "./ContactCard";
import { type Contact } from "@/lib/types";
import { ScrollArea } from "@/components/ui/scroll-area";
import type { SearchFilters } from "./SearchBar";
import { motion, AnimatePresence } from "framer-motion";

interface ContactListProps {
  searchFilters: SearchFilters;
}

type ContactCategory = {
  title: string;
  types: string[];
  color: string;
  contacts: Contact[];
};

const categories: ContactCategory[] = [
  {
    title: "Family",
    types: ["mother", "father", "brother", "sibling", "child", "spouse"],
    color: "hsl(var(--chart-1))",
    contacts: [],
  },
  {
    title: "Friends",
    types: ["friend", "boyfriend/girlfriend"],
    color: "hsl(var(--chart-2))",
    contacts: [],
  },
  {
    title: "Professional",
    types: ["co-worker"],
    color: "hsl(var(--chart-3))",
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
      <motion.div 
        initial={{ opacity: 0 }} 
        animate={{ opacity: 1 }}
        className="p-4 text-center text-muted-foreground"
      >
        Loading contacts...
      </motion.div>
    );
  }

  if (error) {
    return (
      <motion.div 
        initial={{ opacity: 0 }} 
        animate={{ opacity: 1 }}
        className="p-4 text-center text-destructive"
      >
        Error: {error instanceof Error ? error.message : "Failed to fetch contacts"}
      </motion.div>
    );
  }

  if (!contacts?.length) {
    return (
      <motion.div 
        initial={{ opacity: 0 }} 
        animate={{ opacity: 1 }}
        className="p-4 text-center text-muted-foreground"
      >
        No contacts found
      </motion.div>
    );
  }

  const personalContact = contacts.find(c => c.isMe);

  const buildHierarchy = (contactId: number | null = null, depth: number = 0): Contact[] => {
    if (depth >= 4) return [];

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
    return children.map(child => ({
      ...child,
      children: buildHierarchy(child.id, depth + 1)
    }));
  };

  // Get all non-personal contacts that should be categorized
  const categorizableContacts = contacts.filter(c => 
    !c.isMe && 
    (c.parentId === null || c.relationshipType === 'sibling')
  );

  let personalHierarchy = null;
  if (personalContact) {
    personalHierarchy = {
      ...personalContact,
      children: buildHierarchy(personalContact.id)
    };
  }

  // Create categorized groups
  const categorizedContacts = categories.map(category => ({
    ...category,
    contacts: categorizableContacts
      .filter(contact => 
        contact.relationshipType && 
        category.types.includes(contact.relationshipType)
      )
      .map(contact => ({
        ...contact,
        children: buildHierarchy(contact.id)
      }))
      .sort((a, b) => a.name.localeCompare(b.name))
  }));

  // Handle uncategorized contacts
  const uncategorizedContacts = categorizableContacts
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
    }))
    .sort((a, b) => a.name.localeCompare(b.name));

  return (
    <ScrollArea className="h-[calc(100vh-12rem)] pr-4">
      <div className="space-y-8 py-2">
        <AnimatePresence mode="wait">
          {personalHierarchy && (
            <motion.div
              initial={{ opacity: 0, y: -20 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -20 }}
              transition={{ duration: 0.3 }}
            >
              <div className="relative">
                <div className="sticky top-0 pt-2 pb-4 bg-background/95 backdrop-blur-sm z-10">
                  <h2 
                    className="text-xs font-semibold uppercase tracking-wider"
                    style={{ color: "hsl(var(--primary))" }}
                  >
                    Personal Card
                  </h2>
                </div>
                <ContactCard 
                  contact={personalHierarchy}
                  children={personalHierarchy.children}
                />
              </div>
            </motion.div>
          )}

          {categorizedContacts.map((category, index) => 
            category.contacts.length > 0 && (
              <motion.div 
                key={category.title}
                initial={{ opacity: 0, y: -20 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -20 }}
                transition={{ duration: 0.3, delay: index * 0.1 }}
              >
                <div className="relative">
                  <div className="sticky top-0 pt-2 pb-4 bg-background/95 backdrop-blur-sm z-10">
                    <h2 
                      className="text-xs font-semibold uppercase tracking-wider"
                      style={{ color: category.color }}
                    >
                      {category.title}
                    </h2>
                  </div>
                  <div className="space-y-6">
                    {category.contacts.map(contact => (
                      <motion.div
                        key={contact.id}
                        initial={{ opacity: 0, x: -20 }}
                        animate={{ opacity: 1, x: 0 }}
                        transition={{ duration: 0.3 }}
                      >
                        <ContactCard 
                          contact={contact}
                          children={contact.children}
                        />
                      </motion.div>
                    ))}
                  </div>
                </div>
              </motion.div>
            )
          )}

          {uncategorizedContacts.length > 0 && (
            <motion.div
              initial={{ opacity: 0, y: -20 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -20 }}
              transition={{ duration: 0.3 }}
            >
              <div className="relative">
                <div className="sticky top-0 pt-2 pb-4 bg-background/95 backdrop-blur-sm z-10">
                  <h2 
                    className="text-xs font-semibold uppercase tracking-wider text-muted-foreground/70"
                  >
                    Other Contacts
                  </h2>
                </div>
                <div className="space-y-6">
                  {uncategorizedContacts.map(contact => (
                    <motion.div
                      key={contact.id}
                      initial={{ opacity: 0, x: -20 }}
                      animate={{ opacity: 1, x: 0 }}
                      transition={{ duration: 0.3 }}
                    >
                      <ContactCard 
                        contact={contact}
                        children={contact.children}
                      />
                    </motion.div>
                  ))}
                </div>
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </div>
    </ScrollArea>
  );
}