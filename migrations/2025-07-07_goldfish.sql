-- Migration: 2025-07-07_goldfish.sql
-- Enable UUID support and update schema for production-ready database

-- 1-a Enable pgcrypto, switch contacts.id and locations.id to UUID, add DB-managed timestamps
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Update contacts table to use UUID and proper timestamps
ALTER TABLE contacts
  ALTER COLUMN id DROP DEFAULT,
  ALTER COLUMN id SET DATA TYPE uuid USING gen_random_uuid(),
  ALTER COLUMN id SET DEFAULT gen_random_uuid(),
  ALTER COLUMN created_at SET DEFAULT now(),
  ALTER COLUMN updated_at SET DEFAULT now();

-- Update locations table to use UUID
ALTER TABLE locations
  ALTER COLUMN id DROP DEFAULT,
  ALTER COLUMN id SET DATA TYPE uuid USING gen_random_uuid(),
  ALTER COLUMN id SET DEFAULT gen_random_uuid();

-- 1-b Create relationship_type ENUM if missing, convert contacts.relationship to that ENUM
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'relationship_type') THEN
    CREATE TYPE relationship_type AS ENUM ('parent','mother','father','spouse','child','sibling','friend','colleague','other');
  END IF;
END$$;

-- Convert relationship column to use ENUM
ALTER TABLE contacts
  ALTER COLUMN relationship_type TYPE relationship_type
  USING relationship_type::relationship_type;

-- 1-c Quality constraints
ALTER TABLE contacts
  ADD CONSTRAINT one_me UNIQUE (is_me) DEFERRABLE INITIALLY DEFERRED,
  ADD CONSTRAINT birthday_past CHECK (birthday IS NULL OR birthday <= CURRENT_DATE);

-- Update parent_id to use UUID and add proper foreign key
ALTER TABLE contacts
  ALTER COLUMN parent_id DROP NOT NULL,
  ALTER COLUMN parent_id DROP DEFAULT,
  ALTER COLUMN parent_id TYPE uuid USING parent_id::uuid,
  ADD CONSTRAINT contacts_parent_fk FOREIGN KEY (parent_id)
    REFERENCES contacts(id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

-- Update locations constraints
ALTER TABLE locations
  ALTER COLUMN latitude TYPE double precision USING latitude::double precision,
  ALTER COLUMN longitude TYPE double precision USING longitude::double precision,
  ADD CONSTRAINT latlng_range CHECK (latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180);

-- Add proper foreign key for locations
ALTER TABLE locations
  ADD CONSTRAINT fk_location_contact
    FOREIGN KEY (contact_id) REFERENCES contacts(id) ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_locations_contact ON locations(contact_id);

-- 1-d Cycle-prevention trigger
CREATE OR REPLACE FUNCTION reject_cycle() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.parent_id IS NULL THEN RETURN NEW; END IF;
  IF EXISTS (
    WITH RECURSIVE path(id) AS (
      SELECT NEW.parent_id 
      UNION ALL 
      SELECT parent_id FROM contacts c 
      JOIN path ON c.id = path.id 
      WHERE parent_id IS NOT NULL
    ) 
    SELECT 1 FROM path WHERE id = NEW.id
  )
  THEN 
    RAISE EXCEPTION 'Re-parenting % → % would create a cycle', NEW.id, NEW.parent_id; 
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS contacts_acyclic ON contacts;
CREATE TRIGGER contacts_acyclic BEFORE INSERT OR UPDATE OF parent_id ON contacts FOR EACH ROW EXECUTE FUNCTION reject_cycle();

-- 1-e Auto-timestamp trigger
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$ 
BEGIN 
  NEW.updated_at = now(); 
  RETURN NEW; 
END; $$;

DROP TRIGGER IF EXISTS contacts_set_updated ON contacts;
CREATE TRIGGER contacts_set_updated BEFORE UPDATE ON contacts FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 1-f Share token and change-log
ALTER TABLE contacts ADD COLUMN IF NOT EXISTS share_token text UNIQUE;

CREATE TABLE IF NOT EXISTS contact_changes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  contact_id uuid REFERENCES contacts(id) ON DELETE CASCADE,
  op text CHECK (op IN ('insert','update','delete')),
  payload jsonb,
  ts timestamptz DEFAULT now(),
  device_id uuid
);

-- 1-g Text-search indexes
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX IF NOT EXISTS contacts_name_trgm ON contacts USING GIN (name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS contacts_email_trgm ON contacts USING GIN (email gin_trgm_ops);
CREATE INDEX IF NOT EXISTS contacts_phone_trgm ON contacts USING GIN (phone gin_trgm_ops);
CREATE INDEX IF NOT EXISTS contacts_notes_trgm ON contacts USING GIN (notes gin_trgm_ops);