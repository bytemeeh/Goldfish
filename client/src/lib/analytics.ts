import { v4 as uuidv4 } from 'uuid';

const ANALYTICS_ENDPOINT = '/api/analytics';
const STORAGE_KEY = 'goldfish_anonymous_id';

class AnalyticsService {
    private anonymousId: string;

    constructor() {
        const id = localStorage.getItem(STORAGE_KEY);
        if (id) {
            this.anonymousId = id;
        } else {
            const newId = uuidv4();
            localStorage.setItem(STORAGE_KEY, newId);
            this.anonymousId = newId;
        }
    }

    public async track(eventType: string, properties: Record<string, any> = {}) {
        try {
            // Add common properties
            const enrichedProperties = {
                ...properties,
                path: window.location.pathname,
                timestamp: new Date().toISOString(),
                userAgent: navigator.userAgent,
            };

            await fetch(ANALYTICS_ENDPOINT, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    anonymousId: this.anonymousId,
                    eventType,
                    properties: enrichedProperties,
                }),
            });
        } catch (error) {
            // Fail silently to not impact user experience
            console.error('Failed to track event:', error);
        }
    }

    public getAnonymousId(): string {
        return this.anonymousId;
    }
}

export const analytics = new AnalyticsService();
