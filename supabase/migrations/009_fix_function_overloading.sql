-- Fix function overloading conflict for get_bounty_details
-- Created: 2025-01-28

-- Drop all existing versions of get_bounty_details functions
DROP FUNCTION IF EXISTS public.get_bounty_details(UUID, VARCHAR);
DROP FUNCTION IF EXISTS public.get_bounty_details(UUID, TEXT);
DROP FUNCTION IF EXISTS public.get_bounty_with_details(UUID, VARCHAR);
DROP FUNCTION IF EXISTS public.get_bounty_with_details(UUID, TEXT);

-- Create a single, unambiguous get_bounty_details function
CREATE OR REPLACE FUNCTION public.get_bounty_details(
  bounty_uuid UUID,
  wallet_addr TEXT DEFAULT NULL
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

  -- If no bounty found, return null
  IF bounty_data IS NULL THEN
    RETURN NULL;
  END IF;

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
GRANT EXECUTE ON FUNCTION public.get_bounty_details(UUID, TEXT) TO anon;
GRANT EXECUTE ON FUNCTION public.get_bounty_details(UUID, TEXT) TO authenticated;