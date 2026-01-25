-- User profiles with 6-char IDs
CREATE TABLE profiles (
  id uuid REFERENCES auth.users ON DELETE CASCADE PRIMARY KEY,
  call_id text UNIQUE NOT NULL, -- Permanent 6-char code
  display_name text,
  last_seen timestamp with time zone DEFAULT now()
);

-- Signaling table (Realtime must be enabled here)
CREATE TABLE signals (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  sender_id text NOT NULL,
  receiver_id text NOT NULL,
  data jsonb NOT NULL, -- SDP/ICE data
  type text NOT NULL, -- 'offer', 'answer', 'ice', 'reject', 'ping'
  created_at timestamp with time zone DEFAULT now()
);

-- Enable Realtime for signals
ALTER publication supabase_realtime ADD TABLE signals;
