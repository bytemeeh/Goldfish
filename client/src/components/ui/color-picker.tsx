import { useState } from 'react';
import { Check } from 'lucide-react';
import { cn } from '@/lib/utils';
import { getContactColorOptions, ContactColor } from '@/lib/colors';

interface ColorPickerProps {
  value?: string;
  onValueChange: (value: string) => void;
  className?: string;
}

export function ColorPicker({ value, onValueChange, className }: ColorPickerProps) {
  const [isOpen, setIsOpen] = useState(false);
  const colorOptions = getContactColorOptions();

  return (
    <div className={cn("relative", className)}>
      <button
        type="button"
        onClick={() => setIsOpen(!isOpen)}
        className="w-full h-10 px-3 py-2 bg-background border border-input rounded-md text-sm ring-offset-background hover:bg-accent hover:text-accent-foreground focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
      >
        <div className="flex items-center gap-2">
          <div 
            className="w-4 h-4 rounded-full border border-gray-300"
            style={{ backgroundColor: colorOptions.find(c => c.value === value)?.color || '#3b82f6' }}
          />
          <span className="capitalize">
            {colorOptions.find(c => c.value === value)?.label || 'Blue'}
          </span>
        </div>
      </button>
      
      {isOpen && (
        <div className="absolute z-50 mt-1 p-2 bg-background border rounded-md shadow-lg">
          <div className="grid grid-cols-5 gap-2">
            {colorOptions.map((option) => (
              <button
                key={option.value}
                type="button"
                onClick={() => {
                  onValueChange(option.value);
                  setIsOpen(false);
                }}
                className="relative w-8 h-8 rounded-full border border-gray-300 hover:scale-110 transition-transform"
                style={{ backgroundColor: option.color }}
                title={option.label}
              >
                {value === option.value && (
                  <Check className="w-4 h-4 text-white absolute inset-0 m-auto" />
                )}
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}