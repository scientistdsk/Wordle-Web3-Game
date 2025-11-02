-- Create a function to calculate user statistics in real-time
CREATE OR REPLACE FUNCTION get_user_stats(wallet_addr TEXT)
RETURNS TABLE (
  total_bounty_created INTEGER,
  total_bounty_entered INTEGER,
  total_tries INTEGER,
  total_wins INTEGER,
  total_losses INTEGER,
  success_rate DECIMAL(5, 2)
) AS $$
DECLARE
  user_uuid UUID;
  v_bounties_created INTEGER;
  v_bounties_entered INTEGER;
  v_total_attempts INTEGER;
  v_wins_count INTEGER;
  v_losses_count INTEGER;
BEGIN
  -- Get user ID from wallet address
  SELECT id INTO user_uuid
  FROM users
  WHERE wallet_address = wallet_addr;

  -- If user doesn't exist, return zeros
  IF user_uuid IS NULL THEN
    RETURN QUERY SELECT 0, 0, 0, 0, 0, 0.00::DECIMAL(5, 2);
    RETURN;
  END IF;

  -- Count bounties created by this user
  SELECT COUNT(*)::INTEGER INTO v_bounties_created
  FROM bounties
  WHERE creator_id = user_uuid;

  -- Count bounties entered (participated in) by this user
  SELECT COUNT(DISTINCT bounty_id)::INTEGER INTO v_bounties_entered
  FROM bounty_participants
  WHERE user_id = user_uuid;

  -- Count total attempts/tries across all bounties
  -- This sums up the total_attempts from all participations
  -- Use table prefix to avoid ambiguity
  SELECT COALESCE(SUM(bp.total_attempts), 0)::INTEGER INTO v_total_attempts
  FROM bounty_participants bp
  WHERE bp.user_id = user_uuid;

  -- Count wins (bounties where user is_winner = true)
  SELECT COUNT(*)::INTEGER INTO v_wins_count
  FROM bounty_participants
  WHERE user_id = user_uuid
    AND is_winner = true;

  -- Count losses (completed bounties where user participated but didn't win)
  SELECT COUNT(*)::INTEGER INTO v_losses_count
  FROM bounty_participants bp
  INNER JOIN bounties b ON bp.bounty_id = b.id
  WHERE bp.user_id = user_uuid
    AND bp.is_winner = false
    AND bp.status = 'completed'
    AND b.status = 'completed';

  -- Calculate success rate: (Total Wins / Total Bounties Entered) × 100
  RETURN QUERY
  SELECT
    v_bounties_created,
    v_bounties_entered,
    v_total_attempts,
    v_wins_count,
    v_losses_count,
    CASE
      WHEN v_bounties_entered > 0 THEN
        ROUND((v_wins_count::DECIMAL / v_bounties_entered::DECIMAL) * 100, 2)
      ELSE
        0.00
    END AS success_rate;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission to authenticated and anon users
GRANT EXECUTE ON FUNCTION get_user_stats(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION get_user_stats(TEXT) TO anon;
