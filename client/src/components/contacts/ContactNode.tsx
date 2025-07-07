import React from 'react';
import { Handle, Position } from 'reactflow';
import { Contact } from '@/lib/types';
import { User, Phone, Mail } from 'lucide-react';
import { clsx } from 'clsx';

interface ContactNodeProps {
  data: {
    contact: Contact;
    drop?: boolean;
    label: string;
  };
}

export function ContactNode({ data }: ContactNodeProps) {
  const { contact, drop } = data;
  
  return (
    <div
      className={clsx(
        'rounded-xl bg-white shadow-lg p-4 transition-all duration-200 ring-offset-2 border-2 border-gray-100',
        'hover:shadow-xl hover:scale-105',
        drop && 'ring-4 ring-indigo-400 bg-indigo-50'
      )}
      style={{ width: '160px', minHeight: '120px' }}
    >
      <Handle
        type="target"
        position={Position.Top}
        className="w-2 h-2 bg-gray-400"
      />
      
      <div className="flex flex-col items-center space-y-2">
        <div className="w-10 h-10 bg-gradient-to-br from-blue-500 to-purple-600 rounded-full flex items-center justify-center">
          <User className="w-5 h-5 text-white" />
        </div>
        
        <div className="text-center">
          <h3 className="font-semibold text-sm text-gray-900 truncate">
            {contact.name}
          </h3>
          {contact.relationshipType && (
            <p className="text-xs text-gray-500 capitalize">
              {contact.relationshipType}
            </p>
          )}
        </div>
        
        <div className="flex space-x-2">
          {contact.phone && (
            <Phone className="w-3 h-3 text-gray-400" />
          )}
          {contact.email && (
            <Mail className="w-3 h-3 text-gray-400" />
          )}
        </div>
      </div>
      
      <Handle
        type="source"
        position={Position.Bottom}
        className="w-2 h-2 bg-gray-400"
      />
    </div>
  );
}