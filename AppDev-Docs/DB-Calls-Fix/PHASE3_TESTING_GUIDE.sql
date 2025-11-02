-- ============================================================================
-- PHASE 3: TESTING GUIDE
-- Fix Double-Increment Bug - Test & Verification Queries
-- ============================================================================
-- Run these queries after applying migration 021_fix_join_bounty.sql
-- ============================================================================

-- ============================================================================
-- STEP 1: VERIFY MIGRATION WAS APPLIED
-- ============================================================================

-- Check that join_bounty() function was updated
SELECT
    proname as function_name,
    pg_get_functiondef(oid) as function_definition
FROM pg_proc
WHERE proname = 'join_bounty'
  AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');

-- Verify the function definition no longer contains the manual UPDATE
-- Look for absence of: "UPDATE bounties SET participant_count = participant_count + 1"

-- ============================================================================
-- STEP 2: VERIFY TRIGGER IS ACTIVE
-- ============================================================================

SELECT
    tgname as trigger_name,
    tgrelid::regclass as table_name,
    tgenabled as enabled,
    CASE tgenabled
        WHEN 'O' THEN 'ENABLED'
        WHEN 'D' THEN 'DISABLED'
        WHEN 'R' THEN 'REPLICA'
        WHEN 'A' THEN 'ALWAYS'
    END as status,
    pg_get_triggerdef(oid) as definition
FROM pg_trigger
WHERE tgname = 'auto_increment_participant_count'
  AND tgrelid = 'bounty_participants'::regclass;

-- Expected: 1 row with status = 'ENABLED' or 'ORIGIN'

-- ============================================================================
-- STEP 3: IDENTIFY BOUNTIES WITH INCORRECT COUNTS (BEFORE TESTING)
-- ============================================================================
-- This shows which bounties currently have double-counted participants

SELECT
    b.id,
    b.name,
    b.status,
    b.participant_count as stored_count,
    COUNT(bp.id) as actual_count,
    b.participant_count - COUNT(bp.id) as difference,
    CASE
        WHEN b.participant_count = COUNT(bp.id) THEN '✓ OK'
        WHEN b.participant_count > COUNT(bp.id) THEN '✗ OVER-COUNTED'
        WHEN b.participant_count < COUNT(bp.id) THEN '✗ UNDER-COUNTED'
        ELSE '? UNKNOWN'
    END as status,
    CASE
        WHEN b.participant_count = COUNT(bp.id) * 2 THEN 'LIKELY DOUBLE-COUNT'
        ELSE 'CHECK MANUALLY'
    END as diagnosis
FROM bounties b
LEFT JOIN bounty_participants bp ON b.id = bp.bounty_id
GROUP BY b.id, b.name, b.status, b.participant_count
HAVING b.participant_count != COUNT(bp.id)
ORDER BY ABS(b.participant_count - COUNT(bp.id)) DESC;

-- Save these results to compare after recalculation

-- ============================================================================
-- STEP 4: CREATE TEST BOUNTY FOR INCREMENT TESTING
-- ============================================================================
-- Create a new bounty to test that the fix works

INSERT INTO bounties (
    id,
    name,
    description,
    creator_id,
    bounty_type,
    prize_amount,
    prize_currency,
    words,
    hints,
    winner_criteria,
    prize_distribution,
    start_time,
    status,
    is_public,
    requires_registration,
    participant_count,
    completion_count
)
SELECT
    gen_random_uuid(),
    'TEST: Single Increment Bounty',
    'Test bounty for Phase 3 - verifying participant count increments only once',
    u.id,
    'Simple',
    1.00000000,
    'HBAR',
    ARRAY['TEST', 'WORD'],
    ARRAY['Test hint'],
    'time',
    'winner-take-all',
    NOW(),
    'active',
    true,
    false,
    0,  -- Start with 0 participants
    0
FROM users u
LIMIT 1
RETURNING id, name, participant_count;

-- Note the returned bounty ID for testing below

-- ============================================================================
-- TEST 1: Single User Join - Verify Count Increments by 1
-- ============================================================================

-- Get the test bounty ID
DO $$
DECLARE
    v_test_bounty_id UUID;
    v_test_wallet TEXT := '0.0.999991'; -- Test wallet address
    v_participant_id UUID;
    v_count_before INTEGER;
    v_count_after INTEGER;
