-- Fix leaderboard materialized view concurrent refresh issue
-- Created: 2025-01-28

-- Check if leaderboard materialized view exists and drop it if needed
DROP MATERIALIZED VIEW IF EXISTS public.leaderboard CASCADE;

-- Recreate leaderboard as a regular view instead of materialized view to avoid concurrency issues
-- This eliminates the concurrent refresh problem while maintaining functionality
CREATE OR REPLACE VIEW public.leaderboard AS
SELECT
  u.id as user_id,
  u.wallet_address,
  u.username,
  u.display_name,
  u.avatar_url,
  COUNT(DISTINCT bp.bounty_id) as bounties_participated,
  COUNT(DISTINCT CASE WHEN bp.is_winner = true THEN bp.bounty_id END) as bounties_won,
  COALESCE(SUM(CASE WHEN bp.is_winner = true THEN bp.prize_amount_won END), 0) as total_hbar_won,
  COALESCE(AVG(bp.total_attempts), 0) as avg_attempts,
  COALESCE(AVG(bp.total_time_seconds), 0) as avg_time_seconds,
  MAX(CASE WHEN bp.is_winner = true THEN bp.completed_at END) as last_win_date,
  ROW_NUMBER() OVER (ORDER BY
    COUNT(DISTINCT CASE WHEN bp.is_winner = true THEN bp.bounty_id END) DESC,
    COALESCE(SUM(CASE WHEN bp.is_winner = true THEN bp.prize_amount_won END), 0) DESC,
    COALESCE(AVG(bp.total_time_seconds), 999999) ASC
  ) as global_rank
FROM users u
LEFT JOIN bounty_participants bp ON u.id = bp.user_id
GROUP BY u.id, u.wallet_address, u.username, u.display_name, u.avatar_url
ORDER BY global_rank;

-- Grant permissions on the view
GRANT SELECT ON public.leaderboard TO anon;
GRANT SELECT ON public.leaderboard TO authenticated;

-- If there are any functions that try to refresh the materialized view, update them
-- to work with the regular view (no refresh needed)
CREATE OR REPLACE FUNCTION public.refresh_leaderboard() RETURNS VOID AS $$
BEGIN
  -- Since leaderboard is now a regular view, no refresh needed
  -- This function is kept for backward compatibility but does nothing
  RETURN;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.refresh_leaderboard() TO anon;
GRANT EXECUTE ON FUNCTION public.refresh_leaderboard() TO authenticated;