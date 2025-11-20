import { Contact } from "./types";

export type ContactCategory = {
    title: string;
    types: string[];
    color: string;
    contacts: Contact[];
};

export const CATEGORIES: Omit<ContactCategory, "contacts">[] = [
    {
        title: "Family",
        types: ["mother", "father", "brother", "sibling", "child", "spouse"],
        color: "hsl(var(--chart-1))",
    },
    {
        title: "Friends",
        types: ["friend", "boyfriend/girlfriend"],
        color: "hsl(var(--chart-2))",
    },
    {
        title: "Professional",
        types: ["co-worker"],
        color: "hsl(var(--chart-3))",
    },
];
