-- ============================================================================
-- PHASE 2: TESTING GUIDE
-- Step-by-step queries to test winner determination functions
-- ============================================================================
-- Run these queries in your Supabase SQL Editor after running migration 020
-- ============================================================================

-- ============================================================================
-- STEP 1: VERIFY MIGRATION SUCCESS
-- ============================================================================
-- Check that all functions were created successfully

SELECT
    proname as function_name,
    pronargs as argument_count,
    prorettype::regtype as return_type
FROM pg_proc
WHERE proname IN (
    'determine_bounty_winner',
    'complete_bounty_with_winners',
    'mark_prize_paid',
    'auto_complete_first_to_solve_trigger',
    'get_bounty_winner_summary'
)
AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
ORDER BY proname;

-- Expected: 5 rows (all functions exist)

-- ============================================================================
-- STEP 2: VERIFY TRIGGER WAS CREATED
-- ============================================================================

SELECT
    tgname as trigger_name,
    tgrelid::regclass as table_name,
    tgenabled as enabled,
    pg_get_triggerdef(oid) as trigger_definition
FROM pg_trigger
WHERE tgname = 'auto_complete_first_to_solve';

-- Expected: 1 row showing trigger on bounty_participants table

-- ============================================================================
-- STEP 3: FIND A COMPLETED BOUNTY TO TEST WITH
-- ============================================================================

SELECT
    b.id,
    b.name,
    b.status,
    b.winner_criteria,
    b.prize_distribution,
    b.prize_amount,
    COUNT(bp.id) as total_participants,
    COUNT(CASE WHEN bp.status = 'completed' THEN 1 END) as completed_participants,
    COUNT(CASE WHEN bp.is_winner = true THEN 1 END) as existing_winners
FROM bounties b
LEFT JOIN bounty_participants bp ON b.id = bp.bounty_id
WHERE b.status = 'completed'
GROUP BY b.id
ORDER BY b.updated_at DESC
LIMIT 10;

-- Pick a bounty with completed_participants > 0 and existing_winners = 0
-- Copy its ID for testing below

-- ============================================================================
-- TEST 1: Test determine_bounty_winner() Function
-- ============================================================================
-- Replace 'your-bounty-uuid-here' with an actual bounty ID from above

SELECT
    user_id,
    prize_share,
    ranking,
    metric_value
FROM determine_bounty_winner('your-bounty-uuid-here');

-- Expected: Returns 1-3 rows (depending on prize_distribution)
-- Verify:
-- - user_id is valid UUID
-- - prize_share equals total prize (or split if split-winners)
-- - ranking is 1, 2, 3 (sequential)
-- - metric_value matches the winner_criteria (time, attempts, or words_completed)

-- ============================================================================
-- TEST 2: Check Participant Details Before Completion
-- ============================================================================
-- See the current state before we mark winners

SELECT
    bp.user_id,
    bp.status,
    bp.is_winner,
    bp.prize_amount_won,
    bp.total_attempts,
    bp.total_time_seconds,
    bp.words_completed,
    u.username,
    u.total_bounties_won as user_current_wins,
    u.total_hbar_earned as user_current_earnings
FROM bounty_participants bp
JOIN users u ON bp.user_id = u.id
WHERE bp.bounty_id = 'your-bounty-uuid-here'
  AND bp.status = 'completed'
ORDER BY
    CASE
        WHEN (SELECT winner_criteria FROM bounties WHERE id = 'your-bounty-uuid-here') = 'time'
        THEN bp.total_time_seconds
        ELSE bp.total_attempts::DECIMAL
    END ASC;

-- Note the current values - we'll verify they change after completion

-- ============================================================================
-- TEST 3: Run complete_bounty_with_winners()
-- ============================================================================
-- This is the main function that marks all winners

SELECT
    winner_user_id,
    prize_awarded,
    winner_rank
FROM complete_bounty_with_winners('your-bounty-uuid-here');

-- Expected: Returns 1-3 rows with winner details
-- Check:
-- - winner_user_id matches expected winner from determine_bounty_winner()
-- - prize_awarded equals expected amount
-- - winner_rank is sequential (1, 2, 3)

-- ============================================================================
-- TEST 4: Verify Winners Were Marked Correctly
-- ============================================================================
-- Check that bounty_participants table was updated

