# Contact Manager Application

## Overview

This is a modern, full-stack contact management application built with React, Express, and PostgreSQL. The application provides a clean, intuitive interface for managing personal contacts with support for hierarchical relationships (e.g., a friend's spouse or children). It features a graph-based visualization of contact networks and includes location tracking capabilities.

## System Architecture

### Frontend Architecture
- **Framework**: React 18 with TypeScript
- **Build Tool**: Vite for fast development and optimized builds
- **State Management**: TanStack Query for server state management
- **Routing**: Wouter for lightweight client-side routing
- **Styling**: Tailwind CSS with shadcn/ui component library
- **UI Components**: Radix UI primitives for accessible, unstyled components
- **Animations**: Framer Motion for smooth transitions and micro-interactions

### Backend Architecture
- **Runtime**: Node.js with Express.js
- **Language**: TypeScript with ES modules
- **Database ORM**: Drizzle ORM for type-safe database operations
- **API Pattern**: RESTful API with Express routes
- **Development**: Hot reload with tsx for development server

### Data Storage
- **Database**: PostgreSQL with Neon serverless hosting
- **Schema Management**: Drizzle Kit for migrations and schema management
- **Connection**: @neondatabase/serverless for serverless PostgreSQL connections

## Key Components

### Contact Management
- **Hierarchical Relationships**: Supports parent-child contact relationships (friend → friend's spouse → friend's child)
- **Relationship Types**: Predefined types including family, friends, and professional relationships
- **Cascading Updates**: Automatic relationship type updates when parent relationships change
- **Contact Fields**: Name (required), phone, email, birthday, notes, and location data

### Visualization
- **Graph View**: React Flow-based network visualization with advanced drag-and-drop functionality
  - Pixel-perfect node dragging with real-time cursor following
  - Magnetic snap zones (140px radius) for intuitive drop target detection
  - Visual feedback system with opacity changes and outline highlighting
  - Hierarchical tree layout with collision detection and automatic spacing
  - Reorder button for manual layout optimization when needed
- **List View**: Traditional contact list with categorization by relationship type
- **Detail View**: Comprehensive contact information display with edit capabilities

### Location Features
- **Google Maps Integration**: @react-google-maps/api for location picker and display
- **Multiple Locations**: Support for multiple locations per contact (home, work, other)
- **Geocoding**: Address-to-coordinates conversion for mapping

### Search and Filtering
- **Real-time Search**: Partial matching across contact names and details
- **Category Filtering**: Filter by relationship type (family, friends, professional)
- **Persistent Search**: Search state preserved in localStorage

## Data Flow

1. **Client Request**: React components use TanStack Query for API calls
2. **API Layer**: Express.js routes handle HTTP requests and validation
3. **Database Layer**: Drizzle ORM executes type-safe database operations
4. **Response**: JSON data returned to client with proper error handling
5. **State Management**: TanStack Query manages caching and synchronization

### Contact Relationship Flow
- Parent contacts can have multiple child contacts
- Relationship types cascade from parent to child with validation rules
- Updates to parent relationships automatically update child relationship types
- Circular relationships are prevented through validation

## External Dependencies

### Core Framework Dependencies
- React ecosystem (React, React DOM, React Router alternative)
- TypeScript for type safety
- Vite for build tooling and development server

### UI and Styling
- Tailwind CSS for utility-first styling
- Radix UI primitives for accessible components
- Framer Motion for animations
- shadcn/ui component library

### Database and Backend
- PostgreSQL with Neon serverless hosting
- Drizzle ORM for database operations
- Express.js for API server
- Zod for runtime validation

### External Services
- Google Maps API for location services
- React Google Maps API wrapper

## Deployment Strategy

### Development
- **Frontend**: Vite dev server with HMR
- **Backend**: tsx with file watching for hot reload
- **Database**: Neon serverless PostgreSQL

### Production Build
- **Frontend**: Vite build to static assets in `dist/public`
- **Backend**: esbuild bundle to `dist/index.js`
- **Database**: Drizzle migrations via `db:push` command

### Environment Configuration
- Database connection via `DATABASE_URL` environment variable
- Google Maps API key via `VITE_GOOGLE_MAPS_API_KEY`
- Production mode controlled by `NODE_ENV`

## User Preferences

Preferred communication style: Simple, everyday language.

## Recent Changes

- July 15, 2025: Comprehensive Design System Overhaul
  - **Typography upgrade** - Switched to Plus Jakarta Sans font for modern, professional look
  - **Redesigned header with clear value proposition** - "Your intelligent contact network"
  - **Complete button system redesign** - Consistent sizing, better hierarchy, hover effects
  - **Enhanced color scheme** - Dark primary color (hsl(229, 84%, 5%)) with tint variants
  - **Improved card designs** - Rounded corners, better shadows, hover states
  - **Better spacing and typography** - Increased touch targets, improved readability
  - **Enhanced search bar** - Larger touch targets, modern styling with rounded corners
  - **Redesigned control panel** - Grouped secondary actions in floating panel
  - **iOS-inspired tab bar** - Centered view mode selector with clear labels
  - **Sticky header** - Persistent navigation with backdrop blur effect and subtle shadow

- July 07, 2025: AI Voice Integration & Color System Enhancement
  - **Added comprehensive color coding system** with 10 color options for contact cards
  - **Implemented AI voice input components** for contact creation and relationship management
  - **Created VoiceInput component** with recording, transcription, and processing capabilities
  - **Added RelationshipManager component** for voice-controlled relationship changes in graph view
  - **Enhanced contact form** with AI voice input section for hands-free contact creation
  - **Updated database schema** to include color field for contact cards
  - **Applied consistent color styling** across list view, graph view, and minimap
  - **Integrated OpenAI API** for speech-to-text and natural language processing
  - **Voice commands support**: "Add John Smith, phone 555-1234, make him my co-worker"
  - **Relationship voice commands**: "Make Sarah John's daughter", "Connect Mike as Tom's friend"

- July 07, 2025: Comprehensive drag-and-drop system with pixel-perfect behavior
  - **Removed blue drag trail animation** for clean, distraction-free interface
  - **Enhanced collision detection** with 280px minimum spacing between nodes
  - **Added Reorder button** for manual layout optimization when automatic spacing fails
  - **Pixel-perfect drag behavior**: Contact nodes follow cursor in real-time during drag operations
  - **Magnetic snap zones**: 140px radius for natural drop target detection
  - **Visual feedback system**: 75% opacity during drag, indigo ring outline on drop targets
  - **Hierarchical tree layout**: "me" contact at center-top with level-based color coding
  - **Comprehensive reparenting logic**: Prevents circular references, maintains relationships
  - **Undo system**: Track and reverse drag-and-drop relationship changes
  - **Enhanced positioning algorithm**: 5-pass iterative collision resolution with viewport bounds

## Changelog

Changelog:
- July 07, 2025. Initial setup