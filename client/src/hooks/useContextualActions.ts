import { useMemo } from 'react';
import React from 'react';
import { Contact } from '@/lib/types';
import { 
  User, 
  Phone, 
  Mail, 
  Calendar, 
  Edit, 
  Trash2, 
  Share2, 
  MapPin, 
  UserPlus,
  Settings,
  Eye,
  Star,
  Archive,
  Copy,
  Download,
  Upload,
  RefreshCw,
  Filter,
  Search,
  Plus,
  Mic
} from 'lucide-react';

export interface ContextualAction {
  id: string;
  label: string;
  icon: React.ReactNode;
  action: () => void;
  condition?: () => boolean;
  priority?: number;
  category?: 'primary' | 'secondary' | 'destructive';
}

interface UseContextualActionsProps {
  context: 'contact' | 'graph' | 'list' | 'search' | 'settings';
  selectedContact?: Contact | null;
  selectedContacts?: Contact[];
  onEdit?: (contact: Contact) => void;
  onDelete?: (contact: Contact) => void;
  onShare?: (contact: Contact) => void;
  onCall?: (contact: Contact) => void;
  onEmail?: (contact: Contact) => void;
  onViewDetails?: (contact: Contact) => void;
  onAddRelationship?: (contact: Contact) => void;
  onDuplicate?: (contact: Contact) => void;
  onArchive?: (contact: Contact) => void;
  onFavorite?: (contact: Contact) => void;
  onExport?: (contacts: Contact[]) => void;
  onImport?: () => void;
  onBulkEdit?: (contacts: Contact[]) => void;
  onBulkDelete?: (contacts: Contact[]) => void;
  onFilter?: () => void;
  onSearch?: () => void;
  onRefresh?: () => void;
  onSettings?: () => void;
  customActions?: ContextualAction[];
}

