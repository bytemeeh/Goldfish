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
import { SearchBar } from "@/components/contacts/SearchBar";

type ViewMode = "list" | "graph";

export function Home() {
  const [searchQuery, setSearchQuery] = useState("");
  const [isAddingContact, setIsAddingContact] = useState(false);
  const [viewMode, setViewMode] = useState<ViewMode>("list");

  return (
    <div className="container mx-auto p-4">
      <div className="mb-8">
        <h1 className="text-3xl font-bold mb-4">Contacts</h1>
        <div className="flex gap-4">
          <div className="flex-1">
            <SearchBar
              value={searchQuery}
              onChange={setSearchQuery}
            />
          </div>
          <div className="flex gap-2">
            <Button
              variant={viewMode === "list" ? "default" : "outline"}
              onClick={() => setViewMode("list")}
              size="icon"
            >
              <List className="h-4 w-4" />
            </Button>
            <Button
              variant={viewMode === "graph" ? "default" : "outline"}
              onClick={() => setViewMode("graph")}
              size="icon"
            >
              <Network className="h-4 w-4" />
            </Button>
            <Dialog open={isAddingContact} onOpenChange={setIsAddingContact}>
              <DialogTrigger asChild>
                <Button>
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
      </div>

      {viewMode === "list" ? (
        <ContactList searchQuery={searchQuery} />
      ) : (
        <ContactGraph />
      )}
    </div>
  );
}