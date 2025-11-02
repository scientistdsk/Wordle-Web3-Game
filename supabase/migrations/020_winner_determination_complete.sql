-- ============================================================================
-- Migration 020: Winner Determination Logic (COMPLETE & TESTED)
-- Created: 2025-10-08 | Fixed: 2025-10-10
-- Purpose: Implement automatic winner detection, marking, and prize distribution
-- ============================================================================
-- This migration creates the core logic for determining bounty winners based on
-- different criteria (time, attempts, words-correct, first-to-solve) and
-- automatically marking winners with proper prize distribution.
--
-- CONSOLIDATED VERSION: Includes all fixes from migrations 026 and 027
-- - Type casting fixes for determine_bounty_winner (INTEGER -> DECIMAL)
-- - RETURN QUERY fixes for complete_bounty_with_winners (no RETURN NEXT)
-- ============================================================================

-- ============================================================================
-- FUNCTION 1: determine_bounty_winner
-- ============================================================================
-- Purpose: Analyzes all participants and determines winner(s) based on winner_criteria
-- Returns: Table of (user_id, prize_share, ranking, metric_value) for all winners
-- Handles: All 4 winner criteria types with proper tie-breaking logic
-- ============================================================================

CREATE OR REPLACE FUNCTION determine_bounty_winner(bounty_uuid UUID)
RETURNS TABLE(
    user_id UUID,
    prize_share DECIMAL(20, 8),
    ranking INTEGER,
    metric_value DECIMAL(20, 4)
) AS $$
DECLARE
    v_winner_criteria winner_criteria;
    v_prize_distribution prize_distribution;
    v_prize_amount DECIMAL(20, 8);
    v_bounty_status VARCHAR(20);
    v_winner_count INTEGER;
    v_total_share DECIMAL(20, 8);