export function useContextualActions({
  context,
  selectedContact,
  selectedContacts = [],
  onEdit,
  onDelete,
  onShare,
  onCall,
  onEmail,
  onViewDetails,
  onAddRelationship,
  onDuplicate,
  onArchive,
  onFavorite,
  onExport,
  onImport,
  onBulkEdit,
  onBulkDelete,
  onFilter,
  onSearch,
  onRefresh,
  onSettings,
  customActions = []
}: UseContextualActionsProps): ContextualAction[] {
  return useMemo(() => {
    const actions: ContextualAction[] = [];

    // Contact-specific actions
    if (context === 'contact' && selectedContact) {
      actions.push(
        {
          id: 'view-details',
          label: 'View Details',
          icon: React.createElement(Eye, { className: "h-4 w-4" }),
          action: () => onViewDetails?.(selectedContact),
          condition: () => !!onViewDetails,
          priority: 100,
          category: 'primary'
        },
        {
          id: 'edit',
          label: 'Edit Contact',
          icon: React.createElement(Edit, { className: "h-4 w-4" }),
          action: () => onEdit?.(selectedContact),
          condition: () => !!onEdit,
          priority: 90,
          category: 'primary'
        },
        {
          id: 'call',
          label: 'Call',
          icon: React.createElement(Phone, { className: "h-4 w-4" }),
          action: () => onCall?.(selectedContact),
          condition: () => !!onCall && !!selectedContact.phone,
          priority: 85,
          category: 'primary'
        },
        {
          id: 'email',
          label: 'Send Email',
          icon: React.createElement(Mail, { className: "h-4 w-4" }),
          action: () => onEmail?.(selectedContact),
          condition: () => !!onEmail && !!selectedContact.email,
          priority: 80,
          category: 'primary'
        },
        {
          id: 'share',
          label: 'Share Contact',
          icon: React.createElement(Share2, { className: "h-4 w-4" }),
          action: () => onShare?.(selectedContact),
          condition: () => !!onShare,
          priority: 75,
          category: 'secondary'
        },
        {
          id: 'add-relationship',
          label: 'Add Relationship',
          icon: React.createElement(UserPlus, { className: "h-4 w-4" }),
          action: () => onAddRelationship?.(selectedContact),
          condition: () => !!onAddRelationship,
          priority: 70,
          category: 'secondary'
        },
        {
          id: 'duplicate',
          label: 'Duplicate',
          icon: React.createElement(Copy, { className: "h-4 w-4" }),
          action: () => onDuplicate?.(selectedContact),
          condition: () => !!onDuplicate,
          priority: 60,
          category: 'secondary'
        },
        {
          id: 'favorite',
          label: 'Add to Favorites',
          icon: React.createElement(Star, { className: "h-4 w-4" }),
          action: () => onFavorite?.(selectedContact),
          condition: () => !!onFavorite,
          priority: 55,
          category: 'secondary'
        },
        {
          id: 'archive',
          label: 'Archive',
          icon: React.createElement(Archive, { className: "h-4 w-4" }),
          action: () => onArchive?.(selectedContact),
          condition: () => !!onArchive,
          priority: 30,
          category: 'secondary'
        },
        {
          id: 'delete',
          label: 'Delete Contact',
          icon: React.createElement(Trash2, { className: "h-4 w-4" }),
          action: () => onDelete?.(selectedContact),
          condition: () => !!onDelete,
          priority: 10,
          category: 'destructive'
        }
      );
    }

    // List context actions
    if (context === 'list') {
      actions.push(
        {
          id: 'search',
          label: 'Search Contacts',
          icon: React.createElement(Search, { className: "h-4 w-4" }),
          action: () => onSearch?.(),
          condition: () => !!onSearch,
          priority: 95,
          category: 'primary'
        },
        {
          id: 'filter',
          label: 'Filter Contacts',
          icon: React.createElement(Filter, { className: "h-4 w-4" }),
          action: () => onFilter?.(),
          condition: () => !!onFilter,
          priority: 90,
          category: 'primary'
        },
        {
          id: 'refresh',
          label: 'Refresh List',
          icon: React.createElement(RefreshCw, { className: "h-4 w-4" }),
          action: () => onRefresh?.(),
          condition: () => !!onRefresh,
          priority: 85,
          category: 'secondary'
        },
        {
          id: 'export',
          label: 'Export Contacts',
          icon: React.createElement(Download, { className: "h-4 w-4" }),
          action: () => onExport?.(selectedContacts),
          condition: () => !!onExport,
          priority: 70,
          category: 'secondary'
        },
        {
          id: 'import',
          label: 'Import Contacts',
          icon: React.createElement(Upload, { className: "h-4 w-4" }),
          action: () => onImport?.(),
          condition: () => !!onImport,
          priority: 65,
          category: 'secondary'
        }
      );

      // Bulk actions when multiple contacts are selected
      if (selectedContacts.length > 1) {
        actions.push(
          {
            id: 'bulk-edit',
            label: `Edit ${selectedContacts.length} Contacts`,
            icon: React.createElement(Edit, { className: "h-4 w-4" }),
            action: () => onBulkEdit?.(selectedContacts),
            condition: () => !!onBulkEdit,
            priority: 80,
            category: 'primary'
          },
          {
            id: 'bulk-delete',
            label: `Delete ${selectedContacts.length} Contacts`,
            icon: React.createElement(Trash2, { className: "h-4 w-4" }),
            action: () => onBulkDelete?.(selectedContacts),
            condition: () => !!onBulkDelete,
            priority: 20,
            category: 'destructive'
          }
        );
      }
    }

    // Graph context actions
    if (context === 'graph') {
      actions.push(
        {
          id: 'add-contact',
          label: 'Add Contact',
          icon: React.createElement(Plus, { className: "h-4 w-4" }),
          action: () => onEdit?.(null as any),
          condition: () => !!onEdit,
          priority: 100,
          category: 'primary'
        },
        {
          id: 'voice-add',
          label: 'Add by Voice',
          icon: React.createElement(Mic, { className: "h-4 w-4" }),
          action: () => {}, // Handled by VoiceInput component
          condition: () => true,
          priority: 95,
          category: 'primary'
        },
        {
          id: 'show-nearby',
          label: 'Show Nearby',
          icon: React.createElement(MapPin, { className: "h-4 w-4" }),
          action: () => {}, // Handled by ProximityFilter component
          condition: () => true,
          priority: 90,
          category: 'secondary'
        },
        {
          id: 'reorder',
          label: 'Reorder Graph',
          icon: React.createElement(RefreshCw, { className: "h-4 w-4" }),
          action: () => {}, // Handled by graph component
          condition: () => true,
          priority: 85,
          category: 'secondary'
        }
      );
    }

    // Settings context actions
    if (context === 'settings') {
      actions.push(
        {
          id: 'preferences',
          label: 'Preferences',
          icon: React.createElement(Settings, { className: "h-4 w-4" }),
          action: () => onSettings?.(),
          condition: () => !!onSettings,
          priority: 100,
          category: 'primary'
        }
      );
    }

    // Add custom actions
    actions.push(...customActions);

    // Filter and sort actions
    return actions
      .filter(action => !action.condition || action.condition())
      .sort((a, b) => (b.priority || 0) - (a.priority || 0));
  }, [
    context,
    selectedContact,
    selectedContacts,
    onEdit,
    onDelete,
    onShare,
    onCall,
    onEmail,
    onViewDetails,
    onAddRelationship,
    onDuplicate,
    onArchive,
    onFavorite,
    onExport,
    onImport,
    onBulkEdit,
    onBulkDelete,
    onFilter,
    onSearch,
    onRefresh,
    onSettings,
    customActions
  ]);
}