import React from 'react';
import { Handle, Position } from 'reactflow';
import { Contact } from '@/lib/types';
import { getContactColorClasses } from '@/lib/colors';
import { User, Phone, Mail } from 'lucide-react';
import { clsx } from 'clsx';

interface ContactNodeProps {
  data: {
    contact: Contact;
    drop?: boolean;
    isDragged?: boolean;
    isSnapTarget?: boolean;
    level?: number;
    label: string;
  };
}

export function ContactNode({ data }: ContactNodeProps) {
  const { contact, drop = false, isDragged = false, isSnapTarget = false, level = 0 } = data;
  const isMe = contact.isMe;
  const colorClasses = getContactColorClasses(contact.color || 'blue');
  
  return (
    <div
      className={clsx(
        'rounded-xl shadow-lg p-4 ring-offset-2 border-2',
        'hover:shadow-xl transition-all duration-120',
        isDragged ? 'opacity-80 cursor-grabbing shadow-2xl' : 'cursor-grab',
        isSnapTarget && 'ring-2 ring-blue-400 ring-dashed',
        isMe 
          ? 'bg-gradient-to-br from-emerald-400 to-cyan-500 border-emerald-300 shadow-emerald-200' 
          : `${colorClasses.bg} ${colorClasses.border}`,
        drop && 'ring-4 ring-indigo-400 animate-pulse',
        drop && isMe && 'bg-gradient-to-br from-emerald-300 to-cyan-400',
        drop && !isMe && 'bg-indigo-50'
      )}
      style={{ 
        width: '160px', 
        minHeight: '120px',
        zIndex: isDragged ? 1000 : 1,
      }}
      data-is-dragged={isDragged}
      data-is-snap-target={isSnapTarget}
    >
      <Handle
        type="target"
        position={Position.Top}
        className={clsx(
          'w-2 h-2',
          isMe ? 'bg-emerald-600' : 'bg-gray-400'
        )}
      />
      
      <div className="flex flex-col items-center space-y-2">
        <div className={clsx(
          'w-10 h-10 rounded-full flex items-center justify-center',
          isMe 
            ? 'bg-gradient-to-br from-emerald-600 to-cyan-700 shadow-lg' 
            : 'bg-gradient-to-br from-blue-500 to-purple-600'
        )}>
          <User className="w-5 h-5 text-white" />
        </div>
        
        <div className="text-center">
          <h3 className={clsx(
            'font-semibold text-sm truncate',
            isMe ? 'text-white' : 'text-gray-900'
          )}>
            {contact.name}
          </h3>
          {contact.relationshipType && (
            <p className={clsx(
              'text-xs capitalize',
              isMe ? 'text-emerald-100' : 'text-gray-500'
            )}>
              {contact.relationshipType}
            </p>
          )}
          {isMe && (
            <p className="text-xs text-emerald-100 font-medium">
              You
            </p>
          )}
        </div>
        
        <div className="flex space-x-2">
          {contact.phone && (
            <Phone className={clsx(
              'w-3 h-3',
              isMe ? 'text-emerald-100' : 'text-gray-400'
            )} />
          )}
          {contact.email && (
            <Mail className={clsx(
              'w-3 h-3',
              isMe ? 'text-emerald-100' : 'text-gray-400'
            )} />
          )}
        </div>
      </div>
      
      <Handle
        type="source"
        position={Position.Bottom}
        className={clsx(
          'w-2 h-2',
          isMe ? 'bg-emerald-600' : 'bg-gray-400'
        )}
      />
    </div>
  );
}