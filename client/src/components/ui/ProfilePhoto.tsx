import { User, PawPrint } from 'lucide-react';

interface ProfilePhotoProps {
  photo?: string;
  name: string;
  type?: 'person' | 'pet';
  size?: 'sm' | 'md' | 'lg' | 'xl';
  className?: string;
}

export function ProfilePhoto({ photo, name, type = 'person', size = 'md', className = '' }: ProfilePhotoProps) {
  const sizeClasses = {
    sm: 'w-8 h-8',
    md: 'w-12 h-12',
    lg: 'w-16 h-16',
    xl: 'w-32 h-32 md:w-40 md:h-40'
  };

  const iconSizeClasses = {
    sm: 'w-4 h-4',
    md: 'w-6 h-6',
    lg: 'w-8 h-8',
    xl: 'w-16 h-16'
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
          {type === 'pet' ? (
            <PawPrint className={`${iconSizeClasses[size]} text-blue-500`} />
          ) : name ? (
            <span className={`font-medium text-blue-700 ${size === 'sm' ? 'text-xs' : size === 'md' ? 'text-sm' : size === 'lg' ? 'text-base' : 'text-3xl'}`}>
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