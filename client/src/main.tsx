import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { QueryClientProvider } from "@tanstack/react-query";
import { queryClient } from "./lib/queryClient";
import { Toaster } from "@/components/ui/toaster";
import App from './App';
import "./index.css";

import { ErrorBoundary } from '@/components/ErrorBoundary';
import { ReloadPrompt } from "@/components/ui/ReloadPrompt";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <ErrorBoundary>
        <App />
      </ErrorBoundary>
      <Toaster />
      <ReloadPrompt />
    </QueryClientProvider>
  </StrictMode>,
);
