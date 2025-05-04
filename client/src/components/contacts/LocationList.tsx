import { useState, useEffect } from "react";
import { Location, LocationType } from "@/lib/types";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { MapPin, Home, Briefcase, Map, Plus, Trash, Save, Search } from "lucide-react";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

// Add window.google types for TypeScript
declare global {
  interface Window {
    google: {
      maps: {
        places: {
          Autocomplete: new (input: HTMLInputElement, options?: any) => any;
        };
        Geocoder: new () => {
          geocode: (request: { address: string }, callback: (results: any[], status: string) => void) => void;
        };
        GeocoderStatus: {
          OK: string;
        };
      };
    };
  }
}

interface LocationListProps {
  locations: Location[];
  onChange: (locations: Location[]) => void;
  disabled?: boolean;
}

export function LocationList({ locations = [], onChange, disabled = false }: LocationListProps) {
  const [activeLocationId, setActiveLocationId] = useState<string | null>(null);
  
  // Don't use the Google Maps JS API Loader in this component
  // We'll just check if the Google Maps API is available globally
  const [isGoogleMapsLoaded, setIsGoogleMapsLoaded] = useState(false);
  
  useEffect(() => {
    // Check if Google Maps is already loaded
    const checkGoogleMapsLoaded = () => {
      if (window.google && window.google.maps) {
        setIsGoogleMapsLoaded(true);
      } else {
        setTimeout(checkGoogleMapsLoaded, 100);
      }
    };
    
    checkGoogleMapsLoaded();
  }, []);

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

  // Function to handle clicking on an address prediction in the dropdown
  const handleAddressPredictionClick = (address: string, lat: string, lng: string, index: number) => {
    handleLocationChange(index, {
      address: address,
      latitude: lat,
      longitude: lng
    });
  };

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
                      <div className="flex-1" ref={(el) => {
                        // Setup autocomplete for each address input
                        if (isGoogleMapsLoaded && el && !el.getAttribute('data-autocomplete-setup')) {
                          const input = el.querySelector('input') as HTMLInputElement;
                          if (input) {
                            const autocomplete = new window.google.maps.places.Autocomplete(input, {
                              fields: ['address_components', 'formatted_address', 'geometry'],
                              types: ['address']
                            });
                            
                            // Enhanced place_changed handler with better feedback
                            autocomplete.addListener('place_changed', () => {
                              const place = autocomplete.getPlace();
                              if (place.geometry && place.geometry.location) {
                                const pos = {
                                  lat: place.geometry.location.lat(),
                                  lng: place.geometry.location.lng()
                                };
                                
                                // Use our helper function for consistent feedback
                                createSuccessIndicator(
                                  input,
                                  place.formatted_address || '',
                                  pos.lat.toString(),
                                  pos.lng.toString()
                                );
                              }
                            });
                            
                            // Enable enter key behavior for search
                            input.addEventListener('keydown', (e) => {
                              if (e.key === 'Enter' && input.value) {
                                e.preventDefault();
                                
                                // Use geocoding to get the address
                                const geocoder = new window.google.maps.Geocoder();
                                geocoder.geocode({ address: input.value }, (results, status) => {
                                  if (status === window.google.maps.GeocoderStatus.OK && results && results[0]) {
                                    const pos = {
                                      lat: results[0].geometry.location.lat(),
                                      lng: results[0].geometry.location.lng()
                                    };
                                    
                                    // Use our helper function for consistent feedback
                                    createSuccessIndicator(
                                      input,
                                      results[0].formatted_address,
                                      pos.lat.toString(),
                                      pos.lng.toString()
                                    );
                                  }
                                });
                              }
                            });
                            
                            // Create a function to create the success indicator
                            const createSuccessIndicator = (targetInput: HTMLInputElement, formattedAddress: string, lat: string, lng: string) => {
                              // Update input with formatted address
                              targetInput.value = formattedAddress;
                              
                              // Update the model data
                              handleLocationChange(index, {
                                address: formattedAddress,
                                latitude: lat,
                                longitude: lng
                              });
                              
                              // Add visual feedback
                              targetInput.classList.add('address-selected');
                              
                              // Create success indicator
                              const successIndicator = document.createElement('div');
                              successIndicator.className = 'address-success-indicator';
                              successIndicator.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"></path><polyline points="22 4 12 14.01 9 11.01"></polyline></svg><span>Address selected</span>';
                              
                              // Add to DOM
                              const inputContainer = targetInput.parentElement;
                              if (inputContainer && inputContainer.parentElement) {
                                inputContainer.parentElement.appendChild(successIndicator);
                                
                                // Clean up after animation
                                setTimeout(() => {
                                  targetInput.classList.remove('address-selected');
                                  successIndicator.classList.add('fade-out');
                                  setTimeout(() => {
                                    if (successIndicator.parentElement) {
                                      successIndicator.parentElement.removeChild(successIndicator);
                                    }
                                  }, 500);
                                }, 2000);
                              }
                            };
                            
                            // Special handling for clicks in the container
                            document.addEventListener('click', (e) => {
                              const target = e.target as Element;
                              // Check if this is a click on a prediction item
                              if (target.closest('.pac-item') && target.closest('.pac-container')) {
                                setTimeout(() => {
                                  // The Google Places Autocomplete populates the input on click
                                  // but doesn't trigger the place_changed event by itself
                                  // We need to manually trigger a geocode to get coordinates
                                  if (input.value) {
                                    const geocoder = new window.google.maps.Geocoder();
                                    geocoder.geocode({ address: input.value }, (results, status) => {
                                      if (status === window.google.maps.GeocoderStatus.OK && results && results[0]) {
                                        const pos = {
                                          lat: results[0].geometry.location.lat(),
                                          lng: results[0].geometry.location.lng()
                                        };
                                        
                                        // Use our helper function for consistent feedback
                                        createSuccessIndicator(
                                          input,
                                          results[0].formatted_address,
                                          pos.lat.toString(),
                                          pos.lng.toString()
                                        );
                                      }
                                    });
                                  }
                                }, 300); // Small delay to let input update
                              }
                            });
                            
                            el.setAttribute('data-autocomplete-setup', 'true');
                          }
                        }
                      }}>
                        <div className="relative">
                          <Input 
                            id={`location-${index}-address`}
                            value={location.address || ''}
                            onChange={(e) => handleLocationChange(index, { address: e.target.value })}
                            placeholder="123 Main St, City, State, Country"
                            disabled={disabled}
                            className="w-full"
                          />
                          {/* Custom address predictions dropdown */}
                          <div id={`pac-container-${index}`} className="pac-container" style={{ display: 'none', position: 'absolute', width: '100%', zIndex: 50 }}></div>
                        </div>
                      </div>
                      <Button
                        type="button"
                        variant="outline"
                        size="icon"
                        onClick={() => {
                          // Open the address search dialog
                          if (isGoogleMapsLoaded && location.address) {
                            const inputField = document.getElementById(`location-${index}-address`) as HTMLInputElement;
                            
                            // Standard geocoding approach for the search button
                            // This will be used when the autocomplete isn't used directly
                            const geocoder = new window.google.maps.Geocoder();
                            geocoder.geocode({ address: location.address }, (results, status) => {
                              if (status === window.google.maps.GeocoderStatus.OK && results && results[0]) {
                                const pos = {
                                  lat: results[0].geometry.location.lat(),
                                  lng: results[0].geometry.location.lng()
                                };
                                
                                // Use our helper function for consistent feedback
                                if (inputField) {
                                  createSuccessIndicator(
                                    inputField,
                                    results[0].formatted_address,
                                    pos.lat.toString(),
                                    pos.lng.toString()
                                  );
                                }
                              }
                            });
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
                  <input 
                    type="hidden" 
                    id={`location-${index}-lat`} 
                    value={location.latitude || '0'} 
                  />
                  <input 
                    type="hidden" 
                    id={`location-${index}-lng`} 
                    value={location.longitude || '0'} 
                  />
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}