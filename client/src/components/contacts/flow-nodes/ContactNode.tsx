import { memo } from 'react';
import { Handle, Position, NodeProps } from 'reactflow';
import { Contact } from '@/lib/types';
import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import { Badge } from '@/components/ui/badge';

interface ContactNodeData {
  contact: Contact;
  level: number;
  isSelected: boolean;
}

// Color theme for different relationship types
const relationshipColors = {
  family: {
    bg: 'bg-[#00ACE6]/10',
    border: 'border-[#00ACE6]',
    text: 'text-[#00ACE6]'
  },
  friends: {
    bg: 'bg-[#FF0080]/10',
    border: 'border-[#FF0080]',
    text: 'text-[#FF0080]'
  },
  professional: {
    bg: 'bg-[#FF8000]/10',
    border: 'border-[#FF8000]',
    text: 'text-[#FF8000]'
  },
  personal: {
    bg: 'bg-[#00B359]/10',
    border: 'border-[#00B359]',
    text: 'text-[#00B359]'
  },
  default: {
    bg: 'bg-muted/50',
    border: 'border-muted-foreground/50',
    text: 'text-muted-foreground'
  }
};

export const ContactNode = memo(({ data }: NodeProps<ContactNodeData>) => {
  const { contact, level, isSelected } = data;
  
  // Determine style based on relationship type
  const getNodeStyle = () => {
    if (contact.isMe) {
      return relationshipColors.personal;
    }
    
    const relType = contact.relationshipType || 'default';
    
    const categories = {
      family: ['mother', 'father', 'brother', 'sibling', 'child', 'spouse'],
      friends: ['friend', 'boyfriend/girlfriend'],
      professional: ['co-worker']
    };
    
    if (categories.family.includes(relType)) {
      return relationshipColors.family;
    } else if (categories.friends.includes(relType)) {
      return relationshipColors.friends;
    } else if (categories.professional.includes(relType)) {
      return relationshipColors.professional;
    }
    
    return relationshipColors.default;
  };
  
  const nodeStyle = getNodeStyle();
  
  // Generate initials for avatar
  const getInitials = (name: string) => {
    return name
      .split(' ')
      .map(part => part[0])
      .join('')
      .toUpperCase()
      .substring(0, 2);
  };
  
  return (
    <div
      className={`
        group relative w-40 rounded-md border-2 p-2 transition-all duration-200
        ${nodeStyle.bg} ${nodeStyle.border}
        ${isSelected ? 'border-primary shadow-lg scale-110' : 'shadow'}
      `}
    >
      <Handle type="target" position={Position.Top} className="!bg-muted-foreground" />
      
      <div className="flex flex-col items-center gap-1">
        <Avatar className={`w-12 h-12 ${isSelected ? 'ring-2 ring-primary' : ''}`}>
          <AvatarFallback className={`text-sm ${nodeStyle.text}`}>
            {getInitials(contact.name)}
          </AvatarFallback>
        </Avatar>
        
        <div className="text-center mt-1">
          <h3 className="font-medium text-foreground truncate max-w-full">
            {contact.name}
          </h3>
          
          {contact.relationshipType && (
            <Badge 
              variant="outline" 
              className={`mt-1 text-xs ${nodeStyle.text} ${nodeStyle.border}`}
            >
              {contact.relationshipType}
            </Badge>
          )}
          
          {contact.isMe && (
            <Badge 
              variant="outline" 
              className="mt-1 text-xs bg-primary/10 border-primary text-primary"
            >
              You
            </Badge>
          )}
          
          <div className="text-xs text-muted-foreground mt-1">
            Level {level}
          </div>
        </div>
      </div>
      
      <Handle type="source" position={Position.Bottom} className="!bg-muted-foreground" />
    </div>
  );
});