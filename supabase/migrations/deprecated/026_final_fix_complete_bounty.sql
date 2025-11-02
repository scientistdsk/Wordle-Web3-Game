-- ============================================================================
-- Migration 026: Final Fix for complete_bounty_with_winners
-- Created: 2025-10-10
-- Purpose: Fix SQLSTATE 42804 by properly mapping determine_bounty_winner columns
-- ============================================================================
-- ISSUE: determine_bounty_winner returns 4 columns (user_id, prize_share, ranking, metric_value)
--        complete_bounty_with_winners expects 3 columns (winner_user_id, prize_awarded, winner_rank)
-- FIX: Use RETURN QUERY with proper column mapping, avoid RETURN NEXT
-- ============================================================================

DROP FUNCTION IF EXISTS complete_bounty_with_winners(UUID);

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

    -- Return the winners with proper column mapping
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
        RAISE EXCEPTION 'Error in complete_bounty_with_winners for bounty %: % (SQLSTATE: %)',
            bounty_uuid, SQLERRM, SQLSTATE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add comment
COMMENT ON FUNCTION complete_bounty_with_winners(UUID) IS
'Determines winners automatically, marks them, and returns winner details. Migration 026 fixes SQLSTATE 42804 by properly mapping determine_bounty_winner columns (4) to return columns (3).';

-- Grant permissions
GRANT EXECUTE ON FUNCTION complete_bounty_with_winners(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION complete_bounty_with_winners(UUID) TO anon;

-- ============================================================================
-- MIGRATION COMPLETE - Migration 026
-- ============================================================================
-- Changes:
-- 1. Removed RETURN NEXT (causes SQLSTATE 42804 with RETURNS TABLE)
-- 2. Used RETURN QUERY with explicit column mapping
-- 3. Map 4-column determine_bounty_winner output to 3-column return structure
-- 4. Fixed all type casting to match expected types
-- ============================================================================
