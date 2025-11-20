import { useState, useEffect } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { motion, AnimatePresence } from "framer-motion";
import { Plus, Users, Share2, Trash2, Search, Filter, MousePointer2 } from "lucide-react";

interface HelpDialogProps {
    open: boolean;
    onOpenChange: (open: boolean) => void;
}

export function HelpDialog({ open, onOpenChange }: HelpDialogProps) {
    const [activeTab, setActiveTab] = useState<'overview' | 'demo'>('overview');

    return (
        <Dialog open={open} onOpenChange={onOpenChange}>
            <DialogContent className="max-w-3xl h-[80vh] flex flex-col p-0 overflow-hidden">
                <div className="flex h-full">
                    {/* Sidebar */}
                    <div className="w-64 bg-muted/30 border-r p-4 space-y-2">
                        <h3 className="font-semibold mb-4 px-2">Help Center</h3>
                        <Button
                            variant={activeTab === 'overview' ? "secondary" : "ghost"}
                            className="w-full justify-start"
                            onClick={() => setActiveTab('overview')}
                        >
                            Overview
                        </Button>
                        <Button
                            variant={activeTab === 'demo' ? "secondary" : "ghost"}
                            className="w-full justify-start"
                            onClick={() => setActiveTab('demo')}
                        >
                            Live Demo (GOT)
                        </Button>
                    </div>

                    {/* Content */}
                    <div className="flex-1 p-6 overflow-y-auto">
                        {activeTab === 'overview' ? (
                            <div className="space-y-6">
                                <div>
                                    <h2 className="text-2xl font-bold mb-2">Getting Started</h2>
                                    <p className="text-muted-foreground">
                                        Goldfish helps you manage your social context, not just phone numbers.
                                    </p>
                                </div>

                                <div className="grid gap-4">
                                    <div className="p-4 border rounded-lg bg-card">
                                        <div className="flex items-center gap-2 font-semibold mb-2">
                                            <Plus className="w-4 h-4 text-primary" /> Adding Contacts
                                        </div>
                                        <p className="text-sm text-muted-foreground">
                                            Click the "+" button or use "Add by Voice" to quickly create new contacts.
                                        </p>
                                    </div>

                                    <div className="p-4 border rounded-lg bg-card">
                                        <div className="flex items-center gap-2 font-semibold mb-2">
                                            <Users className="w-4 h-4 text-primary" /> Relationships
                                        </div>
                                        <p className="text-sm text-muted-foreground">
                                            Connect people! Open a contact and click "Add Related" to define relationships like "Spouse", "Child", or "Co-worker".
                                        </p>
                                    </div>

                                    <div className="p-4 border rounded-lg bg-card">
                                        <div className="flex items-center gap-2 font-semibold mb-2">
                                            <Filter className="w-4 h-4 text-primary" /> Filtering
                                        </div>
                                        <p className="text-sm text-muted-foreground">
                                            Use the top toolbar in Graph View to filter by "Family", "Friends", or "Work".
                                        </p>
                                    </div>
                                </div>
                            </div>
                        ) : (
                            <DemoAnimation />
                        )}
                    </div>
                </div>
            </DialogContent>
        </Dialog>
    );
}

