import React from 'react';
import { Handle, Position } from 'reactflow';
import { Contact } from '@/lib/types';
import { User, Phone, Mail } from 'lucide-react';
import { clsx } from 'clsx';

interface ContactNodeProps {
  data: {
    contact: Contact;
    drop?: boolean;
    isDragging?: boolean;
    level?: number;
    label: string;
  };
}

export function ContactNode({ data }: ContactNodeProps) {
  const { contact, drop = false, isDragging = false, level = 0 } = data;
  const isMe = contact.isMe;
  
  return (
    <div
      className={clsx(
        'rounded-lg shadow-md border-2 cursor-grab',
        'hover:shadow-lg transition-all duration-150',
        drop && 'ring-3 ring-indigo-400 ring-offset-1',
        level === 0 && !isMe && 'border-blue-300 bg-blue-50',
        level === 1 && 'border-green-300 bg-green-50',
        level >= 2 && 'border-purple-300 bg-purple-50',
        isMe 
          ? 'bg-gradient-to-br from-emerald-400 to-emerald-600 text-white border-emerald-500' 
          : 'bg-white border-gray-300'
      )}
      style={{ 
        width: '140px', 
        height: '90px',
        padding: '8px'
      }}
    >
      <Handle
        type="target"
        position={Position.Top}
        className="w-2 h-2 bg-transparent border-transparent"
      />
      
      <div className="flex flex-col h-full justify-between">
        {/* Header with avatar and name */}
        <div className="flex items-center space-x-2">
          <div className={clsx(
            'w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0',
            isMe 
              ? 'bg-white/20' 
              : 'bg-gray-100'
          )}>
            <User className={clsx('w-4 h-4', isMe ? 'text-white' : 'text-gray-600')} />
          </div>
          
          <div className="flex-1 min-w-0">
            <h3 className={clsx(
              'font-semibold text-sm leading-tight truncate',
              isMe ? 'text-white' : 'text-gray-900'
            )}>
              {contact.name}
            </h3>
            {contact.relationshipType && (
              <p className={clsx(
                'text-xs capitalize truncate',
                isMe ? 'text-white/80' : 'text-gray-500'
              )}>
                {contact.relationshipType}
              </p>
            )}
          </div>
        </div>
        
        {/* Contact info icons */}
        <div className="flex items-center space-x-3">
          {contact.phone && (
            <div className="flex items-center space-x-1">
              <Phone className={clsx('w-3 h-3', isMe ? 'text-white/80' : 'text-gray-500')} />
              <span className={clsx(
                'text-xs truncate max-w-20',
                isMe ? 'text-white/90' : 'text-gray-600'
              )}>
                {contact.phone.slice(-4)}
              </span>
            </div>
          )}
          
          {contact.email && (
            <Mail className={clsx('w-3 h-3', isMe ? 'text-white/80' : 'text-gray-500')} />
          )}
        </div>
      </div>
      
      <Handle
        type="source"
        position={Position.Bottom}
        className="w-2 h-2 bg-transparent border-transparent"
      />
    </div>
  );
}