-- Force profiles.id to be TEXT to support 6-char custom IDs
-- We DROP the foreign key constraint connecting it to auth.users because we use custom IDs.

BEGIN;
    -- 1. Drop the foreign key constraint if it exists
    ALTER TABLE IF EXISTS public.profiles 
    DROP CONSTRAINT IF EXISTS profiles_id_fkey;

    -- 2. Alter the column type (casting existing UUIDs to text if any)
    ALTER TABLE public.profiles 
    ALTER COLUMN id TYPE text;

COMMIT;
