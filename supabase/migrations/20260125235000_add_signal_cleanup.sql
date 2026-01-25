-- Add pg_cron extension for scheduled signal cleanup
-- This migration sets up a cron job to run every 20 minutes

-- Note: pg_cron is available on Supabase Pro plan
-- For free tier, you can use an external cron service (Vercel Cron, GitHub Actions, etc.)
-- or call the edge function periodically from your app

-- Enable pg_cron extension (Pro plan only)
-- CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Create a function to call the edge function
CREATE OR REPLACE FUNCTION cleanup_old_signals()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Delete signals older than 2 minutes
  DELETE FROM signals
  WHERE created_at < NOW() - INTERVAL '2 minutes';
END;
$$;

-- For Supabase Pro: Schedule the cleanup every 20 minutes
-- Uncomment if you have pg_cron available
-- SELECT cron.schedule(
--   'cleanup-signals',
--   '*/20 * * * *',  -- Every 20 minutes
--   $$SELECT cleanup_old_signals()$$
-- );

-- Alternative: Create an RPC function that can be called from the app
CREATE OR REPLACE FUNCTION run_signal_cleanup()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  deleted_count INTEGER;
  total_before INTEGER;
  total_after INTEGER;
BEGIN
  -- Count before
  SELECT COUNT(*) INTO total_before FROM signals;
  
  -- Delete old signals
  DELETE FROM signals
  WHERE created_at < NOW() - INTERVAL '2 minutes';
  
  GET DIAGNOSTICS deleted_count = ROW_COUNT;
  
  -- Count after
  SELECT COUNT(*) INTO total_after FROM signals;
  
  RETURN json_build_object(
    'success', true,
    'deleted', deleted_count,
    'before', total_before,
    'after', total_after,
    'timestamp', NOW()
  );
END;
$$;

-- Grant execute permission for the cleanup function
GRANT EXECUTE ON FUNCTION run_signal_cleanup() TO authenticated;
GRANT EXECUTE ON FUNCTION run_signal_cleanup() TO anon;