BEGIN
    -- Log function call
    RAISE NOTICE 'determine_bounty_winner() called for bounty: %', bounty_uuid;

    -- Get bounty details
    SELECT b.winner_criteria, b.prize_distribution, b.prize_amount, b.status
    INTO v_winner_criteria, v_prize_distribution, v_prize_amount, v_bounty_status
    FROM bounties b
    WHERE b.id = bounty_uuid;

    -- Validate bounty exists
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Bounty not found: %', bounty_uuid;
    END IF;

    -- Validate bounty is completed or can be completed
    IF v_bounty_status NOT IN ('completed', 'active', 'expired') THEN
        RAISE EXCEPTION 'Bounty cannot be completed. Current status: %', v_bounty_status;
    END IF;

    RAISE NOTICE 'Bounty details - Criteria: %, Distribution: %, Prize: %',
        v_winner_criteria, v_prize_distribution, v_prize_amount;

    -- ========================================================================
    -- WINNER CRITERIA: first-to-solve
    -- ========================================================================
    -- Winner is the first person to complete the bounty
    IF v_winner_criteria = 'first-to-solve' THEN
        RAISE NOTICE 'Applying first-to-solve criteria';

        RETURN QUERY
        SELECT
            bp.user_id,
            v_prize_amount AS prize_share,
            1::INTEGER AS ranking,
            EXTRACT(EPOCH FROM bp.completed_at)::DECIMAL(20, 4) AS metric_value
        FROM bounty_participants bp
        WHERE bp.bounty_id = bounty_uuid
          AND bp.status = 'completed'
        ORDER BY bp.completed_at ASC
        LIMIT 1;

    -- ========================================================================
    -- WINNER CRITERIA: time
    -- ========================================================================
    -- Winner is the person with the fastest total_time_seconds
    ELSIF v_winner_criteria = 'time' THEN
        RAISE NOTICE 'Applying time-based criteria';

        -- Handle prize distribution type
        IF v_prize_distribution = 'winner-take-all' THEN
            -- Single winner with best (lowest) time
            RETURN QUERY
            SELECT
                bp.user_id,
                v_prize_amount AS prize_share,
                1::INTEGER AS ranking,
                bp.total_time_seconds::DECIMAL(20, 4) AS metric_value
            FROM bounty_participants bp
            WHERE bp.bounty_id = bounty_uuid
              AND bp.status = 'completed'
              AND bp.total_time_seconds IS NOT NULL
              AND bp.total_time_seconds > 0
            ORDER BY bp.total_time_seconds ASC
            LIMIT 1;

        ELSIF v_prize_distribution = 'split-winners' THEN
            -- Multiple winners split the prize equally (top 3 fastest)
            -- First, count how many winners we'll have
            SELECT COUNT(*) INTO v_winner_count
            FROM (
                SELECT bp.user_id
                FROM bounty_participants bp
                WHERE bp.bounty_id = bounty_uuid
                  AND bp.status = 'completed'
                  AND bp.total_time_seconds IS NOT NULL
                  AND bp.total_time_seconds > 0
                ORDER BY bp.total_time_seconds ASC
                LIMIT 3
            ) winners;

            -- Calculate prize share per winner
            v_total_share := v_prize_amount / NULLIF(v_winner_count, 0);

            RAISE NOTICE 'Split-winners: % winners, % HBAR each', v_winner_count, v_total_share;

            -- Return top 3 with equal shares
            RETURN QUERY
            SELECT
                bp.user_id,
                v_total_share AS prize_share,
                ROW_NUMBER() OVER (ORDER BY bp.total_time_seconds ASC)::INTEGER AS ranking,
                bp.total_time_seconds::DECIMAL(20, 4) AS metric_value
            FROM bounty_participants bp
            WHERE bp.bounty_id = bounty_uuid
              AND bp.status = 'completed'
              AND bp.total_time_seconds IS NOT NULL
              AND bp.total_time_seconds > 0
            ORDER BY bp.total_time_seconds ASC
            LIMIT 3;

        ELSE
            RAISE EXCEPTION 'Unknown prize_distribution: %', v_prize_distribution;
        END IF;

    -- ========================================================================
    -- WINNER CRITERIA: attempts
    -- ========================================================================
    -- Winner is the person with the fewest total_attempts
    ELSIF v_winner_criteria = 'attempts' THEN
        RAISE NOTICE 'Applying attempts-based criteria';

        -- Handle prize distribution type
        IF v_prize_distribution = 'winner-take-all' THEN
            -- Single winner with best (lowest) attempts
            RETURN QUERY
            SELECT
                bp.user_id,
                v_prize_amount AS prize_share,
                1::INTEGER AS ranking,
                bp.total_attempts::DECIMAL(20, 4) AS metric_value
            FROM bounty_participants bp
            WHERE bp.bounty_id = bounty_uuid
              AND bp.status = 'completed'
              AND bp.total_attempts > 0
            ORDER BY bp.total_attempts ASC, bp.total_time_seconds ASC
            LIMIT 1;

        ELSIF v_prize_distribution = 'split-winners' THEN
            -- Multiple winners split the prize equally (top 3 fewest attempts)
            SELECT COUNT(*) INTO v_winner_count
            FROM (
                SELECT bp.user_id
                FROM bounty_participants bp
                WHERE bp.bounty_id = bounty_uuid
                  AND bp.status = 'completed'
                  AND bp.total_attempts > 0
                ORDER BY bp.total_attempts ASC, bp.total_time_seconds ASC
                LIMIT 3
            ) winners;

            v_total_share := v_prize_amount / NULLIF(v_winner_count, 0);

            RAISE NOTICE 'Split-winners: % winners, % HBAR each', v_winner_count, v_total_share;

            RETURN QUERY
            SELECT
                bp.user_id,
                v_total_share AS prize_share,
                ROW_NUMBER() OVER (ORDER BY bp.total_attempts ASC, bp.total_time_seconds ASC)::INTEGER AS ranking,
                bp.total_attempts::DECIMAL(20, 4) AS metric_value
            FROM bounty_participants bp
            WHERE bp.bounty_id = bounty_uuid
              AND bp.status = 'completed'
              AND bp.total_attempts > 0
            ORDER BY bp.total_attempts ASC, bp.total_time_seconds ASC
            LIMIT 3;

        ELSE
            RAISE EXCEPTION 'Unknown prize_distribution: %', v_prize_distribution;
        END IF;

    -- ========================================================================
    -- WINNER CRITERIA: words-correct
    -- ========================================================================
    -- Winner is the person who completed the most words correctly
    ELSIF v_winner_criteria = 'words-correct' THEN
        RAISE NOTICE 'Applying words-correct criteria';

        -- Handle prize distribution type
        IF v_prize_distribution = 'winner-take-all' THEN
            -- Single winner with most (highest) words_completed
            RETURN QUERY
            SELECT
                bp.user_id,
                v_prize_amount AS prize_share,
                1::INTEGER AS ranking,
                bp.words_completed::DECIMAL(20, 4) AS metric_value
            FROM bounty_participants bp
            WHERE bp.bounty_id = bounty_uuid
              AND bp.status = 'completed'
              AND bp.words_completed > 0
            ORDER BY bp.words_completed DESC, bp.total_time_seconds ASC
            LIMIT 1;

        ELSIF v_prize_distribution = 'split-winners' THEN
            -- Multiple winners split the prize equally (top 3 most words)
            SELECT COUNT(*) INTO v_winner_count
            FROM (
                SELECT bp.user_id
                FROM bounty_participants bp
                WHERE bp.bounty_id = bounty_uuid
                  AND bp.status = 'completed'
                  AND bp.words_completed > 0
                ORDER BY bp.words_completed DESC, bp.total_time_seconds ASC
                LIMIT 3
            ) winners;

            v_total_share := v_prize_amount / NULLIF(v_winner_count, 0);

            RAISE NOTICE 'Split-winners: % winners, % HBAR each', v_winner_count, v_total_share;

            RETURN QUERY
            SELECT
                bp.user_id,
                v_total_share AS prize_share,
                ROW_NUMBER() OVER (ORDER BY bp.words_completed DESC, bp.total_time_seconds ASC)::INTEGER AS ranking,
                bp.words_completed::DECIMAL(20, 4) AS metric_value
            FROM bounty_participants bp
            WHERE bp.bounty_id = bounty_uuid
              AND bp.status = 'completed'
              AND bp.words_completed > 0
            ORDER BY bp.words_completed DESC, bp.total_time_seconds ASC
            LIMIT 3;

        ELSE
            RAISE EXCEPTION 'Unknown prize_distribution: %', v_prize_distribution;
        END IF;

    ELSE
        RAISE EXCEPTION 'Unknown winner_criteria: %', v_winner_criteria;
    END IF;

    -- Log if no winners found
    IF NOT FOUND THEN
        RAISE WARNING 'No eligible winners found for bounty: %', bounty_uuid;
    END IF;

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add comment
COMMENT ON FUNCTION determine_bounty_winner(UUID) IS
'Analyzes all participants and determines winner(s) based on bounty winner_criteria. Returns user_id and prize_share for each winner. Includes type casting fixes from migration 027.';

