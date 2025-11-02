-- ============================================================================
-- Migration 021: Fix Double-Increment Bug in join_bounty()
-- Created: 2025-10-08
-- Purpose: Remove manual participant_count increment to prevent double-counting
-- ============================================================================
-- ISSUE: The join_bounty() function manually increments participant_count,
-- but migration 015 added a trigger that also increments it automatically.
-- This causes each join to increment the count by 2 instead of 1.
--
-- SOLUTION: Remove the manual UPDATE statement and let the trigger handle it.
-- ============================================================================

-- ============================================================================
-- BEFORE (Current State - Lines 147-150 in 003_sample_data.sql):
-- ============================================================================
-- INSERT INTO bounty_participants (bounty_id, user_id, status)
-- VALUES (bounty_uuid, user_uuid, 'active')
-- RETURNING id INTO participant_id;
--
-- -- Update participant count (WRONG - causes double count with trigger)
-- UPDATE bounties
-- SET participant_count = participant_count + 1
-- WHERE id = bounty_uuid;
-- ============================================================================

-- ============================================================================
-- AFTER (Fixed Version):
-- ============================================================================
-- INSERT INTO bounty_participants (bounty_id, user_id, status)
-- VALUES (bounty_uuid, user_uuid, 'active')
-- RETURNING id INTO participant_id;
--
-- -- No manual update needed - the trigger from migration 015 handles it!
-- ============================================================================

-- ============================================================================
-- FIX: Recreate join_bounty() without manual participant_count increment
-- ============================================================================

CREATE OR REPLACE FUNCTION join_bounty(
    bounty_uuid UUID,
    wallet_addr TEXT
)
RETURNS UUID AS $$
DECLARE
    user_uuid UUID;
    participant_id UUID;
    bounty_record RECORD;
BEGIN
    -- Get or create user
    user_uuid := upsert_user(wallet_addr);

    -- Check if bounty exists and is joinable
    SELECT * INTO bounty_record
    FROM bounties
    WHERE id = bounty_uuid
    AND status = 'active'
    AND is_public = true
    AND (end_time IS NULL OR end_time > NOW())
    AND (max_participants IS NULL OR participant_count < max_participants);

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Bounty not found or not joinable';
    END IF;

    -- Check if user already joined
    SELECT id INTO participant_id
    FROM bounty_participants
    WHERE bounty_id = bounty_uuid AND user_id = user_uuid;

    IF FOUND THEN
        RAISE EXCEPTION 'User already joined this bounty';
    END IF;

    -- Join the bounty
    INSERT INTO bounty_participants (bounty_id, user_id, status)
    VALUES (bounty_uuid, user_uuid, 'active')
    RETURNING id INTO participant_id;

    -- ========================================================================
    -- REMOVED: Manual participant_count increment
    -- ========================================================================
    -- The trigger auto_increment_participant_count from migration 015
    -- handles this automatically after the INSERT above.
    -- No manual UPDATE needed!
    -- ========================================================================

    RAISE NOTICE 'User % joined bounty %. Participant count will be incremented by trigger.',
        user_uuid, bounty_uuid;

    RETURN participant_id;
END;
$$ LANGUAGE plpgsql;

-- Add comment explaining the fix
COMMENT ON FUNCTION join_bounty(UUID, TEXT) IS
'Adds a user to a bounty. Participant count is automatically incremented by the auto_increment_participant_count trigger from migration 015.';

-- ============================================================================
-- VERIFICATION: Check that trigger still exists and is active
-- ============================================================================

DO $$
DECLARE
    v_trigger_count INTEGER;
BEGIN
    -- Verify the trigger from migration 015 still exists
    SELECT COUNT(*)
    INTO v_trigger_count
    FROM pg_trigger
    WHERE tgname = 'auto_increment_participant_count'
      AND tgrelid = 'bounty_participants'::regclass
      AND tgenabled != 'D';  -- Not disabled

    IF v_trigger_count = 0 THEN
        RAISE EXCEPTION 'CRITICAL: auto_increment_participant_count trigger not found or disabled. This trigger is required for participant counting to work correctly.';
    END IF;

    RAISE NOTICE 'Verification passed: auto_increment_participant_count trigger is active';
END $$;

-- ============================================================================
-- OPTIONAL: Recalculate existing participant counts
-- ============================================================================
-- Use this query if you suspect existing bounties have incorrect counts
-- due to the double-increment bug.
--
-- IMPORTANT: Run this manually AFTER the migration, not as part of it.
-- Review the differences first before updating.
-- ============================================================================

-- See PHASE3_TESTING_GUIDE.sql for the recalculation query

-- ============================================================================
-- GRANT PERMISSIONS (maintain existing permissions)
-- ============================================================================

GRANT EXECUTE ON FUNCTION join_bounty(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION join_bounty(UUID, TEXT) TO anon;

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================
-- What changed:
-- - Removed lines 148-150 from join_bounty() function
-- - Added verification that trigger still exists
-- - Added NOTICE log for debugging
-- - Maintained all existing validation logic
-- - No schema changes, only function update
--
-- Expected behavior after this migration:
-- 1. User calls join_bounty(bounty_id, wallet_address)
-- 2. INSERT creates new bounty_participants row
-- 3. Trigger fires automatically and increments participant_count by 1
-- 4. Function returns participant_id
-- Result: participant_count increments exactly once (not twice)
-- ============================================================================
