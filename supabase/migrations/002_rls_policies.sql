-- Row Level Security (RLS) Policies
-- Created: 2025-01-28

-- Enable RLS on all tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE bounties ENABLE ROW LEVEL SECURITY;
ALTER TABLE bounty_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE game_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_transactions ENABLE ROW LEVEL SECURITY;

-- Helper function to get current user's wallet address from JWT
CREATE OR REPLACE FUNCTION current_user_wallet()
RETURNS TEXT AS $$
BEGIN
    RETURN COALESCE(
        current_setting('request.jwt.claims', true)::json->>'wallet_address',
        current_setting('request.jwt.claims', true)::json->>'sub'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Helper function to get current user ID
CREATE OR REPLACE FUNCTION current_user_id()
RETURNS UUID AS $$
BEGIN
    RETURN (
        SELECT id FROM users
        WHERE wallet_address = current_user_wallet()
        LIMIT 1
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- USERS table policies
-- Users can read all public user profiles
CREATE POLICY "Users can view public profiles" ON users
    FOR SELECT USING (is_active = true);

-- Users can only update their own profile
CREATE POLICY "Users can update own profile" ON users
    FOR UPDATE USING (wallet_address = current_user_wallet());

-- Users can insert their own profile
CREATE POLICY "Users can create own profile" ON users
    FOR INSERT WITH CHECK (wallet_address = current_user_wallet());

-- BOUNTIES table policies
-- Anyone can read active public bounties
CREATE POLICY "Anyone can view active public bounties" ON bounties
    FOR SELECT USING (
        status = 'active'
        AND is_public = true
        AND (end_time IS NULL OR end_time > NOW())
    );

-- Users can read all their own bounties (any status)
CREATE POLICY "Users can view own bounties" ON bounties
    FOR SELECT USING (creator_id = current_user_id());

-- Users can create bounties
CREATE POLICY "Users can create bounties" ON bounties
    FOR INSERT WITH CHECK (creator_id = current_user_id());

-- Users can update their own bounties (only if not completed/cancelled)
CREATE POLICY "Users can update own bounties" ON bounties
    FOR UPDATE USING (
        creator_id = current_user_id()
        AND status NOT IN ('completed', 'cancelled')
    );

-- Users can delete their own bounties (only if draft or no participants)
CREATE POLICY "Users can delete own bounties" ON bounties
    FOR DELETE USING (
        creator_id = current_user_id()
        AND (status = 'draft' OR participant_count = 0)
    );

-- BOUNTY_PARTICIPANTS table policies
-- Users can view participants of bounties they created
CREATE POLICY "Creators can view participants" ON bounty_participants
    FOR SELECT USING (
        bounty_id IN (
            SELECT id FROM bounties WHERE creator_id = current_user_id()
        )
    );

-- Users can view their own participation records
CREATE POLICY "Users can view own participation" ON bounty_participants
    FOR SELECT USING (user_id = current_user_id());

-- Users can join bounties (insert participation)
CREATE POLICY "Users can join bounties" ON bounty_participants
    FOR INSERT WITH CHECK (
        user_id = current_user_id()
        AND bounty_id IN (
            SELECT id FROM bounties
            WHERE status = 'active'
            AND is_public = true
            AND (end_time IS NULL OR end_time > NOW())
            AND (max_participants IS NULL OR participant_count < max_participants)
        )
    );

-- Users can update their own participation status
CREATE POLICY "Users can update own participation" ON bounty_participants
    FOR UPDATE USING (user_id = current_user_id());

-- GAME_ATTEMPTS table policies
-- Users can view their own attempts
CREATE POLICY "Users can view own attempts" ON game_attempts
    FOR SELECT USING (
        participant_id IN (
            SELECT id FROM bounty_participants WHERE user_id = current_user_id()
        )
    );

-- Bounty creators can view attempts for their bounties
CREATE POLICY "Creators can view bounty attempts" ON game_attempts
    FOR SELECT USING (
        bounty_id IN (
            SELECT id FROM bounties WHERE creator_id = current_user_id()
        )
    );

-- Users can create attempts for their participations
CREATE POLICY "Users can create own attempts" ON game_attempts
    FOR INSERT WITH CHECK (
        participant_id IN (
            SELECT id FROM bounty_participants
            WHERE user_id = current_user_id()
            AND status = 'active'
        )
    );

-- PAYMENT_TRANSACTIONS table policies
-- Users can view their own transactions
CREATE POLICY "Users can view own transactions" ON payment_transactions
    FOR SELECT USING (user_id = current_user_id());

-- Bounty creators can view transactions related to their bounties
CREATE POLICY "Creators can view bounty transactions" ON payment_transactions
    FOR SELECT USING (
        bounty_id IN (
            SELECT id FROM bounties WHERE creator_id = current_user_id()
        )
    );

-- System can insert transactions (this will be handled by edge functions with service role)
-- No direct INSERT policy for users - transactions are created by the system

-- LEADERBOARD view policy
-- Anyone can read the leaderboard (it's a materialized view, RLS doesn't apply directly)
-- But we'll create a security definer function for it

-- Function to get public leaderboard data
CREATE OR REPLACE FUNCTION get_leaderboard(limit_count INTEGER DEFAULT 100)
RETURNS TABLE (
    user_id UUID,
    wallet_address VARCHAR(255),
    username VARCHAR(50),
    display_name VARCHAR(100),
    avatar_url TEXT,
    bounties_participated BIGINT,
    bounties_won BIGINT,
    total_hbar_won NUMERIC,
    avg_attempts NUMERIC,
    avg_time_seconds NUMERIC,
    last_win_date TIMESTAMP WITH TIME ZONE,
    global_rank BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT * FROM leaderboard
    ORDER BY global_rank
    LIMIT limit_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get user's leaderboard position
CREATE OR REPLACE FUNCTION get_user_leaderboard_position(wallet_addr TEXT)
RETURNS TABLE (
    user_id UUID,
    wallet_address VARCHAR(255),
    username VARCHAR(50),
    display_name VARCHAR(100),
    avatar_url TEXT,
    bounties_participated BIGINT,
    bounties_won BIGINT,
    total_hbar_won NUMERIC,
    avg_attempts NUMERIC,
    avg_time_seconds NUMERIC,
    last_win_date TIMESTAMP WITH TIME ZONE,
    global_rank BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT * FROM leaderboard
    WHERE leaderboard.wallet_address = wallet_addr;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get bounty-specific leaderboard
CREATE OR REPLACE FUNCTION get_bounty_leaderboard(bounty_uuid UUID)
RETURNS TABLE (
    user_id UUID,
    wallet_address VARCHAR(255),
    username VARCHAR(50),
    display_name VARCHAR(100),
    total_attempts INTEGER,
    total_time_seconds INTEGER,
    words_completed INTEGER,
    is_winner BOOLEAN,
    completed_at TIMESTAMP WITH TIME ZONE,
    rank BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        u.id,
        u.wallet_address,
        u.username,
        u.display_name,
        bp.total_attempts,
        bp.total_time_seconds,
        bp.words_completed,
        bp.is_winner,
        bp.completed_at,
        RANK() OVER (
            ORDER BY
                bp.is_winner DESC,
                bp.words_completed DESC,
                bp.total_attempts ASC,
                bp.total_time_seconds ASC
        ) as rank
    FROM bounty_participants bp
    JOIN users u ON bp.user_id = u.id
    WHERE bp.bounty_id = bounty_uuid
    AND bp.status IN ('completed', 'active')
    ORDER BY rank;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant necessary permissions
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated;