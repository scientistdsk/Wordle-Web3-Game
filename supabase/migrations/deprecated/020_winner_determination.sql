-- ============================================================================
-- Migration 020: Winner Determination Logic
-- Created: 2025-10-08
-- Purpose: Implement automatic winner detection, marking, and prize distribution
-- ============================================================================
-- This migration creates the core logic for determining bounty winners based on
-- different criteria (time, attempts, words-correct, first-to-solve) and
-- automatically marking winners with proper prize distribution.
-- ============================================================================

-- ============================================================================
-- FUNCTION 1: determine_bounty_winner
-- ============================================================================
-- Purpose: Analyzes all participants and determines winner(s) based on winner_criteria
-- Returns: Table of (user_id, prize_share) for all winners
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
            1 AS ranking,
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
                1 AS ranking,
                bp.total_time_seconds AS metric_value
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
                bp.total_time_seconds AS metric_value
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
                1 AS ranking,
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
                1 AS ranking,
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
'Analyzes all participants and determines winner(s) based on bounty winner_criteria. Returns user_id and prize_share for each winner.';

-- ============================================================================
-- FUNCTION 2: complete_bounty_with_winners
-- ============================================================================
-- Purpose: Orchestrates the complete winner marking process
-- - Calls determine_bounty_winner() to get all winners
-- - Marks each winner using existing complete_bounty() function
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

        -- Add to return result (assign to output columns)
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

    RETURN;

EXCEPTION
    WHEN OTHERS THEN
        -- Log error and re-raise
        RAISE EXCEPTION 'Error in complete_bounty_with_winners for bounty %: % (SQLSTATE: %)',
            bounty_uuid, SQLERRM, SQLSTATE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add comment
COMMENT ON FUNCTION complete_bounty_with_winners(UUID) IS
'Orchestrates the complete bounty winner marking process. Determines all winners and marks them with appropriate prize shares.';

-- ============================================================================
-- FUNCTION 3: mark_prize_paid
-- ============================================================================
-- Purpose: Records blockchain payment details after prizes are paid
-- Updates: prize_paid_at timestamp and prize_transaction_hash
-- Used by: Frontend after successful blockchain transaction
-- ============================================================================

CREATE OR REPLACE FUNCTION mark_prize_paid(
    bounty_uuid UUID,
    user_uuid UUID,
    tx_hash VARCHAR(255)
)
RETURNS void AS $$
DECLARE
    v_participant_id UUID;
    v_is_winner BOOLEAN;
    v_prize_amount DECIMAL(20, 8);
BEGIN
    -- Log function call
    RAISE NOTICE 'mark_prize_paid() called - bounty: %, user: %, tx: %',
        bounty_uuid, user_uuid, tx_hash;

    -- Validate participant exists and is a winner
    SELECT
        bp.id,
        bp.is_winner,
        bp.prize_amount_won
    INTO
        v_participant_id,
        v_is_winner,
        v_prize_amount
    FROM bounty_participants bp
    WHERE bp.bounty_id = bounty_uuid AND bp.user_id = user_uuid;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Participant not found for bounty % and user %', bounty_uuid, user_uuid;
    END IF;

    IF NOT v_is_winner THEN
        RAISE EXCEPTION 'User % is not marked as a winner for bounty %', user_uuid, bounty_uuid;
    END IF;

    IF v_prize_amount <= 0 THEN
        RAISE EXCEPTION 'Prize amount is 0 for user % in bounty %', user_uuid, bounty_uuid;
    END IF;

    -- Check if already marked as paid
    IF EXISTS (
        SELECT 1 FROM bounty_participants
        WHERE bounty_id = bounty_uuid
          AND user_id = user_uuid
          AND prize_paid_at IS NOT NULL
    ) THEN
        RAISE WARNING 'Prize already marked as paid for user % in bounty %. Updating tx_hash.', user_uuid, bounty_uuid;
    END IF;

    -- Update prize payment details
    UPDATE bounty_participants
    SET
        prize_paid_at = NOW(),
        prize_transaction_hash = tx_hash
    WHERE bounty_id = bounty_uuid AND user_id = user_uuid;

    RAISE NOTICE 'Prize payment recorded: user=%, amount=%, tx=%',
        user_uuid, v_prize_amount, tx_hash;

    -- Record in payment_transactions table if it exists
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_name = 'payment_transactions'
    ) THEN
        INSERT INTO payment_transactions (
            bounty_id,
            user_id,
            transaction_type,
            amount,
            currency,
            transaction_hash,
            status,
            created_at
        ) VALUES (
            bounty_uuid,
            user_uuid,
            'prize_payout',
            v_prize_amount,
            'HBAR',
            tx_hash,
            'completed',
            NOW()
        );

        RAISE NOTICE 'Payment transaction record created';
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error in mark_prize_paid for bounty % and user %: % (SQLSTATE: %)',
            bounty_uuid, user_uuid, SQLERRM, SQLSTATE;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add comment
