import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { Users, Briefcase, Heart, ChevronRight, ChevronDown, Filter } from "lucide-react";
import { useState } from "react";
import { motion, AnimatePresence } from "framer-motion";

interface QuickFilterProps {
    selectedFilter: string;
    onFilterChange: (filter: string) => void;
    className?: string;
}

export function QuickFilter({ selectedFilter, onFilterChange, className, showToggle = true }: QuickFilterProps & { showToggle?: boolean }) {
    const [isExpanded, setIsExpanded] = useState(!showToggle);

    const filters = [
        { id: "all", label: "All", icon: Filter },
        { id: "family", label: "Family", icon: Heart },
        { id: "friends", label: "Friends", icon: Users },
        { id: "professional", label: "Work", icon: Briefcase },
    ];

    return (
        <div className={cn("flex items-center gap-2", className)}>
            {showToggle && (
                <Button
                    variant="ghost"
                    size="sm"
                    className="h-8 w-8 p-0 rounded-full hover:bg-slate-100"
                    onClick={() => setIsExpanded(!isExpanded)}
                >
                    {isExpanded ? (
                        <ChevronRight className="h-4 w-4 text-muted-foreground" />
                    ) : (
                        <Filter className="h-4 w-4 text-muted-foreground" />
                    )}
                </Button>
            )}

            <AnimatePresence initial={false}>
                {isExpanded && (
                    <motion.div
                        initial={{ width: 0, opacity: 0 }}
                        animate={{ width: "auto", opacity: 1 }}
                        exit={{ width: 0, opacity: 0 }}
                        className="flex items-center gap-2 overflow-hidden"
                    >
                        {filters.map((filter) => {
                            const Icon = filter.icon;
                            const isSelected = selectedFilter === filter.id;

                            return (
                                <Button
                                    key={filter.id}
                                    variant={isSelected ? "default" : "outline"}
                                    size="sm"
                                    onClick={() => onFilterChange(filter.id)}
                                    className={cn(
                                        "h-7 text-xs gap-1.5 rounded-full transition-all",
                                        isSelected
                                            ? "bg-slate-900 text-white hover:bg-slate-800"
                                            : "bg-white/50 hover:bg-white border-slate-200 text-slate-600"
                                    )}
                                >
                                    <Icon className="w-3 h-3" />
                                    {filter.label}
                                </Button>
                            );
                        })}
                    </motion.div>
                )}
            </AnimatePresence>
        </div>
    );
}
