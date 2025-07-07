
-- Migration: 2025-07-07_goldfish.sql
-- Goal: Introduce all schema-level guarantees needed for offline sync, duplicate checks, and graph integrity

-- 1. Enable required extensions
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- 2. Create relationship_type ENUM if it doesn't exist
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'relationship_type') THEN
        CREATE TYPE relationship_type AS ENUM (
            'sibling',
            'mother', 
            'father',
            'brother',
            'friend',
            'child',
            'co-worker',
            'spouse',
            'boyfriend/girlfriend'
        );
    END IF;
END$$;

-- 3. Backup existing data before migration
CREATE TEMP TABLE contacts_backup AS SELECT * FROM contacts;
CREATE TEMP TABLE locations_backup AS SELECT * FROM locations;

-- 4. Migrate contacts table to UUID primary keys
-- First, add new UUID columns
ALTER TABLE contacts ADD COLUMN new_id uuid DEFAULT gen_random_uuid();
ALTER TABLE contacts ADD COLUMN new_parent_id uuid;

-- Update new_parent_id based on existing relationships
UPDATE contacts 
SET new_parent_id = (
    SELECT new_id 
    FROM contacts AS parent 
    WHERE parent.id = contacts.parent_id
);

-- 5. Update locations to reference new contact UUIDs
ALTER TABLE locations ADD COLUMN new_contact_id uuid;
UPDATE locations 
SET new_contact_id = (
    SELECT new_id 
    FROM contacts 
    WHERE contacts.id = locations.contact_id
);

-- 6. Drop existing constraints and indexes
ALTER TABLE locations DROP CONSTRAINT IF EXISTS locations_contact_id_fkey;
ALTER TABLE contacts DROP CONSTRAINT IF EXISTS contacts_parent_id_fkey;

-- 7. Replace old primary keys with new UUID columns
ALTER TABLE contacts DROP CONSTRAINT contacts_pkey;
ALTER TABLE contacts DROP COLUMN id;
ALTER TABLE contacts RENAME COLUMN new_id TO id;
ALTER TABLE contacts ADD PRIMARY KEY (id);

-- Update parent_id to new UUID column
ALTER TABLE contacts DROP COLUMN parent_id;
ALTER TABLE contacts RENAME COLUMN new_parent_id TO parent_id;

-- 8. Update locations table
ALTER TABLE locations DROP CONSTRAINT locations_pkey;
ALTER TABLE locations DROP COLUMN id;
ALTER TABLE locations ADD COLUMN id uuid PRIMARY KEY DEFAULT gen_random_uuid();

-- Update contact_id reference
ALTER TABLE locations DROP COLUMN contact_id;
ALTER TABLE locations RENAME COLUMN new_contact_id TO contact_id;

-- 9. Convert relationship_type column to ENUM
ALTER TABLE contacts 
    ALTER COLUMN relationship_type TYPE relationship_type 
    USING relationship_type::relationship_type;

