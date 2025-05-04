import { useState, useEffect } from "react";
import { Location, LocationType } from "@/lib/types";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { MapPin, Home, Briefcase, Map, Plus, Trash, Save, Search } from "lucide-react";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { useJsApiLoader } from "@react-google-maps/api";

interface LocationListProps {
  locations: Location[];
  onChange: (locations: Location[]) => void;
  disabled?: boolean;
}

export function LocationList({ locations = [], onChange, disabled = false }: LocationListProps) {
  const [activeLocationId, setActiveLocationId] = useState<string | null>(null);
  
  // Load Google Maps API
  const { isLoaded } = useJsApiLoader({
    id: 'google-map-script',
    googleMapsApiKey: import.meta.env.VITE_GOOGLE_MAPS_API_KEY || '',
    libraries: ['places'],
  });

  const handleAddLocation = () => {
    const newLocation: Location = {
      id: Math.random() * -1000, // Temporary negative ID
      type: "other" as LocationType,
      name: "",
      address: "",
      latitude: "",
      longitude: "",
      isNew: true,
    };
    
    const newLocations = [...locations, newLocation];
    onChange(newLocations);
    setActiveLocationId(String(newLocation.id));
  };

  const handleLocationChange = (index: number, updatedLocation: Partial<Location>) => {
    const newLocations = [...locations];
    newLocations[index] = { ...newLocations[index], ...updatedLocation };
    onChange(newLocations);
  };

  const handleDeleteLocation = (index: number) => {
    const location = locations[index];
    
    if (location.id && location.id > 0) {
      // Mark existing location for deletion instead of removing it from the array
      const newLocations = [...locations];
      newLocations[index] = { ...newLocations[index], isDeleted: true };
      onChange(newLocations);
    } else {
      // Remove new location from array
      const newLocations = locations.filter((_, i) => i !== index);
      onChange(newLocations);
    }
    
    setActiveLocationId(null);
  };

  const getLocationTypeIcon = (type: LocationType) => {
    switch (type) {
      case "home":
        return <Home className="h-4 w-4" />;
      case "work":
        return <Briefcase className="h-4 w-4" />;
      default:
        return <MapPin className="h-4 w-4" />;
    }
  };

  // Filter out deleted locations for display
  const visibleLocations = locations.filter(loc => !loc.isDeleted);

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-medium">Locations</h3>
        <Button 
          type="button" 
          size="sm" 
          variant="outline" 
          onClick={handleAddLocation}
          className="flex items-center gap-1"
          disabled={disabled}
        >
          <Plus className="h-3.5 w-3.5" />
          Add Location
        </Button>
      </div>

      {visibleLocations.length === 0 ? (
        <div className="flex flex-col items-center justify-center p-4 border border-dashed rounded-lg bg-muted/20">
          <MapPin className="h-8 w-8 text-muted-foreground/50 mb-2" />
          <p className="text-sm text-muted-foreground text-center">No locations added yet</p>
          <Button 
            type="button" 
            variant="secondary" 
            size="sm" 
            className="mt-2" 
            onClick={handleAddLocation}
            disabled={disabled}
          >
            <Plus className="h-3.5 w-3.5 mr-1" />
            Add First Location
          </Button>
        </div>
      ) : (
        <div className="grid gap-3">
          {visibleLocations.map((location, index) => (
            <Card key={location.id || index} className="overflow-hidden border">
              <div className="p-3 bg-muted/10 border-b flex items-center justify-between">
                <div className="flex items-center gap-2">
                  {getLocationTypeIcon(location.type)}
                  <span className="font-medium">
                    {location.name || location.type.charAt(0).toUpperCase() + location.type.slice(1)}
                  </span>
                </div>
                <Button 
                  type="button" 
                  variant="ghost" 
                  size="sm" 
                  onClick={() => handleDeleteLocation(index)}
                  disabled={disabled}
                >
                  <Trash className="h-4 w-4 text-destructive" />
                </Button>
              </div>
              
              <CardContent className="p-3">
                <div className="space-y-3">
                  <div className="grid gap-2 grid-cols-2">
                    <div>
                      <Label htmlFor={`location-${index}-type`}>Type</Label>
                      <Select 
                        value={location.type} 
                        onValueChange={(value) => handleLocationChange(index, { type: value as LocationType })}
                        disabled={disabled}
                      >
                        <SelectTrigger id={`location-${index}-type`}>
                          <SelectValue placeholder="Select type" />
                        </SelectTrigger>
                        <SelectContent>
                          <SelectItem value="home">Home</SelectItem>
                          <SelectItem value="work">Work</SelectItem>
                          <SelectItem value="other">Other</SelectItem>
                        </SelectContent>
                      </Select>
                    </div>
                    <div>
                      <Label htmlFor={`location-${index}-name`}>Name (Optional)</Label>
                      <Input 
                        id={`location-${index}-name`}
                        value={location.name || ''}
                        onChange={(e) => handleLocationChange(index, { name: e.target.value })}
                        placeholder="John's Office"
                        disabled={disabled}
                      />
                    </div>
                  </div>

                  <div>
                    <Label htmlFor={`location-${index}-address`}>Full Address</Label>
                    <div className="flex gap-2">
                      <div className="flex-1">
                        <Input 
                          id={`location-${index}-address`}
                          value={location.address || ''}
                          onChange={(e) => handleLocationChange(index, { address: e.target.value })}
                          placeholder="123 Main St, City, State, Country"
                          disabled={disabled}
                        />
                      </div>
                      <Button
                        type="button"
                        variant="outline"
                        size="icon"
                        onClick={() => {
                          // Open the address search dialog
                          if (typeof window !== 'undefined') {
                            const geocoder = new google.maps.Geocoder();
                            if (location.address) {
                              geocoder.geocode({ address: location.address }, (results, status) => {
                                if (status === 'OK' && results && results[0]) {
                                  const pos = {
                                    lat: results[0].geometry.location.lat(),
                                    lng: results[0].geometry.location.lng()
                                  };
                                  handleLocationChange(index, {
                                    address: results[0].formatted_address,
                                    latitude: pos.lat.toString(),
                                    longitude: pos.lng.toString()
                                  });
                                }
                              });
                            }
                          }
                        }}
                        disabled={!location.address || disabled}
                        title="Search for this address"
                      >
                        <Search className="h-4 w-4" />
                      </Button>
                    </div>
                  </div>

                  {/* Latitude and longitude fields are now hidden and autofilled by the address search */}
                  <input type="hidden" id={`location-${index}-lat`} value={location.latitude || ''} />
                  <input type="hidden" id={`location-${index}-lng`} value={location.longitude || ''} />
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}