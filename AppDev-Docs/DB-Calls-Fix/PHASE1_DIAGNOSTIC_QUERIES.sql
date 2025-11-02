-- ============================================================================
-- PHASE 1: DIAGNOSTIC QUERIES
-- Database Integrity Investigation
-- ============================================================================
-- Run these queries in your Supabase SQL Editor to verify the issues
-- before proceeding with fixes.
-- ============================================================================

-- ============================================================================
-- QUERY 1: Find completed bounties with no winners marked
-- ============================================================================
-- Expected: Should return rows if there are completed bounties without winners
-- This is a CRITICAL ISSUE if results are found

SELECT
  b.id,
  b.name,
  b.status,
  b.winner_criteria,
  b.prize_distribution,
  b.prize_amount,
  COUNT(bp.id) as total_participants,
  COUNT(CASE WHEN bp.status = 'completed' THEN 1 END) as completed_participants,
  COUNT(CASE WHEN bp.is_winner = true THEN 1 END) as marked_winners,
  b.created_at,
  b.updated_at
FROM bounties b
LEFT JOIN bounty_participants bp ON b.id = bp.bounty_id
WHERE b.status = 'completed'
GROUP BY b.id, b.name, b.status, b.winner_criteria, b.prize_distribution, b.prize_amount, b.created_at, b.updated_at
HAVING COUNT(CASE WHEN bp.is_winner = true THEN 1 END) = 0
ORDER BY b.updated_at DESC;

-- Interpretation:
-- - If this returns rows: PROBLEM - completed bounties exist without winners
-- - If this returns 0 rows: GOOD - all completed bounties have winners marked

-- ============================================================================
-- QUERY 2: Check participant prize fields for completed participants
-- ============================================================================
-- Expected: Should show that prize fields are NULL/0 for completed participants
-- This confirms the prize distribution is not working

SELECT
  bp.id,
  bp.user_id,
  bp.bounty_id,
  b.name as bounty_name,
  bp.status,
  bp.is_winner,
  bp.prize_amount_won,
  bp.prize_paid_at,
  bp.prize_transaction_hash,
  bp.completed_at,
  bp.total_attempts,
  bp.total_time_seconds,
  bp.words_completed,
  u.wallet_address,
  u.username
FROM bounty_participants bp
JOIN bounties b ON bp.bounty_id = b.id
LEFT JOIN users u ON bp.user_id = u.id
WHERE bp.status = 'completed'
ORDER BY bp.completed_at DESC
LIMIT 20;

-- Interpretation:
-- Look for records where:
-- - status = 'completed' BUT is_winner = false
-- - prize_amount_won = 0.000
-- - prize_paid_at = NULL
-- - prize_transaction_hash = NULL
-- These indicate the winner marking system is not working

-- ============================================================================
-- QUERY 2B: Prize Field Statistics
-- ============================================================================
-- Aggregate view of the prize field problem

SELECT
  COUNT(*) as total_completed_participants,
  COUNT(CASE WHEN is_winner = true THEN 1 END) as marked_as_winner,
  COUNT(CASE WHEN prize_amount_won > 0 THEN 1 END) as with_prize_amount,
  COUNT(CASE WHEN prize_paid_at IS NOT NULL THEN 1 END) as with_prize_paid_at,
  COUNT(CASE WHEN prize_transaction_hash IS NOT NULL THEN 1 END) as with_tx_hash,
  ROUND(100.0 * COUNT(CASE WHEN is_winner = true THEN 1 END) / NULLIF(COUNT(*), 0), 2) as winner_percentage,
  ROUND(100.0 * COUNT(CASE WHEN prize_amount_won > 0 THEN 1 END) / NULLIF(COUNT(*), 0), 2) as prize_amount_percentage
FROM bounty_participants
WHERE status = 'completed';

-- Interpretation:
-- - winner_percentage should be close to 100% (accounting for ties/multiple winners)
-- - If winner_percentage is low (< 50%), the system is not marking winners
-- - If prize_amount_percentage is low, prize distribution is broken

-- ============================================================================
-- QUERY 3: Verify complete_bounty() function exists
-- ============================================================================
-- Expected: Should return 1 row showing the function definition

SELECT
  proname as function_name,
  pronargs as num_arguments,
  prorettype::regtype as return_type,
  prosrc as source_code
FROM pg_proc
WHERE proname = 'complete_bounty'
  AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public');

-- Interpretation:
-- - If 1 row returned: Function EXISTS (good, but may not be called correctly)
-- - If 0 rows returned: Function DOES NOT EXIST (major problem)

-- ============================================================================
-- QUERY 3B: Check for other winner-related functions
-- ============================================================================
-- Check if any of the planned fix functions already exist