SELECT
    bp.user_id,
    bp.status,
    bp.is_winner,
    bp.prize_amount_won,
    bp.prize_paid_at,
    bp.prize_transaction_hash,
    bp.total_attempts,
    bp.total_time_seconds,
    bp.words_completed,
    u.username,
    u.total_bounties_won,
    u.total_hbar_earned
FROM bounty_participants bp
JOIN users u ON bp.user_id = u.id
WHERE bp.bounty_id = 'your-bounty-uuid-here'
  AND bp.is_winner = true;

-- Verify:
-- ✓ is_winner = true
-- ✓ prize_amount_won > 0
-- ✓ User's total_bounties_won increased by 1
-- ✓ User's total_hbar_earned increased by prize_amount_won

-- ============================================================================
-- TEST 5: Verify Bounty Status Updated
-- ============================================================================

SELECT
    id,
    name,
    status,
    completion_count,
    updated_at
FROM bounties
WHERE id = 'your-bounty-uuid-here';

-- Verify:
-- ✓ status = 'completed'
-- ✓ completion_count increased
-- ✓ updated_at is recent

-- ============================================================================
-- TEST 6: Try Duplicate Completion (Should Be Prevented)
-- ============================================================================
-- Run complete_bounty_with_winners() again on the same bounty

SELECT
    winner_user_id,
    prize_awarded,
    winner_rank
FROM complete_bounty_with_winners('your-bounty-uuid-here');

-- Expected: Returns existing winners (no duplicates)
-- Check Postgres logs for WARNING message about duplicate completion

-- Verify no duplicate prizes were awarded:
SELECT
    u.id,
    u.username,
    u.total_bounties_won,
    u.total_hbar_earned,
    COUNT(bp.id) as wins_in_this_bounty
FROM users u
JOIN bounty_participants bp ON u.id = bp.user_id
WHERE bp.bounty_id = 'your-bounty-uuid-here'
  AND bp.is_winner = true
GROUP BY u.id;

-- wins_in_this_bounty should be 1 for each user (not 2)

-- ============================================================================
-- TEST 7: Test mark_prize_paid() Function
-- ============================================================================
-- Simulate recording a blockchain payment

-- First, get a winner's user_id from the bounty
SELECT user_id
FROM bounty_participants
WHERE bounty_id = 'your-bounty-uuid-here'
  AND is_winner = true
LIMIT 1;

-- Call mark_prize_paid() with a test transaction hash
SELECT mark_prize_paid(
    'your-bounty-uuid-here',
    'winner-user-id-from-above',
    '0x1234567890abcdef1234567890abcdef12345678'
);

-- Verify payment was recorded:
SELECT
    user_id,
    prize_amount_won,
    prize_paid_at,
    prize_transaction_hash
FROM bounty_participants
WHERE bounty_id = 'your-bounty-uuid-here'
  AND user_id = 'winner-user-id-from-above';

-- Verify:
-- ✓ prize_paid_at is set (NOT NULL)
-- ✓ prize_transaction_hash matches the hash we provided

-- ============================================================================
-- TEST 8: Test get_bounty_winner_summary() Helper Function
-- ============================================================================

SELECT
    bounty_name,
    bounty_status,
    winner_criteria,
    prize_distribution,
    total_prize,
    winner_count,
    total_distributed,
    winners
FROM get_bounty_winner_summary('your-bounty-uuid-here');

-- Verify:
-- ✓ winner_count matches number of winners
-- ✓ total_distributed matches sum of prizes awarded
-- ✓ winners JSONB contains all winner details
-- ✓ Each winner has proper fields (user_id, prize_amount, etc.)

-- ============================================================================
-- TEST 9: Test Different Winner Criteria Types
-- ============================================================================

-- Test TIME-based winner
SELECT * FROM determine_bounty_winner(
    (SELECT id FROM bounties WHERE winner_criteria = 'time' LIMIT 1)
);

-- Test ATTEMPTS-based winner
SELECT * FROM determine_bounty_winner(
    (SELECT id FROM bounties WHERE winner_criteria = 'attempts' LIMIT 1)
);

-- Test WORDS-CORRECT-based winner
SELECT * FROM determine_bounty_winner(
    (SELECT id FROM bounties WHERE winner_criteria = 'words-correct' LIMIT 1)
);

-- Test FIRST-TO-SOLVE winner
SELECT * FROM determine_bounty_winner(
    (SELECT id FROM bounties WHERE winner_criteria = 'first-to-solve' LIMIT 1)
);

