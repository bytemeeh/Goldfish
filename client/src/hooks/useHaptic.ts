import { useCallback } from 'react';

export function useHaptic() {
    const vibrate = useCallback((pattern: number | number[] = 10) => {
        if (typeof navigator !== 'undefined' && navigator.vibrate) {
            navigator.vibrate(pattern);
        }
    }, []);

    const triggerSuccess = useCallback(() => vibrate([10, 30, 10]), [vibrate]);
    const triggerError = useCallback(() => vibrate([50, 30, 50]), [vibrate]);
    const triggerImpact = useCallback(() => vibrate(15), [vibrate]);

    return {
        vibrate,
        triggerSuccess,
        triggerError,
        triggerImpact
    };
}
