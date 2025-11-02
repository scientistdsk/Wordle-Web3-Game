-- Fix user creation and RLS policies
-- Created: 2025-01-28

-- Drop existing upsert_user function if it exists
DROP FUNCTION IF EXISTS upsert_user(VARCHAR, VARCHAR, VARCHAR);

-- Create a public function for user creation that bypasses RLS
CREATE OR REPLACE FUNCTION public.get_or_create_user(
  wallet_addr VARCHAR(255),
  user_name VARCHAR(50) DEFAULT NULL,
  display_name VARCHAR(100) DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
  user_uuid UUID;
BEGIN
  -- Check if user exists
  SELECT id INTO user_uuid
  FROM users
  WHERE wallet_address = wallet_addr;

  -- If user doesn't exist, create one
  IF user_uuid IS NULL THEN
    INSERT INTO users (
      wallet_address,
      username,
      display_name,
      created_at,
      updated_at
    ) VALUES (
      wallet_addr,
      COALESCE(user_name, 'user_' || substr(md5(random()::text), 1, 8)),
      COALESCE(display_name, 'User ' || substr(wallet_addr, 1, 8)),
      NOW(),
      NOW()
    ) RETURNING id INTO user_uuid;
  ELSE
    -- Update user if new username or display name provided
    IF user_name IS NOT NULL OR display_name IS NOT NULL THEN
      UPDATE users
      SET
        username = COALESCE(user_name, username),
        display_name = COALESCE(display_name, display_name),
        updated_at = NOW()
      WHERE id = user_uuid;
    END IF;
  END IF;

  RETURN user_uuid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to anon and authenticated
GRANT EXECUTE ON FUNCTION public.get_or_create_user(VARCHAR, VARCHAR, VARCHAR) TO anon;
GRANT EXECUTE ON FUNCTION public.get_or_create_user(VARCHAR, VARCHAR, VARCHAR) TO authenticated;

-- Create a simplified create_bounty_with_wallet function
CREATE OR REPLACE FUNCTION public.create_bounty_with_wallet(
  wallet_addr VARCHAR(255),
  bounty_data JSONB
) RETURNS UUID AS $$
DECLARE
  user_uuid UUID;
  bounty_uuid UUID;
BEGIN
  -- Get or create user
  user_uuid := public.get_or_create_user(wallet_addr);

  -- Create bounty
  INSERT INTO bounties (
    name,
    description,
    creator_id,
    bounty_type,
    prize_amount,
    prize_currency,
    words,
    hints,
    max_participants,
    max_attempts_per_user,
    time_limit_seconds,
    winner_criteria,
    duration_hours,
    status,
    is_public,
    requires_registration,
    start_time,
    end_time
  ) VALUES (
    bounty_data->>'name',
    bounty_data->>'description',
    user_uuid,
    COALESCE((bounty_data->>'bounty_type')::bounty_type, 'Simple'::bounty_type),
    COALESCE((bounty_data->>'prize_amount')::DECIMAL, 0),
    COALESCE(bounty_data->>'prize_currency', 'HBAR'),
    COALESCE(
      ARRAY(SELECT jsonb_array_elements_text(bounty_data->'words')),
      ARRAY['WORDLE']
    ),
    COALESCE(
      ARRAY(SELECT jsonb_array_elements_text(bounty_data->'hints')),
      ARRAY[]::TEXT[]
    ),
    (bounty_data->>'max_participants')::INTEGER,
    (bounty_data->>'max_attempts_per_user')::INTEGER,
    (bounty_data->>'time_limit_seconds')::INTEGER,
    COALESCE((bounty_data->>'winner_criteria')::winner_criteria, 'attempts'::winner_criteria),
    (bounty_data->>'duration_hours')::INTEGER,
    COALESCE((bounty_data->>'status')::bounty_status, 'active'::bounty_status),
    COALESCE((bounty_data->>'is_public')::BOOLEAN, true),
    COALESCE((bounty_data->>'requires_registration')::BOOLEAN, false),
    NOW(),
    CASE
      WHEN bounty_data->>'duration_hours' IS NOT NULL
      THEN NOW() + ((bounty_data->>'duration_hours')::INTEGER || ' hours')::INTERVAL
      ELSE NULL
    END
  ) RETURNING id INTO bounty_uuid;

  RETURN bounty_uuid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.create_bounty_with_wallet(VARCHAR, JSONB) TO anon;
GRANT EXECUTE ON FUNCTION public.create_bounty_with_wallet(VARCHAR, JSONB) TO authenticated;

-- Update RLS policies for users table to allow reading public user info
DROP POLICY IF EXISTS "Users can view all users" ON users;
CREATE POLICY "Users can view all users"
  ON users FOR SELECT
  TO anon, authenticated
  USING (true);

-- Update RLS policies for bounties to allow creation via function
DROP POLICY IF EXISTS "Anyone can view public bounties" ON bounties;
CREATE POLICY "Anyone can view public bounties"
  ON bounties FOR SELECT
  TO anon, authenticated
  USING (is_public = true);

-- Ensure bounty participants can be created
DROP POLICY IF EXISTS "Users can join bounties" ON bounty_participants;
CREATE POLICY "Users can join bounties"
  ON bounty_participants FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "Users can view participations" ON bounty_participants;
CREATE POLICY "Users can view participations"
  ON bounty_participants FOR SELECT
  TO anon, authenticated
  USING (true);

-- Ensure game attempts can be created
DROP POLICY IF EXISTS "Users can submit attempts" ON game_attempts;
CREATE POLICY "Users can submit attempts"
  ON game_attempts FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "Users can view attempts" ON game_attempts;
CREATE POLICY "Users can view attempts"
  ON game_attempts FOR SELECT
  TO anon, authenticated
  USING (true);

-- Create helper function to get bounty with details
CREATE OR REPLACE FUNCTION public.get_bounty_with_details(
  bounty_uuid UUID,
  wallet_addr VARCHAR(255) DEFAULT NULL
) RETURNS JSONB AS $$
DECLARE
  bounty_data JSONB;
  user_uuid UUID;
  participation_data JSONB;
BEGIN
  -- Get bounty data
  SELECT to_jsonb(b.*) ||
         jsonb_build_object(
           'creator', to_jsonb(u.*),
           'words_count', array_length(b.words, 1)
         )
  INTO bounty_data
  FROM bounties b
  JOIN users u ON b.creator_id = u.id
  WHERE b.id = bounty_uuid;

  -- If wallet address provided, get participation data
  IF wallet_addr IS NOT NULL THEN
    SELECT id INTO user_uuid FROM users WHERE wallet_address = wallet_addr;

    IF user_uuid IS NOT NULL THEN
      SELECT to_jsonb(bp.*)
      INTO participation_data
      FROM bounty_participants bp
      WHERE bp.bounty_id = bounty_uuid AND bp.user_id = user_uuid;

      IF participation_data IS NOT NULL THEN
        bounty_data := bounty_data || jsonb_build_object('participation', participation_data);
      END IF;
    END IF;
  END IF;

  RETURN bounty_data;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.get_bounty_with_details(UUID, VARCHAR) TO anon;
GRANT EXECUTE ON FUNCTION public.get_bounty_with_details(UUID, VARCHAR) TO authenticated;