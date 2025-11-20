import React from 'react';
import { Handle, Position } from 'reactflow';
import { Contact } from '@/lib/types';
import { getContactColorClasses } from '@/lib/colors';
import { User, Phone, Mail, Plus, Heart, Users, Briefcase, Baby, Star, Trash2 } from 'lucide-react';
import { clsx } from 'clsx';
import { ProfilePhoto } from '@/components/ui/ProfilePhoto';

interface ContactNodeProps {
  data: {
    contact: Contact;
    drop?: boolean;
    isDragged?: boolean;
    isSnapTarget?: boolean;
    level?: number;
    label: string;
    onAddChild?: (parentId: string) => void;
    onAddParent?: (childId: string) => void;
    onDelete?: (contactId: string) => void;
  };
}

const getRelationshipIcon = (type?: string | null) => {
  switch (type) {
    case 'spouse':
    case 'boyfriend/girlfriend':
      return <Heart className="w-3 h-3" />;
    case 'child':
      return <Baby className="w-3 h-3" />;
    case 'co-worker':
      return <Briefcase className="w-3 h-3" />;
    case 'friend':
      return <Users className="w-3 h-3" />;
    case 'mother':
    case 'father':
    case 'parent':
      return <Star className="w-3 h-3" />;
    default:
      return <User className="w-3 h-3" />;
  }
};

export function ContactNode({ data }: ContactNodeProps) {
  const { contact, drop = false, isDragged = false, isSnapTarget = false, level = 0, onAddChild, onAddParent, onDelete } = data;
  const isMe = contact.isMe;
  const colorClasses = getContactColorClasses(contact.color || 'blue');

  const handleAddParent = (e: React.MouseEvent) => {
    e.stopPropagation();
    if (onAddParent) {
      onAddParent(contact.id);
    }
  };

  const handleAddChild = (e: React.MouseEvent) => {
    e.stopPropagation();
    if (onAddChild) {
      onAddChild(contact.id);
    }
  };

  const handleDelete = (e: React.MouseEvent) => {
    e.stopPropagation();
    if (onDelete && !contact.isMe) {
      onDelete(contact.id);
    }
  };

  return (
    <div
      className={clsx(
        'rounded-3xl p-3 transition-all duration-300 ease-out relative group',
        'backdrop-blur-md border',
        isDragged ? 'scale-105 shadow-2xl cursor-grabbing z-50' : 'cursor-grab hover:scale-105 hover:shadow-xl',
        isSnapTarget && 'ring-4 ring-indigo-400/50 ring-offset-2',
        isMe
          ? 'bg-gradient-to-br from-emerald-400/90 to-cyan-500/90 border-emerald-300/50 shadow-lg shadow-emerald-500/20 text-white'
          : 'bg-white/60 border-white/60 shadow-lg hover:bg-white/80 dark:bg-slate-900/60 dark:border-slate-700/60',
        drop && 'ring-4 ring-indigo-400 animate-pulse',
        drop && isMe && 'from-emerald-300 to-cyan-400',
        drop && !isMe && 'bg-indigo-50/80'
      )}
      style={{
        width: '200px', // Slightly wider for better text fit
        minHeight: '90px', // More compact
        zIndex: isDragged ? 1000 : 1,
      }}
      data-is-dragged={isDragged}
      data-is-snap-target={isSnapTarget}
    >
      {/* Delete icon - top right corner */}
      {!contact.isMe && onDelete && (
        <div
          className="absolute -top-3 -right-3 cursor-pointer group/delete z-10 opacity-0 group-hover:opacity-100 transition-opacity duration-200"
          onClick={handleDelete}
          title="Delete contact"
        >
          <div className="w-6 h-6 rounded-full border-2 border-white bg-red-100 hover:bg-red-200 text-red-600 transition-all duration-200 flex items-center justify-center shadow-sm hover:scale-110">
            <Trash2 className="w-3 h-3" />
          </div>
        </div>
      )}

      {/* Top Handle - Add Parent */}
      <div
        className="absolute -top-3 left-1/2 -translate-x-1/2 cursor-pointer group/handle z-10 opacity-0 group-hover:opacity-100 transition-opacity duration-200"
        onClick={handleAddParent}
        title="Add parent contact"
      >
        <div className={clsx(
          'w-6 h-6 rounded-full border-2 border-white transition-all duration-200 flex items-center justify-center shadow-sm',
          'hover:scale-110',
          isMe ? 'bg-emerald-200 hover:bg-emerald-300' : 'bg-indigo-100 hover:bg-indigo-200 text-indigo-600'
        )}>
          <Plus className="w-3 h-3" />
        </div>
        <Handle
          type="target"
          position={Position.Top}
          className="opacity-0 w-1 h-1"
        />
      </div>

      <div className="flex items-center gap-3">
        <div className="relative flex-shrink-0">
          <ProfilePhoto
            photo={contact.photo}
            name={contact.name}
            type={contact.type}
            size="md"
            className={clsx(
              'shadow-md ring-2 ring-white/70 transition-transform duration-300',
              isMe && 'ring-emerald-200/50'
            )}
          />
          {/* Status Dot (optional, maybe for online status later) */}
          {/* <div className="absolute bottom-0 right-0 w-3 h-3 bg-green-400 border-2 border-white rounded-full"></div> */}
        </div>

        <div className="flex flex-col min-w-0">
          <h3 className={clsx(
            'font-bold text-sm truncate leading-tight',
            isMe ? 'text-white' : 'text-slate-800 dark:text-slate-100'
          )}>
            {contact.name}
          </h3>

          {isMe ? (
            <p className="text-xs text-emerald-50 font-medium flex items-center gap-1 mt-0.5">
              <Star className="w-3 h-3 fill-emerald-50/50" />
              You
            </p>
          ) : contact.relationshipType ? (
            <div className={clsx(
              "flex items-center gap-1.5 mt-1 text-xs font-medium px-2 py-0.5 rounded-full w-fit",
              "bg-white/50 text-slate-600 border border-white/20"
            )}>
              {getRelationshipIcon(contact.relationshipType)}
              <span className="capitalize truncate max-w-[80px]">{contact.relationshipType}</span>
            </div>
          ) : (
            <p className="text-xs text-muted-foreground mt-0.5 italic">Contact</p>
          )}
        </div>
      </div>

      {/* Bottom Handle - Add Child */}
      <div
        className="absolute -bottom-3 left-1/2 -translate-x-1/2 cursor-pointer group/handle z-10 opacity-0 group-hover:opacity-100 transition-opacity duration-200"
        onClick={handleAddChild}
        title="Add child contact"
      >
        <div className={clsx(
          'w-6 h-6 rounded-full border-2 border-white transition-all duration-200 flex items-center justify-center shadow-sm',
          'hover:scale-110',
          isMe ? 'bg-emerald-200 hover:bg-emerald-300' : 'bg-indigo-100 hover:bg-indigo-200 text-indigo-600'
        )}>
          <Plus className="w-3 h-3" />
        </div>
        <Handle
          type="source"
          position={Position.Bottom}
          className="opacity-0 w-1 h-1"
        />
      </div>
    </div>
  );
}