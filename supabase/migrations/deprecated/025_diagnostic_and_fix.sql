-- ============================================================================
-- Migration 025: Diagnostic and Ultimate Fix for complete_bounty_with_winners
-- Created: 2025-10-10
-- Purpose: Completely rewrite the function to avoid any type mismatches
-- ============================================================================

-- First, let's drop and recreate to ensure clean slate
DROP FUNCTION IF EXISTS complete_bounty_with_winners(UUID);

-- Recreate with explicit column handling
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
            1::INTEGER AS winner_rank
        FROM bounty_participants bp
        WHERE bp.bounty_id = bounty_uuid AND bp.is_winner = true
        ORDER BY bp.prize_amount_won DESC;

        RETURN;
    END IF;

    -- Process each winner determined by determine_bounty_winner
    -- Use explicit INSERT...SELECT to mark winners in one operation
    WITH winners AS (
        SELECT
            user_id,
            prize_share,
            ranking,
            ROW_NUMBER() OVER (ORDER BY ranking) as seq
        FROM determine_bounty_winner(bounty_uuid)
    )
    UPDATE bounty_participants bp
    SET
        status = 'completed',
        is_winner = true,
        prize_amount_won = w.prize_share,
        completed_at = COALESCE(bp.completed_at, NOW())
    FROM winners w
    WHERE bp.bounty_id = bounty_uuid
      AND bp.user_id = w.user_id;

    -- Get count of winners
    GET DIAGNOSTICS v_winner_count = ROW_COUNT;

    -- If first winner, call complete_bounty for bounty status update
    IF v_winner_count > 0 THEN
        -- Get the first winner's details
        DECLARE
            v_first_winner_id UUID;
            v_first_prize DECIMAL(20, 8);
        BEGIN
            SELECT user_id, prize_share
            INTO v_first_winner_id, v_first_prize
            FROM determine_bounty_winner(bounty_uuid)
            ORDER BY ranking ASC
            LIMIT 1;

            -- Call complete_bounty for first winner to set status
            PERFORM complete_bounty(
                bounty_uuid,
                v_first_winner_id,
                v_first_prize
            );
        END;

        -- Update user statistics for all winners
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
    ELSE
        RAISE WARNING 'No winners determined for bounty: % (%)', v_bounty_name, bounty_uuid;
    END IF;

    -- Ensure bounty status is completed
    UPDATE bounties
    SET
        status = 'completed',
        updated_at = NOW()
    WHERE id = bounty_uuid AND status != 'completed';

    -- Return the winners with explicit casting
    RETURN QUERY
    SELECT
        bp.user_id::UUID AS winner_user_id,
        bp.prize_amount_won::DECIMAL(20, 8) AS prize_awarded,
        ROW_NUMBER() OVER (ORDER BY bp.prize_amount_won DESC)::INTEGER AS winner_rank
    FROM bounty_participants bp
    WHERE bp.bounty_id = bounty_uuid
      AND bp.is_winner = true
    ORDER BY bp.prize_amount_won DESC;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error in complete_bounty_with_winners for bounty %: % (SQLSTATE: %)',
            bounty_uuid, SQLERRM, SQLSTATE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add comment
COMMENT ON FUNCTION complete_bounty_with_winners(UUID) IS
'Determines winners automatically, marks them, and returns winner details. Completely rewritten in migration 025 to avoid type mismatches.';

-- Grant permissions
GRANT EXECUTE ON FUNCTION complete_bounty_with_winners(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION complete_bounty_with_winners(UUID) TO anon;

-- ============================================================================
-- DIAGNOSTIC TEST (run manually after migration)
-- ============================================================================
/*
-- Test the function on your bounty:
SELECT * FROM complete_bounty_with_winners('3b994b5a-963f-4977-834f-61743b8e2d09');

-- This should return:
-- winner_user_id | prize_awarded | winner_rank
-- --------------+--------------+-------------
-- (winner data)
*/