function DemoAnimation() {
    const [step, setStep] = useState(0);

    // Auto-play steps
    useEffect(() => {
        const timer = setInterval(() => {
            setStep((prev) => (prev + 1) % 6);
        }, 3000);
        return () => clearInterval(timer);
    }, []);

    const steps = [
        { text: "Start with your first contact", action: "Click '+'" },
        { text: "Add Jon Snow", action: "Typing..." },
        { text: "Contact Created", action: "Jon Snow added" },
        { text: "Add a relationship", action: "Click 'Add Related'" },
        { text: "Add Arya Stark (Sister)", action: "Defining relation..." },
        { text: "Network Visualized", action: "Connection established" },
    ];

    return (
        <div className="space-y-6">
            <div>
                <h2 className="text-2xl font-bold mb-2">Interactive Demo</h2>
                <p className="text-muted-foreground">
                    Watch how to organize the Stark family from Game of Thrones.
                </p>
            </div>

            <div className="relative w-full aspect-video bg-slate-900 rounded-xl overflow-hidden border shadow-2xl ring-1 ring-slate-800">
                {/* Mock UI Container */}
                <div className="absolute inset-0 p-8 flex items-center justify-center bg-slate-950/50">

                    {/* Step 0: Empty State */}
                    <AnimatePresence mode="wait">
                        {step === 0 && (
                            <motion.div
                                key="step0"
                                initial={{ opacity: 0 }}
                                animate={{ opacity: 1 }}
                                exit={{ opacity: 0 }}
                                className="absolute inset-0 flex items-center justify-center"
                            >
                                <div className="text-slate-500 flex flex-col items-center gap-2">
                                    <Users className="w-12 h-12 opacity-20" />
                                    <span>Your network is empty</span>
                                </div>

                                {/* Cursor clicking Plus */}
                                <motion.div
                                    initial={{ x: 100, y: 100, opacity: 0 }}
                                    animate={{ x: 140, y: -120, opacity: 1 }}
                                    transition={{ duration: 1 }}
                                    className="absolute z-50"
                                >
                                    <MousePointer2 className="w-6 h-6 text-white drop-shadow-md fill-black" />
                                    <div className="absolute top-full left-0 bg-white text-black text-xs px-2 py-1 rounded shadow mt-1 whitespace-nowrap">
                                        Click Add
                                    </div>
                                </motion.div>
                            </motion.div>
                        )}

                        {/* Step 1: Form Filling */}
                        {step === 1 && (
                            <motion.div
                                key="step1"
                                initial={{ opacity: 0, scale: 0.9 }}
                                animate={{ opacity: 1, scale: 1 }}
                                exit={{ opacity: 0, scale: 1.1 }}
                                className="bg-white p-6 rounded-lg shadow-2xl w-80 space-y-4 relative z-10"
                            >
                                <div className="h-4 bg-slate-100 rounded w-1/3" />
                                <div className="h-10 border rounded w-full flex items-center px-3 text-sm text-slate-800">
                                    <motion.span
                                        initial={{ width: 0 }}
                                        animate={{ width: "auto" }}
                                        className="overflow-hidden whitespace-nowrap border-r-2 border-blue-500 pr-1"
                                    >
                                        Jon Snow
                                    </motion.span>
                                </div>
                                <div className="h-8 bg-blue-500 rounded w-full flex items-center justify-center text-white text-sm font-medium shadow-lg shadow-blue-500/20">
                                    Save Contact
                                </div>
                            </motion.div>
                        )}

                        {/* Step 2: Jon Card */}
                        {(step === 2 || step === 3) && (
                            <motion.div
                                key="step2"
                                initial={{ opacity: 0, y: 20 }}
                                animate={{ opacity: 1, y: 0 }}
                                exit={{ opacity: 0, x: -50 }}
                                className="bg-slate-800 p-4 rounded-xl border border-slate-700 w-48 flex flex-col items-center gap-3 shadow-xl"
                            >
                                <div className="w-12 h-12 rounded-full bg-slate-700 flex items-center justify-center text-lg">🐺</div>
                                <div className="text-white font-medium">Jon Snow</div>
                                {step === 3 && (
                                    <motion.div
                                        initial={{ opacity: 0 }}
                                        animate={{ opacity: 1 }}
                                        className="absolute -right-12 top-1/2"
                                    >
                                        <MousePointer2 className="w-6 h-6 text-white drop-shadow-md fill-black" />
                                    </motion.div>
                                )}
                            </motion.div>
                        )}

                        {/* Step 4: Add Arya Form */}
                        {step === 4 && (
                            <motion.div
                                key="step4"
                                initial={{ opacity: 0, x: 50 }}
                                animate={{ opacity: 1, x: 0 }}
                                exit={{ opacity: 0 }}
                                className="bg-white p-6 rounded-lg shadow-2xl w-80 space-y-4 relative z-10"
                            >
                                <div className="text-xs text-slate-400 uppercase font-bold">Related to Jon Snow</div>
                                <div className="h-10 border rounded w-full flex items-center px-3 text-sm text-slate-800">
                                    Arya Stark
                                </div>
                                <div className="flex gap-2">
                                    <div className="h-8 bg-pink-100 text-pink-600 rounded px-3 flex items-center text-xs font-medium border border-pink-200">
                                        Sister
                                    </div>
                                </div>
                                <div className="h-8 bg-blue-500 rounded w-full flex items-center justify-center text-white text-sm font-medium">
                                    Save Relationship
                                </div>
                            </motion.div>
                        )}

                        {/* Step 5: Network */}
                        {step === 5 && (
                            <motion.div
                                key="step5"
                                initial={{ opacity: 0 }}
                                animate={{ opacity: 1 }}
                                className="flex items-center gap-8"
                            >
                                <div className="bg-slate-800 p-4 rounded-xl border border-slate-700 w-40 flex flex-col items-center gap-2 z-10">
                                    <div className="w-10 h-10 rounded-full bg-slate-700 flex items-center justify-center">🐺</div>
                                    <div className="text-white text-sm font-medium">Jon Snow</div>
                                </div>

                                <motion.div
                                    initial={{ width: 0 }}
                                    animate={{ width: 60 }}
                                    className="h-0.5 bg-slate-600 relative"
                                >
                                    <div className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 bg-slate-900 px-2 text-[10px] text-slate-400">
                                        Sibling
                                    </div>
                                </motion.div>

                                <div className="bg-slate-800 p-4 rounded-xl border border-slate-700 w-40 flex flex-col items-center gap-2 z-10">
                                    <div className="w-10 h-10 rounded-full bg-slate-700 flex items-center justify-center">🗡️</div>
                                    <div className="text-white text-sm font-medium">Arya Stark</div>
                                </div>
                            </motion.div>
                        )}
                    </AnimatePresence>

                    {/* Progress Indicator */}
                    <div className="absolute bottom-4 left-0 right-0 flex justify-center gap-2">
                        {steps.map((_, i) => (
                            <div
                                key={i}
                                className={`h-1.5 rounded-full transition-all duration-300 ${i === step ? "w-8 bg-blue-500" : "w-1.5 bg-slate-700"}`}
                            />
                        ))}
                    </div>

                    <div className="absolute bottom-4 right-4 text-xs text-slate-500 font-mono">
                        {steps[step].action}
                    </div>
                </div>
            </div>

        </div>
    </div >
  );
}
