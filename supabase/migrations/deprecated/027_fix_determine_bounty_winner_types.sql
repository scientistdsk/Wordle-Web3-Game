-- ============================================================================
-- Migration 027: Fix determine_bounty_winner Type Casting
-- Created: 2025-10-10
-- Purpose: Fix SQLSTATE 42804 by adding explicit type casts in determine_bounty_winner
-- ============================================================================
-- ISSUE: Column 4 (metric_value) expects DECIMAL(20, 4) but columns are returning INTEGER
-- COLUMNS AFFECTED:
--   - total_time_seconds (INTEGER) -> needs ::DECIMAL(20, 4)
--   - total_attempts (INTEGER) -> needs ::DECIMAL(20, 4)
--   - words_completed (INTEGER) -> needs ::DECIMAL(20, 4)
--   - ranking (using "1 AS ranking") -> needs ::INTEGER cast
-- ============================================================================

DROP FUNCTION IF EXISTS determine_bounty_winner(UUID);

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
    ELSIF v_winner_criteria = 'time' THEN
        RAISE NOTICE 'Applying time-based criteria';

        IF v_prize_distribution = 'winner-take-all' THEN
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

            v_total_share := v_prize_amount / NULLIF(v_winner_count, 0);

            RAISE NOTICE 'Split-winners: % winners, % HBAR each', v_winner_count, v_total_share;

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
    ELSIF v_winner_criteria = 'attempts' THEN
        RAISE NOTICE 'Applying attempts-based criteria';

        IF v_prize_distribution = 'winner-take-all' THEN
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
    ELSIF v_winner_criteria = 'words-correct' THEN
        RAISE NOTICE 'Applying words-correct criteria';

        IF v_prize_distribution = 'winner-take-all' THEN
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
'Analyzes all participants and determines winner(s) based on bounty winner_criteria. Returns user_id and prize_share for each winner. Migration 027 fixes type casting issues.';

-- Grant permissions
GRANT EXECUTE ON FUNCTION determine_bounty_winner(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION determine_bounty_winner(UUID) TO anon;

-- ============================================================================
-- MIGRATION COMPLETE - Migration 027
-- ============================================================================
-- Changes:
-- 1. Added ::INTEGER cast to all "1 AS ranking" literals
-- 2. Added ::DECIMAL(20, 4) cast to total_time_seconds (was INTEGER)
-- 3. Added ::DECIMAL(20, 4) cast to total_attempts (was INTEGER)
-- 4. Added ::DECIMAL(20, 4) cast to words_completed (was INTEGER)
-- 5. Kept ROW_NUMBER() with ::INTEGER cast for split-winners ranking
-- ============================================================================
