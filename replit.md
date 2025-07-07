# Contact Manager Application

## Overview

This is a hierarchical contact management application built with React, Express, and PostgreSQL. The application allows users to manage contacts with relationship hierarchies (e.g., friend → spouse → child) and includes features like contact searching, location management, and birthday reminders.

## System Architecture

### Frontend Architecture
- **Framework**: React 18 with TypeScript
- **Build Tool**: Vite with custom configuration
- **State Management**: TanStack Query for server state, local React state for UI
- **Styling**: Tailwind CSS with shadcn/ui component library
- **Routing**: Wouter for lightweight client-side routing
- **UI Components**: Radix UI primitives with custom styling

### Backend Architecture
- **Runtime**: Node.js with Express.js
- **Language**: TypeScript with ESM modules
- **API Pattern**: RESTful API with Express routes
- **Development**: Hot reload with tsx and Vite middleware

### Database Architecture
- **Database**: PostgreSQL (configured for Neon serverless)
- **ORM**: Drizzle ORM with migrations
- **Schema**: Hierarchical contact structure with relationship cascade rules

## Key Components

### Database Schema
- **Contacts Table**: Core contact information with hierarchical relationships
- **Locations Table**: Multiple locations per contact (home, work, other)
- **Relationship Types**: Predefined relationship categories with cascade rules
- **Relationship Hierarchy**: Parent-child relationships with validation

### Frontend Components
- **ContactCard**: Individual contact display with relationship indicators
- **ContactForm**: Form for creating/editing contacts with location management
- **ContactList**: Categorized contact display with search and filtering
- **ContactGraph**: Visual relationship mapping using force-directed graphs
- **DetailedContactView**: Full contact information display
- **LocationList**: Management of multiple locations per contact
- **BirthdayReminder**: Automatic birthday notifications

### API Endpoints
- Contact CRUD operations with relationship validation
- Search functionality across contact fields
- Location management endpoints
- Relationship cascade update logic

## Data Flow

1. **Contact Creation**: Form submission → validation → database insertion → cascade relationship updates
2. **Contact Display**: Database query → categorization → component rendering with relationship indicators
3. **Search**: User input → filtered database query → real-time results update
4. **Relationship Updates**: Parent change → cascade rule validation → child relationship updates

## External Dependencies

### Core Dependencies
- **@neondatabase/serverless**: PostgreSQL database connection
- **drizzle-orm**: Database ORM and query builder
- **@tanstack/react-query**: Server state management
- **@radix-ui/***: Accessible UI component primitives
- **framer-motion**: Animation library
- **@react-google-maps/api**: Google Maps integration

### Development Dependencies
- **tsx**: TypeScript execution for development
- **esbuild**: Production build bundling
- **vite**: Development server and build tool

## Deployment Strategy

### Development
- **Server**: tsx with hot reload
- **Client**: Vite development server with HMR
- **Database**: Drizzle migrations with push command

### Production
- **Build Process**: Vite build for client, esbuild for server
- **Server Bundle**: Single ESM bundle with external packages
- **Database**: PostgreSQL with connection pooling via Neon

### Environment Configuration
- **DATABASE_URL**: PostgreSQL connection string (required)
- **VITE_GOOGLE_MAPS_API_KEY**: Google Maps API key for location features
- **NODE_ENV**: Environment detection for build optimization

## Changelog

```
Changelog:
- July 07, 2025. Initial setup
```

## User Preferences

```
Preferred communication style: Simple, everyday language.
```