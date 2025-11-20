import { useQuery } from "@tanstack/react-query";
import { ContactCard } from "./ContactCard";
import { type Contact, type Location, type RelationshipType } from "@/lib/types";
import { ScrollArea } from "@/components/ui/scroll-area";
import { cn } from "@/lib/utils";
import type { SearchFilters } from "./SearchBar";
import { buildContactTree, flattenContactTree, groupByFamilyTrees, calculateRelationshipLevels, type HierarchicalContact } from "@/lib/hierarchicalSort";
import { motion, AnimatePresence, Reorder } from "framer-motion";
import { Button } from "@/components/ui/button";
import { useToast } from "@/hooks/use-toast";
import React, { useState, useEffect, useRef } from "react";
import {
  Check,
  Navigation,
  X,
  Users,
  Briefcase,
  Heart,
  ListFilter,
  Eye,
  EyeOff,
  GripVertical,
  Layers,
  Network,
  RefreshCw,
  Trash2,
  CheckSquare
} from "lucide-react";
import { Checkbox } from "@/components/ui/checkbox";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";
import { BirthdayReminder } from "./BirthdayReminder";
import { QuickFilter } from "./QuickFilter";
import { SwipeableItem } from "@/components/ui/SwipeableItem";

interface ContactListProps {
  searchFilters: SearchFilters;
  selectedContactId?: string | null;
}

import { CATEGORIES } from "@/lib/constants";

type ContactCategory = {
  title: string;
  types: string[];
  color: string;
  contacts: Contact[];
};

const categories: ContactCategory[] = CATEGORIES.map(cat => ({
  ...cat,
  contacts: []
}));

// Calculate distance between two coordinates using the Haversine formula (in kilometers)
function calculateDistance(
  lat1: number | string | null | undefined,
  lon1: number | string | null | undefined,
  lat2: number | string | null | undefined,
  lon2: number | string | null | undefined
): number {
  if (!lat1 || !lon1 || !lat2 || !lon2) return Infinity;

  // Convert to numbers if they're strings
  const latitude1 = typeof lat1 === 'string' ? parseFloat(lat1) : lat1;
  const longitude1 = typeof lon1 === 'string' ? parseFloat(lon1) : lon1;
  const latitude2 = typeof lat2 === 'string' ? parseFloat(lat2) : lat2;
  const longitude2 = typeof lon2 === 'string' ? parseFloat(lon2) : lon2;

  // Convert degrees to radians
  const toRadians = (degrees: number) => degrees * Math.PI / 180;

  const dLat = toRadians(latitude2 - latitude1);
  const dLon = toRadians(longitude2 - longitude1);

  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRadians(latitude1)) * Math.cos(toRadians(latitude2)) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  // Earth's radius in kilometers
  const R = 6371;

  return R * c;
}

// Get the best/closest location for a contact based on current position
function getClosestLocation(contact: Contact, userLat?: number, userLon?: number): {
  distance: number;
  location: Location | null;
} {
  if (!userLat || !userLon || !contact.locations || contact.locations.length === 0) {
    // Use legacy location fields as fallback
    if (contact.latitude && contact.longitude) {
      const distance = calculateDistance(userLat, userLon, contact.latitude, contact.longitude);
      return {
        distance,
        location: {
          id: "0",
          contactId: contact.id,
          type: 'other',
          latitude: contact.latitude,
          longitude: contact.longitude,
          address: undefined,
          name: undefined
        }
      };
    }
    return { distance: Infinity, location: null };
  }

  let closestLocation: Location | null = null;
  let minDistance = Infinity;

  for (const location of contact.locations) {
    if (location.latitude && location.longitude) {
      const distance = calculateDistance(userLat, userLon, location.latitude, location.longitude);
      if (distance < minDistance) {
        minDistance = distance;
        closestLocation = location;
      }
    }
  }

  return { distance: minDistance, location: closestLocation };
}

// Define sort types
type SortType = 'hierarchical' | 'proximity' | 'manual' | 'family-trees' | 'relationship-depth';

