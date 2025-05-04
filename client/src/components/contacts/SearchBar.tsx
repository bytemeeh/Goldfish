import { useState } from "react";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { Search, X, User, Mail, Phone, FileText } from "lucide-react";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";

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
    <div>
      <div className="flex gap-1.5 items-center">
        <Select 
          value={activeFilter} 
          onValueChange={(value) => setActiveFilter(value as keyof SearchFilters)}
        >
          <SelectTrigger className="w-[100px] h-8 flex-shrink-0 text-xs">
            <SelectValue placeholder="Search by" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value="name" className="text-xs">
              <div className="flex items-center gap-1.5">
                <User className="h-3.5 w-3.5" />
                <span>Name</span>
              </div>
            </SelectItem>
            <SelectItem value="email" className="text-xs">
              <div className="flex items-center gap-1.5">
                <Mail className="h-3.5 w-3.5" />
                <span>Email</span>
              </div>
            </SelectItem>
            <SelectItem value="phone" className="text-xs">
              <div className="flex items-center gap-1.5">
                <Phone className="h-3.5 w-3.5" />
                <span>Phone</span>
              </div>
            </SelectItem>
            <SelectItem value="notes" className="text-xs">
              <div className="flex items-center gap-1.5">
                <FileText className="h-3.5 w-3.5" />
                <span>Notes</span>
              </div>
            </SelectItem>
          </SelectContent>
        </Select>
        
        <div className="relative flex-1">
          <Search className="absolute left-2 top-1.5 h-3.5 w-3.5 text-muted-foreground" />
          <Input
            type="search"
            placeholder={`Search by ${activeFilter}...`}
            value={filters[activeFilter] || ""}
            onChange={(e) => handleFilterChange(e.target.value)}
            className="pl-8 h-8 text-xs"
          />
        </div>

        {Object.keys(filters).length > 0 && (
          <Button
            variant="ghost"
            size="sm"
            onClick={clearFilters}
            className="text-muted-foreground h-8 px-2 py-0"
          >
            <X className="h-3.5 w-3.5" />
          </Button>
        )}
      </div>
    </div>
  );
}
