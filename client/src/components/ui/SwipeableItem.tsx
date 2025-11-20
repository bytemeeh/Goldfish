import React, { useRef, useState } from 'react';
import { motion, useMotionValue, useTransform, PanInfo } from 'framer-motion';
import { Phone, Trash2 } from 'lucide-react';
import { useHaptic } from '@/hooks/useHaptic';

interface SwipeableItemProps {
    children: React.ReactNode;
    onSwipeLeft?: () => void;
    onSwipeRight?: () => void;
    className?: string;
    enabled?: boolean;
}

export function SwipeableItem({
    children,
    onSwipeLeft,
    onSwipeRight,
    className = "",
    enabled = true
}: SwipeableItemProps) {
    const x = useMotionValue(0);
    const { triggerImpact } = useHaptic();
    const [swiped, setSwiped] = useState<'left' | 'right' | null>(null);

    // Threshold for triggering action
    const SWIPE_THRESHOLD = 100;

    // Background color opacity based on drag distance
    const leftOpacity = useTransform(x, [-SWIPE_THRESHOLD, 0], [1, 0]);
    const rightOpacity = useTransform(x, [0, SWIPE_THRESHOLD], [0, 1]);

    // Icon scale based on drag distance
    const leftIconScale = useTransform(x, [-SWIPE_THRESHOLD, -20], [1, 0.5]);
    const rightIconScale = useTransform(x, [20, SWIPE_THRESHOLD], [0.5, 1]);

    const handleDragEnd = (_: any, info: PanInfo) => {
        const offset = info.offset.x;

        if (offset < -SWIPE_THRESHOLD && onSwipeLeft) {
            triggerImpact();
            setSwiped('left');
            onSwipeLeft();
            // Reset after delay if action doesn't remove item
            setTimeout(() => setSwiped(null), 500);
        } else if (offset > SWIPE_THRESHOLD && onSwipeRight) {
            triggerImpact();
            setSwiped('right');
            onSwipeRight();
            setTimeout(() => setSwiped(null), 500);
        }
    };

    if (!enabled) {
        return <div className={className}>{children}</div>;
    }

    return (
        <div className={`relative overflow-hidden ${className}`}>
            {/* Left Action (Delete) - Visible when swiping left */}
            <motion.div
                style={{ opacity: leftOpacity }}
                className="absolute inset-y-0 right-0 w-full bg-red-500 flex items-center justify-end px-6 rounded-lg z-0"
            >
                <motion.div style={{ scale: leftIconScale }}>
                    <Trash2 className="text-white w-5 h-5" />
                </motion.div>
            </motion.div>

            {/* Right Action (Call) - Visible when swiping right */}
            <motion.div
                style={{ opacity: rightOpacity }}
                className="absolute inset-y-0 left-0 w-full bg-green-500 flex items-center justify-start px-6 rounded-lg z-0"
            >
                <motion.div style={{ scale: rightIconScale }}>
                    <Phone className="text-white w-5 h-5" />
                </motion.div>
            </motion.div>

            {/* Content */}
            <motion.div
                drag="x"
                dragConstraints={{ left: 0, right: 0 }}
                dragElastic={0.7}
                onDragEnd={handleDragEnd}
                style={{ x }}
                className="relative z-10 bg-background"
            >
                {children}
            </motion.div>
        </div>
    );
}
