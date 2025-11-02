-- ============================================================================
-- Migration 023: Fix complete_bounty_with_winners Return Type
-- Created: 2025-10-10
-- Purpose: Fix "structure of query does not match function result type" error
-- ============================================================================
-- ERROR: SQLSTATE 42804 - structure of query does not match function result type
-- CAUSE: RETURN NEXT was used incorrectly with RETURNS TABLE
-- FIX: Properly assign output columns before RETURN NEXT
-- ============================================================================

CREATE OR REPLACE FUNCTION complete_bounty_with_winners(bounty_uuid UUID)
RETURNS TABLE(
    winner_user_id UUID,
    prize_awarded DECIMAL(20, 8),
    winner_rank INTEGER
) AS $$
DECLARE
    v_winner_record RECORD;
    v_bounty_status VARCHAR(20);
    v_bounty_name TEXT;
    v_winner_count INTEGER := 0;
    v_total_prize_distributed DECIMAL(20, 8) := 0;
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
        RAISE WARNING 'Bounty % already has winners marked. Skipping duplicate completion.', bounty_uuid;

        -- Return existing winners
        RETURN QUERY
        SELECT
            bp.user_id AS winner_user_id,
            bp.prize_amount_won AS prize_awarded,
            1 AS winner_rank
        FROM bounty_participants bp
        WHERE bp.bounty_id = bounty_uuid AND bp.is_winner = true;

        RETURN;
    END IF;

    -- Determine winners using the winner determination function
    FOR v_winner_record IN
        SELECT * FROM determine_bounty_winner(bounty_uuid)
    LOOP
        v_winner_count := v_winner_count + 1;

        RAISE NOTICE 'Marking winner #%: user_id=%, prize=%, metric=%',
            v_winner_count,
            v_winner_record.user_id,
            v_winner_record.prize_share,
            v_winner_record.metric_value;

        -- Mark this winner using the existing complete_bounty() function
        -- Note: complete_bounty() updates bounty status, so we only call it for the first winner
        -- For subsequent winners, we update directly to avoid status conflicts
        IF v_winner_count = 1 THEN
            -- First winner - use complete_bounty() to set bounty status
            PERFORM complete_bounty(
                bounty_uuid,
                v_winner_record.user_id,
                v_winner_record.prize_share
            );
        ELSE
            -- Subsequent winners - update directly without changing bounty status
            UPDATE bounty_participants
            SET
                status = 'completed',
                is_winner = true,
                prize_amount_won = v_winner_record.prize_share,
                completed_at = COALESCE(completed_at, NOW())
            WHERE bounty_id = bounty_uuid AND user_id = v_winner_record.user_id;

            -- Update user statistics
            UPDATE users
            SET
                total_bounties_won = total_bounties_won + 1,
                total_hbar_earned = total_hbar_earned + v_winner_record.prize_share,
                updated_at = NOW()
            WHERE id = v_winner_record.user_id;
        END IF;

        v_total_prize_distributed := v_total_prize_distributed + v_winner_record.prize_share;

        -- Add to return result (assign to output columns before RETURN NEXT)
        winner_user_id := v_winner_record.user_id;
        prize_awarded := v_winner_record.prize_share;
        winner_rank := v_winner_record.ranking;
        RETURN NEXT;
    END LOOP;

    -- Log summary
    IF v_winner_count = 0 THEN
        RAISE WARNING 'No winners determined for bounty: % (%). Check completion criteria.',
            v_bounty_name, bounty_uuid;
    ELSE
        RAISE NOTICE 'Completed bounty: % - Marked % winner(s), distributed % HBAR total',
            v_bounty_name, v_winner_count, v_total_prize_distributed;
    END IF;

    -- Ensure bounty status is set to completed
    UPDATE bounties
    SET
        status = 'completed',
        updated_at = NOW()
    WHERE id = bounty_uuid AND status != 'completed';

    RAISE NOTICE 'complete_bounty_with_winners() completed successfully';

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error in complete_bounty_with_winners for bounty %: % (SQLSTATE: %)',
            bounty_uuid, SQLERRM, SQLSTATE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add comment
COMMENT ON FUNCTION complete_bounty_with_winners(UUID) IS
'Determines winners automatically based on bounty criteria, marks them, and returns winner details. Fixed RETURN NEXT structure in migration 023.';

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================

GRANT EXECUTE ON FUNCTION complete_bounty_with_winners(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION complete_bounty_with_winners(UUID) TO anon;

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================
-- Fix applied: Properly assign output columns before RETURN NEXT
-- This resolves SQLSTATE 42804 error: "structure of query does not match function result type"
-- ============================================================================
