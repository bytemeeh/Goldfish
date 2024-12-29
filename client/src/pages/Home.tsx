import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Plus, List, Network } from "lucide-react";
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

type ViewMode = "list" | "graph";

export function Home() {
  const [filters, setFilters] = useState<SearchFilters>({});
  const [isAddingContact, setIsAddingContact] = useState(false);
  const [viewMode, setViewMode] = useState<ViewMode>("list");

  return (
    <div className="min-h-screen bg-background">
      <div className="container mx-auto px-4 py-8">
        <div className="space-y-6">
          <div className="flex flex-col gap-6 md:flex-row md:items-center md:justify-between">
            <h1 className="text-4xl font-bold tracking-tight">Contacts</h1>
            <div className="flex items-center gap-2">
              <Button
                variant={viewMode === "list" ? "default" : "outline"}
                onClick={() => setViewMode("list")}
                size="icon"
                className="h-9 w-9"
              >
                <List className="h-4 w-4" />
              </Button>
              <Button
                variant={viewMode === "graph" ? "default" : "outline"}
                onClick={() => setViewMode("graph")}
                size="icon"
                className="h-9 w-9"
              >
                <Network className="h-4 w-4" />
              </Button>
              <Dialog open={isAddingContact} onOpenChange={setIsAddingContact}>
                <DialogTrigger asChild>
                  <Button size="sm" className="h-9">
                    <Plus className="mr-2 h-4 w-4" />
                    New Contact
                  </Button>
                </DialogTrigger>
                <DialogContent>
                  <DialogHeader>
                    <DialogTitle>Add New Contact</DialogTitle>
                  </DialogHeader>
                  <ContactForm onSuccess={() => setIsAddingContact(false)} />
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
        </div>
      </div>
    </div>
  );
}