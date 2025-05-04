import { useState, useCallback, useEffect, useRef } from 'react';
import { GoogleMap, Marker, useJsApiLoader, Autocomplete } from '@react-google-maps/api';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { MapPin, Search, Loader2 } from 'lucide-react';

interface Location {
  address?: string;
  latitude: string | null;
  longitude: string | null;
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
  const [searchTerm, setSearchTerm] = useState('');
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
    googleMapsApiKey: import.meta.env.VITE_GOOGLE_MAPS_API_KEY || ''
  });
  
  // Handle load errors
  useEffect(() => {
    if (loadError) {
      console.error('Google Maps API failed to load:', loadError);
    }
  }, [loadError]);

  useEffect(() => {
    // Update marker when value changes externally
    if (value.latitude && value.longitude) {
      const position = {
        lat: parseFloat(value.latitude),
        lng: parseFloat(value.longitude)
      };
      setMarker(position);
      setMapCenter(position);
    }
  }, [value.latitude, value.longitude]);

  const onMapClick = useCallback((e: google.maps.MapMouseEvent) => {
    if (e.latLng) {
      const position = {
        lat: e.latLng.lat(),
        lng: e.latLng.lng()
      };
      setMarker(position);
      onChange({
        ...value,
        latitude: position.lat.toString(),
        longitude: position.lng.toString()
      });

      // Get address from coordinates (reverse geocoding)
      const geocoder = new google.maps.Geocoder();
      geocoder.geocode({ location: position }, (results, status) => {
        if (status === 'OK' && results && results[0]) {
          onChange({
            ...value,
            address: results[0].formatted_address,
            latitude: position.lat.toString(),
            longitude: position.lng.toString()
          });
        }
      });
    }
  }, [onChange, value]);

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
        onChange({
          address: results[0].formatted_address,
          latitude: position.lat.toString(),
          longitude: position.lng.toString()
        });
      }
    });
  };

  const handleKeyPress = (e: React.KeyboardEvent) => {
    if (e.key === 'Enter') {
      e.preventDefault();
      handleSearch();
    }
  };

  if (!isLoaded) return <div className="h-[300px] bg-muted flex items-center justify-center">Loading Maps...</div>;

  return (
    <div className="space-y-4">
      <Card className="border border-input">
        <CardContent className="pt-4">
          <div className="flex gap-2 mb-4">
            <div className="flex-1">
              <Input 
                placeholder="Search for an address" 
                value={searchTerm} 
                onChange={(e) => setSearchTerm(e.target.value)} 
                onKeyPress={handleKeyPress}
              />
            </div>
            <Button type="button" onClick={handleSearch} variant="outline">
              <Search className="h-4 w-4 mr-2" />
              Search
            </Button>
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
