-- Create profiles table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.profiles (
    id text PRIMARY KEY,
    username text,
    avatar_url text,
    created_at timestamp with time zone DEFAULT timezone('utc'::text, now()) NOT NULL,
    last_seen timestamp with time zone DEFAULT timezone('utc'::text, now())
);

-- Turn on RLS
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Allow public read/write (since we use anon key and custom ID logic)
CREATE POLICY "Public profiles access" ON public.profiles
    FOR ALL USING (true) WITH CHECK (true);
