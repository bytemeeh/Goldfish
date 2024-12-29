import { useState, useEffect } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Checkbox } from "@/components/ui/checkbox";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Card } from "@/components/ui/card";
import { Share2 } from "lucide-react";
import { useToast } from "@/hooks/use-toast";
import type { Contact } from "@/lib/types";

interface ShareDialogProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  contacts: Contact[];
}

interface ContactWithSelection extends Contact {
  selected: boolean;
  children?: ContactWithSelection[];
}

export function ShareDialog({ open, onOpenChange, contacts }: ShareDialogProps) {
  const { toast } = useToast();
  const [selectedContacts, setSelectedContacts] = useState<ContactWithSelection[]>([]);

  // Initialize contacts with selection state when dialog opens
  useEffect(() => {
    if (open) {
      const rootContacts = contacts.filter(c => !c.parentId);
      const childContacts = contacts.filter(c => c.parentId);

      const contactsWithSelection: ContactWithSelection[] = rootContacts.map(contact => ({
        ...contact,
        selected: false,
        children: childContacts
          .filter(child => child.parentId === contact.id)
          .map(child => ({ ...child, selected: false }))
      }));

      setSelectedContacts(contactsWithSelection);
    }
  }, [contacts, open]);

  // Handle parent contact selection
  const handleParentSelect = (contactId: number, checked: boolean) => {
    setSelectedContacts(prev => prev.map(contact => {
      if (contact.id === contactId) {
        return {
          ...contact,
          selected: checked,
          children: contact.children?.map(child => ({
            ...child,
            selected: checked // Auto-select/deselect children
          }))
        };
      }
      return contact;
    }));
  };

  // Handle child contact selection
  const handleChildSelect = (parentId: number, childId: number, checked: boolean) => {
    setSelectedContacts(prev => prev.map(contact => {
      if (contact.id === parentId) {
        return {
          ...contact,
          children: contact.children?.map(child => 
            child.id === childId 
              ? { ...child, selected: checked }
              : child
          )
        };
      }
      return contact;
    }));
  };

  // Generate share link for selected contacts
  const handleShare = async () => {
    try {
      const selectedIds = selectedContacts.flatMap(contact => [
        ...(contact.selected ? [contact.id] : []),
        ...(contact.children?.filter(child => child.selected).map(child => child.id) || [])
      ]);

      if (selectedIds.length === 0) {
        toast({
          title: "No Contacts Selected",
          description: "Please select at least one contact to share.",
          variant: "destructive",
        });
        return;
      }

      const response = await fetch('/api/contacts/share', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ contactIds: selectedIds }),
        credentials: 'include',
      });

      if (!response.ok) {
        throw new Error('Failed to generate share link');
      }

      const { shareToken } = await response.json();
      const shareUrl = `${window.location.origin}/contacts/shared/${shareToken}`;
      await navigator.clipboard.writeText(shareUrl);

      toast({
        title: "Share Link Copied!",
        description: "The share link has been copied to your clipboard.",
      });
      onOpenChange(false);
    } catch (error) {
      toast({
        title: "Error",
        description: "Failed to generate share link.",
        variant: "destructive",
      });
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl">
        <DialogHeader>
          <DialogTitle>Share Contacts</DialogTitle>
        </DialogHeader>
        <ScrollArea className="h-[60vh] pr-4">
          <div className="space-y-4">
            {selectedContacts.map(contact => (
              <Card key={contact.id} className="p-4">
                <div className="space-y-4">
                  <div className="flex items-center space-x-2">
                    <Checkbox
                      id={`contact-${contact.id}`}
                      checked={contact.selected}
                      onCheckedChange={(checked) => handleParentSelect(contact.id, checked as boolean)}
                    />
                    <label
                      htmlFor={`contact-${contact.id}`}
                      className="text-sm font-medium leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70"
                    >
                      {contact.name}
                    </label>
                  </div>
                  {contact.children && contact.children.length > 0 && (
                    <div className="ml-6 space-y-2">
                      {contact.children.map(child => (
                        <div key={child.id} className="flex items-center space-x-2">
                          <Checkbox
                            id={`contact-${child.id}`}
                            checked={child.selected}
                            onCheckedChange={(checked) => 
                              handleChildSelect(contact.id, child.id, checked as boolean)
                            }
                          />
                          <label
                            htmlFor={`contact-${child.id}`}
                            className="text-sm font-medium leading-none peer-disabled:cursor-not-allowed peer-disabled:opacity-70"
                          >
                            {child.name}
                          </label>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              </Card>
            ))}
          </div>
        </ScrollArea>
        <div className="flex justify-end space-x-2 mt-4">
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button onClick={handleShare}>
            <Share2 className="mr-2 h-4 w-4" />
            Generate Share Link
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}