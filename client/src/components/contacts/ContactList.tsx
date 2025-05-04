import { useQuery } from "@tanstack/react-query";
import { ContactCard } from "./ContactCard";
import { type Contact, type Location, type RelationshipType } from "@/lib/types";
import { ScrollArea } from "@/components/ui/scroll-area";
import type { SearchFilters } from "./SearchBar";
import { motion, AnimatePresence } from "framer-motion";
import { Button } from "@/components/ui/button";
import { useToast } from "@/hooks/use-toast";
import { useState } from "react";
import { Check, Navigation, X, Users, Briefcase, Heart } from "lucide-react";
import { Switch } from "@/components/ui/switch";
import { Label } from "@/components/ui/label";
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from "@/components/ui/tooltip";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Badge } from "@/components/ui/badge";

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

export function ContactList({ searchFilters }: ContactListProps) {
  const { toast } = useToast();
  const [proximitySort, setProximitySort] = useState(false);
  const [userLocation, setUserLocation] = useState<{ latitude: number; longitude: number } | null>(null);
  const [isGettingLocation, setIsGettingLocation] = useState(false);
  const [relationshipFilter, setRelationshipFilter] = useState<string>("all");
  const [relationLevelFilter, setRelationLevelFilter] = useState<string>("all");
  
  // Get user's current location
  const getCurrentLocation = () => {
    if (!navigator.geolocation) {
      toast({
        title: "Error",
        description: "Geolocation is not supported by your browser",
        variant: "destructive",
      });
      return;
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
      },
      (error) => {
        setIsGettingLocation(false);
        toast({
          title: "Error",
          description: `Failed to get your location: ${error.message}`,
          variant: "destructive",
        });
      }
    );
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

  // Create categorized groups
  const categorizedContacts = categories.map(category => {
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

  // Apply proximity-based sorting if enabled
  if (proximitySort && userLocation) {
    categorizedContacts.forEach(category => {
      category.contacts = sortContactsByProximity(category.contacts);
    });
    
    uncategorizedContacts.sort((a, b) => {
      const locationA = getClosestLocation(a, userLocation.latitude, userLocation.longitude);
      const locationB = getClosestLocation(b, userLocation.latitude, userLocation.longitude);
      return locationA.distance - locationB.distance;
    });
  } else {
    // Default sorting by name
    categorizedContacts.forEach(category => {
      category.contacts.sort((a, b) => a.name.localeCompare(b.name));
    });
    uncategorizedContacts.sort((a, b) => a.name.localeCompare(b.name));
  }
  
  return (
    <div className="space-y-4">
      {/* Filters and Controls Section */}
      <div className="space-y-4 bg-background sticky top-0 z-20 pt-2 pb-2 max-w-full">
        {/* Relationship Type Tabs */}
        <div className="space-y-1">
          <div className="flex items-center justify-between">
            <span className="text-xs font-medium text-muted-foreground">Relationship Type:</span>
            {relationshipFilter !== 'all' && (
              <Button 
                variant="ghost" 
                size="sm" 
                className="h-6 px-2 text-xs" 
                onClick={() => setRelationshipFilter('all')}
              >
                <X className="h-3 w-3 mr-1" />
                Clear
              </Button>
            )}
          </div>
          <Tabs value={relationshipFilter} onValueChange={setRelationshipFilter} className="w-full">
            <TabsList className="w-full h-auto flex flex-wrap bg-muted/50 p-1 mb-1">
              <TabsTrigger 
                value="all" 
                className="flex items-center h-7 px-2 py-0 text-xs data-[state=active]:bg-background"
              >
                All
              </TabsTrigger>
              <TabsTrigger 
                value="mother" 
                className="flex items-center h-7 px-2 py-0 text-xs data-[state=active]:bg-background"
              >
                <Badge variant="outline" className="mr-1.5 h-4 px-1 text-[10px] font-normal bg-[hsl(var(--chart-1))/10]">F</Badge>
                Mother
              </TabsTrigger>
              <TabsTrigger 
                value="father" 
                className="flex items-center h-7 px-2 py-0 text-xs data-[state=active]:bg-background"
              >
                <Badge variant="outline" className="mr-1.5 h-4 px-1 text-[10px] font-normal bg-[hsl(var(--chart-1))/10]">F</Badge>
                Father
              </TabsTrigger>
              <TabsTrigger 
                value="sibling" 
                className="flex items-center h-7 px-2 py-0 text-xs data-[state=active]:bg-background"
              >
                <Badge variant="outline" className="mr-1.5 h-4 px-1 text-[10px] font-normal bg-[hsl(var(--chart-1))/10]">F</Badge>
                Sibling
              </TabsTrigger>
              <TabsTrigger 
                value="child" 
                className="flex items-center h-7 px-2 py-0 text-xs data-[state=active]:bg-background"
              >
                <Badge variant="outline" className="mr-1.5 h-4 px-1 text-[10px] font-normal bg-[hsl(var(--chart-1))/10]">F</Badge>
                Child
              </TabsTrigger>
              <TabsTrigger 
                value="spouse" 
                className="flex items-center h-7 px-2 py-0 text-xs data-[state=active]:bg-background"
              >
                <Badge variant="outline" className="mr-1.5 h-4 px-1 text-[10px] font-normal bg-[hsl(var(--chart-1))/10]">F</Badge>
                Spouse
              </TabsTrigger>
              <TabsTrigger 
                value="friend" 
                className="flex items-center h-7 px-2 py-0 text-xs data-[state=active]:bg-background"
              >
                <Badge variant="outline" className="mr-1.5 h-4 px-1 text-[10px] font-normal bg-[hsl(var(--chart-2))/10]">F</Badge>
                Friend
              </TabsTrigger>
              <TabsTrigger 
                value="boyfriend/girlfriend" 
                className="flex items-center h-7 px-2 py-0 text-xs data-[state=active]:bg-background"
              >
                <Badge variant="outline" className="mr-1.5 h-4 px-1 text-[10px] font-normal bg-[hsl(var(--chart-2))/10]">F</Badge>
                Partner
              </TabsTrigger>
              <TabsTrigger 
                value="co-worker" 
                className="flex items-center h-7 px-2 py-0 text-xs data-[state=active]:bg-background"
              >
                <Badge variant="outline" className="mr-1.5 h-4 px-1 text-[10px] font-normal bg-[hsl(var(--chart-3))/10]">P</Badge>
                Co-worker
              </TabsTrigger>
            </TabsList>
          </Tabs>
        </div>

        {/* Relationship Level Tabs */}
        <div className="space-y-1">
          <div className="flex items-center justify-between">
            <span className="text-xs font-medium text-muted-foreground">Relation Level:</span>
            {relationLevelFilter !== 'all' && (
              <Button 
                variant="ghost" 
                size="sm" 
                className="h-6 px-2 text-xs" 
                onClick={() => setRelationLevelFilter('all')}
              >
                <X className="h-3 w-3 mr-1" />
                Clear
              </Button>
            )}
          </div>
          <Tabs value={relationLevelFilter} onValueChange={setRelationLevelFilter} className="w-full">
            <TabsList className="w-full bg-muted/50 p-1">
              <TabsTrigger value="all" className="text-xs h-7 data-[state=active]:bg-background">All</TabsTrigger>
              <TabsTrigger value="1" className="text-xs h-7 data-[state=active]:bg-background">1st Level</TabsTrigger>
              <TabsTrigger value="2" className="text-xs h-7 data-[state=active]:bg-background">2nd Level</TabsTrigger>
              <TabsTrigger value="3" className="text-xs h-7 data-[state=active]:bg-background">3rd Level</TabsTrigger>
              <TabsTrigger value="4" className="text-xs h-7 data-[state=active]:bg-background">4th Level</TabsTrigger>
            </TabsList>
          </Tabs>
        </div>

        {/* Location Controls */}
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div className="flex items-center space-x-1">
            <Switch
              id="proximity-sort"
              checked={proximitySort}
              onCheckedChange={setProximitySort}
              disabled={!userLocation || isGettingLocation}
            />
            <Label htmlFor="proximity-sort" className="text-sm font-medium cursor-pointer">
              Sort by proximity
            </Label>
          </div>
          
          <TooltipProvider>
            <Tooltip>
              <TooltipTrigger asChild>
                <Button
                  variant="outline"
                  size="sm"
                  className="ml-auto flex items-center gap-1 h-8 flex-shrink-0"
                  onClick={getCurrentLocation}
                  disabled={isGettingLocation}
                >
                  {isGettingLocation ? (
                    <span className="animate-pulse text-xs">Getting location...</span>
                  ) : (
                    <>
                      <Navigation className="h-3.5 w-3.5" />
                      <span className="text-xs hidden sm:inline">
                        {userLocation ? 'Update location' : 'Get current location'}
                      </span>
                      {userLocation && <Check className="h-3.5 w-3.5 ml-1 text-green-500" />}
                    </>
                  )}
                </Button>
              </TooltipTrigger>
              <TooltipContent side="bottom">
                <p>Use your current location for proximity-based sorting</p>
              </TooltipContent>
            </Tooltip>
          </TooltipProvider>
        </div>
      </div>
      
      <ScrollArea className="h-[calc(100vh-14rem)] pr-4">
        <div className="space-y-8 py-2">
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
    </div>
  );
}