import React, { useState, useEffect, useRef } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Button } from '@/components/ui/button';
import { Plus, X, MoreHorizontal } from 'lucide-react';

interface MenuItem {
  id: string;
  label: string;
  icon: React.ReactNode;
  action: () => void;
  condition?: () => boolean;
  priority?: number;
}

interface ContextualFloatingMenuProps {
  trigger: React.ReactNode;
  items: MenuItem[];
  position?: 'auto' | 'top' | 'bottom' | 'left' | 'right';
  className?: string;
  maxItems?: number;
  onStateChange?: (isOpen: boolean) => void;
}

export function ContextualFloatingMenu({
  trigger,
  items,
  position = 'auto',
  className = '',
  maxItems = 6,
  onStateChange
}: ContextualFloatingMenuProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [calculatedPosition, setCalculatedPosition] = useState<'top' | 'bottom' | 'left' | 'right'>('bottom');
  const [availableItems, setAvailableItems] = useState<MenuItem[]>([]);
  const [overflowItems, setOverflowItems] = useState<MenuItem[]>([]);
  const triggerRef = useRef<HTMLDivElement>(null);
  const menuRef = useRef<HTMLDivElement>(null);

  // Filter items based on conditions and sort by priority
  useEffect(() => {
    const filtered = items
      .filter(item => !item.condition || item.condition())
      .sort((a, b) => (b.priority || 0) - (a.priority || 0));
    
    if (filtered.length <= maxItems) {
      setAvailableItems(filtered);
      setOverflowItems([]);
    } else {
      setAvailableItems(filtered.slice(0, maxItems - 1));
      setOverflowItems(filtered.slice(maxItems - 1));
    }
  }, [items, maxItems]);

  // Smart positioning logic
  useEffect(() => {
    if (!isOpen || !triggerRef.current) return;

    const triggerRect = triggerRef.current.getBoundingClientRect();
    const viewportWidth = window.innerWidth;
    const viewportHeight = window.innerHeight;
    
    if (position === 'auto') {
      // Calculate best position based on available space
      const spaceAbove = triggerRect.top;
      const spaceBelow = viewportHeight - triggerRect.bottom;
      const spaceLeft = triggerRect.left;
      const spaceRight = viewportWidth - triggerRect.right;
      
      // Prioritize bottom, then top, then sides
      if (spaceBelow > 200) {
        setCalculatedPosition('bottom');
      } else if (spaceAbove > 200) {
        setCalculatedPosition('top');
      } else if (spaceRight > 300) {
        setCalculatedPosition('right');
      } else {
        setCalculatedPosition('left');
      }
    } else {
      setCalculatedPosition(position);
    }
  }, [isOpen, position]);

  // Handle click outside
  useEffect(() => {
    const handleClickOutside = (event: MouseEvent) => {
      if (
        isOpen &&
        triggerRef.current &&
        menuRef.current &&
        !triggerRef.current.contains(event.target as Node) &&
        !menuRef.current.contains(event.target as Node)
      ) {
        setIsOpen(false);
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [isOpen]);

  // Handle escape key
  useEffect(() => {
    const handleEscape = (event: KeyboardEvent) => {
      if (event.key === 'Escape' && isOpen) {
        setIsOpen(false);
      }
    };

    document.addEventListener('keydown', handleEscape);
    return () => document.removeEventListener('keydown', handleEscape);
  }, [isOpen]);

  // Notify parent of state changes
  useEffect(() => {
    onStateChange?.(isOpen);
  }, [isOpen, onStateChange]);

  const getMenuPositionClasses = () => {
    const baseClasses = 'absolute z-50';
    
    switch (calculatedPosition) {
      case 'top':
        return `${baseClasses} bottom-full mb-2 left-1/2 transform -translate-x-1/2`;
      case 'bottom':
        return `${baseClasses} top-full mt-2 left-1/2 transform -translate-x-1/2`;
      case 'left':
        return `${baseClasses} right-full mr-2 top-1/2 transform -translate-y-1/2`;
      case 'right':
        return `${baseClasses} left-full ml-2 top-1/2 transform -translate-y-1/2`;
      default:
        return `${baseClasses} top-full mt-2 left-1/2 transform -translate-x-1/2`;
    }
  };

  const getAnimationDirection = () => {
    switch (calculatedPosition) {
      case 'top':
        return { initial: { opacity: 0, y: 10 }, animate: { opacity: 1, y: 0 } };
      case 'bottom':
        return { initial: { opacity: 0, y: -10 }, animate: { opacity: 1, y: 0 } };
      case 'left':
        return { initial: { opacity: 0, x: 10 }, animate: { opacity: 1, x: 0 } };
      case 'right':
        return { initial: { opacity: 0, x: -10 }, animate: { opacity: 1, x: 0 } };
      default:
        return { initial: { opacity: 0, y: -10 }, animate: { opacity: 1, y: 0 } };
    }
  };

  const handleItemClick = (item: MenuItem) => {
    item.action();
    setIsOpen(false);
  };

  const toggleMenu = () => {
    setIsOpen(!isOpen);
  };

  const animation = getAnimationDirection();

  return (
    <div className={`relative ${className}`}>
      {/* Trigger */}
      <div ref={triggerRef} onClick={toggleMenu} className="cursor-pointer">
        {trigger}
      </div>

      {/* Menu */}
      <AnimatePresence>
        {isOpen && (
          <motion.div
            ref={menuRef}
            className={getMenuPositionClasses()}
            initial={animation.initial}
            animate={animation.animate}
            exit={animation.initial}
            transition={{ duration: 0.15, ease: 'easeOut' }}
          >
            <div className="bg-background/95 backdrop-blur-sm border border-border/40 rounded-lg shadow-lg p-1 min-w-[200px]">
              {/* Main items */}
              {availableItems.map((item) => (
                <Button
                  key={item.id}
                  variant="ghost"
                  size="sm"
                  className="w-full justify-start h-8 px-3 font-normal hover:bg-muted/30 text-xs"
                  onClick={() => handleItemClick(item)}
                >
                  <span className="mr-2">{item.icon}</span>
                  {item.label}
                </Button>
              ))}

              {/* Overflow items */}
              {overflowItems.length > 0 && (
                <div className="border-t border-border/40 mt-1 pt-1">
                  <div className="text-xs text-muted-foreground px-3 py-1">More actions</div>
                  {overflowItems.map((item) => (
                    <Button
                      key={item.id}
                      variant="ghost"
                      size="sm"
                      className="w-full justify-start h-8 px-3 font-normal hover:bg-muted/30 text-xs"
                      onClick={() => handleItemClick(item)}
                    >
                      <span className="mr-2">{item.icon}</span>
                      {item.label}
                    </Button>
                  ))}
                </div>
              )}

              {/* Empty state */}
              {availableItems.length === 0 && overflowItems.length === 0 && (
                <div className="text-xs text-muted-foreground px-3 py-2 text-center">
                  No actions available
                </div>
              )}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}