-- ============================================================================
-- FUNCTION 2: complete_bounty_with_winners
-- ============================================================================
-- Purpose: Orchestrates the complete winner marking process
-- - Calls determine_bounty_winner() to get all winners
-- - Marks each winner in bounty_participants
-- - Updates bounty status to 'completed'
-- - Handles errors and rollback if any step fails
-- ============================================================================

CREATE OR REPLACE FUNCTION complete_bounty_with_winners(bounty_uuid UUID)
RETURNS TABLE(
    winner_user_id UUID,
    prize_awarded DECIMAL(20, 8),
    winner_rank INTEGER
) AS $$
DECLARE
    v_bounty_status VARCHAR(20);
    v_bounty_name TEXT;
    v_winner_count INTEGER := 0;
    v_first_winner_id UUID;
    v_first_prize DECIMAL(20, 8);
BEGIN
    -- Log function call
    RAISE NOTICE 'complete_bounty_with_winners() called for bounty: %', bounty_uuid;

    -- Get bounty details
    SELECT b.status, b.name INTO v_bounty_status, v_bounty_name
    FROM bounties b
    WHERE b.id = bounty_uuid;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Bounty not found: %', bounty_uuid;
    END IF;

    RAISE NOTICE 'Processing bounty: % (status: %)', v_bounty_name, v_bounty_status;

    -- Check if bounty already has winners marked
    IF EXISTS (
        SELECT 1 FROM bounty_participants
        WHERE bounty_id = bounty_uuid AND is_winner = true
    ) THEN
        RAISE WARNING 'Bounty % already has winners marked. Returning existing winners.', bounty_uuid;

        -- Return existing winners
        RETURN QUERY
        SELECT
            bp.user_id::UUID AS winner_user_id,
            bp.prize_amount_won::DECIMAL(20, 8) AS prize_awarded,
            ROW_NUMBER() OVER (ORDER BY bp.prize_amount_won DESC, bp.completed_at ASC)::INTEGER AS winner_rank
        FROM bounty_participants bp
        WHERE bp.bounty_id = bounty_uuid AND bp.is_winner = true
        ORDER BY bp.prize_amount_won DESC, bp.completed_at ASC;

        RETURN;
    END IF;

    -- Process winners using CTE to mark them in one operation
    WITH winners AS (
        SELECT
            user_id,
            prize_share,
            ranking
        FROM determine_bounty_winner(bounty_uuid)
    ),
    updated_participants AS (
        UPDATE bounty_participants bp
        SET
            status = 'completed',
            is_winner = true,
            prize_amount_won = w.prize_share,
            completed_at = COALESCE(bp.completed_at, NOW())
        FROM winners w
        WHERE bp.bounty_id = bounty_uuid
          AND bp.user_id = w.user_id
        RETURNING bp.user_id, bp.prize_amount_won, w.ranking
    )
    SELECT COUNT(*) INTO v_winner_count FROM updated_participants;

    -- Update user statistics for all winners
    IF v_winner_count > 0 THEN
        UPDATE users u
        SET
            total_bounties_won = total_bounties_won + 1,
            total_hbar_earned = total_hbar_earned + bp.prize_amount_won,
            updated_at = NOW()
        FROM bounty_participants bp
        WHERE u.id = bp.user_id
          AND bp.bounty_id = bounty_uuid
          AND bp.is_winner = true;

        RAISE NOTICE 'Completed bounty: % - Marked % winner(s)', v_bounty_name, v_winner_count;

        -- Get first winner for complete_bounty call
        SELECT user_id, prize_share
        INTO v_first_winner_id, v_first_prize
        FROM determine_bounty_winner(bounty_uuid)
        ORDER BY ranking ASC
        LIMIT 1;

        -- Call complete_bounty for first winner to ensure bounty status update
        IF v_first_winner_id IS NOT NULL THEN
            PERFORM complete_bounty(
                bounty_uuid,
                v_first_winner_id,
                v_first_prize
            );
        END IF;
    ELSE
        RAISE WARNING 'No winners determined for bounty: % (%)', v_bounty_name, bounty_uuid;
    END IF;

    -- Ensure bounty status is completed
    UPDATE bounties
    SET
        status = 'completed',
        updated_at = NOW()
    WHERE id = bounty_uuid AND status != 'completed';

    RAISE NOTICE 'complete_bounty_with_winners() completed successfully';

    -- Return the winners with proper column mapping (uses RETURN QUERY, not RETURN NEXT)
    RETURN QUERY
    SELECT
        bp.user_id::UUID AS winner_user_id,
        bp.prize_amount_won::DECIMAL(20, 8) AS prize_awarded,
        ROW_NUMBER() OVER (ORDER BY bp.prize_amount_won DESC, bp.completed_at ASC)::INTEGER AS winner_rank
    FROM bounty_participants bp
    WHERE bp.bounty_id = bounty_uuid
      AND bp.is_winner = true
    ORDER BY bp.prize_amount_won DESC, bp.completed_at ASC;

