import React, { createContext, useContext, useEffect, useState } from 'react';
import { useJsApiLoader, Libraries } from '@react-google-maps/api';
import { analytics } from './analytics';

// Define the libraries we want to load
// @ts-ignore - The type definition in @react-google-maps/api is incorrect
const libraries: Libraries = ['places'];

// Define the context shape
interface GoogleMapsContextType {
  isLoaded: boolean;
  loadError: Error | undefined;
}

// Create the context
const GoogleMapsContext = createContext<GoogleMapsContextType>({
  isLoaded: false,
  loadError: undefined,
});

// Provider component
export function GoogleMapsProvider({ children }: { children: React.ReactNode }) {
  const { isLoaded, loadError } = useJsApiLoader({
    id: 'google-map-script',
    googleMapsApiKey: import.meta.env.VITE_GOOGLE_MAPS_API_KEY || 'AIzaSyDmk73iGX4BcnLkaPma14SXfhVZuMIAD4g',
    libraries,
  });

  useEffect(() => {
    if (loadError) {
      analytics.track('maps_load_error', { error: loadError.message });
    } else if (isLoaded) {
      analytics.track('maps_loaded');
    }
  }, [isLoaded, loadError]);

  return (
    <GoogleMapsContext.Provider value={{ isLoaded, loadError }}>
      {children}
    </GoogleMapsContext.Provider>
  );
}

// Hook to use the Google Maps context
export function useGoogleMaps() {
  const context = useContext(GoogleMapsContext);
  if (context === undefined) {
    throw new Error('useGoogleMaps must be used within a GoogleMapsProvider');
  }
  return context;
}
