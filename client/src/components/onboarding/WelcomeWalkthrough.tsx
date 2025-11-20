import { useState, useEffect } from "react";
import { Dialog, DialogContent } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { motion, AnimatePresence } from "framer-motion";
import { Network, Sparkles, Users, ArrowRight, Check } from "lucide-react";

const STORAGE_KEY = "goldfish_has_seen_welcome";

export function WelcomeWalkthrough() {
    const [open, setOpen] = useState(false);
    const [step, setStep] = useState(0);

    useEffect(() => {
        const hasSeen = localStorage.getItem(STORAGE_KEY);
        if (!hasSeen) {
            // Small delay to let the app load first
            const timer = setTimeout(() => setOpen(true), 1000);
            return () => clearTimeout(timer);
        }
    }, []);

    const handleComplete = () => {
        localStorage.setItem(STORAGE_KEY, "true");
        setOpen(false);
    };

    const steps = [
        {
            icon: <div className="w-full h-full p-4"><img src="/logo.png" alt="Goldfish" className="w-full h-full object-contain" /></div>,
            title: "Welcome to Goldfish",
            description: "Your External Memory. Never forget a face, a name, or a connection.",
            color: "bg-blue-50 text-blue-600"
        },
        {
            icon: <Network className="w-12 h-12 text-purple-500" />,
            title: "Visualize Your Network",
            description: "See how everyone is connected. Switch to the Graph view to explore relationships dynamically.",
            color: "bg-purple-50 text-purple-600"
        },
        {
            icon: <Sparkles className="w-12 h-12 text-amber-500" />,
            title: "Context is King",
            description: "Don't just remember names. Remember how you met, who they know, and why they matter.",
            color: "bg-amber-50 text-amber-600"
        }
    ];

    const currentStep = steps[step];

    return (
        <Dialog open={open} onOpenChange={(val) => !val && handleComplete()}>
            <DialogContent className="sm:max-w-[425px] p-0 overflow-hidden border-0 shadow-2xl">
                <div className="relative h-[400px] flex flex-col">
                    {/* Background Patterns */}
                    <div className="absolute inset-0 bg-gradient-to-b from-background to-muted/20 z-0" />
                    <div className="absolute top-0 right-0 -mt-16 -mr-16 w-64 h-64 bg-primary/5 rounded-full blur-3xl" />
                    <div className="absolute bottom-0 left-0 -mb-16 -ml-16 w-64 h-64 bg-blue-500/5 rounded-full blur-3xl" />

                    <div className="relative z-10 flex-1 flex flex-col items-center justify-center p-8 text-center">
                        <AnimatePresence mode="wait">
                            <motion.div
                                key={step}
                                initial={{ opacity: 0, y: 20, scale: 0.95 }}
                                animate={{ opacity: 1, y: 0, scale: 1 }}
                                exit={{ opacity: 0, y: -20, scale: 0.95 }}
                                transition={{ duration: 0.3 }}
                                className="flex flex-col items-center"
                            >
                                <div className={`w-24 h-24 rounded-3xl ${currentStep.color} flex items-center justify-center mb-8 shadow-sm`}>
                                    {currentStep.icon}
                                </div>
                                <h2 className="text-2xl font-bold tracking-tight mb-3">
                                    {currentStep.title}
                                </h2>
                                <p className="text-muted-foreground leading-relaxed">
                                    {currentStep.description}
                                </p>
                            </motion.div>
                        </AnimatePresence>
                    </div>

                    <div className="relative z-10 p-6 bg-background/50 backdrop-blur-sm border-t flex items-center justify-between">
                        <div className="flex gap-1.5">
                            {steps.map((_, i) => (
                                <div
                                    key={i}
                                    className={`h-1.5 rounded-full transition-all duration-300 ${i === step ? "w-6 bg-primary" : "w-1.5 bg-muted-foreground/20"
                                        }`}
                                />
                            ))}
                        </div>

                        <Button
                            onClick={() => {
                                if (step < steps.length - 1) {
                                    setStep(step + 1);
                                } else {
                                    handleComplete();
                                }
                            }}
                            className="rounded-full px-6"
                        >
                            {step < steps.length - 1 ? (
                                <>
                                    Next <ArrowRight className="w-4 h-4 ml-2" />
                                </>
                            ) : (
                                <>
                                    Get Started <Check className="w-4 h-4 ml-2" />
                                </>
                            )}
                        </Button>
                    </div>
                </div>
            </DialogContent>
        </Dialog>
    );
}