-- Verify each returns appropriate winner based on criteria

-- ============================================================================
-- TEST 10: Test Split-Winners Prize Distribution
-- ============================================================================

-- Find a bounty with split-winners and multiple completions
SELECT
    b.id,
    b.name,
    b.prize_distribution,
    b.prize_amount,
    COUNT(bp.id) as completed_count
FROM bounties b
JOIN bounty_participants bp ON b.id = bp.bounty_id
WHERE b.prize_distribution = 'split-winners'
  AND bp.status = 'completed'
  AND b.status != 'completed'  -- Not yet completed
GROUP BY b.id
HAVING COUNT(bp.id) >= 3  -- At least 3 completions
LIMIT 1;

-- Complete this bounty
SELECT * FROM complete_bounty_with_winners('split-winners-bounty-id');

-- Verify prizes were split correctly
SELECT
    user_id,
    prize_amount_won,
    ROUND(prize_amount_won * 3, 8) as verify_equals_total_prize
FROM bounty_participants
WHERE bounty_id = 'split-winners-bounty-id'
  AND is_winner = true;

-- All three verify_equals_total_prize should be the same value (the total prize)

-- ============================================================================
-- TEST 11: Test Auto-Complete Trigger for First-to-Solve
-- ============================================================================
-- This test requires creating a test bounty and having a user complete it

-- Step 1: Create a first-to-solve test bounty (use your frontend or SQL)
-- Step 2: Have a user join and complete it
-- Step 3: Watch for automatic completion

-- Check if trigger fired:
SELECT
    b.id,
    b.name,
    b.status,
    b.winner_criteria,
    COUNT(CASE WHEN bp.is_winner = true THEN 1 END) as winners_marked
FROM bounties b
JOIN bounty_participants bp ON b.id = bp.bounty_id
WHERE b.winner_criteria = 'first-to-solve'
  AND b.status = 'completed'
  AND b.updated_at >= NOW() - INTERVAL '1 hour'
GROUP BY b.id;

-- If winners_marked > 0, the trigger worked!

-- ============================================================================
-- TEST 12: Error Handling Tests
-- ============================================================================

-- Test with invalid bounty UUID (should raise exception)
SELECT * FROM determine_bounty_winner('00000000-0000-0000-0000-000000000000');
-- Expected: ERROR: Bounty not found

-- Test marking prize paid for non-existent user (should raise exception)
SELECT mark_prize_paid(
    'valid-bounty-id',
    '00000000-0000-0000-0000-000000000000',
    '0xtest'
);
-- Expected: ERROR: Participant not found

-- Test marking prize paid for non-winner (should raise exception)
-- First find a non-winner participant
SELECT user_id FROM bounty_participants
WHERE bounty_id = 'your-bounty-uuid-here'
  AND is_winner = false
LIMIT 1;

SELECT mark_prize_paid('your-bounty-uuid-here', 'non-winner-user-id', '0xtest');
-- Expected: ERROR: User is not marked as a winner

-- ============================================================================
-- CLEANUP (OPTIONAL)
-- ============================================================================
-- If you want to reset test data to test again

-- WARNING: This will remove winner markings - only use in staging/testing!
/*
UPDATE bounty_participants
SET
    is_winner = false,
    prize_amount_won = 0,
    prize_paid_at = NULL,
    prize_transaction_hash = NULL
WHERE bounty_id = 'your-test-bounty-id';

UPDATE bounties
SET status = 'active'
WHERE id = 'your-test-bounty-id';
*/

-- ============================================================================
-- SUMMARY CHECKLIST
-- ============================================================================
-- After running all tests, verify:
--
-- ✓ All 5 functions created successfully
-- ✓ Trigger created and enabled
-- ✓ determine_bounty_winner() returns correct winners for all 4 criteria
-- ✓ complete_bounty_with_winners() marks winners and updates all tables
-- ✓ mark_prize_paid() records payment details
-- ✓ Duplicate completion is prevented
-- ✓ Split-winners prize distribution works correctly
-- ✓ User statistics update correctly
-- ✓ Auto-complete trigger fires for first-to-solve
-- ✓ Error handling works as expected
-- ✓ get_bounty_winner_summary() returns proper JSONB data
--
-- If all tests pass, proceed to PHASE 3!
-- ============================================================================