export function ContactList({ searchFilters, selectedContactId }: ContactListProps) {
  const { toast } = useToast();
  // Create refs for selected contact scrolling
  const contactRefs = useRef<Record<string, HTMLDivElement | null>>({});
  // State hooks - must be called in the same order every render
  const [sortType, setSortType] = useState<SortType>('family-trees');
  const [proximitySort, setProximitySort] = useState(() => {
    return localStorage.getItem('proximity_sort') === 'true';
  });
  const [userLocation, setUserLocation] = useState<{ latitude: number; longitude: number } | null>(null);
  const [isGettingLocation, setIsGettingLocation] = useState(false);
  const [relationshipFilter, setRelationshipFilter] = useState<string>(() => {
    return localStorage.getItem('relationship_filter') || "all";
  });
  const [relationLevelFilter, setRelationLevelFilter] = useState<string>(() => {
    return localStorage.getItem('relation_level_filter') || "all";
  });

  // Manual sort state
  const [manualOrderIds, setManualOrderIds] = useState<string[]>([]);
  const [hiddenContactIds, setHiddenContactIds] = useState<Set<string>>(new Set());

  // Category order state for draggable categories
  const [categoryOrder, setCategoryOrder] = useState<string[]>(() => {
    // Load from localStorage or use default order
    const savedOrder = localStorage.getItem('category_order');
    return savedOrder ? JSON.parse(savedOrder) : categories.map(cat => cat.title);
  });

  // Selection mode state
  const [isSelectionMode, setIsSelectionMode] = useState(false);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());

  const toggleSelectionMode = () => {
    setIsSelectionMode(!isSelectionMode);
    setSelectedIds(new Set()); // Clear selection when toggling
  };

  const toggleContactSelection = (contactId: string) => {
    setSelectedIds(prev => {
      const newSet = new Set(prev);
      if (newSet.has(contactId)) {
        newSet.delete(contactId);
      } else {
        newSet.add(contactId);
      }
      return newSet;
    });
  };

  const handleSwipeLeft = (contact: Contact) => {
    // Swipe to Delete
    if (confirm(`Delete ${contact.name}?`)) {
      // Call delete API
      fetch(`/api/contacts/${contact.id}`, { method: 'DELETE' })
        .then(res => {
          if (res.ok) {
            toast({ title: "Contact deleted", description: `${contact.name} has been removed.` });
            // Invalidate queries would be better here
            window.location.reload();
          }
        });
    }
  };

  const handleSwipeRight = (contact: Contact) => {
    // Swipe to Call
    if (contact.phone) {
      window.location.href = `tel:${contact.phone}`;
      toast({ title: "Calling", description: `Calling ${contact.name}...` });
    } else {
      toast({ title: "No phone number", description: "This contact doesn't have a phone number.", variant: "destructive" });
    }
  };

  const handleBulkDelete = async () => {
    if (selectedIds.size === 0) return;

    if (confirm(`Are you sure you want to delete ${selectedIds.size} contacts? This action cannot be undone.`)) {
      try {
        const response = await fetch('/api/contacts/bulk-delete', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ contactIds: Array.from(selectedIds) }),
        });

        if (!response.ok) throw new Error('Failed to delete contacts');

        toast({
          title: "Success",
          description: `Deleted ${selectedIds.size} contacts`,
        });

        setSelectedIds(new Set());
        setIsSelectionMode(false);
        // Invalidate queries to refresh list
        // queryClient.invalidateQueries({ queryKey: ['contacts'] }); // This needs queryClient access
        window.location.reload(); // Temporary reload until queryClient is available
      } catch (error) {
        toast({
          title: "Error",
          description: "Failed to delete contacts",
          variant: "destructive",
        });
      }
    }
  };

  // Save category order to localStorage when it changes
  useEffect(() => {
    localStorage.setItem('category_order', JSON.stringify(categoryOrder));
  }, [categoryOrder]);

  // Load saved sort preferences on mount
  useEffect(() => {
    const savedSortType = localStorage.getItem('contact_sort_type');
    if (savedSortType) {
      setSortType(savedSortType as SortType);
    }

    const savedManualOrderIds = localStorage.getItem('manual_order_ids');
    if (savedManualOrderIds) {
      setManualOrderIds(JSON.parse(savedManualOrderIds));
    }

    const savedHiddenContactIds = localStorage.getItem('hidden_contact_ids');
    if (savedHiddenContactIds) {
      setHiddenContactIds(new Set(JSON.parse(savedHiddenContactIds)));
    }
  }, []);

  // Save manual sort order and hidden contacts when they change
  useEffect(() => {
    if (manualOrderIds.length > 0) {
      localStorage.setItem('manual_order_ids', JSON.stringify(manualOrderIds));
    }
  }, [manualOrderIds]);

  useEffect(() => {
    if (hiddenContactIds.size > 0) {
      localStorage.setItem('hidden_contact_ids', JSON.stringify([...hiddenContactIds]));
    }

    // Set up event listener for hiding contacts from ContactCard components
    const handleHideContact = (event: Event) => {
      const customEvent = event as CustomEvent;
      const contactId = customEvent.detail?.contactId;
      if (contactId) {
        setHiddenContactIds((prev: Set<string>) => {
          const newSet = new Set(prev);
          newSet.add(contactId);
          return newSet;
        });
      }
    };

    window.addEventListener('contact:hide', handleHideContact);

    return () => {
      window.removeEventListener('contact:hide', handleHideContact);
    };
  }, [hiddenContactIds]);

  // Update localStorage when sort type changes
  useEffect(() => {
    localStorage.setItem('contact_sort_type', sortType);

    // If changing to proximity sort, get location if not already available
    if (sortType === 'proximity' && !userLocation && !isGettingLocation) {
      getCurrentLocation();
    }
  }, [sortType, userLocation, isGettingLocation]);

  // Save relationship filters when they change
  useEffect(() => {
    localStorage.setItem('relationship_filter', relationshipFilter);
  }, [relationshipFilter]);

  useEffect(() => {
    localStorage.setItem('relation_level_filter', relationLevelFilter);
  }, [relationLevelFilter]);

  // Effect to scroll to selected contact when it changes
  useEffect(() => {
    // First, clear any previously selected contacts
    console.log('🚨 ContactList useEffect - selectedContactId:', selectedContactId);
    console.log('🚨 ContactList useEffect - Available refs:', Object.keys(contactRefs.current));

    // Reset all selections
    Object.values(contactRefs.current).forEach(el => {
      if (el) {
        el.setAttribute('data-selected', 'false');
        el.classList.remove('highlight-pulse');
      }
    });

    if (selectedContactId && contactRefs.current[selectedContactId]) {
      console.log('🚨 ContactList useEffect - Found matching ref for ID:', selectedContactId);
      const contactElement = contactRefs.current[selectedContactId];

      if (contactElement) {
        console.log('🚨 ContactList useEffect - Setting data-selected attribute');
        contactElement.setAttribute('data-selected', 'true');
        contactElement.classList.add('highlight-pulse');

        // Smooth scroll to the selected contact with a small delay to ensure the UI is ready
        setTimeout(() => {
          try {
            console.log('🚨 ContactList useEffect - Scrolling to element');
            contactElement.scrollIntoView({
              behavior: 'smooth',
              block: 'center'
            });

            // Ensure the highlight stays long enough to be visible
            setTimeout(() => {
              contactElement.classList.remove('highlight-pulse');
              // Keep the selected state for longer
            }, 3000);
          } catch (error) {
            console.error('🚨 Error scrolling to contact:', error);
          }
        }, 100);
      } else {
        console.log('🚨 ContactList useEffect - Contact element is null despite having a ref');
      }
    } else {
      console.log('🚨 ContactList useEffect - No matching ref found for ID:', selectedContactId);
    }
  }, [selectedContactId]);

  // Get user's current location
  const getCurrentLocation = () => {
    if (!navigator.geolocation) {
      toast({
        title: "Error",
        description: "Geolocation is not supported by your browser",
        variant: "destructive",
      });
      return false;
    }

    setIsGettingLocation(true);
    navigator.geolocation.getCurrentPosition(
      (position) => {
        setUserLocation({
          latitude: position.coords.latitude,
          longitude: position.coords.longitude
        });
        setProximitySort(true);
        setIsGettingLocation(false);
        toast({
          title: "Success",
          description: "Your location has been detected",
        });
        return true;
      },
      (error) => {
        setIsGettingLocation(false);
        toast({
          title: "Error",
          description: `Failed to get your location: ${error.message}`,
          variant: "destructive",
        });
        return false;
      }
    );
    return true; // Return true if the geolocation request was initiated
  };

  // Save proximity sort setting when it changes
  useEffect(() => {
    localStorage.setItem('proximity_sort', proximitySort.toString());
  }, [proximitySort]);

  // Toggle proximity sorting
  const toggleProximitySort = () => {
    if (proximitySort) {
      // Turn off proximity sorting
      setProximitySort(false);
    } else {
      // Turn on proximity sorting & get location if needed
      if (!userLocation) {
        getCurrentLocation();
      } else {
        setProximitySort(true);
      }
    }
  };

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

  const buildHierarchy = (contactId: string | null = null, depth: number = 0): Contact[] => {
    if (depth >= 4) return [];

    if (depth === 0 && contactId === personalContact?.id) {
      const directRelations = contacts.filter((c: Contact) =>
        c.parentId === contactId ||
        (c.relationshipType === 'sibling' && !c.parentId)
      );
      return directRelations.map((child: Contact) => ({
        ...child,
        children: buildHierarchy(child.id, 1)
      }));
    }

    const children = contacts.filter((c: Contact) => c.parentId === contactId);
    return children.map((child: Contact) => ({
      ...child,
      children: buildHierarchy(child.id, depth + 1)
    }));
  };

  // Get all non-personal contacts that should be categorized
  const categorizableContacts = contacts.filter((c: Contact) =>
    !c.isMe &&
    (c.parentId === null || c.relationshipType === 'sibling')
  );

  let personalHierarchy: Contact | null = null;
  if (personalContact) {
    personalHierarchy = {
      ...personalContact,
      children: buildHierarchy(personalContact.id)
    };
  }

  // Apply intelligent hierarchical sorting
  const getSortedContacts = (): Contact[] => {
    let sortedContacts = [...contacts];

    switch (sortType) {
      case 'family-trees':
        const familyTrees = groupByFamilyTrees(contacts);
        sortedContacts = familyTrees.flat();
        break;

      case 'hierarchical':
        const tree = buildContactTree(contacts);
        sortedContacts = flattenContactTree(tree);
        break;

      case 'relationship-depth':
        const relationshipLevels = calculateRelationshipLevels(contacts);
        sortedContacts = contacts.sort((a: Contact, b: Contact) => {
          const levelA = relationshipLevels.get(a.id) || 999;
          const levelB = relationshipLevels.get(b.id) || 999;

          if (levelA !== levelB) return levelA - levelB;
          return a.name.localeCompare(b.name);
        });
        break;

      case 'proximity':
        sortedContacts = sortContactsByProximity(contacts);
        break;

      case 'manual':
        if (manualOrderIds.length > 0) {
          const orderMap = new Map<string, number>(manualOrderIds.map((id: string, index: number) => [id, index]));
          sortedContacts = contacts.sort((a: Contact, b: Contact) => {
            const orderA = orderMap.get(a.id) ?? 999;
            const orderB = orderMap.get(b.id) ?? 999;
            if (orderA !== orderB) return orderA - orderB;
            return a.name.localeCompare(b.name);
          });
        }
        break;

      default:
        sortedContacts = contacts.sort((a: Contact, b: Contact) => a.name.localeCompare(b.name));
    }

    return sortedContacts;
  };

  // Apply proximity-based sorting if enabled
  const sortContactsByProximity = (contactsToSort: Contact[]) => {
    if (!proximitySort || !userLocation) return contactsToSort.sort((a: Contact, b: Contact) => a.name.localeCompare(b.name));

    return [...contactsToSort].sort((a: Contact, b: Contact) => {
      const locationA = getClosestLocation(a, userLocation.latitude, userLocation.longitude);
      const locationB = getClosestLocation(b, userLocation.latitude, userLocation.longitude);

      // Sort by distance, with contacts without locations at the end
      return locationA.distance - locationB.distance;
    });
  };

  // Function to get the relationship level of a contact relative to personal contact
  const getRelationshipLevel = (contact: Contact): number => {
    if (contact.isMe) return 0;

    // Direct children of personal contact or siblings are level 1
    if ((personalContact && contact.parentId === personalContact.id) ||
      (contact.relationshipType === 'sibling' && !contact.parentId)) {
      return 1;
    }

    // Find the shortest path to the personal contact
    let level = 1;
    let currentId = contact.parentId;
    const visited = new Set<string>([contact.id]);

    while (currentId && level < 5) {
      if (visited.has(currentId)) {
        // Avoid cycles
        break;
      }
      visited.add(currentId);

      // If we reach the personal contact or a sibling, we've found the path
      if (personalContact && currentId === personalContact.id) {
        return level;
      }

      // Find the parent contact
      const parentContact = contacts.find((c: Contact) => c.id === currentId);
      if (!parentContact) break;

      // If parent is sibling with no parent, it's one level from personal
      if (parentContact.relationshipType === 'sibling' && !parentContact.parentId) {
        return level + 1;
      }

      // Move up to the next parent
      currentId = parentContact.parentId;
      level++;
    }

    return level;
  };

  // Apply filters to the input contacts
  const applyFilters = (inputContacts: Contact[]): Contact[] => {
    let filtered = [...inputContacts];

    // Apply relationship type filter
    if (relationshipFilter !== 'all') {
      filtered = filtered.filter(contact => contact.relationshipType === relationshipFilter);
    }

    // Apply relationship level filter
    if (relationLevelFilter !== 'all') {
      const level = parseInt(relationLevelFilter);
      filtered = filtered.filter(contact => getRelationshipLevel(contact) === level);
    }

    return filtered;
  };

  // Sort categories based on the saved order
  const sortedCategories = [...categories].sort((a, b) => {
    const indexA = categoryOrder.indexOf(a.title);
    const indexB = categoryOrder.indexOf(b.title);
    return indexA - indexB;
  });

  // Create categorized groups
  const categorizedContacts: ContactCategory[] = sortedCategories.map(category => {
    // Filter contacts by category
    const categoryContacts = categorizableContacts
      .filter((contact: Contact) =>
        contact.relationshipType &&
        category.types.includes(contact.relationshipType)
      );

    // Apply additional filters  
    const filteredCategoryContacts = applyFilters(categoryContacts);

    return {
      ...category,
      contacts: filteredCategoryContacts.map((contact: Contact) => ({
        ...contact,
        children: buildHierarchy(contact.id)
      }))
    };
  });

  // Handle uncategorized contacts
  const uncategorizedContacts: Contact[] = applyFilters(
    categorizableContacts
      .filter(contact =>
        !contact.relationshipType ||
        !categories.some(cat =>
          contact.relationshipType &&
          cat.types.includes(contact.relationshipType)
        )
      )
  ).map(contact => ({
    ...contact,
    children: buildHierarchy(contact.id)
  }));

  // Apply sorting based on selected sort type
  const applySelectedSorting = () => {
    // Filter hidden contacts when in manual mode
    if (sortType === 'manual') {
      categorizedContacts.forEach(category => {
        category.contacts = category.contacts.filter((c: Contact) =>
          !hiddenContactIds.has(c.id)
        );
      });

      const visibleUncategorized = uncategorizedContacts.filter(
        contact => !hiddenContactIds.has(contact.id)
      );

      // Apply manual order if available
      if (manualOrderIds.length > 0) {
        // Create a map for quick lookup by ID
        const contactMap = new Map();
        contacts.forEach((c: Contact) => contactMap.set(c.id, c));

        // Order contacts based on manual order
        const orderedContacts = manualOrderIds
          .map((id: string) => contactMap.get(id))
          .filter(Boolean); // Remove any undefined entries

        // For any contacts not in manualOrderIds, maintain their position at the end
        const unorderedIds = new Set(manualOrderIds);
        const remainingContacts = contacts.filter((c: Contact) => !unorderedIds.has(c.id));

        // Update each category with the manually ordered contacts
        categorizedContacts.forEach(category => {
          const categoryIds = new Set(category.contacts.map((c: Contact) => c.id));
          category.contacts = orderedContacts
            .filter((c: Contact) => categoryIds.has(c.id))
            .map((contact: Contact) => ({
              ...contact,
              children: buildHierarchy(contact.id)
            }));
        });

        // Update uncategorized contacts
        const uncategorizedIds = new Set(uncategorizedContacts.map(c => c.id));
        uncategorizedContacts.splice(0, uncategorizedContacts.length, ...orderedContacts
          .filter((c: Contact) => uncategorizedIds.has(c.id))
          .map((contact: Contact) => ({
            ...contact,
            children: buildHierarchy(contact.id)
          })));

        // Add any remaining contacts that weren't in the manual order
        remainingContacts.forEach((contact: Contact) => {
          if (categorizedContacts.some(cat =>
            cat.types.includes(contact.relationshipType || '') &&
            !hiddenContactIds.has(contact.id)
          )) {
            const category = categorizedContacts.find(cat =>
              cat.types.includes(contact.relationshipType || '')
            );
            if (category) {
              category.contacts.push({
                ...contact,
                children: buildHierarchy(contact.id)
              });
            }
          } else if (!hiddenContactIds.has(contact.id) && !contact.isMe) {
            uncategorizedContacts.push({
              ...contact,
              children: buildHierarchy(contact.id)
            });
          }
        });
      }
      return;
    }

    // Proximity-based sorting
    if (sortType === 'proximity' && userLocation) {
      categorizedContacts.forEach(category => {
        category.contacts = sortContactsByProximity(category.contacts);
      });

      uncategorizedContacts.sort((a, b) => {
        const locationA = getClosestLocation(a, userLocation.latitude, userLocation.longitude);
        const locationB = getClosestLocation(b, userLocation.latitude, userLocation.longitude);
        return locationA.distance - locationB.distance;
      });
      return;
    }

    // Default hierarchical sorting (by name)
    categorizedContacts.forEach(category => {
      category.contacts.sort((a, b) => a.name.localeCompare(b.name));
    });
    uncategorizedContacts.sort((a, b) => a.name.localeCompare(b.name));
  };

  // Apply the selected sorting method
  applySelectedSorting();

  return (
    <div className="space-y-4">
      {/* Filters and Controls Section */}
      <div className="sticky top-0 z-20 pb-2 -mx-4 px-4 pt-2 glass border-b border-white/10">
        <div className="space-y-3">
          {/* Filter Pills */}
          <ScrollArea className="w-full whitespace-nowrap pb-2">
            <div className="flex space-x-2">
              <Button
                variant={relationshipFilter === 'all' ? "default" : "outline"}
                size="sm"
                className="rounded-full h-7 text-xs"
                onClick={() => setRelationshipFilter('all')}
              >
                All
              </Button>
              <div className="flex items-center gap-2">
                {isSelectionMode ? (
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={toggleSelectionMode}
                    className="h-8 px-2 text-muted-foreground hover:text-foreground"
                  >
                    Cancel
                  </Button>
                ) : (
                  <Button
                    variant="ghost"
                    size="sm"
                    onClick={toggleSelectionMode}
                    className={cn(
                      "h-8 px-2 text-muted-foreground hover:text-foreground",
                      isSelectionMode && "bg-accent text-accent-foreground"
                    )}
                  >
                    <CheckSquare className="h-4 w-4 mr-1.5" />
                    Select
                  </Button>
                )}


              </div>
              <Button
                variant={relationshipFilter === 'family' ? "default" : "outline"}
                size="sm"
                className="rounded-full h-7 text-xs border-[hsl(var(--rel-family))]/30 text-[hsl(var(--rel-family))] hover:bg-[hsl(var(--rel-family))]/10 data-[state=active]:bg-[hsl(var(--rel-family))] data-[state=active]:text-white"
                data-state={relationshipFilter === 'family' ? 'active' : 'inactive'}
                onClick={() => setRelationshipFilter(relationshipFilter === 'family' ? 'all' : 'family')}
              >
                <Heart className="mr-1.5 h-3 w-3" />
                Family
              </Button>
              <Button
                variant={relationshipFilter === 'friend' ? "default" : "outline"}
                size="sm"
                className="rounded-full h-7 text-xs border-[hsl(var(--rel-friend))]/30 text-[hsl(var(--rel-friend))] hover:bg-[hsl(var(--rel-friend))]/10 data-[state=active]:bg-[hsl(var(--rel-friend))] data-[state=active]:text-white"
                data-state={relationshipFilter === 'friend' ? 'active' : 'inactive'}
                onClick={() => setRelationshipFilter(relationshipFilter === 'friend' ? 'all' : 'friend')}
              >
                <Users className="mr-1.5 h-3 w-3" />
                Friends
              </Button>
              <Button
                variant={relationshipFilter === 'professional' ? "default" : "outline"}
                size="sm"
                className="rounded-full h-7 text-xs border-[hsl(var(--rel-work))]/30 text-[hsl(var(--rel-work))] hover:bg-[hsl(var(--rel-work))]/10 data-[state=active]:bg-[hsl(var(--rel-work))] data-[state=active]:text-white"
                data-state={relationshipFilter === 'professional' ? 'active' : 'inactive'}
                onClick={() => setRelationshipFilter(relationshipFilter === 'professional' ? 'all' : 'professional')}
              >
                <Briefcase className="mr-1.5 h-3 w-3" />
                Work
              </Button>

              <div className="w-px h-6 bg-border mx-2 self-center" />

              {[1, 2, 3, 4].map((level) => (
                <Button
                  key={level}
                  variant={relationLevelFilter === level.toString() ? "secondary" : "ghost"}
                  size="sm"
                  className="rounded-full h-7 text-xs w-8 p-0"
                  onClick={() => setRelationLevelFilter(relationLevelFilter === level.toString() ? 'all' : level.toString())}
                >
                  L{level}
                </Button>
              ))}
            </div>
          </ScrollArea>
        </div>

        {/* Sorting Controls */}
        < div className="pt-1 pb-1" >
          <div className="flex items-center justify-between mb-1">
            <span className="text-xs font-medium text-muted-foreground">Sort Mode:</span>
          </div>

          <div className="flex flex-wrap gap-1 mb-1">
            <Button
              variant={sortType === 'hierarchical' ? "default" : "outline"}
              size="sm"
              className="h-7 px-3 py-0 text-xs flex items-center gap-1.5"
              onClick={() => setSortType('hierarchical')}
            >
              <Layers className="h-3.5 w-3.5" />
              Hierarchical
            </Button>

            <Button
              variant={sortType === 'proximity' ? "default" : "outline"}
              size="sm"
              className="h-7 px-3 py-0 text-xs flex items-center gap-1.5"
              onClick={() => {
                setSortType('proximity');
                if (!userLocation) {
                  getCurrentLocation();
                }
              }}
            >
              <Navigation className="h-3.5 w-3.5" />
              Proximity
              {isGettingLocation && <span className="ml-1 text-xs animate-pulse">Getting location...</span>}
            </Button>

            <Button
              variant={sortType === 'manual' ? "default" : "outline"}
              size="sm"
              className="h-7 px-3 py-0 text-xs flex items-center gap-1.5"
              onClick={() => setSortType('manual')}
            >
              <GripVertical className="h-3.5 w-3.5" />
              Manual
            </Button>

            {/* Action buttons for manual mode, positioned next to sort buttons */}
            {sortType === 'manual' && (
              <div className="flex items-center gap-2 ml-auto">
                <Button
                  variant="outline"
                  size="sm"
                  className="h-7 px-3 py-0 text-xs flex items-center gap-1.5"
                  onClick={() => setHiddenContactIds(new Set())}
                >
                  <Eye className="h-3.5 w-3.5" />
                  Show All
                </Button>
                <Button
                  variant="outline"
                  size="sm"
                  className="h-7 px-3 py-0 text-xs flex items-center gap-1.5"
                  onClick={() => {
                    setSortType('hierarchical');
                    setManualOrderIds([]);
                    localStorage.removeItem('manual_order_ids');
                  }}
                >
                  <RefreshCw className="h-3.5 w-3.5" />
                  Reset
                </Button>
              </div>
            )}
          </div>

          {/* Show reorder instructions for category sorting in manual mode */}
          {
            sortType === 'manual' && (
              <div className="bg-muted/30 py-1.5 px-2 mt-1 rounded-md border border-dashed flex items-center">
                <GripVertical className="h-3.5 w-3.5 mr-1.5 text-muted-foreground flex-shrink-0" />
                <p className="text-xs text-muted-foreground">
                  <span className="font-medium">Manual sorting mode:</span> Drag categories and contacts to reorder them
                </p>
              </div>
            )
          }
        </div >
      </div >

      <ScrollArea className="h-[calc(100vh-14rem)] pr-4">
        <div className="space-y-8 py-2">
          {/* Add Birthday Reminder Component */}
          <BirthdayReminder contacts={contacts} />

          <AnimatePresence mode="sync">
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
                  <div
                    ref={(element: HTMLDivElement | null) => {
                      if (personalHierarchy) {
                        contactRefs.current[personalHierarchy.id] = element;
                      }
                    }}
                    data-selected={selectedContactId === personalHierarchy.id ? 'true' : 'false'}
                  >
                    <ContactCard
                      contact={personalHierarchy}
                      children={personalHierarchy.children}
                      relationshipLevel={0}
                      isSelected={selectedContactId === personalHierarchy.id}
                    />
                  </div>
                </div>
              </motion.div>
            )}

            {sortType === 'manual' ? (
              <Reorder.Group
                axis="y"
                values={sortedCategories}
                onReorder={(items: ContactCategory[]) => {
                  // Update category order
                  const newOrder = items.map(cat => cat.title);
                  setCategoryOrder(newOrder);
                }}
                className="space-y-8"
              >
                {categorizedContacts.map((category, index) =>
                  category.contacts.length > 0 && (
                    <Reorder.Item
                      key={category.title}
                      value={categories.find(c => c.title === category.title) || category}
                      className="relative cursor-move"
                    >
                      <div className="relative">
                        <div className="sticky top-0 pt-2 pb-4 bg-background/95 backdrop-blur-sm z-10 flex items-center">
                          <div className="mr-2 opacity-40 hover:opacity-100 transition-opacity">
                            <GripVertical className="w-4 h-4 text-muted-foreground" />
                          </div>
                          <h2
                            className="text-xs font-semibold uppercase tracking-wider"
                            style={{ color: category.color }}
                          >
                            {category.title}
                          </h2>
                        </div>
                        <Reorder.Group
                          axis="y"
                          values={category.contacts}
                          onReorder={(items: Contact[]) => {
                            // Update category contacts
                            const newCategory = {
                              ...category,
                              contacts: items
                            };

                            // Find category index
                            const catIndex = categorizedContacts.findIndex(c => c.title === category.title);
                            if (catIndex !== -1) {
                              categorizedContacts[catIndex] = newCategory;
                            }

                            // Update manual order
                            const allContactIds = [
                              ...categorizedContacts.flatMap(cat => cat.contacts.map(c => c.id)),
                              ...uncategorizedContacts.map(c => c.id)
                            ];
                            setManualOrderIds(allContactIds);
                          }}
                          className="space-y-6"
                        >
                          {category.contacts.map(contact => (
                            <Reorder.Item
                              key={contact.id}
                              value={contact}
                              className="relative pb-2 cursor-move"
                            >
                              <div className="absolute -left-4 top-1/2 transform -translate-y-1/2 opacity-40 hover:opacity-100 transition-opacity">
                                <GripVertical className="w-4 h-4 text-muted-foreground" />
                              </div>
                              <div
                                ref={element => {
                                  contactRefs.current[contact.id] = element;
                                }}
                              >
                                <ContactCard
                                  contact={contact}
                                  children={contact.children}
                                  manualSortMode={sortType === 'manual'}
                                  relationshipLevel={getRelationshipLevel(contact)}
                                  isSelected={selectedContactId === contact.id}
                                />
                              </div>
                              <Button
                                variant="ghost"
                                size="sm"
                                className="absolute right-8 top-2 h-6 w-6 p-0 bg-background/80 hover:bg-background shadow-sm border border-border/50"
                                onClick={() => {
                                  // Add to hidden contacts
                                  const newHidden = new Set(hiddenContactIds);
                                  newHidden.add(contact.id);
                                  setHiddenContactIds(newHidden);
                                }}
                              >
                                <EyeOff className="h-3.5 w-3.5" />
                              </Button>
                            </Reorder.Item>
                          ))}
                        </Reorder.Group>
                      </div>
                    </Reorder.Item>
                  )
                )}

                {/* Uncategorized Contacts in Manual Mode */}
                {uncategorizedContacts.length > 0 && (
                  <div className="mt-8">
                    <div className="sticky top-0 pt-2 pb-4 bg-background/95 backdrop-blur-sm z-10">
                      <h2 className="text-xs font-semibold uppercase tracking-wider text-muted-foreground/70">
                        Other Contacts
                      </h2>
                    </div>
                    <Reorder.Group
                      axis="y"
                      values={uncategorizedContacts}
                      onReorder={(items: Contact[]) => {
                        // Update uncategorized contacts
                        uncategorizedContacts.splice(0, uncategorizedContacts.length, ...items);

                        // Update manual order
                        const allContactIds = [
                          ...categorizedContacts.flatMap(cat => cat.contacts.map(c => c.id)),
                          ...uncategorizedContacts.map(c => c.id)
                        ];
                        setManualOrderIds(allContactIds);
                      }}
                      className="space-y-6"
                    >
                      {uncategorizedContacts.map(contact => (
                        <Reorder.Item
                          key={contact.id}
                          value={contact}
                          className="relative pb-2 cursor-move"
                        >
                          <div className="absolute -left-4 top-1/2 transform -translate-y-1/2 opacity-40 hover:opacity-100 transition-opacity">
                            <GripVertical className="w-4 h-4 text-muted-foreground" />
                          </div>
                          <div
                            ref={element => {
                              contactRefs.current[contact.id] = element;
                            }}
                          >
                            <ContactCard
                              contact={contact}
                              children={contact.children}
                              manualSortMode={true}
                              relationshipLevel={getRelationshipLevel(contact)}
                              isSelected={selectedContactId === contact.id}
                              onChildrenReorder={(newChildren) => {
                                // Update child contacts recursively
                                const updatedContact = { ...contact, children: newChildren };
                                const updatedContacts = [...uncategorizedContacts];
                                const index = updatedContacts.findIndex(c => c.id === contact.id);
                                if (index >= 0) {
                                  updatedContacts[index] = updatedContact;
                                  uncategorizedContacts.splice(0, uncategorizedContacts.length, ...updatedContacts);
                                }
                              }}
                            />
                          </div>
                          <Button
                            variant="ghost"
                            size="sm"
                            className="absolute right-8 top-2 h-6 w-6 p-0 bg-background/80 hover:bg-background shadow-sm border border-border/50"
                            onClick={() => {
                              const newHidden = new Set(hiddenContactIds);
                              newHidden.add(contact.id);
                              setHiddenContactIds(newHidden);
                            }}
                          >
                            <EyeOff className="h-3.5 w-3.5" />
                          </Button>
                        </Reorder.Item>
                      ))}
                    </Reorder.Group>
                  </div>
                )}
              </Reorder.Group>
            ) : (
              <>
                {categorizedContacts.map((category, index) =>
                  category.contacts.length > 0 && (
                    <motion.div
                      key={category.title}
                      initial={{ opacity: 0, y: -20 }}
                      animate={{ opacity: 1, y: 0 }}
                      exit={{ opacity: 0, y: -20 }}
                      className="mb-8"
                    >
                      <div className="sticky top-0 pt-2 pb-4 bg-background/95 backdrop-blur-sm z-10 flex items-center gap-2">
                        <h2
                          className="text-xs font-semibold uppercase tracking-wider text-muted-foreground/70"
                          style={{ color: category.color }}
                        >
                          {category.title}
                        </h2>
                        <div className="h-px flex-1 bg-border/50" />
                        <span className="text-[10px] font-medium px-1.5 py-0.5 rounded-full bg-muted text-muted-foreground">
                          {category.contacts.length}
                        </span>
                      </div>

                      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
                        {category.contacts.map((contact) => (
                          <motion.div
                            layout
                            key={contact.id}
                            ref={(element) => {
                              contactRefs.current[contact.id] = element;
                            }}
                          >
                            <SwipeableItem
                              onSwipeLeft={() => handleSwipeLeft(contact)}
                              onSwipeRight={() => handleSwipeRight(contact)}
                              className="rounded-xl"
                            >
                              <ContactCard
                                contact={contact}
                                children={contact.children}
                                manualSortMode={false}
                                relationshipLevel={getRelationshipLevel(contact)}
                                isSelected={selectedContactId === contact.id}
                              />
                            </SwipeableItem>
                          </motion.div>
                        ))}
                      </div>
                    </motion.div>
                  ))}

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
                            layout
                            key={contact.id}
                            layoutId={contact.id}
                            initial={{ opacity: 0, y: 20 }}
                            animate={{ opacity: 1, y: 0 }}
                            exit={{ opacity: 0, scale: 0.95 }}
                            className="group flex items-center gap-2"
                          >
                            <div className="flex items-center gap-3 flex-1 min-w-0">
                              {isSelectionMode && (
                                <Checkbox
                                  checked={selectedIds.has(contact.id)}
                                  onCheckedChange={() => toggleContactSelection(contact.id)}
                                  className="data-[state=checked]:bg-primary data-[state=checked]:border-primary"
                                />
                              )}
                              <SwipeableItem
                                onSwipeLeft={() => handleSwipeLeft(contact)}
                                onSwipeRight={() => handleSwipeRight(contact)}
                                className="flex-1 rounded-xl"
                              >
                                <ContactCard
                                  contact={contact}
                                  isSelected={selectedContactId === contact.id}
                                />
                              </SwipeableItem>
                            </div>
                          </motion.div>
                        ))}
                      </div>
                    </div>
                  </motion.div>
                )}
              </>
            )}
          </AnimatePresence>
        </div>
      </ScrollArea>
    </div >
  );
}