BEGIN
    -- Get the test bounty we just created
    SELECT id INTO v_test_bounty_id
    FROM bounties
    WHERE name = 'TEST: Single Increment Bounty'
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_test_bounty_id IS NULL THEN
        RAISE EXCEPTION 'Test bounty not found. Please create it first.';
    END IF;

    -- Get count before join
    SELECT participant_count INTO v_count_before
    FROM bounties
    WHERE id = v_test_bounty_id;

    RAISE NOTICE 'Test bounty ID: %', v_test_bounty_id;
    RAISE NOTICE 'Participant count BEFORE join: %', v_count_before;

    -- Join the bounty
    SELECT join_bounty(v_test_bounty_id, v_test_wallet) INTO v_participant_id;

    RAISE NOTICE 'User joined successfully. Participant ID: %', v_participant_id;

    -- Get count after join
    SELECT participant_count INTO v_count_after
    FROM bounties
    WHERE id = v_test_bounty_id;

    RAISE NOTICE 'Participant count AFTER join: %', v_count_after;

    -- Verify increment
    IF v_count_after = v_count_before + 1 THEN
        RAISE NOTICE '✓ SUCCESS: Count incremented by exactly 1 (% → %)', v_count_before, v_count_after;
    ELSIF v_count_after = v_count_before + 2 THEN
        RAISE EXCEPTION '✗ FAIL: Count incremented by 2 (% → %). Double-increment bug still exists!', v_count_before, v_count_after;
    ELSE
        RAISE WARNING '? UNEXPECTED: Count changed from % to % (difference: %)', v_count_before, v_count_after, v_count_after - v_count_before;
    END IF;
END $$;

-- ============================================================================
-- TEST 2: Multiple Users Join - Verify Linear Increment
-- ============================================================================

DO $$
DECLARE
    v_test_bounty_id UUID;
    v_test_wallet TEXT;
    v_participant_id UUID;
    v_expected_count INTEGER;
    v_actual_count INTEGER;
    i INTEGER;
BEGIN
    -- Get the test bounty
    SELECT id INTO v_test_bounty_id
    FROM bounties
    WHERE name = 'TEST: Single Increment Bounty'
    ORDER BY created_at DESC
    LIMIT 1;

    -- Get current count
    SELECT participant_count INTO v_expected_count
    FROM bounties
    WHERE id = v_test_bounty_id;

    RAISE NOTICE 'Starting count: %', v_expected_count;

    -- Add 5 more users
    FOR i IN 1..5 LOOP
        v_test_wallet := '0.0.99999' || i::TEXT;
        v_expected_count := v_expected_count + 1;

        -- Join bounty
        SELECT join_bounty(v_test_bounty_id, v_test_wallet) INTO v_participant_id;

        -- Check count
        SELECT participant_count INTO v_actual_count
        FROM bounties
        WHERE id = v_test_bounty_id;

        IF v_actual_count != v_expected_count THEN
            RAISE EXCEPTION '✗ FAIL at user %: Expected %, got %', i, v_expected_count, v_actual_count;
        END IF;

        RAISE NOTICE 'User % joined. Count: % (expected: %) ✓', i, v_actual_count, v_expected_count;
    END LOOP;

    RAISE NOTICE '✓ SUCCESS: All 5 users joined with correct single increments';
END $$;

-- ============================================================================
-- TEST 3: Verify Stored Count Matches Actual Participants
-- ============================================================================

SELECT
    b.id,
    b.name,
    b.participant_count as stored_count,
    COUNT(bp.id) as actual_participants,
    CASE
        WHEN b.participant_count = COUNT(bp.id) THEN '✓ MATCH'
        ELSE '✗ MISMATCH'
    END as status
FROM bounties b
LEFT JOIN bounty_participants bp ON b.id = bp.bounty_id
WHERE b.name = 'TEST: Single Increment Bounty'
GROUP BY b.id, b.name, b.participant_count;

-- Expected: status = '✓ MATCH'

-- ============================================================================
-- TEST 4: Cleanup Test Data (Optional)
-- ============================================================================

-- Remove test bounty and participants
/*
DELETE FROM bounty_participants
WHERE bounty_id IN (
    SELECT id FROM bounties WHERE name = 'TEST: Single Increment Bounty'
);

DELETE FROM bounties
WHERE name = 'TEST: Single Increment Bounty';
*/

-- ============================================================================
-- RECALCULATION QUERY: Fix Existing Double-Counted Bounties
-- ============================================================================
-- IMPORTANT: Run this ONLY AFTER verifying the fix works (tests above pass)
-- This will correct all existing bounties that have incorrect counts
-- ============================================================================