COMMENT ON FUNCTION mark_prize_paid(UUID, UUID, VARCHAR) IS
'Records blockchain payment details (transaction hash and timestamp) after prize is paid to winner.';

-- ============================================================================
-- FUNCTION 4: auto_complete_first_to_solve_trigger (Trigger Function)
-- ============================================================================
-- Purpose: Automatically completes bounty when first person solves
-- Trigger: Fires AFTER UPDATE on bounty_participants when status changes to 'completed'
-- Only for: Bounties with winner_criteria = 'first-to-solve' and prize_distribution = 'winner-take-all'
-- ============================================================================

CREATE OR REPLACE FUNCTION auto_complete_first_to_solve_trigger()
RETURNS TRIGGER AS $$
DECLARE
    v_winner_criteria winner_criteria;
    v_prize_distribution prize_distribution;
    v_bounty_status VARCHAR(20);
    v_existing_completions INTEGER;
BEGIN
    -- Only process if status changed to 'completed'
    IF NEW.status != 'completed' OR OLD.status = 'completed' THEN
        RETURN NEW;
    END IF;

    RAISE NOTICE 'auto_complete_first_to_solve_trigger fired for participant % in bounty %',
        NEW.id, NEW.bounty_id;

    -- Get bounty details
    SELECT b.winner_criteria, b.prize_distribution, b.status
    INTO v_winner_criteria, v_prize_distribution, v_bounty_status
    FROM bounties b
    WHERE b.id = NEW.bounty_id;

    IF NOT FOUND THEN
        RAISE WARNING 'Bounty not found: %', NEW.bounty_id;
        RETURN NEW;
    END IF;

    -- Only proceed if this is a first-to-solve bounty
    IF v_winner_criteria != 'first-to-solve' THEN
        RAISE NOTICE 'Bounty % is not first-to-solve (criteria: %). Skipping auto-completion.',
            NEW.bounty_id, v_winner_criteria;
        RETURN NEW;
    END IF;

    -- Check if bounty is already completed
    IF v_bounty_status = 'completed' THEN
        RAISE NOTICE 'Bounty % is already completed. Skipping auto-completion.', NEW.bounty_id;
        RETURN NEW;
    END IF;

    -- Check if this is the first completion
    SELECT COUNT(*)
    INTO v_existing_completions
    FROM bounty_participants
    WHERE bounty_id = NEW.bounty_id
      AND status = 'completed'
      AND id != NEW.id;

    IF v_existing_completions > 0 THEN
        RAISE NOTICE 'Bounty % already has % completion(s). Not the first to solve.',
            NEW.bounty_id, v_existing_completions;
        RETURN NEW;
    END IF;

    -- This is the first completion - auto-complete the bounty!
    RAISE NOTICE 'First completion detected for bounty %! Auto-completing with winner %',
        NEW.bounty_id, NEW.user_id;

    -- Call complete_bounty_with_winners to mark the winner and complete bounty
    PERFORM complete_bounty_with_winners(NEW.bounty_id);

    RAISE NOTICE 'Auto-completion successful for bounty %', NEW.bounty_id;

    RETURN NEW;

EXCEPTION
    WHEN OTHERS THEN
        -- Log error but don't block the participant update
        RAISE WARNING 'Error in auto_complete_first_to_solve_trigger for bounty %: % (SQLSTATE: %)',
            NEW.bounty_id, SQLERRM, SQLSTATE;
        RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Add comment
COMMENT ON FUNCTION auto_complete_first_to_solve_trigger() IS
'Trigger function that automatically completes first-to-solve bounties when the first participant completes.';

