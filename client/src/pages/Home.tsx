import { useState, useEffect, useCallback } from "react";
import { Button } from "@/components/ui/button";
import { Plus, List, Network, User, Share2 } from "lucide-react";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { ContactForm } from "@/components/contacts/ContactForm";
import { ContactList } from "@/components/contacts/ContactList";
import { ContactGraph } from "@/components/contacts/ContactGraph";
import { SearchBar, type SearchFilters } from "@/components/contacts/SearchBar";
import { ShareDialog } from "@/components/contacts/ShareDialog";
import { useQuery } from "@tanstack/react-query";
import type { Contact } from "@/lib/types";

type ViewMode = "list" | "graph";

// Local storage keys
const STORAGE_KEY_VIEW_MODE = 'contacts-app-view-mode';

export function Home() {
  const [filters, setFilters] = useState<SearchFilters>({});
  const [isAddingContact, setIsAddingContact] = useState(false);
  const [isEditingPersonal, setIsEditingPersonal] = useState(false);
  const [isSharing, setIsSharing] = useState(false);
  const [selectedContactId, setSelectedContactId] = useState<number | null>(null);
  const [viewMode, setViewMode] = useState<ViewMode>(() => {
    // Try to get the saved view mode from local storage
    const savedViewMode = localStorage.getItem(STORAGE_KEY_VIEW_MODE);
    // Return the saved mode if valid, otherwise default to "list"
    return (savedViewMode === 'list' || savedViewMode === 'graph') 
      ? savedViewMode as ViewMode 
      : "list";
  });
  
  // Enhanced contact selection handler with multi-step retry mechanism
  const handleContactSelect = useCallback((contactId: number) => {
    console.log('🚨 Home.tsx - handleContactSelect called with ID:', contactId);
    
    // First change the view mode to list to ensure the contact list is rendered
    // before we try to set the selected contact and scroll to it
    if (viewMode !== "list") {
      console.log('🚨 Home.tsx - Changing view mode to list first');
      setViewMode("list");
      
      // Enhanced multi-step selection strategy for better reliability
      // Step 1: Initial selection after view change (short delay to ensure view is updated)
      setTimeout(() => {
        console.log('🚨 Home.tsx - Initial selection for ID:', contactId);
        setSelectedContactId(contactId);
        
        // Step 2: First retry attempt - clear and reselect with a longer delay
        // This helps load any dynamically rendered components or collapsed sections
        setTimeout(() => {
          console.log('🚨 Home.tsx - First retry selection for ID:', contactId);
          setSelectedContactId(null);
          setTimeout(() => {
            setSelectedContactId(contactId);
          }, 50);
          
          // Step 3: Second retry attempt - for contacts that require more time to render
          // especially nested contacts in deep hierarchies
          setTimeout(() => {
            console.log('🚨 Home.tsx - Final retry selection for ID:', contactId);
            setSelectedContactId(null);
            setTimeout(() => {
              setSelectedContactId(contactId);
            }, 50);
          }, 1500);
        }, 800);
      }, 350);
    } else {
      // If already in list view, use a similar pattern but without changing the view
      console.log('🚨 Home.tsx - Already in list view, setting selectedContactId:', contactId);
      // Immediate selection
      setSelectedContactId(contactId);
      
      // Multiple retry attempts for better reliability
      setTimeout(() => {
        console.log('🚨 Home.tsx - Retry 1 for ID:', contactId);
        setSelectedContactId(null);
        setTimeout(() => {
          setSelectedContactId(contactId);
          
          // Final retry after a longer delay
          setTimeout(() => {
            console.log('🚨 Home.tsx - Final retry for ID:', contactId);
            setSelectedContactId(null);
            setTimeout(() => {
              setSelectedContactId(contactId);
            }, 50);
          }, 1000);
        }, 50);
      }, 500);
    }
  }, [viewMode]);
  
  // Debug effects for contact selection
  useEffect(() => {
    console.log('🚨 Home.tsx - selectedContactId changed to:', selectedContactId);
  }, [selectedContactId]);
  
  useEffect(() => {
    console.log('🚨 Home.tsx - viewMode changed to:', viewMode);
  }, [viewMode]);

  const { data: contacts } = useQuery<Contact[]>({
    queryKey: ["/api/contacts"],
  });
  
  // Save the view mode to local storage whenever it changes
  useEffect(() => {
    localStorage.setItem(STORAGE_KEY_VIEW_MODE, viewMode);
  }, [viewMode]);

  return (
    <div className="min-h-screen bg-background overflow-x-hidden">
      <div className="container mx-auto px-2 sm:px-4 py-6 sm:py-8">
        <div className="space-y-6">
          <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
            <h1 className="text-2xl sm:text-3xl font-bold tracking-tight">Goldfish</h1>
            <div className="grid grid-cols-4 gap-1.5 w-full md:w-auto max-w-full">
              <div className="flex items-center border rounded-md overflow-hidden h-8 col-span-1">
                <Button
                  variant={viewMode === "list" ? "default" : "ghost"}
                  onClick={() => setViewMode("list")}
                  size="sm"
                  className="h-8 w-full rounded-none px-1"
                >
                  <List className="h-4 w-4" />
                </Button>
                <Button
                  variant={viewMode === "graph" ? "default" : "ghost"}
                  onClick={() => setViewMode("graph")}
                  size="sm"
                  className="h-8 w-full rounded-none px-1"
                >
                  <Network className="h-4 w-4" />
                </Button>
              </div>
              <Dialog open={isEditingPersonal} onOpenChange={setIsEditingPersonal}>
                <DialogTrigger asChild>
                  <Button variant="outline" size="sm" className="h-8 col-span-1 px-1 py-0">
                    <User className="h-4 w-4 mr-1" />
                    <span className="whitespace-nowrap text-xs">My Info</span>
                  </Button>
                </DialogTrigger>
                <DialogContent className="h-[80vh] max-w-3xl flex flex-col overflow-hidden">
                  <DialogHeader>
                    <DialogTitle>Edit Personal Card</DialogTitle>
                  </DialogHeader>
                  <div className="flex flex-1 overflow-hidden">
                    <ContactForm 
                      onSuccess={() => setIsEditingPersonal(false)} 
                      isPersonalCard={true}
                      initialData={contacts?.find(c => c.isMe)}
                    />
                  </div>
                </DialogContent>
              </Dialog>
              <Button
                variant="outline"
                size="sm"
                className="h-8 col-span-1 px-1 py-0"
                onClick={() => setIsSharing(true)}
              >
                <Share2 className="h-4 w-4 mr-1" />
                <span className="whitespace-nowrap text-xs">Share</span>
              </Button>
              <Dialog open={isAddingContact} onOpenChange={setIsAddingContact}>
                <DialogTrigger asChild>
                  <Button size="sm" className="h-8 col-span-1 px-1 py-0">
                    <Plus className="h-4 w-4 mr-1" />
                    <span className="whitespace-nowrap text-xs">New</span>
                  </Button>
                </DialogTrigger>
                <DialogContent className="h-[80vh] max-w-3xl flex flex-col overflow-hidden">
                  <DialogHeader>
                    <DialogTitle>Add New Contact</DialogTitle>
                  </DialogHeader>
                  <div className="flex flex-1 overflow-hidden">
                    <ContactForm onSuccess={() => setIsAddingContact(false)} />
                  </div>
                </DialogContent>
              </Dialog>
            </div>
          </div>

          <div className="w-full max-w-2xl">
            <SearchBar onSearch={setFilters} />
          </div>

          <div className="mt-6">
            {viewMode === "list" ? (
              <ContactList searchFilters={filters} selectedContactId={selectedContactId} />
            ) : (
              <ContactGraph onContactSelect={handleContactSelect} />
            )}
          </div>

          {contacts && (
            <ShareDialog
              open={isSharing}
              onOpenChange={setIsSharing}
              contacts={contacts}
            />
          )}
        </div>
      </div>
    </div>
  );
}