EXCEPTION
    WHEN OTHERS THEN
        -- Log error and re-raise
        RAISE EXCEPTION 'Error in complete_bounty_with_winners for bounty %: % (SQLSTATE: %)',
            bounty_uuid, SQLERRM, SQLSTATE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add comment
COMMENT ON FUNCTION complete_bounty_with_winners(UUID) IS
'Determines winners automatically, marks them, and returns winner details. Includes fixes from migration 026 - uses RETURN QUERY instead of RETURN NEXT.';

-- ============================================================================
-- FUNCTION 3: mark_prize_paid
-- ============================================================================
-- Purpose: Records blockchain payment details after prize distribution
-- Called by: Frontend after successful blockchain transaction
-- ============================================================================

CREATE OR REPLACE FUNCTION mark_prize_paid(
    bounty_uuid UUID,
    winner_user_id UUID,
    transaction_hash VARCHAR(255),
    blockchain_amount DECIMAL(20, 8)
)
RETURNS void AS $$
BEGIN
    -- Update the participant record
    UPDATE bounty_participants
    SET
        prize_paid = true,
        blockchain_tx_hash = transaction_hash,
        prize_paid_at = NOW()
    WHERE bounty_id = bounty_uuid
      AND user_id = winner_user_id
      AND is_winner = true;

    -- Verify the update worked
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Winner record not found for bounty % and user %',
            bounty_uuid, winner_user_id;
    END IF;

    -- Log payment in payment_transactions table
    INSERT INTO payment_transactions (
        user_id,
        bounty_id,
        transaction_type,
        amount,
        transaction_hash,
        status
    ) VALUES (
        winner_user_id,
        bounty_uuid,
        'prize_payment',
        blockchain_amount,
        transaction_hash,
        'completed'
    );

    RAISE NOTICE 'Marked prize paid for bounty % to user % (tx: %)',
        bounty_uuid, winner_user_id, transaction_hash;

END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add comment
COMMENT ON FUNCTION mark_prize_paid(UUID, UUID, VARCHAR, DECIMAL) IS
'Records blockchain payment details after prize distribution to winner.';

-- Grant permissions
GRANT EXECUTE ON FUNCTION determine_bounty_winner(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION determine_bounty_winner(UUID) TO anon;
GRANT EXECUTE ON FUNCTION complete_bounty_with_winners(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION complete_bounty_with_winners(UUID) TO anon;
GRANT EXECUTE ON FUNCTION mark_prize_paid(UUID, UUID, VARCHAR, DECIMAL) TO authenticated;

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================
-- This consolidated migration includes:
-- 1. determine_bounty_winner with proper type casting (INTEGER -> DECIMAL)
-- 2. complete_bounty_with_winners with RETURN QUERY (not RETURN NEXT)
-- 3. mark_prize_paid for blockchain payment tracking
--
-- Replaces: Original 020, 023, 024, 025, 026, 027
-- ============================================================================