SELECT
  proname as function_name,
  pronargs as num_arguments,
  prorettype::regtype as return_type
FROM pg_proc
WHERE proname IN (
  'complete_bounty',
  'complete_bounty_with_winners',
  'determine_bounty_winner',
  'mark_prize_paid',
  'submit_attempt'
)
  AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
ORDER BY proname;

-- Interpretation:
-- Expected results:
-- - complete_bounty: Should EXIST (from early migrations)
-- - submit_attempt: Should EXIST (for gameplay)
-- - complete_bounty_with_winners: Should NOT EXIST (we'll create in Phase 2)
-- - determine_bounty_winner: Should NOT EXIST (we'll create in Phase 2)
-- - mark_prize_paid: Should NOT EXIST (we'll create in Phase 2)

-- ============================================================================
-- QUERY 4: Check for participant count double-increment issue
-- ============================================================================
-- Verify if participant_count matches actual participant count

SELECT
  b.id,
  b.name,
  b.participant_count as stored_count,
  COUNT(bp.id) as actual_count,
  b.participant_count - COUNT(bp.id) as difference,
  CASE
    WHEN b.participant_count = COUNT(bp.id) THEN '✓ OK'
    WHEN b.participant_count > COUNT(bp.id) THEN '✗ OVER-COUNTED'
    ELSE '✗ UNDER-COUNTED'
  END as status
FROM bounties b
LEFT JOIN bounty_participants bp ON b.id = bp.bounty_id
GROUP BY b.id, b.name, b.participant_count
HAVING b.participant_count != COUNT(bp.id)
ORDER BY ABS(b.participant_count - COUNT(bp.id)) DESC;

-- Interpretation:
-- - If rows returned with 'OVER-COUNTED': Confirms double-increment bug
-- - Difference of exactly 2x suggests double counting
-- - If 0 rows: participant counts are accurate

-- ============================================================================
-- QUERY 5: Detailed bounty completion analysis
-- ============================================================================
-- Show which bounties should have winners but don't

SELECT
  b.id,
  b.name,
  b.status,
  b.winner_criteria,
  b.prize_distribution,
  b.prize_amount,
  b.participant_count,
  b.completion_count,
  COUNT(bp.id) as actual_participants,
  COUNT(CASE WHEN bp.status = 'completed' THEN 1 END) as actual_completions,
  COUNT(CASE WHEN bp.is_winner = true THEN 1 END) as winners_marked,
  ARRAY_AGG(
    CASE WHEN bp.status = 'completed'
    THEN bp.user_id::text || ' (attempts: ' || bp.total_attempts || ', time: ' || bp.total_time_seconds || 's)'
    ELSE NULL END
  ) FILTER (WHERE bp.status = 'completed') as completed_by,
  b.created_at,
  b.updated_at
FROM bounties b
LEFT JOIN bounty_participants bp ON b.id = bp.bounty_id
WHERE b.status IN ('completed', 'expired')
GROUP BY b.id
ORDER BY b.updated_at DESC
LIMIT 10;

-- Interpretation:
-- Review the completed_by array to see who completed each bounty
-- Cross-reference with winner criteria to manually verify who SHOULD have won
-- If winners_marked = 0 but completed_by has entries, the system failed

-- ============================================================================
-- QUERY 6: Check for trigger on bounty_participants
-- ============================================================================
-- Verify the trigger for auto-incrementing participant_count exists

SELECT
  tgname as trigger_name,
  tgrelid::regclass as table_name,
  pg_get_triggerdef(oid) as trigger_definition
FROM pg_trigger
WHERE tgrelid = 'bounty_participants'::regclass
  AND tgname LIKE '%participant%';

-- Interpretation:
-- Should show the trigger from migration 015
-- If trigger exists AND join_bounty() also increments, that's the double-count bug

-- ============================================================================
-- SUMMARY CHECKLIST
-- ============================================================================
-- After running all queries, verify:
--
-- ✓ Query 1: Found completed bounties without winners? (YES = problem exists)
-- ✓ Query 2: Prize fields are NULL/0 for completed participants? (YES = problem exists)
-- ✓ Query 2B: Winner percentage is low (< 50%)? (YES = problem exists)
-- ✓ Query 3: complete_bounty() function exists? (YES = good, NO = major issue)
-- ✓ Query 3B: New functions (determine_bounty_winner, etc.) DON'T exist yet? (CORRECT)
-- ✓ Query 4: Participant counts are off by 2x? (YES = double-increment bug confirmed)
-- ✓ Query 5: Can manually identify who should have won? (Use for validation)
-- ✓ Query 6: Trigger exists on bounty_participants? (YES = confirms double-increment if join_bounty also updates)
--
-- If all these confirm the issues, proceed to PHASE 2.
-- ============================================================================
