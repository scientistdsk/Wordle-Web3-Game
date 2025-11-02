-- Fix leaderboard refresh triggers and functions
-- Created: 2025-01-28

-- Drop the trigger that tries to refresh materialized view
DROP TRIGGER IF EXISTS refresh_leaderboard_on_bounty_completion ON bounties;

-- Update the trigger function to work with regular view (no refresh needed)
CREATE OR REPLACE FUNCTION refresh_leaderboard_on_completion()
RETURNS TRIGGER AS $$
BEGIN
    -- Since leaderboard is now a regular view, no refresh needed
    -- This function is kept for backward compatibility but does nothing
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Update the main refresh_leaderboard function (in case other places call it)
CREATE OR REPLACE FUNCTION refresh_leaderboard()
RETURNS VOID AS $$
BEGIN
    -- Since leaderboard is now a regular view, no refresh needed
    -- This function is kept for backward compatibility but does nothing
    RETURN;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION refresh_leaderboard_on_completion() TO anon;
GRANT EXECUTE ON FUNCTION refresh_leaderboard_on_completion() TO authenticated;
GRANT EXECUTE ON FUNCTION refresh_leaderboard() TO anon;
GRANT EXECUTE ON FUNCTION refresh_leaderboard() TO authenticated;

-- Optionally recreate a harmless trigger if needed (just for compatibility)
-- This trigger will fire but do nothing since the function does nothing
CREATE TRIGGER refresh_leaderboard_on_bounty_completion
    AFTER UPDATE OF status ON bounties
    FOR EACH ROW
    WHEN (NEW.status = 'completed' AND OLD.status != 'completed')
    EXECUTE FUNCTION refresh_leaderboard_on_completion();