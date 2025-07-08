import { User } from 'lucide-react';

interface ProfilePhotoProps {
  photo?: string;
  name: string;
  size?: 'sm' | 'md' | 'lg';
  className?: string;
}

export function ProfilePhoto({ photo, name, size = 'md', className = '' }: ProfilePhotoProps) {
  const sizeClasses = {
    sm: 'w-8 h-8',
    md: 'w-12 h-12',
    lg: 'w-16 h-16'
  };

  const iconSizeClasses = {
    sm: 'w-4 h-4',
    md: 'w-6 h-6', 
    lg: 'w-8 h-8'
  };

  const getInitials = (fullName: string) => {
    return fullName
      .split(' ')
      .map(word => word.charAt(0))
      .join('')
      .toUpperCase()
      .slice(0, 2);
  };

  return (
    <div className={`${sizeClasses[size]} rounded-full border-2 border-blue-500 bg-blue-50 flex items-center justify-center overflow-hidden ${className}`}>
      {photo ? (
        <img 
          src={photo} 
          alt={`${name}'s profile`}
          className="w-full h-full object-cover"
        />
      ) : (
        <div className="w-full h-full bg-blue-100 flex items-center justify-center">
          {name ? (
            <span className={`font-medium text-blue-700 ${size === 'sm' ? 'text-xs' : size === 'md' ? 'text-sm' : 'text-base'}`}>
              {getInitials(name)}
            </span>
          ) : (
            <User className={`${iconSizeClasses[size]} text-blue-500`} />
          )}
        </div>
      )}
    </div>
  );
}