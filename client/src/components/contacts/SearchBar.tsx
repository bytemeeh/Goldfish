import { useState, useEffect } from "react";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Search, X } from "lucide-react";

export interface SearchFilters {
  name?: string;
}

interface SearchBarProps {
  onSearch: (filters: SearchFilters) => void;
}

// Local storage key for search text
const STORAGE_KEY_SEARCH_TEXT = 'contact-search-text';

export function SearchBar({ onSearch }: SearchBarProps) {
  const [searchText, setSearchText] = useState<string>(() => {
    return localStorage.getItem(STORAGE_KEY_SEARCH_TEXT) || "";
  });

  // On mount, apply any saved search filters
  useEffect(() => {
    if (searchText) {
      onSearch({ name: searchText });
    }
  }, []);
  
  // Save search text to localStorage when it changes
  useEffect(() => {
    localStorage.setItem(STORAGE_KEY_SEARCH_TEXT, searchText);
  }, [searchText]);

  const handleSearchChange = (value: string) => {
    setSearchText(value);
    onSearch({ name: value });
  };

  const clearSearch = () => {
    setSearchText("");
    onSearch({});
  };

  return (
    <div className="w-full">
      <div className="relative">
        <Search className="absolute left-3 top-2.5 h-4 w-4 text-muted-foreground/50" />
        <Input
          type="search"
          placeholder="Search contacts..."
          value={searchText}
          onChange={(e) => handleSearchChange(e.target.value)}
          className="pl-10 pr-10 h-9 sm:h-9 text-sm w-full rounded-lg border border-border/40 bg-background/50 focus:border-foreground/15 focus:bg-background transition-all font-normal placeholder:text-muted-foreground/50 shadow-sm"
        />
        {searchText && (
          <Button
            variant="ghost"
            size="sm"
            onClick={clearSearch}
            className="absolute right-1.5 top-1.5 text-muted-foreground h-6 w-6 p-0 hover:bg-muted/30 rounded-md touch-manipulation"
          >
            <X className="h-3.5 w-3.5" />
          </Button>
        )}
      </div>
    </div>
  );
}
