import { Switch, Route } from "wouter";
import { Home } from "./pages/Home";
import { QueryClientProvider } from "@tanstack/react-query";
import { queryClient } from "./lib/queryClient";
import { Toaster } from "@/components/ui/toaster";

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <Switch>
        <Route path="/" component={Home} />
      </Switch>
      <Toaster />
    </QueryClientProvider>
  );
}

export default App;
