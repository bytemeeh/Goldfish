import { useQuery } from "@tanstack/react-query";
import { ContactCard } from "./ContactCard";
import { type Contact, type Location, type RelationshipType } from "@/lib/types";
import { ScrollArea } from "@/components/ui/scroll-area";
import type { SearchFilters } from "./SearchBar";
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
  RefreshCw
} from "lucide-react";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";
import { BirthdayReminder } from "./BirthdayReminder";

interface ContactListProps {
  searchFilters: SearchFilters;
  selectedContactId?: number | null;
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
    Math.sin(dLat/2) * Math.sin(dLat/2) +
    Math.cos(toRadians(latitude1)) * Math.cos(toRadians(latitude2)) * 
    Math.sin(dLon/2) * Math.sin(dLon/2);
  
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
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
          id: 0,
          type: 'other',
          latitude: contact.latitude,
          longitude: contact.longitude
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
type SortType = 'hierarchical' | 'proximity' | 'manual';

export function ContactList({ searchFilters, selectedContactId }: ContactListProps) {
  const { toast } = useToast();
  // Create refs for selected contact scrolling
  const contactRefs = useRef<Record<number, HTMLDivElement | null>>({});
  
  // Query to fetch contacts data
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

  // Pre-register all contacts for ref tracking
  useEffect(() => {
    if (contacts) {
      console.log('🚨 ContactList - Pre-registering all contacts for refs tracking');
      console.log('🚨 ContactList - Total contacts to register:', contacts.length);
      
      // Add all contact IDs to the refs object first, even with null values
      // This ensures the lookup works even before the elements are actually rendered
      contacts.forEach(contact => {
        if (contact && contact.id) {
          contactRefs.current[contact.id] = contactRefs.current[contact.id] || null;
        }
      });
    }
  }, [contacts]);
  
  // State hooks - must be called in the same order every render
  const [sortType, setSortType] = useState<SortType>('hierarchical');
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
  const [manualOrderIds, setManualOrderIds] = useState<number[]>([]);
  const [hiddenContactIds, setHiddenContactIds] = useState<Set<number>>(new Set());
  
  // Category order state for draggable categories
  const [categoryOrder, setCategoryOrder] = useState<string[]>(() => {
    // Load from localStorage or use default order
    const savedOrder = localStorage.getItem('category_order');
    return savedOrder ? JSON.parse(savedOrder) : categories.map(cat => cat.title);
  });
  
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
    const handleHideContact = (event: CustomEvent) => {
      const contactId = event.detail?.contactId;
      if (contactId) {
        setHiddenContactIds(prev => {
          const newSet = new Set(prev);
          newSet.add(contactId);
          return newSet;
        });
      }
    };
    
    window.addEventListener('contact:hide', handleHideContact as EventListener);
    
    return () => {
      window.removeEventListener('contact:hide', handleHideContact as EventListener);
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
          } catch(error) {
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

  // Apply proximity-based sorting if enabled
  const sortContactsByProximity = (contactsToSort: Contact[]) => {
    if (!proximitySort || !userLocation) return contactsToSort.sort((a, b) => a.name.localeCompare(b.name));
    
    return [...contactsToSort].sort((a, b) => {
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
    const visited = new Set<number>([contact.id]);
    
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
      const parentContact = contacts.find(c => c.id === currentId);
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
  const categorizedContacts = sortedCategories.map(category => {
    // Filter contacts by category
    const categoryContacts = categorizableContacts
      .filter(contact => 
        contact.relationshipType && 
        category.types.includes(contact.relationshipType)
      );
      
    // Apply additional filters  
    const filteredCategoryContacts = applyFilters(categoryContacts);
    
    return {
      ...category,
      contacts: filteredCategoryContacts.map(contact => ({
        ...contact,
        children: buildHierarchy(contact.id)
      }))
    };
  });

  // Handle uncategorized contacts
  const uncategorizedContacts = applyFilters(
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
        category.contacts = category.contacts.filter(contact => 
          !hiddenContactIds.has(contact.id)
        );
      });

      const visibleUncategorized = uncategorizedContacts.filter(
        contact => !hiddenContactIds.has(contact.id)
      );
      
      // Apply manual order if available
      if (manualOrderIds.length > 0) {
        // Create a map for quick lookup by ID
        const contactMap = new Map();
        contacts.forEach(c => contactMap.set(c.id, c));
        
        // Order contacts based on manual order
        const orderedContacts = manualOrderIds
          .map(id => contactMap.get(id))
          .filter(Boolean); // Remove any undefined entries
        
        // For any contacts not in manualOrderIds, maintain their position at the end
        const unorderedIds = new Set(manualOrderIds);
        const remainingContacts = contacts.filter(c => !unorderedIds.has(c.id));
        
        // Update each category with the manually ordered contacts
        categorizedContacts.forEach(category => {
          const categoryIds = new Set(category.contacts.map(c => c.id));
          category.contacts = orderedContacts
            .filter(c => categoryIds.has(c.id))
            .map(contact => ({
              ...contact,
              children: buildHierarchy(contact.id)
            }));
        });
        
        // Update uncategorized contacts
        const uncategorizedIds = new Set(uncategorizedContacts.map(c => c.id));
        uncategorizedContacts.splice(0, uncategorizedContacts.length, ...orderedContacts
          .filter(c => uncategorizedIds.has(c.id))
          .map(contact => ({
            ...contact,
            children: buildHierarchy(contact.id)
          })));
        
        // Add any remaining contacts that weren't in the manual order
        remainingContacts.forEach(contact => {
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
      <div className="space-y-3 bg-background sticky top-0 z-20 pt-2 pb-2 max-w-full">
        {/* Quick Filter Tabs */}
        <div>
          <div className="flex items-center justify-between mb-1.5">
            <span className="text-xs font-medium text-muted-foreground">Quick Filter:</span>
            {(relationshipFilter !== 'all' || relationLevelFilter !== 'all') && (
              <Button 
                variant="ghost" 
                size="sm" 
                className="h-6 px-2 py-0 text-xs" 
                onClick={() => {
                  setRelationshipFilter('all');
                  setRelationLevelFilter('all');
                }}
              >
                <X className="h-3 w-3 mr-1" />
                Clear
              </Button>
            )}
          </div>
          <Tabs value={relationshipFilter} onValueChange={(value) => {
              // Toggle off if same value clicked again
              if (value === relationshipFilter) {
                setRelationshipFilter('all');
              } else {
                setRelationshipFilter(value);
              }
            }} className="w-full">
            <TabsList className="grid grid-cols-4 gap-0.5 bg-transparent p-0 mb-1" style={{ maxWidth: 'calc(100% - 1px)' }}>
              <TabsTrigger 
                value="all" 
                className="flex-1 flex items-center justify-center h-7 px-2 py-0 text-xs rounded-md border bg-background/60 data-[state=active]:bg-primary/10 data-[state=active]:text-primary data-[state=active]:border-primary/30"
              >
                All
              </TabsTrigger>
              <TabsTrigger 
                value="family" 
                className="flex-1 flex items-center justify-center h-7 px-2 py-0 text-xs rounded-md border bg-background/60 data-[state=active]:bg-primary/10 data-[state=active]:text-primary data-[state=active]:border-primary/30"
              >
                <Users className="h-3 w-3 mr-1" />
                Family
              </TabsTrigger>
              <TabsTrigger 
                value="friend" 
                className="flex-1 flex items-center justify-center h-7 px-2 py-0 text-xs rounded-md border bg-background/60 data-[state=active]:bg-primary/10 data-[state=active]:text-primary data-[state=active]:border-primary/30"
              >
                <Heart className="h-3 w-3 mr-1" />
                Friends
              </TabsTrigger>
              <TabsTrigger 
                value="co-worker" 
                className="flex-1 flex items-center justify-center h-7 px-2 py-0 text-xs rounded-md border bg-background/60 data-[state=active]:bg-primary/10 data-[state=active]:text-primary data-[state=active]:border-primary/30"
              >
                <Briefcase className="h-3 w-3 mr-1" />
                Work
              </TabsTrigger>
            </TabsList>
          </Tabs>
          
          {/* Relationship Level Tabs */}
          <Tabs value={relationLevelFilter} onValueChange={(value) => {
              // Toggle off if same value clicked again
              if (value === relationLevelFilter) {
                setRelationLevelFilter('all');
              } else {
                setRelationLevelFilter(value);
              }
            }} className="w-full">
            <TabsList className="grid grid-cols-5 gap-0.5 bg-transparent p-0" style={{ maxWidth: 'calc(100% - 1px)' }}>
              <TabsTrigger 
                value="all" 
                className="flex-1 flex items-center justify-center h-7 px-2 py-0 text-xs rounded-md border bg-background/60 data-[state=active]:bg-primary/10 data-[state=active]:text-primary data-[state=active]:border-primary/30"
              >
                Any L
              </TabsTrigger>
              <TabsTrigger 
                value="1" 
                className="flex-1 flex items-center justify-center h-7 px-2 py-0 text-xs rounded-md border bg-background/60 data-[state=active]:bg-primary/10 data-[state=active]:text-primary data-[state=active]:border-primary/30"
              >
                L1
              </TabsTrigger>
              <TabsTrigger 
                value="2" 
                className="flex-1 flex items-center justify-center h-7 px-2 py-0 text-xs rounded-md border bg-background/60 data-[state=active]:bg-primary/10 data-[state=active]:text-primary data-[state=active]:border-primary/30"
              >
                L2
              </TabsTrigger>
              <TabsTrigger 
                value="3" 
                className="flex-1 flex items-center justify-center h-7 px-2 py-0 text-xs rounded-md border bg-background/60 data-[state=active]:bg-primary/10 data-[state=active]:text-primary data-[state=active]:border-primary/30"
              >
                L3
              </TabsTrigger>
              <TabsTrigger 
                value="4" 
                className="flex-1 flex items-center justify-center h-7 px-2 py-0 text-xs rounded-md border bg-background/60 data-[state=active]:bg-primary/10 data-[state=active]:text-primary data-[state=active]:border-primary/30"
              >
                L4
              </TabsTrigger>
            </TabsList>
          </Tabs>
        </div>
        
        {/* Sort Controls */}
        <div className="flex flex-col md:flex-row gap-2 px-1">
          <div className="flex flex-wrap gap-2 items-center">
            <div className="flex items-center space-x-2">
              <Button 
                size="sm" 
                variant={sortType === 'hierarchical' ? 'default' : 'outline'} 
                className="h-7 px-2 py-0 text-xs"
                onClick={() => setSortType('hierarchical')}
              >
                <Layers size="14" className="mr-1" />
                Hierarchy
              </Button>
            </div>
            
            <div className="flex items-center space-x-2">
              <Button 
                size="sm" 
                variant={sortType === 'proximity' ? 'default' : 'outline'} 
                className="h-7 px-2 py-0 text-xs"
                onClick={() => setSortType('proximity')}
              >
                <Navigation size="14" className="mr-1" />
                Distance
              </Button>
            </div>
            
            <div className="flex items-center space-x-2">
              <Button 
                size="sm" 
                variant={sortType === 'manual' ? 'default' : 'outline'} 
                className="h-7 px-2 py-0 text-xs"
                onClick={() => setSortType('manual')}
              >
                <ListFilter size="14" className="mr-1" />
                Manual
              </Button>
              
              {sortType === 'manual' ? (
                <TooltipProvider>
                  <Tooltip>
                    <TooltipTrigger asChild>
                      <Button
                        size="sm"
                        variant="ghost"
                        className="h-7 w-7 p-0"
                        onClick={() => {
                          // Reset manual sort order
                          setManualOrderIds([]);
                        }}
                      >
                        <RefreshCw size="14" />
                      </Button>
                    </TooltipTrigger>
                    <TooltipContent>
                      <p>Reset manual order</p>
                    </TooltipContent>
                  </Tooltip>
                </TooltipProvider>
              ) : (
                <TooltipProvider>
                  <Tooltip>
                    <TooltipTrigger asChild>
                      <div>
                        <Switch
                          checked={proximitySort}
                          onCheckedChange={toggleProximitySort}
                          disabled={sortType !== 'proximity'}
                        />
                      </div>
                    </TooltipTrigger>
                    <TooltipContent>
                      <p>Toggle proximity sorting</p>
                    </TooltipContent>
                  </Tooltip>
                </TooltipProvider>
              )}
            </div>
          </div>
          
          <div className="flex-1"></div>
          
          {/* Additional controls based on sort type */}
          {sortType === 'manual' && (
            <div className="flex items-center space-x-2">
              <Label htmlFor="show-hidden" className="text-xs font-normal text-muted-foreground">
                Show hidden:
              </Label>
              <Switch
                id="show-hidden"
                checked={false}
                onCheckedChange={(checked) => {
                  if (checked) {
                    setHiddenContactIds(new Set());
                  }
                }}
              />
            </div>
          )}
        </div>
      </div>
      
      {/* Optional Birthday Reminder Section */}
      {contacts && contacts.length > 0 && (
        <BirthdayReminder contacts={contacts} />
      )}
      
      {/* Contact List */}
      <div className="space-y-4">
        {/* Personal Contact Card */}
        {personalHierarchy && (
          <div className="mb-4 max-w-full">
            <div className="mb-2 px-1">
              <Badge 
                className="bg-primary/15 hover:bg-primary/20 text-primary px-2.5 py-1" 
                variant="outline"
              >
                <Network className="h-3 w-3 mr-1.5 text-primary" />
                <span className="font-medium">My Card</span>
              </Badge>
            </div>
            <div
              ref={element => {
                contactRefs.current[personalHierarchy.id] = element;
              }}
            >
              <ContactCard 
                contact={personalHierarchy} 
                children={personalHierarchy.children}
                level={0}
                isSelected={selectedContactId === personalHierarchy.id}
              />
            </div>
          </div>
        )}
        
        {/* Categorized Contacts */}
        {sortType === 'manual' ? (
          // Manual sort mode (draggable categories)
          <AnimatePresence>
            {categoryOrder.map(categoryTitle => {
              const category = categorizedContacts.find(c => c.title === categoryTitle);
              if (!category) return null;
              
              // Skip empty categories unless in manual sort mode
              if (category.contacts.length === 0) return null;
              
              return (
                <motion.div
                  key={category.title}
                  className="mb-4"
                  initial={{ opacity: 0, y: 20 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, height: 0 }}
                  transition={{ type: "spring", bounce: 0.2 }}
                >
                  <div className="flex items-center justify-between px-1 mb-2">
                    <Badge 
                      className={`px-2.5 py-1`}
                      variant="outline"
                      style={{ 
                        backgroundColor: `${category.color}15`, 
                        color: category.color, 
                        borderColor: `${category.color}30`
                      }}
                    >
                      <GripVertical className="h-3 w-3 mr-1.5 cursor-move" />
                      <span className="font-medium">{category.title}</span>
                      <span className="ml-1 opacity-60">({category.contacts.length})</span>
                    </Badge>
                    
                    {/* Hide all in category button */}
                    <TooltipProvider>
                      <Tooltip>
                        <TooltipTrigger asChild>
                          <Button 
                            variant="ghost" 
                            size="sm" 
                            className="h-6 w-6 p-0" 
                            onClick={() => {
                              // Hide all contacts in this category
                              const newHidden = new Set(hiddenContactIds);
                              category.contacts.forEach(contact => {
                                newHidden.add(contact.id);
                              });
                              setHiddenContactIds(newHidden);
                            }}
                          >
                            <EyeOff className="h-3.5 w-3.5" />
                          </Button>
                        </TooltipTrigger>
                        <TooltipContent>
                          <p>Hide all in category</p>
                        </TooltipContent>
                      </Tooltip>
                    </TooltipProvider>
                  </div>
                  
                  <div className="space-y-2 mb-2">
                    <Reorder.Group 
                      axis="y" 
                      values={category.contacts} 
                      onReorder={(newOrder) => {
                        // Update the manual order IDs
                        const newManualOrderIds = [...manualOrderIds];
                        
                        // First, remove any IDs from this category
                        const categoryIds = new Set(category.contacts.map(c => c.id));
                        const filteredOrderIds = newManualOrderIds.filter(id => !categoryIds.has(id));
                        
                        // Then, add the new order
                        const newOrderIds = newOrder.map(c => c.id);
                        
                        // Find the position to insert - either after the last ID from a previous category
                        // or at the beginning
                        setManualOrderIds([...filteredOrderIds, ...newOrderIds]);
                        
                        // Update the category in the categorizedContacts array
                        const updatedCategories = categorizedContacts.map(c => 
                          c.title === category.title 
                            ? { ...c, contacts: newOrder } 
                            : c
                        );
                      }}
                      className="space-y-2"
                    >
                      {category.contacts.map(contact => (
                        <Reorder.Item
                          key={contact.id}
                          value={contact}
                          className="cursor-grab active:cursor-grabbing"
                        >
                          <div
                            ref={element => {
                              contactRefs.current[contact.id] = element;
                            }}
                          >
                            <ContactCard 
                              contact={contact}
                              children={contact.children}
                              level={getRelationshipLevel(contact)}
                              manualSortMode={true}
                              onChildrenReorder={(newChildren) => {
                                // Implement children reordering logic
                                const newOrderIds = [...manualOrderIds];
                                const childIds = new Set(contact.children?.map(c => c.id) || []);
                                const filteredOrderIds = newOrderIds.filter(id => !childIds.has(id));
                                const newChildOrderIds = newChildren.map(c => c.id);
                                setManualOrderIds([...filteredOrderIds, ...newChildOrderIds]);
                              }}
                              isSelected={selectedContactId === contact.id}
                            />
                          </div>
                        </Reorder.Item>
                      ))}
                    </Reorder.Group>
                  </div>
                </motion.div>
              );
            })}
            
            {/* Uncategorized Contacts in Manual Mode */}
            {uncategorizedContacts.length > 0 && (
              <motion.div
                className="mb-4"
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, height: 0 }}
                transition={{ type: "spring", bounce: 0.2 }}
              >
                <div className="flex items-center justify-between px-1 mb-2">
                  <Badge 
                    className="px-2.5 py-1 bg-muted hover:bg-muted/80 border-border"
                    variant="outline"
                  >
                    <GripVertical className="h-3 w-3 mr-1.5 cursor-move" />
                    <span className="font-medium">Other</span>
                    <span className="ml-1 opacity-60">({uncategorizedContacts.length})</span>
                  </Badge>
                  
                  {/* Hide all in uncategorized button */}
                  <TooltipProvider>
                    <Tooltip>
                      <TooltipTrigger asChild>
                        <Button 
                          variant="ghost" 
                          size="sm" 
                          className="h-6 w-6 p-0" 
                          onClick={() => {
                            // Hide all uncategorized contacts
                            const newHidden = new Set(hiddenContactIds);
                            uncategorizedContacts.forEach(contact => {
                              newHidden.add(contact.id);
                            });
                            setHiddenContactIds(newHidden);
                          }}
                        >
                          <EyeOff className="h-3.5 w-3.5" />
                        </Button>
                      </TooltipTrigger>
                      <TooltipContent>
                        <p>Hide all uncategorized</p>
                      </TooltipContent>
                    </Tooltip>
                  </TooltipProvider>
                </div>
                
                <div className="space-y-2">
                  <Reorder.Group 
                    axis="y" 
                    values={uncategorizedContacts} 
                    onReorder={(newOrder) => {
                      // Update the manual order IDs
                      const newManualOrderIds = [...manualOrderIds];
                      
                      // First, remove any IDs from uncategorized
                      const uncatIds = new Set(uncategorizedContacts.map(c => c.id));
                      const filteredOrderIds = newManualOrderIds.filter(id => !uncatIds.has(id));
                      
                      // Then, add the new order
                      const newOrderIds = newOrder.map(c => c.id);
                      
                      setManualOrderIds([...filteredOrderIds, ...newOrderIds]);
                      
                      // Update the uncategorized contacts
                      uncategorizedContacts.splice(0, uncategorizedContacts.length, ...newOrder);
                    }}
                    className="space-y-2"
                  >
                    {uncategorizedContacts.map(contact => (
                      <Reorder.Item
                        key={contact.id}
                        value={contact}
                        className="cursor-grab active:cursor-grabbing"
                      >
                        <div
                          ref={element => {
                            contactRefs.current[contact.id] = element;
                          }}
                        >
                          <ContactCard 
                            contact={contact}
                            children={contact.children}
                            level={getRelationshipLevel(contact)}
                            manualSortMode={true}
                            onChildrenReorder={(newChildren) => {
                              // Implement children reordering logic
                              const newOrderIds = [...manualOrderIds];
                              const childIds = new Set(contact.children?.map(c => c.id) || []);
                              const filteredOrderIds = newOrderIds.filter(id => !childIds.has(id));
                              const newChildOrderIds = newChildren.map(c => c.id);
                              setManualOrderIds([...filteredOrderIds, ...newChildOrderIds]);
                            }}
                            isSelected={selectedContactId === contact.id}
                          />
                        </div>
                      </Reorder.Item>
                    ))}
                  </Reorder.Group>
                </div>
              </motion.div>
            )}
          </AnimatePresence>
        ) : (
          // Non-draggable categories (hierarchical or proximity sort)
          <AnimatePresence>
            {categoryOrder.map(categoryTitle => {
              const category = categorizedContacts.find(c => c.title === categoryTitle);
              if (!category) return null;
              
              // Skip empty categories
              if (category.contacts.length === 0) return null;
              
              return (
                <motion.div
                  key={category.title}
                  className="mb-4"
                  initial={{ opacity: 0, y: 20 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, height: 0 }}
                  transition={{ type: "spring", bounce: 0.2 }}
                >
                  <div className="flex items-center justify-between px-1 mb-2">
                    <Badge 
                      className={`px-2.5 py-1`}
                      variant="outline"
                      style={{ 
                        backgroundColor: `${category.color}15`, 
                        color: category.color, 
                        borderColor: `${category.color}30`
                      }}
                    >
                      <span className="font-medium">{category.title}</span>
                      <span className="ml-1 opacity-60">({category.contacts.length})</span>
                    </Badge>
                  </div>
                  
                  <div className="space-y-2 mb-2">
                    {category.contacts.map(contact => (
                      <div 
                        key={contact.id} 
                        className="transition-all duration-200"
                        ref={element => {
                          contactRefs.current[contact.id] = element;
                        }}
                      >
                        <ContactCard 
                          contact={contact}
                          children={contact.children}
                          level={getRelationshipLevel(contact)}
                          relationshipLevel={getRelationshipLevel(contact)}
                          isSelected={selectedContactId === contact.id}
                        />
                      </div>
                    ))}
                  </div>
                </motion.div>
              );
            })}
            
            {/* Uncategorized Contacts */}
            {uncategorizedContacts.length > 0 && (
              <motion.div
                className="mb-4"
                initial={{ opacity: 0, y: 20 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, height: 0 }}
                transition={{ type: "spring", bounce: 0.2 }}
              >
                <div className="flex items-center justify-between px-1 mb-2">
                  <Badge 
                    className="px-2.5 py-1 bg-muted hover:bg-muted/80 border-border"
                    variant="outline"
                  >
                    <span className="font-medium">Other</span>
                    <span className="ml-1 opacity-60">({uncategorizedContacts.length})</span>
                  </Badge>
                </div>
                
                <div className="space-y-2">
                  {uncategorizedContacts.map(contact => (
                    <div
                      key={contact.id}
                      ref={element => {
                        contactRefs.current[contact.id] = element;
                      }}
                    >
                      <ContactCard 
                        contact={contact}
                        children={contact.children}
                        level={getRelationshipLevel(contact)}
                        relationshipLevel={getRelationshipLevel(contact)}
                        isSelected={selectedContactId === contact.id}
                      />
                    </div>
                  ))}
                </div>
              </motion.div>
            )}
          </AnimatePresence>
        )}
      </div>
    </div>
  );
}
