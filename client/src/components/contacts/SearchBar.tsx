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
        <Search className="absolute left-3 top-3 h-4 w-4 text-muted-foreground" />
        <Input
          type="search"
          placeholder="Search contacts..."
          value={searchText}
          onChange={(e) => handleSearchChange(e.target.value)}
          className="pl-10 pr-10 h-11 text-sm w-full rounded-lg border-2 border-border/50 bg-background/60 focus:border-primary/50 focus:bg-background transition-colors"
        />
        {searchText && (
          <Button
            variant="ghost"
            size="sm"
            onClick={clearSearch}
            className="absolute right-2 top-2 text-muted-foreground h-7 w-7 p-0 hover:bg-muted/50 rounded-md"
          >
            <X className="h-4 w-4" />
          </Button>
        )}
      </div>
    </div>
  );
}
