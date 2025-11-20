import { useRegisterSW } from 'virtual:pwa-register/react'
import { Button } from "@/components/ui/button";
import { ToastAction } from "@/components/ui/toast";
import { useToast } from "@/hooks/use-toast";
import { useEffect } from 'react';

export function ReloadPrompt() {
    const { toast } = useToast();

    const {
        offlineReady: [offlineReady, setOfflineReady],
        needRefresh: [needRefresh, setNeedRefresh],
        updateServiceWorker,
    } = useRegisterSW({
        onRegistered(r) {
            console.log('SW Registered: ' + r)
        },
        onRegisterError(error) {
            console.log('SW registration error', error)
        },
    })

    const close = () => {
        setOfflineReady(false)
        setNeedRefresh(false)
    }

    useEffect(() => {
        if (offlineReady) {
            toast({
                title: "App ready to work offline",
                description: "Goldfish can now be used without an internet connection.",
            });
            setOfflineReady(false);
        }
    }, [offlineReady, toast]);

    useEffect(() => {
        if (needRefresh) {
            toast({
                title: "New content available",
                description: "Click reload to update the app.",
                action: (
                    <ToastAction altText="Reload" onClick={() => updateServiceWorker(true)}>
                        Reload
                    </ToastAction>
                ),
                duration: Infinity, // Keep it open until action is taken
            });
        }
    }, [needRefresh, toast, updateServiceWorker]);

    return null; // The UI is handled by the toast
}
