import React, { useState, useEffect } from "react";
import { Dialog, DialogContent } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { motion, AnimatePresence } from "framer-motion";
import { Network, Sparkles, ArrowRight, ArrowLeft, Database, Upload, Rocket } from "lucide-react";

const STORAGE_KEY = "goldfish_has_seen_welcome";
const DEMO_DATA_KEY = "goldfish_demo_data_active";

type StartChoice = "demo" | "import" | "scratch";

export function WelcomeWalkthrough() {
    const [open, setOpen] = useState(false);
    const [step, setStep] = useState(0);

    useEffect(() => {
        const hasSeen = localStorage.getItem(STORAGE_KEY);
        if (!hasSeen) {
            const timer = setTimeout(() => setOpen(true), 1000);
            return () => clearTimeout(timer);
        }
    }, []);

    const handleChoice = (choice: StartChoice) => {
        localStorage.setItem(STORAGE_KEY, "true");

        switch (choice) {
            case "demo":
                localStorage.setItem(DEMO_DATA_KEY, "true");
                break;
            case "import":
                localStorage.setItem(DEMO_DATA_KEY, "false");
                // Dispatch a custom event so the app can open the import dialog
                window.dispatchEvent(new CustomEvent("goldfish:import-contacts"));
                break;
            case "scratch":
                localStorage.setItem(DEMO_DATA_KEY, "false");
                break;
        }

        setOpen(false);
    };

    const totalSteps = 4;

    const contentSteps = [
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

    const isChoiceStep = step === 3;
    const currentContentStep = !isChoiceStep ? contentSteps[step] : null;

    const choices: { key: StartChoice; icon: React.ReactNode; title: string; description: string; gradient: string; border: string }[] = [
        {
            key: "demo",
            icon: <Database className="w-6 h-6" />,
            title: "Keep Demo Data",
            description: "Explore with pre-loaded sample contacts & connections.",
            gradient: "from-purple-500/10 to-blue-500/10",
            border: "border-purple-500/20 hover:border-purple-500/50"
        },
        {
            key: "import",
            icon: <Upload className="w-6 h-6" />,
            title: "Import Contacts",
            description: "Bring in your existing contacts to get started quickly.",
            gradient: "from-blue-500/10 to-cyan-500/10",
            border: "border-blue-500/20 hover:border-blue-500/50"
        },
        {
            key: "scratch",
            icon: <Rocket className="w-6 h-6" />,
            title: "Start Fresh",
            description: "Begin with a clean slate and add contacts as you go.",
            gradient: "from-amber-500/10 to-orange-500/10",
            border: "border-amber-500/20 hover:border-amber-500/50"
        }
    ];

    return (
        <Dialog open={open} onOpenChange={(val) => { if (!val) handleChoice("demo"); }}>
            <DialogContent className="sm:max-w-[425px] p-0 overflow-hidden border-0 shadow-2xl">
                <div className={`relative ${isChoiceStep ? "h-[480px]" : "h-[400px]"} flex flex-col transition-all duration-300`}>
                    {/* Background Patterns */}
                    <div className="absolute inset-0 bg-gradient-to-b from-background to-muted/20 z-0" />
                    <div className="absolute top-0 right-0 -mt-16 -mr-16 w-64 h-64 bg-primary/5 rounded-full blur-3xl" />
                    <div className="absolute bottom-0 left-0 -mb-16 -ml-16 w-64 h-64 bg-blue-500/5 rounded-full blur-3xl" />

                    <div className="relative z-10 flex-1 flex flex-col items-center justify-center p-8 text-center">
                        <AnimatePresence mode="wait">
                            {!isChoiceStep && currentContentStep ? (
                                <motion.div
                                    key={step}
                                    initial={{ opacity: 0, y: 20, scale: 0.95 }}
                                    animate={{ opacity: 1, y: 0, scale: 1 }}
                                    exit={{ opacity: 0, y: -20, scale: 0.95 }}
                                    transition={{ duration: 0.3 }}
                                    className="flex flex-col items-center"
                                >
                                    <div className={`w-24 h-24 rounded-3xl ${currentContentStep.color} flex items-center justify-center mb-8 shadow-sm`}>
                                        {currentContentStep.icon}
                                    </div>
                                    <h2 className="text-2xl font-bold tracking-tight mb-3">
                                        {currentContentStep.title}
                                    </h2>
                                    <p className="text-muted-foreground leading-relaxed">
                                        {currentContentStep.description}
                                    </p>
                                </motion.div>
                            ) : (
                                <motion.div
                                    key="choice"
                                    initial={{ opacity: 0, y: 20, scale: 0.95 }}
                                    animate={{ opacity: 1, y: 0, scale: 1 }}
                                    exit={{ opacity: 0, y: -20, scale: 0.95 }}
                                    transition={{ duration: 0.3 }}
                                    className="flex flex-col items-center w-full"
                                >
                                    <h2 className="text-2xl font-bold tracking-tight mb-2">
                                        How would you like to start?
                                    </h2>
                                    <p className="text-muted-foreground text-sm mb-6">
                                        You can always change this later in Settings.
                                    </p>
                                    <div className="flex flex-col gap-3 w-full">
                                        {choices.map((c, i) => (
                                            <motion.button
                                                key={c.key}
                                                initial={{ opacity: 0, x: -20 }}
                                                animate={{ opacity: 1, x: 0 }}
                                                transition={{ duration: 0.3, delay: i * 0.1 }}
                                                onClick={() => handleChoice(c.key)}
                                                className={`w-full flex items-center gap-4 p-4 rounded-xl border bg-gradient-to-r ${c.gradient} ${c.border} transition-all duration-200 hover:shadow-md hover:scale-[1.02] active:scale-[0.98] text-left cursor-pointer`}
                                            >
                                                <div className="shrink-0 w-10 h-10 rounded-lg bg-background/80 flex items-center justify-center shadow-sm">
                                                    {c.icon}
                                                </div>
                                                <div className="min-w-0">
                                                    <div className="font-semibold text-sm">{c.title}</div>
                                                    <div className="text-xs text-muted-foreground">{c.description}</div>
                                                </div>
                                            </motion.button>
                                        ))}
                                    </div>
                                </motion.div>
                            )}
                        </AnimatePresence>
                    </div>

                    <div className="relative z-10 p-6 bg-background/50 backdrop-blur-sm border-t flex items-center justify-between">
                        <div className="flex items-center gap-3">
                            {step > 0 && (
                                <Button
                                    variant="ghost"
                                    size="sm"
                                    onClick={() => setStep(step - 1)}
                                    className="rounded-full px-3"
                                >
                                    <ArrowLeft className="w-4 h-4 mr-1" /> Back
                                </Button>
                            )}
                        </div>

                        <div className="flex gap-1.5">
                            {Array.from({ length: totalSteps }).map((_, i) => (
                                <div
                                    key={i}
                                    className={`h-1.5 rounded-full transition-all duration-300 ${i === step ? "w-6 bg-primary" : "w-1.5 bg-muted-foreground/20"
                                        }`}
                                />
                            ))}
                        </div>

                        {!isChoiceStep && (
                            <Button
                                onClick={() => setStep(step + 1)}
                                className="rounded-full px-6"
                            >
                                Next <ArrowRight className="w-4 h-4 ml-2" />
                            </Button>
                        )}
                        {isChoiceStep && <div className="w-[100px]" />}
                    </div>
                </div>
            </DialogContent>
        </Dialog>
    );
}
