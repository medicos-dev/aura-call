-- Add status column to signals table
ALTER TABLE public.signals 
ADD COLUMN IF NOT EXISTS status text DEFAULT 'active';

-- Add index for cleanup performance
CREATE INDEX IF NOT EXISTS signals_status_created_idx ON public.signals(status, created_at);
