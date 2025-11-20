import React, { useState, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import { MapPin, Loader2 } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';
import { PermissionPrimingDialog } from '@/components/ui/PermissionPrimingDialog';

interface ProximityFilterProps {
  onFilterChange: (enabled: boolean, userLocation?: { lat: number; lng: number }) => void;
  className?: string;
}

export function ProximityFilter({ onFilterChange, className }: ProximityFilterProps) {
  const [isEnabled, setIsEnabled] = useState(false);
  const [isLoading, setIsLoading] = useState(false);
  const [userLocation, setUserLocation] = useState<{ lat: number; lng: number } | null>(null);
  const [showPermissionDialog, setShowPermissionDialog] = useState(false);
  const { toast } = useToast();

  const getCurrentLocation = (): Promise<{ lat: number; lng: number }> => {
    return new Promise((resolve, reject) => {
      if (!navigator.geolocation) {
        reject(new Error('Geolocation is not supported by this browser'));
        return;
      }

      navigator.geolocation.getCurrentPosition(
        (position) => {
          resolve({
            lat: position.coords.latitude,
            lng: position.coords.longitude,
          });
        },
        (error) => {
          reject(error);
        },
        {
          enableHighAccuracy: true,
          timeout: 10000,
          maximumAge: 300000, // 5 minutes
        }
      );
    });
  };

  const handleToggleFilter = () => {
    if (!isEnabled) {
      // Show permission priming dialog first
      setShowPermissionDialog(true);
    } else {
      // Disable filter
      setIsEnabled(false);
      setUserLocation(null);
      onFilterChange(false);
      toast({
        title: "Location filter disabled",
        description: "Showing all contacts",
      });
    }
  };

  const handlePermissionContinue = async () => {
    setShowPermissionDialog(false);
    setIsLoading(true);
    try {
      const location = await getCurrentLocation();
      setUserLocation(location);
      setIsEnabled(true);
      onFilterChange(true, location);
      toast({
        title: "Location filter enabled",
        description: "Showing contacts within 1 km of your location",
      });
    } catch (error) {
      console.error('Error getting location:', error);
      toast({
        title: "Location access denied",
        description: "Please allow location access to use proximity filter",
        variant: "destructive",
      });
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <>
      <Button
        onClick={handleToggleFilter}
        variant={isEnabled ? "default" : "outline"}
        disabled={isLoading}
        className={className}
      >
        {isLoading ? (
          <Loader2 className="h-4 w-4 mr-2 animate-spin" />
        ) : (
          <MapPin className="h-4 w-4 mr-2" />
        )}
        {isLoading ? 'Getting location...' : isEnabled ? 'Within 1km' : 'Show Nearby'}
      </Button>

      <PermissionPrimingDialog
        open={showPermissionDialog}
        onOpenChange={setShowPermissionDialog}
        permissionType="location"
        onContinue={handlePermissionContinue}
        onCancel={() => setShowPermissionDialog(false)}
      />
    </>
  );
}