-- 10. Add data quality constraints
ALTER TABLE contacts
    ADD CONSTRAINT contacts_one_me_check UNIQUE (is_me) DEFERRABLE INITIALLY DEFERRED,
    ADD CONSTRAINT contacts_birthday_past_check CHECK (birthday IS NULL OR birthday <= CURRENT_DATE),
    ADD CONSTRAINT contacts_email_format_check CHECK (email IS NULL OR email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$');

-- 11. Add foreign key constraints with proper CASCADE behavior
ALTER TABLE contacts
    ADD CONSTRAINT contacts_parent_fk 
    FOREIGN KEY (parent_id) REFERENCES contacts(id) 
    ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED;

ALTER TABLE locations
    ADD CONSTRAINT locations_contact_fk 
    FOREIGN KEY (contact_id) REFERENCES contacts(id) 
    ON DELETE CASCADE DEFERRABLE INITIALLY DEFERRED;

-- 12. Add coordinate validation for locations
ALTER TABLE locations
    ALTER COLUMN latitude TYPE double precision USING latitude::double precision,
    ALTER COLUMN longitude TYPE double precision USING longitude::double precision,
    ADD CONSTRAINT locations_coordinates_range_check CHECK (
        (latitude IS NULL AND longitude IS NULL) OR 
        (latitude BETWEEN -90 AND 90 AND longitude BETWEEN -180 AND 180)
    );

-- 13. Create cycle prevention function and trigger
CREATE OR REPLACE FUNCTION prevent_contact_cycles() RETURNS trigger 
LANGUAGE plpgsql AS $$
BEGIN
    -- Allow NULL parent_id (root contacts)
    IF NEW.parent_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Prevent self-parenting
    IF NEW.id = NEW.parent_id THEN
        RAISE EXCEPTION 'Contact cannot be its own parent: %', NEW.id;
    END IF;

    -- Check for cycles using recursive CTE
    IF EXISTS (
        WITH RECURSIVE contact_path(id, depth) AS (
            -- Start from the proposed parent
            SELECT NEW.parent_id, 1
            UNION ALL
            SELECT c.parent_id, cp.depth + 1
            FROM contacts c 
            JOIN contact_path cp ON c.id = cp.id 
            WHERE c.parent_id IS NOT NULL AND cp.depth < 100 -- Prevent infinite recursion
        )
        SELECT 1 FROM contact_path WHERE id = NEW.id
    ) THEN
        RAISE EXCEPTION 'Setting parent % for contact % would create a cycle', NEW.parent_id, NEW.id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS contacts_cycle_prevention ON contacts;
CREATE TRIGGER contacts_cycle_prevention
    BEFORE INSERT OR UPDATE OF parent_id ON contacts
    FOR EACH ROW EXECUTE FUNCTION prevent_contact_cycles();

-- 14. Create auto-timestamp function and trigger
CREATE OR REPLACE FUNCTION update_timestamp() RETURNS trigger 
LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS contacts_update_timestamp ON contacts;
CREATE TRIGGER contacts_update_timestamp
    BEFORE UPDATE ON contacts
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

DROP TRIGGER IF EXISTS locations_update_timestamp ON locations;
CREATE TRIGGER locations_update_timestamp
    BEFORE UPDATE ON locations
    FOR EACH ROW EXECUTE FUNCTION update_timestamp();

-- 15. Add offline sync support columns
ALTER TABLE contacts 
    ADD COLUMN IF NOT EXISTS sync_status text DEFAULT 'synced' CHECK (sync_status IN ('synced', 'pending', 'conflict')),
    ADD COLUMN IF NOT EXISTS last_sync_at timestamptz,
    ADD COLUMN IF NOT EXISTS version_hash text,
    ADD COLUMN IF NOT EXISTS device_id uuid;

ALTER TABLE locations
    ADD COLUMN IF NOT EXISTS sync_status text DEFAULT 'synced' CHECK (sync_status IN ('synced', 'pending', 'conflict')),
    ADD COLUMN IF NOT EXISTS last_sync_at timestamptz,
    ADD COLUMN IF NOT EXISTS version_hash text,
    ADD COLUMN IF NOT EXISTS device_id uuid;

-- 16. Create change log table for sync tracking
CREATE TABLE IF NOT EXISTS contact_changes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    contact_id uuid REFERENCES contacts(id) ON DELETE CASCADE,
    operation text NOT NULL CHECK (operation IN ('insert', 'update', 'delete')),
    old_data jsonb,
    new_data jsonb,
    timestamp timestamptz DEFAULT now(),
    device_id uuid,
    sync_status text DEFAULT 'pending' CHECK (sync_status IN ('pending', 'synced')),
    created_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS location_changes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    location_id uuid,
    contact_id uuid REFERENCES contacts(id) ON DELETE CASCADE,
    operation text NOT NULL CHECK (operation IN ('insert', 'update', 'delete')),
    old_data jsonb,
    new_data jsonb,
    timestamp timestamptz DEFAULT now(),
    device_id uuid,
    sync_status text DEFAULT 'pending' CHECK (sync_status IN ('pending', 'synced')),
    created_at timestamptz DEFAULT now()
);