-- ============================================================================
-- TRIGGER: auto_complete_first_to_solve
-- ============================================================================
-- Fires after bounty_participants status is updated to 'completed'
-- Automatically completes the bounty for first-to-solve criteria

CREATE TRIGGER auto_complete_first_to_solve
AFTER UPDATE OF status ON bounty_participants
FOR EACH ROW
WHEN (NEW.status = 'completed' AND OLD.status != 'completed')
EXECUTE FUNCTION auto_complete_first_to_solve_trigger();

-- Add comment
COMMENT ON TRIGGER auto_complete_first_to_solve ON bounty_participants IS
'Automatically completes first-to-solve bounties when the first participant completes.';

-- ============================================================================
-- HELPER FUNCTION: get_bounty_winner_summary
-- ============================================================================
-- Purpose: Returns a human-readable summary of winners for a bounty
-- Useful for: Admin dashboard, debugging, reporting
-- ============================================================================

CREATE OR REPLACE FUNCTION get_bounty_winner_summary(bounty_uuid UUID)
RETURNS TABLE(
    bounty_name TEXT,
    bounty_status VARCHAR(20),
    winner_criteria winner_criteria,
    prize_distribution prize_distribution,
    total_prize DECIMAL(20, 8),
    winner_count INTEGER,
    total_distributed DECIMAL(20, 8),
    winners JSONB
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        b.name AS bounty_name,
        b.status AS bounty_status,
        b.winner_criteria,
        b.prize_distribution,
        b.prize_amount AS total_prize,
        COUNT(bp.id)::INTEGER AS winner_count,
        COALESCE(SUM(bp.prize_amount_won), 0) AS total_distributed,
        JSONB_AGG(
            JSONB_BUILD_OBJECT(
                'user_id', bp.user_id,
                'wallet_address', u.wallet_address,
                'username', u.username,
                'prize_amount', bp.prize_amount_won,
                'total_attempts', bp.total_attempts,
                'total_time_seconds', bp.total_time_seconds,
                'words_completed', bp.words_completed,
                'completed_at', bp.completed_at,
                'prize_paid', (bp.prize_paid_at IS NOT NULL),
                'prize_tx_hash', bp.prize_transaction_hash
            ) ORDER BY bp.prize_amount_won DESC
        ) AS winners
    FROM bounties b
    LEFT JOIN bounty_participants bp ON b.id = bp.bounty_id AND bp.is_winner = true
    LEFT JOIN users u ON bp.user_id = u.id
    WHERE b.id = bounty_uuid
    GROUP BY b.id, b.name, b.status, b.winner_criteria, b.prize_distribution, b.prize_amount;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Add comment
COMMENT ON FUNCTION get_bounty_winner_summary(UUID) IS
'Returns a comprehensive summary of all winners for a bounty including their stats and payment details.';

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================
-- Grant execute permissions to authenticated users and anon (for public queries)

GRANT EXECUTE ON FUNCTION determine_bounty_winner(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION complete_bounty_with_winners(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION mark_prize_paid(UUID, UUID, VARCHAR) TO authenticated;
GRANT EXECUTE ON FUNCTION get_bounty_winner_summary(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_bounty_winner_summary(UUID) TO anon;

-- ============================================================================
-- VALIDATION QUERIES
-- ============================================================================
-- Run these queries after migration to verify everything is working

-- Test 1: Check if all functions exist
-- SELECT proname, pronargs FROM pg_proc WHERE proname LIKE '%winner%' OR proname LIKE '%prize%';

-- Test 2: Check if trigger exists
-- SELECT tgname, tgrelid::regclass, tgenabled FROM pg_trigger WHERE tgname = 'auto_complete_first_to_solve';

-- Test 3: Test determine_bounty_winner on an existing completed bounty
-- SELECT * FROM determine_bounty_winner('your-bounty-uuid-here');

-- Test 4: Get winner summary for a bounty
-- SELECT * FROM get_bounty_winner_summary('your-bounty-uuid-here');

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================
-- Next Steps:
-- 1. Test each function with real bounty data
-- 2. Verify trigger fires correctly on first-to-solve bounties
-- 3. Proceed to Phase 3: Fix double-increment bug in join_bounty()
-- 4. Proceed to Phase 4: Update application code to use these functions
-- ============================================================================
