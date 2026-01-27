-- 1. Migrate any data from 'display_name' to 'username' if 'username' is empty
UPDATE public.profiles 
SET username = display_name 
WHERE username IS NULL AND display_name IS NOT NULL;

-- 2. Drop the redundant 'display_name' column
ALTER TABLE public.profiles DROP COLUMN IF EXISTS display_name;
