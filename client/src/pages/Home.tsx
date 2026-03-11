import { useState, useEffect, useCallback, useMemo } from "react";
import { useToast } from "@/hooks/use-toast";
import { Button } from "@/components/ui/button";
import { Plus, Network, User, Share2, Settings2, HelpCircle } from "lucide-react";
// import { List } from "lucide-react"; // FUTURE FEATURE: List view - Currently hidden, may be added in future releases
// import { VoiceInput } from "@/components/ai/VoiceInput"; // FUTURE FEATURE: AI Voice Typing - Currently hidden, may be added in future releases
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { ContactForm } from "@/components/contacts/ContactForm";
// import { ContactList } from "@/components/contacts/ContactList"; // FUTURE FEATURE: List view component - Currently not used
import ContactFlowGraph from "@/components/contacts/ContactFlowGraph";
import { DetailedContactView } from "@/components/contacts/DetailedContactView";
import { SearchBar, type SearchFilters } from "@/components/contacts/SearchBar";
import { ShareDialog } from "@/components/contacts/ShareDialog";
import { RelationshipManager } from "@/components/settings/RelationshipManager";
import { WelcomeWalkthrough } from "@/components/onboarding/WelcomeWalkthrough";
import { HelpDialog } from "@/components/onboarding/HelpDialogFinal";
import { useQuery } from "@tanstack/react-query";
import { motion, AnimatePresence } from "framer-motion";
import { MotionButton, tapAnimation } from "@/components/ui/MotionButton";
import type { Contact } from "@/lib/types";

// FUTURE FEATURE: "list" mode is currently hidden but may be reintroduced in future releases
type ViewMode = "graph" | "detail"; // "list" | removed for initial launch

// Local storage keys
const STORAGE_KEY_VIEW_MODE = 'contacts-app-view-mode';

