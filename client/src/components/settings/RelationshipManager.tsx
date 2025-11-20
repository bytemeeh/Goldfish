import { useState } from "react";
import { useQuery, useMutation, useQueryClient } from "@tanstack/react-query";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
    Select,
    SelectContent,
    SelectItem,
    SelectTrigger,
    SelectValue,
} from "@/components/ui/select";
import { Trash2, Plus, Loader2, Settings2 } from "lucide-react";
import { useToast } from "@/hooks/use-toast";
import { Badge } from "@/components/ui/badge";
import { ScrollArea } from "@/components/ui/scroll-area";

type RelationshipDefinition = {
    id: string;
    name: string;
    category: string;
    isCore: boolean;
};

export function RelationshipManager() {
    const { toast } = useToast();
    const queryClient = useQueryClient();
    const [newName, setNewName] = useState("");
    const [newCategory, setNewCategory] = useState("friend");

    const { data: definitions, isLoading } = useQuery<RelationshipDefinition[]>({
        queryKey: ["/api/contacts/relationships/definitions"],
    });

    const createMutation = useMutation({
        mutationFn: async (data: { name: string; category: string }) => {
            const res = await fetch("/api/contacts/relationships/definitions", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify(data),
            });
            if (!res.ok) {
                const error = await res.json();
                throw new Error(error.error || "Failed to create relationship type");
            }
            return res.json();
        },
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ["/api/contacts/relationships/definitions"] });
            setNewName("");
            toast({ title: "Relationship type created" });
        },
        onError: (error: Error) => {
            toast({
                title: "Error",
                description: error.message,
                variant: "destructive",
            });
        },
    });

    const deleteMutation = useMutation({
        mutationFn: async (id: string) => {
            const res = await fetch(`/api/contacts/relationships/definitions/${id}`, {
                method: "DELETE",
            });
            if (!res.ok) {
                const error = await res.json();
                throw new Error(error.error || "Failed to delete relationship type");
            }
        },
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ["/api/contacts/relationships/definitions"] });
            toast({ title: "Relationship type deleted" });
        },
        onError: (error: Error) => {
            toast({
                title: "Error",
                description: error.message,
                variant: "destructive",
            });
        },
    });

    const handleSubmit = (e: React.FormEvent) => {
        e.preventDefault();
        if (!newName.trim()) return;
        createMutation.mutate({ name: newName, category: newCategory });
    };

    if (isLoading) {
        return <div className="flex justify-center p-8"><Loader2 className="h-6 w-6 animate-spin text-muted-foreground" /></div>;
    }

    const groupedDefinitions = definitions?.reduce((acc, def) => {
        if (!acc[def.category]) acc[def.category] = [];
        acc[def.category].push(def);
        return acc;
    }, {} as Record<string, RelationshipDefinition[]>) || {};

    return (
        <div className="space-y-6 p-1">
            <div className="bg-muted/30 p-4 rounded-lg border border-border/50">
                <h3 className="text-sm font-medium mb-3 flex items-center gap-2">
                    <Plus className="h-4 w-4" /> Add New Type
                </h3>
                <form onSubmit={handleSubmit} className="flex gap-2 items-end">
                    <div className="flex-1 space-y-1.5">
                        <Label htmlFor="name" className="text-xs">Name</Label>
                        <Input
                            id="name"
                            placeholder="e.g. Gym Buddy, Mentor"
                            value={newName}
                            onChange={(e) => setNewName(e.target.value)}
                            className="h-8 text-sm"
                        />
                    </div>
                    <div className="w-[140px] space-y-1.5">
                        <Label htmlFor="category" className="text-xs">Category</Label>
                        <Select value={newCategory} onValueChange={setNewCategory}>
                            <SelectTrigger className="h-8 text-sm">
                                <SelectValue />
                            </SelectTrigger>
                            <SelectContent>
                                <SelectItem value="family">Family</SelectItem>
                                <SelectItem value="friend">Friend</SelectItem>
                                <SelectItem value="work">Work</SelectItem>
                                <SelectItem value="other">Other</SelectItem>
                            </SelectContent>
                        </Select>
                    </div>
                    <Button
                        type="submit"
                        size="sm"
                        className="h-8"
                        disabled={createMutation.isPending || !newName.trim()}
                    >
                        {createMutation.isPending ? <Loader2 className="h-3 w-3 animate-spin" /> : "Add"}
                    </Button>
                </form>
            </div>

            <ScrollArea className="h-[400px] pr-4">
                <div className="space-y-6">
                    {Object.entries(groupedDefinitions).map(([category, defs]) => (
                        <div key={category}>
                            <h4 className="text-xs font-semibold uppercase text-muted-foreground mb-2 tracking-wider">
                                {category}
                            </h4>
                            <div className="grid grid-cols-1 gap-2">
                                {defs.map((def) => (
                                    <div
                                        key={def.id}
                                        className="flex items-center justify-between p-2 rounded-md bg-card border hover:bg-accent/50 transition-colors group"
                                    >
                                        <div className="flex items-center gap-2">
                                            <span className="text-sm font-medium">{def.name}</span>
                                            {def.isCore && (
                                                <Badge variant="secondary" className="text-[10px] h-5 px-1.5 font-normal text-muted-foreground">
                                                    Core
                                                </Badge>
                                            )}
                                        </div>
                                        {!def.isCore && (
                                            <Button
                                                variant="ghost"
                                                size="icon"
                                                className="h-7 w-7 text-muted-foreground hover:text-destructive opacity-0 group-hover:opacity-100 transition-opacity"
                                                onClick={() => deleteMutation.mutate(def.id)}
                                                disabled={deleteMutation.isPending}
                                            >
                                                <Trash2 className="h-3.5 w-3.5" />
                                            </Button>
                                        )}
                                    </div>
                                ))}
                            </div>
                        </div>
                    ))}
                </div>
            </ScrollArea>
        </div>
    );
}
