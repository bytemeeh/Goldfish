import { Switch, Route } from "wouter";
import { Home } from "./pages/Home";
import { QueryClientProvider } from "@tanstack/react-query";
import { queryClient } from "./lib/queryClient";
import { Toaster } from "@/components/ui/toaster";
import { GoogleMapsProvider } from "./lib/googleMapsLoader";

function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <GoogleMapsProvider>
        <Switch>
          <Route path="/" component={Home} />
        </Switch>
        <Toaster />
      </GoogleMapsProvider>
    </QueryClientProvider>
  );
}

export default App;
