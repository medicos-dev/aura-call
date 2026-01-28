-- CRITICAL FIX: Recreate profiles table with correct schema
-- The old table has conflicting uuid id + call_id columns from initial schema
-- This migration drops and recreates with call_id as the primary key

BEGIN;

-- 1. Backup existing profile data (if any)
-- Only select columns that exist in the current schema
CREATE TEMP TABLE profiles_backup AS 
SELECT call_id, username, avatar_url, last_seen 
FROM public.profiles 
WHERE call_id IS NOT NULL;

-- 2. Drop the old table
DROP TABLE IF EXISTS public.profiles CASCADE;

-- 3. Create new table with call_id as primary key (no uuid required)
CREATE TABLE public.profiles (
    call_id text PRIMARY KEY,  -- The 6-char deterministic ID is the primary key
    username text,
    avatar_url text,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    last_seen timestamp with time zone DEFAULT timezone('utc'::text, now())
);

-- 4. Restore data from backup
INSERT INTO public.profiles (call_id, username, avatar_url, last_seen)
SELECT call_id, username, avatar_url, last_seen
FROM profiles_backup
ON CONFLICT (call_id) DO NOTHING;

-- 5. Drop backup table
DROP TABLE IF EXISTS profiles_backup;

-- 6. Enable RLS
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- 7. Create public access policy
DROP POLICY IF EXISTS "Public profiles access" ON public.profiles;
CREATE POLICY "Public profiles access" ON public.profiles
    FOR ALL USING (true) WITH CHECK (true);

COMMIT;