export function Home() {
  const [filters, setFilters] = useState<SearchFilters>({});
  const [isAddingContact, setIsAddingContact] = useState(false);
  const [isEditingPersonal, setIsEditingPersonal] = useState(false);
  const [isSharing, setIsSharing] = useState(false);
  const [isHelpOpen, setIsHelpOpen] = useState(false);
  const [selectedContactId, setSelectedContactId] = useState<string | null>(null);
  const [previousViewMode, setPreviousViewMode] = useState<ViewMode>("graph");
  // const [voiceTranscription, setVoiceTranscription] = useState<string>(""); // Hidden for initial release
  const { toast } = useToast();
  const [viewMode, setViewMode] = useState<ViewMode>("graph"); // FUTURE FEATURE: Always default to graph view (list view hidden for initial launch)

  const [relationContext, setRelationContext] = useState<{ parentId: string | null }>({ parentId: null });

  // Enhanced contact selection handler with detail view
  const handleContactSelect = useCallback((contactId: string) => {
    console.log('🚨 Home.tsx - handleContactSelect called with ID:', contactId);

    // Save current view mode before switching to detail view
    setPreviousViewMode(viewMode);

    // Set the selected contact ID
    setSelectedContactId(contactId);

    // Switch to detail view
    setViewMode("detail");

  }, [viewMode]);

  const handleAddRelation = useCallback((sourceId: string, type: 'child' | 'parent') => {
    console.log('Adding relation:', { sourceId, type });
    setRelationContext({ parentId: type === 'child' ? sourceId : null });
    setIsAddingContact(true);
  }, []);

  // Handler for returning from detail view
  const handleBackFromDetail = useCallback(() => {
    // Go back to the previous view mode (graph or list)
    setViewMode(previousViewMode);
    // Clear the selection
    setSelectedContactId(null);
  }, [previousViewMode]);

  // Debug effects for contact selection
  useEffect(() => {
    console.log('🚨 Home.tsx - selectedContactId changed to:', selectedContactId);
  }, [selectedContactId]);

  useEffect(() => {
    console.log('🚨 Home.tsx - viewMode changed to:', viewMode);
  }, [viewMode]);

  // Handle contact import event from walkthrough
  useEffect(() => {
    const handleImport = () => {
      toast({
        title: "Import Contacts",
        description: "VCard import coming soon to web version. Use the mobile app for full import capabilities.",
      });
    };

    window.addEventListener("goldfish:import-contacts", handleImport);
    return () => window.removeEventListener("goldfish:import-contacts", handleImport);
  }, [toast]);

  const { data: contacts, refetch } = useQuery<Contact[]>({
    queryKey: ["/api/contacts"],
  });

  // Filter contacts based on demo mode preference
  const filteredContacts = useMemo(() => {
    if (!contacts) return [];
    const demoDataActive = localStorage.getItem('goldfish_demo_data_active') !== 'false'; // Default to true if not set
    if (demoDataActive) return contacts;
    return contacts.filter(c => !c.isDemo || c.isMe);
  }, [contacts]);

  // Handle start from scratch (clear all non-me contacts)
  useEffect(() => {
    const checkReset = async () => {
      const hasSeen = localStorage.getItem('goldfish_has_seen_welcome');
      const demoDataActive = localStorage.getItem('goldfish_demo_data_active');

      if (hasSeen === 'true' && demoDataActive === 'false' && contacts?.some(c => c.isDemo)) {
        try {
          const res = await fetch("/api/contacts/reset", { method: "POST" });
          if (res.ok) {
            toast({
              title: "Started Fresh",
              description: "Demo data has been removed. You can now start building your own network!",
            });
            refetch();
          }
        } catch (error) {
          console.error("Failed to reset:", error);
        }
      }
    };
    checkReset();
  }, [contacts, refetch, toast]);

  // FUTURE FEATURE: View mode persistence - Currently only graph mode is available
  // useEffect(() => {
  //   if (viewMode === "graph") {
  //     localStorage.setItem(STORAGE_KEY_VIEW_MODE, viewMode);
  //   }
  // }, [viewMode]);

  // Render content based on view mode
  const renderContent = () => {
    switch (viewMode) {
      case "detail":
        return selectedContactId ? (
          <DetailedContactView
            contactId={selectedContactId}
            onBack={handleBackFromDetail}
          />
        ) : (
          // Fallback if no contact is selected
          <div className="text-center py-12">
            <p className="text-muted-foreground mb-4">No contact selected</p>
            <Button onClick={handleBackFromDetail}>Go Back</Button>
          </div>
        );

      // FUTURE FEATURE: List view rendering - Currently hidden
      // case "list":
      //   return (
      //     <ContactList searchFilters={filters} selectedContactId={selectedContactId} />
      //   );

      case "graph":
      default:
        return (
          <ContactFlowGraph
            contacts={filteredContacts}
            onContactSelect={handleContactSelect}
            onAddRelation={handleAddRelation}
          />
        );
    }
  };

  return (
    <div className="min-h-screen bg-background">
      {/* Clean header with value proposition */}
      {/* Apple-style Header & Navigation */}
      <div className="sticky top-0 z-50 w-full border-b border-white/20 bg-white/80 backdrop-blur-xl supports-[backdrop-filter]:bg-white/60">
        <div className="container mx-auto px-4 h-16 flex items-center justify-between">
          {/* Brand */}
          <div className="flex items-center gap-2">
            <div className="h-10 w-10 rounded-xl bg-white/50 flex items-center justify-center shadow-sm overflow-hidden">
              <img src="/logo.png" alt="Goldfish Logo" className="h-full w-full object-cover" />
            </div>
            <div className="flex flex-col">
              <h1 className="text-lg font-semibold tracking-tight text-foreground leading-none">
                Goldfish
              </h1>
              <span className="text-[10px] font-medium text-muted-foreground tracking-wide uppercase">Your External Memory</span>
            </div>
          </div>

          {/* FUTURE FEATURE: Desktop View Mode Toggle - Currently only Network view is available */}
          {/* {viewMode !== "detail" && (
            <div className="hidden md:flex items-center bg-muted/50 p-1 rounded-lg border border-black/5">
              <button
                onClick={() => setViewMode("graph")}
                className={`flex items-center gap-2 px-4 py-1.5 rounded-md text-sm font-medium transition-all duration-200 ${viewMode === "graph"
                  ? "bg-white text-primary shadow-sm ring-1 ring-black/5"
                  : "text-muted-foreground hover:text-foreground hover:bg-black/5"
                  }`}
              >
                <Network className="h-4 w-4" />
                Network
              </button>
            </div>
          )} */}

          {/* Right: Actions */}
          <div className="flex items-center gap-2">
            {viewMode !== "detail" && (
              <>
                {/* FUTURE FEATURE: Mobile View Toggle - Currently only Network view is available */}
                {/* <div className="md:hidden flex bg-muted/50 p-1 rounded-lg border border-black/5 mr-2">
                  <button
                    onClick={() => setViewMode("graph")}
                    className={`p-1.5 rounded-md transition-all ${viewMode === "graph" ? "bg-white text-primary shadow-sm" : "text-muted-foreground"}`}
                  >
                    <Network className="h-4 w-4" />
                  </button>
                </div> */}

                <Dialog open={isAddingContact} onOpenChange={(open) => {
                  setIsAddingContact(open);
                  if (!open) setRelationContext({ parentId: null });
                }}>
                  <DialogTrigger asChild>
                    <MotionButton
                      size="sm"
                      className="h-9 px-4 rounded-full bg-primary text-primary-foreground hover:bg-primary/90 shadow-lg shadow-primary/25 border-0 font-medium"
                      whileTap={tapAnimation}
                    >
                      <Plus className="h-4 w-4 mr-1.5" />
                      Add Contact
                    </MotionButton>
                  </DialogTrigger>
                  <DialogContent className="h-[90vh] sm:h-[80vh] max-w-[95vw] sm:max-w-3xl flex flex-col overflow-hidden m-2 sm:m-6">
                    <DialogHeader>
                      <DialogTitle>
                        {relationContext.parentId ? "Add Related Contact" : "Add New Contact"}
                      </DialogTitle>
                    </DialogHeader>
                    <div className="flex flex-1 overflow-hidden">
                      <ContactForm
                        onSuccess={() => setIsAddingContact(false)}
                        parentId={relationContext.parentId || undefined}
                      />
                    </div>
                  </DialogContent>
                </Dialog>

                {/* Settings Menu */}
                <Dialog>
                  <DialogTrigger asChild>
                    <Button variant="ghost" size="icon" className="h-9 w-9 rounded-full hover:bg-black/5 text-muted-foreground">
                      <Settings2 className="h-5 w-5" />
                    </Button>
                  </DialogTrigger>
                  <DialogContent className="max-w-md">
                    <DialogHeader>
                      <DialogTitle>Manage Relationship Types</DialogTitle>
                    </DialogHeader>
                    <RelationshipManager />
                  </DialogContent>
                </Dialog>

                {/* More Menu (My Info, Share, Help) */}
                <Dialog open={isEditingPersonal} onOpenChange={setIsEditingPersonal}>
                  <DialogTrigger asChild>
                    <Button variant="ghost" size="icon" className="h-9 w-9 rounded-full hover:bg-black/5 text-muted-foreground">
                      <User className="h-5 w-5" />
                    </Button>
                  </DialogTrigger>
                  <DialogContent className="h-[90vh] sm:h-[80vh] max-w-[95vw] sm:max-w-3xl flex flex-col overflow-hidden m-2 sm:m-6">
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
              </>
            )}
          </div>
        </div>
      </div>

      {/* Main content area */}
      <div className="container mx-auto px-3 sm:px-6 py-3 sm:py-6">
        <div className="space-y-3 sm:space-y-6">
          {/* Hide search bar in detail view */}
          {viewMode !== "detail" && (
            <div className="flex justify-center">
              <div className="w-full max-w-2xl">
                <SearchBar onSearch={setFilters} />
              </div>
            </div>
          )}

          {/* Content with smooth transitions */}
          <div className="mt-3 sm:mt-6">
            <AnimatePresence mode="wait">
              <motion.div
                key={viewMode}
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -10 }}
                transition={{ duration: 0.3 }}
              >
                {renderContent()}
              </motion.div>
            </AnimatePresence>
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
      <WelcomeWalkthrough />
      <HelpDialog open={isHelpOpen} onOpenChange={setIsHelpOpen} />
    </div>
  );
}