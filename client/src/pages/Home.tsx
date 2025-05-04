import { useState } from "react";
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

export function Home() {
  const [filters, setFilters] = useState<SearchFilters>({});
  const [isAddingContact, setIsAddingContact] = useState(false);
  const [isEditingPersonal, setIsEditingPersonal] = useState(false);
  const [isSharing, setIsSharing] = useState(false);
  const [viewMode, setViewMode] = useState<ViewMode>("list");

  const { data: contacts } = useQuery<Contact[]>({
    queryKey: ["/api/contacts"],
  });

  return (
    <div className="min-h-screen bg-background overflow-x-hidden">
      <div className="container mx-auto px-2 sm:px-4 py-6 sm:py-8">
        <div className="space-y-6">
          <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
            <h1 className="text-3xl sm:text-4xl font-bold tracking-tight">Contacts</h1>
            <div className="flex flex-wrap items-center gap-2 max-w-full">
              <div className="flex items-center border rounded-md overflow-hidden">
                <Button
                  variant={viewMode === "list" ? "default" : "ghost"}
                  onClick={() => setViewMode("list")}
                  size="sm"
                  className="h-8 rounded-none px-2"
                >
                  <List className="h-4 w-4 mr-1.5" />
                  <span className="hidden sm:inline text-xs">List</span>
                </Button>
                <Button
                  variant={viewMode === "graph" ? "default" : "ghost"}
                  onClick={() => setViewMode("graph")}
                  size="sm"
                  className="h-8 rounded-none px-2"
                >
                  <Network className="h-4 w-4 mr-1.5" />
                  <span className="hidden sm:inline text-xs">Graph</span>
                </Button>
              </div>
              <Dialog open={isEditingPersonal} onOpenChange={setIsEditingPersonal}>
                <DialogTrigger asChild>
                  <Button variant="outline" size="sm" className="h-8">
                    <User className="h-4 w-4 mr-1.5" />
                    <span className="whitespace-nowrap text-xs">Personal Info</span>
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
                    />
                  </div>
                </DialogContent>
              </Dialog>
              <Button
                variant="outline"
                size="sm"
                className="h-8"
                onClick={() => setIsSharing(true)}
              >
                <Share2 className="h-4 w-4 mr-1.5" />
                <span className="whitespace-nowrap text-xs">Share</span>
              </Button>
              <Dialog open={isAddingContact} onOpenChange={setIsAddingContact}>
                <DialogTrigger asChild>
                  <Button size="sm" className="h-8">
                    <Plus className="h-4 w-4 mr-1.5" />
                    <span className="whitespace-nowrap text-xs">New Contact</span>
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
              <ContactList searchFilters={filters} />
            ) : (
              <ContactGraph />
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