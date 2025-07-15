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
        <Search className="absolute left-2.5 top-2 h-3 w-3 text-muted-foreground/40" />
        <Input
          type="search"
          placeholder="Search contacts..."
          value={searchText}
          onChange={(e) => handleSearchChange(e.target.value)}
          className="pl-8 pr-8 h-7 sm:h-7 text-xs w-full rounded-md border border-border/30 bg-background/40 focus:border-muted-foreground/20 focus:bg-background transition-all font-normal placeholder:text-muted-foreground/40 shadow-sm"
        />
        {searchText && (
          <Button
            variant="ghost"
            size="sm"
            onClick={clearSearch}
            className="absolute right-1 top-1 text-muted-foreground h-5 w-5 p-0 hover:bg-muted/20 rounded-sm touch-manipulation"
          >
            <X className="h-3 w-3" />
          </Button>
        )}
      </div>
    </div>
  );
}