-- 17. Create triggers to log changes
CREATE OR REPLACE FUNCTION log_contact_changes() RETURNS trigger 
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        INSERT INTO contact_changes (contact_id, operation, old_data, device_id)
        VALUES (OLD.id, 'delete', to_jsonb(OLD), OLD.device_id);
        RETURN OLD;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO contact_changes (contact_id, operation, old_data, new_data, device_id)
        VALUES (NEW.id, 'update', to_jsonb(OLD), to_jsonb(NEW), NEW.device_id);
        RETURN NEW;
    ELSIF TG_OP = 'INSERT' THEN
        INSERT INTO contact_changes (contact_id, operation, new_data, device_id)
        VALUES (NEW.id, 'insert', to_jsonb(NEW), NEW.device_id);
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION log_location_changes() RETURNS trigger 
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        INSERT INTO location_changes (location_id, contact_id, operation, old_data)
        VALUES (OLD.id, OLD.contact_id, 'delete', to_jsonb(OLD));
        RETURN OLD;
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO location_changes (location_id, contact_id, operation, old_data, new_data)
        VALUES (NEW.id, NEW.contact_id, 'update', to_jsonb(OLD), to_jsonb(NEW));
        RETURN NEW;
    ELSIF TG_OP = 'INSERT' THEN
        INSERT INTO location_changes (location_id, contact_id, operation, new_data)
        VALUES (NEW.id, NEW.contact_id, 'insert', to_jsonb(NEW));
        RETURN NEW;
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS contacts_change_log ON contacts;
CREATE TRIGGER contacts_change_log
    AFTER INSERT OR UPDATE OR DELETE ON contacts
    FOR EACH ROW EXECUTE FUNCTION log_contact_changes();

DROP TRIGGER IF EXISTS locations_change_log ON locations;
CREATE TRIGGER locations_change_log
    AFTER INSERT OR UPDATE OR DELETE ON locations
    FOR EACH ROW EXECUTE FUNCTION log_location_changes();

-- 18. Create search optimization indexes
CREATE INDEX IF NOT EXISTS idx_contacts_name_trgm ON contacts USING GIN (name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_contacts_email_trgm ON contacts USING GIN (email gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_contacts_phone_trgm ON contacts USING GIN (phone gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_contacts_notes_trgm ON contacts USING GIN (notes gin_trgm_ops);

-- 19. Create performance indexes
CREATE INDEX IF NOT EXISTS idx_contacts_parent_id ON contacts(parent_id) WHERE parent_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_contacts_relationship_type ON contacts(relationship_type) WHERE relationship_type IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_contacts_is_me ON contacts(is_me) WHERE is_me = true;
CREATE INDEX IF NOT EXISTS idx_contacts_sync_status ON contacts(sync_status) WHERE sync_status != 'synced';
CREATE INDEX IF NOT EXISTS idx_locations_contact_id ON locations(contact_id);
CREATE INDEX IF NOT EXISTS idx_locations_type ON locations(type);
CREATE INDEX IF NOT EXISTS idx_contact_changes_contact_id ON contact_changes(contact_id);
CREATE INDEX IF NOT EXISTS idx_contact_changes_timestamp ON contact_changes(timestamp);
CREATE INDEX IF NOT EXISTS idx_contact_changes_sync_status ON contact_changes(sync_status) WHERE sync_status = 'pending';

-- 20. Create duplicate detection function
CREATE OR REPLACE FUNCTION find_duplicate_contacts(
    p_name text DEFAULT NULL,
    p_email text DEFAULT NULL,
    p_phone text DEFAULT NULL,
    p_threshold real DEFAULT 0.6
) RETURNS TABLE (
    contact_id uuid,
    name text,
    email text,
    phone text,
    similarity_score real
) LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT 
        c.id,
        c.name,
        c.email,
        c.phone,
        GREATEST(
            COALESCE(similarity(c.name, p_name), 0),
            COALESCE(similarity(c.email, p_email), 0),
            COALESCE(similarity(c.phone, p_phone), 0)
        ) as score
    FROM contacts c
    WHERE 
        (p_name IS NULL OR similarity(c.name, p_name) > p_threshold) OR
        (p_email IS NULL OR similarity(c.email, p_email) > p_threshold) OR
        (p_phone IS NULL OR similarity(c.phone, p_phone) > p_threshold)
    ORDER BY score DESC;
END;
$$;

-- 21. Update default values for timestamps
ALTER TABLE contacts 
    ALTER COLUMN created_at SET DEFAULT now(),
    ALTER COLUMN updated_at SET DEFAULT now();

ALTER TABLE locations
    ALTER COLUMN created_at SET DEFAULT now(),
    ALTER COLUMN updated_at SET DEFAULT now();

-- 22. Clean up temporary tables
DROP TABLE contacts_backup;
DROP TABLE locations_backup;

-- Migration completed successfully
-- All schema-level guarantees for offline sync, duplicate checks, and graph integrity are now in place