-- Step 1: PREVIEW what will be corrected (SAFE - doesn't modify data)

WITH correct_counts AS (
    SELECT
        b.id as bounty_id,
        b.name,
        b.participant_count as current_stored_count,
        COUNT(bp.id) as correct_count,
        b.participant_count - COUNT(bp.id) as difference
    FROM bounties b
    LEFT JOIN bounty_participants bp ON b.id = bp.bounty_id
    GROUP BY b.id, b.name, b.participant_count
    HAVING b.participant_count != COUNT(bp.id)
)
SELECT
    bounty_id,
    name,
    current_stored_count,
    correct_count,
    difference,
    CASE
        WHEN difference = correct_count THEN 'Likely doubled (2x actual)'
        WHEN difference > 0 THEN 'Over-counted'
        ELSE 'Under-counted'
    END as issue_type
FROM correct_counts
ORDER BY ABS(difference) DESC;

-- Review this output carefully before proceeding to Step 2

-- ============================================================================
-- Step 2: RECALCULATE AND UPDATE (MODIFIES DATA - use with caution!)
-- ============================================================================
-- This query will fix all bounties with incorrect participant counts

DO $$
DECLARE
    v_bounty RECORD;
    v_corrected_count INTEGER := 0;
    v_total_difference INTEGER := 0;
BEGIN
    RAISE NOTICE 'Starting participant count recalculation...';

    FOR v_bounty IN
        SELECT
            b.id,
            b.name,
            b.participant_count as old_count,
            COUNT(bp.id) as correct_count
        FROM bounties b
        LEFT JOIN bounty_participants bp ON b.id = bp.bounty_id
        GROUP BY b.id, b.name, b.participant_count
        HAVING b.participant_count != COUNT(bp.id)
    LOOP
        -- Update the bounty with correct count
        UPDATE bounties
        SET
            participant_count = v_bounty.correct_count,
            updated_at = NOW()
        WHERE id = v_bounty.id;

        v_corrected_count := v_corrected_count + 1;
        v_total_difference := v_total_difference + (v_bounty.old_count - v_bounty.correct_count);

        RAISE NOTICE 'Fixed bounty "%": % → % (difference: %)',
            v_bounty.name,
            v_bounty.old_count,
            v_bounty.correct_count,
            v_bounty.old_count - v_bounty.correct_count;
    END LOOP;

    IF v_corrected_count = 0 THEN
        RAISE NOTICE '✓ No bounties needed correction. All counts are accurate.';
    ELSE
        RAISE NOTICE '✓ Recalculation complete: % bounties corrected, total difference: %',
            v_corrected_count, v_total_difference;
    END IF;
END $$;

-- ============================================================================
-- Step 3: VERIFY recalculation worked
-- ============================================================================

SELECT
    COUNT(*) as total_bounties,
    COUNT(CASE WHEN b.participant_count = COALESCE(participant_actual.count, 0) THEN 1 END) as correct_count_bounties,
    COUNT(CASE WHEN b.participant_count != COALESCE(participant_actual.count, 0) THEN 1 END) as incorrect_count_bounties,
    ROUND(100.0 * COUNT(CASE WHEN b.participant_count = COALESCE(participant_actual.count, 0) THEN 1 END) / COUNT(*), 2) as accuracy_percentage
FROM bounties b
LEFT JOIN (
    SELECT bounty_id, COUNT(*) as count
    FROM bounty_participants
    GROUP BY bounty_id
) participant_actual ON b.id = participant_actual.bounty_id;

-- Expected: accuracy_percentage = 100.00

-- ============================================================================
-- ADDITIONAL MONITORING QUERIES
-- ============================================================================

-- Query 1: Check for any remaining mismatches
SELECT
    b.id,
    b.name,
    b.status,
    b.participant_count as stored,
    COUNT(bp.id) as actual,
    b.participant_count - COUNT(bp.id) as difference
FROM bounties b
LEFT JOIN bounty_participants bp ON b.id = bp.bounty_id
GROUP BY b.id
HAVING b.participant_count != COUNT(bp.id);

-- Expected: 0 rows (all counts match)

-- Query 2: Verify trigger is working for new joins
SELECT
    tgname,
    tgenabled,
    tgisinternal,
    pg_get_triggerdef(oid) as definition
FROM pg_trigger
WHERE tgrelid = 'bounty_participants'::regclass
  AND tgname LIKE '%participant%';

-- Expected: auto_increment_participant_count and auto_decrement_participant_count both enabled

-- Query 3: Check recent bounty joins
-- NOTE: bounty_participants uses 'joined_at' not 'created_at'
SELECT
    b.name,
    b.participant_count,
    bp.joined_at as last_join,
    COUNT(bp.id) as total_participants
FROM bounties b
JOIN bounty_participants bp ON b.id = bp.bounty_id
WHERE bp.joined_at >= NOW() - INTERVAL '1 hour'
GROUP BY b.id, b.name, b.participant_count, bp.joined_at
ORDER BY bp.joined_at DESC
LIMIT 10;

-- Verify participant_count matches COUNT(bp.id) for recent joins

-- ============================================================================
-- SUMMARY CHECKLIST
-- ============================================================================
-- After running all tests, verify:
--
-- ✓ Migration 021 applied successfully
-- ✓ join_bounty() function no longer has manual UPDATE
-- ✓ Trigger auto_increment_participant_count is active
-- ✓ Test bounty increments by exactly 1 per join (not 2)
-- ✓ Multiple joins increment linearly (5 joins = +5 count)
-- ✓ Stored count matches actual participant count
-- ✓ Existing bounties recalculated (if needed)
-- ✓ No mismatches remain in database
-- ✓ New joins work correctly going forward
--
-- If all tests pass, proceed to PHASE 4!
-- ============================================================================
