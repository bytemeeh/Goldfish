import { useState } from "react";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Search, Filter, X } from "lucide-react";

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

      <DropdownMenu>
        <DropdownMenuTrigger asChild>
          <Button variant="outline" size="icon">
            <Filter className="h-4 w-4" />
          </Button>
        </DropdownMenuTrigger>
        <DropdownMenuContent align="end">
          <DropdownMenuItem onClick={() => setActiveFilter("name")}>
            Search by Name
          </DropdownMenuItem>
          <DropdownMenuItem onClick={() => setActiveFilter("email")}>
            Search by Email
          </DropdownMenuItem>
          <DropdownMenuItem onClick={() => setActiveFilter("phone")}>
            Search by Phone
          </DropdownMenuItem>
          <DropdownMenuItem onClick={() => setActiveFilter("notes")}>
            Search in Notes
          </DropdownMenuItem>
        </DropdownMenuContent>
      </DropdownMenu>

      {Object.keys(filters).length > 0 && (
        <Button
          variant="ghost"
          size="icon"
          onClick={clearFilters}
          className="text-muted-foreground"
        >
          <X className="h-4 w-4" />
        </Button>
      )}
    </div>
  );
}