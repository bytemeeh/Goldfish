import { useState, useCallback, useEffect, useRef } from 'react';
import { GoogleMap, Marker, useJsApiLoader, Autocomplete } from '@react-google-maps/api';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { MapPin, Search, Loader2 } from 'lucide-react';
import { analytics } from '@/lib/analytics';

interface Location {
  address?: string;
  latitude: string | null;
  longitude: string | null;
  name?: string;
}

interface LocationPickerProps {
  value: Location;
  onChange: (location: Location) => void;
}

const containerStyle = {
  width: '100%',
  height: '300px',
  borderRadius: '0.5rem',
};

const defaultCenter = {
  lat: 51.505, // Default location (London)
  lng: -0.09
};

export function LocationPicker({ value, onChange }: LocationPickerProps) {
  const [locationName, setLocationName] = useState('');
  const [searchTerm, setSearchTerm] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const autocompleteRef = useRef<google.maps.places.Autocomplete | null>(null);
  const searchInputRef = useRef<HTMLInputElement | null>(null);

  const [mapCenter, setMapCenter] = useState<google.maps.LatLngLiteral>(
    value.latitude && value.longitude
      ? {
        lat: parseFloat(value.latitude),
        lng: parseFloat(value.longitude)
      }
      : defaultCenter
  );
  const [marker, setMarker] = useState<google.maps.LatLngLiteral | null>(
    value.latitude && value.longitude
      ? {
        lat: parseFloat(value.latitude),
        lng: parseFloat(value.longitude)
      }
      : null
  );

  // Log environment variables for debugging (will be redacted in production)
  console.log('VITE_GOOGLE_MAPS_API_KEY available:', !!import.meta.env.VITE_GOOGLE_MAPS_API_KEY);

  const { isLoaded, loadError } = useJsApiLoader({
    id: 'google-map-script',
    googleMapsApiKey: import.meta.env.VITE_GOOGLE_MAPS_API_KEY || 'AIzaSyDmk73iGX4BcnLkaPma14SXfhVZuMIAD4g',
    libraries: ['places']
  });

  // Handle load errors
  // Initialize and handle autocomplete
  const onAutocompleteLoad = useCallback((autocomplete: google.maps.places.Autocomplete) => {
    autocompleteRef.current = autocomplete;

    autocomplete.addListener('place_changed', () => {
      const place = autocomplete.getPlace();

      if (!place.geometry || !place.geometry.location) {
        console.error('Place details not found');
        analytics.track('location_autocomplete_error', { error: 'Place details not found' });
        return;
      }

      const position = {
        lat: place.geometry.location.lat(),
        lng: place.geometry.location.lng()
      };

      setMapCenter(position);
      setMarker(position);
      setSearchTerm(place.formatted_address || '');

      analytics.track('location_picked', { method: 'autocomplete', address: place.formatted_address });

      onChange({
        name: locationName,
        address: place.formatted_address || '',
        latitude: position.lat.toString(),
        longitude: position.lng.toString()
      });
    });
  }, [onChange, locationName]);

  // Handle geolocation for personal card
  const detectCurrentLocation = useCallback(() => {
    if (!navigator.geolocation) {
      console.error('Geolocation is not supported by your browser');
      analytics.track('geolocation_error', { error: 'not_supported' });
      return;
    }

    setIsLoading(true);
    navigator.geolocation.getCurrentPosition(
      (position) => {
        const pos = {
          lat: position.coords.latitude,
          lng: position.coords.longitude
        };

        setMapCenter(pos);
        setMarker(pos);

        // Get address from coordinates (reverse geocoding)
        const geocoder = new google.maps.Geocoder();
        geocoder.geocode({ location: pos }, (results, status) => {
          setIsLoading(false);
          if (status === 'OK' && results && results[0]) {
            analytics.track('location_picked', { method: 'current_location', address: results[0].formatted_address });
            onChange({
              name: locationName,
              address: results[0].formatted_address,
              latitude: pos.lat.toString(),
              longitude: pos.lng.toString()
            });
            setSearchTerm(results[0].formatted_address);
          } else {
            console.error('Geocoder failed: ' + status);
            analytics.track('geocoding_error', { status });
          }
        });
      },
      (error) => {
        setIsLoading(false);
        console.error('Error getting location:', error);
        analytics.track('geolocation_error', { error: error.message });
      }
    );
  }, [onChange, locationName]);

  useEffect(() => {
    if (loadError) {
      console.error('Google Maps API failed to load:', loadError);
    }
  }, [loadError]);

  // Update location name and search term when location value changes
  useEffect(() => {
    // Initialize location name and search term from value
    if (value.name) {
      setLocationName(value.name);
    }
    if (value.address) {
      setSearchTerm(value.address);
    }

    // Update marker when value changes externally
    if (value.latitude && value.longitude) {
      const position = {
        lat: parseFloat(value.latitude),
        lng: parseFloat(value.longitude)
      };
      setMarker(position);
      setMapCenter(position);
    }
  }, [value]);

  const onMapClick = useCallback((e: google.maps.MapMouseEvent) => {
    if (e.latLng) {
      const position = {
        lat: e.latLng.lat(),
        lng: e.latLng.lng()
      };
      setMarker(position);
      onChange({
        ...value,
        name: locationName,
        latitude: position.lat.toString(),
        longitude: position.lng.toString()
      });

      // Get address from coordinates (reverse geocoding)
      const geocoder = new google.maps.Geocoder();
      geocoder.geocode({ location: position }, (results, status) => {
        if (status === 'OK' && results && results[0]) {
          const address = results[0].formatted_address;
          setSearchTerm(address);
          analytics.track('location_picked', { method: 'map_click', address });
          onChange({
            ...value,
            name: locationName,
            address: address,
            latitude: position.lat.toString(),
            longitude: position.lng.toString()
          });
        }
      });
    }
  }, [onChange, value, locationName]);

  const handleSearch = () => {
    if (searchTerm.trim() === '') return;

    const geocoder = new google.maps.Geocoder();
    geocoder.geocode({ address: searchTerm }, (results, status) => {
      if (status === 'OK' && results && results[0] && results[0].geometry && results[0].geometry.location) {
        const position = {
          lat: results[0].geometry.location.lat(),
          lng: results[0].geometry.location.lng()
        };
        setMapCenter(position);
        setMarker(position);
        analytics.track('location_picked', { method: 'manual_search', address: results[0].formatted_address });
        onChange({
          name: locationName,
          address: results[0].formatted_address,
          latitude: position.lat.toString(),
          longitude: position.lng.toString()
        });
      } else {
        analytics.track('geocoding_error', { status, searchTerm });
      }
    });
  };

  const handleKeyPress = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      if (searchTerm.trim() !== '') {
        handleSearch();
      }
    }
  };

  if (!isLoaded) return <div className="h-[300px] bg-muted flex items-center justify-center">Loading Maps...</div>;

  return (
    <div className="space-y-4">
      <Card className="border border-input">
        <CardContent className="pt-4">
          <div className="flex flex-col gap-3 mb-4">
            <div className="flex gap-2">
              <div className="flex-1">
                <Input
                  placeholder="Enter name for this location"
                  value={locationName}
                  onChange={(e) => setLocationName(e.target.value)}
                />
              </div>
            </div>
            <div className="flex gap-2">
              <div className="flex-1">
                <Autocomplete
                  onLoad={onAutocompleteLoad}
                  options={{
                    componentRestrictions: { country: "us" },
                    fields: ["address_components", "geometry", "formatted_address"],
                    types: ["address"]
                  }}
                >
                  <Input
                    ref={searchInputRef}
                    placeholder="Enter an address"
                    value={searchTerm}
                    onChange={(e) => setSearchTerm(e.target.value)}
                    onKeyPress={handleKeyPress}
                  />
                </Autocomplete>
              </div>
              <Button
                type="button"
                onClick={detectCurrentLocation}
                variant="outline"
                disabled={isLoading}
              >
                {isLoading ? (
                  <Loader2 className="h-4 w-4 animate-spin mr-2" />
                ) : (
                  <MapPin className="h-4 w-4 mr-2" />
                )}
                Current Location
              </Button>
            </div>
          </div>

          <GoogleMap
            mapContainerStyle={containerStyle}
            center={mapCenter}
            zoom={13}
            onClick={onMapClick}
            options={{
              streetViewControl: false,
              mapTypeControl: false,
              fullscreenControl: false,
            }}
          >
            {marker && (
              <Marker
                position={marker}
                animation={google.maps.Animation.DROP}
              />
            )}
          </GoogleMap>
        </CardContent>
      </Card>

      {value.address && (
        <div className="flex items-start gap-2 text-sm p-2 bg-muted/20 rounded border border-input">
          <MapPin className="h-4 w-4 mt-0.5 text-primary/60" />
          <div>
            <p className="font-medium">Selected location:</p>
            <p className="text-muted-foreground">{value.address}</p>
          </div>
        </div>
      )}
    </div>
  );
}
