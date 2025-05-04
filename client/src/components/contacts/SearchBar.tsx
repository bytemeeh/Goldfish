import { useState } from "react";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { cn } from "@/lib/utils";
import { Search, X, User, Mail, Phone, FileText } from "lucide-react";

export interface SearchFilters {
  name?: string;
  email?: string;
  phone?: string;
  notes?: string;
}

interface SearchBarProps {
  onSearch: (filters: SearchFilters) => void;
}

export function SearchBar({ onSearch }: SearchBarProps) {
  const [activeFilter, setActiveFilter] = useState<keyof SearchFilters>("name");
  const [filters, setFilters] = useState<SearchFilters>({});

  const handleFilterChange = (value: string) => {
    const newFilters = { ...filters, [activeFilter]: value };
    if (!value) {
      delete newFilters[activeFilter];
    }
    setFilters(newFilters);
    onSearch(newFilters);
  };

  const clearFilters = () => {
    setFilters({});
    onSearch({});
  };

  return (
    <div className="space-y-2">
      <Tabs 
        value={activeFilter} 
        onValueChange={(value) => setActiveFilter(value as keyof SearchFilters)}
        className="w-full"
      >
        <TabsList className="w-full grid grid-cols-4 h-9">
          <TabsTrigger value="name" className="flex items-center gap-1.5">
            <User className="h-3.5 w-3.5" />
            <span className="hidden sm:inline">Name</span>
          </TabsTrigger>
          <TabsTrigger value="email" className="flex items-center gap-1.5">
            <Mail className="h-3.5 w-3.5" />
            <span className="hidden sm:inline">Email</span>
          </TabsTrigger>
          <TabsTrigger value="phone" className="flex items-center gap-1.5">
            <Phone className="h-3.5 w-3.5" />
            <span className="hidden sm:inline">Phone</span>
          </TabsTrigger>
          <TabsTrigger value="notes" className="flex items-center gap-1.5">
            <FileText className="h-3.5 w-3.5" />
            <span className="hidden sm:inline">Notes</span>
          </TabsTrigger>
        </TabsList>
      </Tabs>
      
      <div className="flex gap-2 items-center">
        <div className="relative flex-1">
          <Search className="absolute left-2 top-2.5 h-4 w-4 text-muted-foreground" />
          <Input
            type="search"
            placeholder={`Search by ${activeFilter}...`}
            value={filters[activeFilter] || ""}
            onChange={(e) => handleFilterChange(e.target.value)}
            className="pl-8"
          />
        </div>

        {Object.keys(filters).length > 0 && (
          <Button
            variant="outline"
            size="icon"
            onClick={clearFilters}
            className="text-muted-foreground"
          >
            <X className="h-4 w-4" />
          </Button>
        )}
      </div>
    </div>
  );
}
