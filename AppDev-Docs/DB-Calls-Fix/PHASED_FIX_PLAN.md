# DATABASE FIX - PHASED IMPLEMENTATION PLAN
## Winner Marking & Data Integrity Restoration

**Created:** 2025-10-07
**Status:** READY FOR EXECUTION
**Total Phases:** 6
**Estimated Timeline:** 5-7 days

---

## OVERVIEW

This document outlines a comprehensive, phased approach to fix the critical data integrity issues in the Wordle Bounty Game database. The primary issue is that the `complete_bounty()` function exists but is never called, resulting in winner data never being recorded.

### Critical Issues Being Fixed:
1. ❌ `is_winner` stays FALSE even after marking winners
2. ❌ `prize_amount_won` remains 0.000
3. ❌ `prize_paid_at` and `prize_transaction_hash` stay NULL
4. ❌ No automatic winner determination logic exists
5. ❌ Participant count increments twice (double-counting)

---

## PHASE 1: FOUNDATION & UNDERSTANDING
### Objective: Verify audit findings and prepare environment

**Duration:** 1 day
**Risk Level:** LOW
**Can be rolled back:** YES

### Tasks:
1. ✅ Review audit documents (DATABASE_AUDIT_REPORT.md & EXECUTIVE_SUMMARY)
2. ✅ Run diagnostic queries to confirm issues
3. ✅ Back up current database state
4. ✅ Set up test environment (staging database)
5. ✅ Document current data state for comparison

### Diagnostic Queries to Run:

```sql
-- Query 1: Find completed bounties with no winners marked
SELECT
  b.id,
  b.name,
  b.status,
  COUNT(CASE WHEN bp.status = 'completed' THEN 1 END) as completed_participants,
  COUNT(CASE WHEN bp.is_winner = true THEN 1 END) as marked_winners
FROM bounties b
LEFT JOIN bounty_participants bp ON b.id = bp.bounty_id
WHERE b.status = 'completed'
GROUP BY b.id
HAVING COUNT(CASE WHEN bp.is_winner = true THEN 1 END) = 0;

-- Query 2: Check participant prize fields
SELECT
  bp.id,
  bp.status,
  bp.is_winner,
  bp.prize_amount_won,
  bp.prize_paid_at,
  bp.prize_transaction_hash,
  b.name as bounty_name
FROM bounty_participants bp
JOIN bounties b ON bp.bounty_id = b.id
WHERE bp.status = 'completed';

-- Query 3: Verify complete_bounty() function exists
SELECT
  proname as function_name,
  pg_get_functiondef(oid) as definition
FROM pg_proc
WHERE proname = 'complete_bounty';
```

### Success Criteria:
- [ ] Audit documents reviewed and understood
- [ ] Database backup completed
- [ ] Diagnostic queries run and results documented
- [ ] Test environment ready
- [ ] Team aligned on fix approach

### 🎯 PROMPT FOR PHASE 1:

```
EXECUTE PHASE 1: Foundation & Understanding

Review the database audit findings and run all diagnostic queries listed in PHASE 1 of the PHASED_FIX_PLAN.md document.

Tasks:
1. Execute all three diagnostic queries and show me the results
2. Verify that the complete_bounty() function exists
3. Confirm the exact issues with real data examples
4. Provide a summary of what you found

DO NOT make any changes yet - this is investigation only.
```

---

## PHASE 2: CREATE WINNER DETERMINATION LOGIC
### Objective: Build automatic winner detection and marking system

**Duration:** 2 days
**Risk Level:** MEDIUM
**Can be rolled back:** YES

### Tasks:
1. Create migration `020_winner_determination.sql`
2. Implement `determine_bounty_winner(bounty_uuid)` function
3. Implement `complete_bounty_with_winners(bounty_uuid)` function
4. Implement `mark_prize_paid(bounty_uuid, user_uuid, tx_hash)` function
5. Create trigger for 'first-to-solve' auto-completion
6. Test all winner criteria types (time, attempts, words-correct, first-to-solve)

### Key Functions to Create:

#### Function 1: `determine_bounty_winner(bounty_uuid UUID)`
**Purpose:** Analyzes all participants and determines winner(s) based on winner_criteria

**Logic:**
- For `winner_criteria = 'first-to-solve'`: First person to complete
- For `winner_criteria = 'time'`: Fastest total_time_seconds
- For `winner_criteria = 'attempts'`: Fewest total_attempts
- For `winner_criteria = 'words-correct'`: Most words_completed

**Returns:** TABLE(user_id UUID, prize_share DECIMAL)

#### Function 2: `complete_bounty_with_winners(bounty_uuid UUID)`
**Purpose:** Orchestrates winner marking and prize distribution

**Logic:**
1. Call `determine_bounty_winner(bounty_uuid)`
2. For each winner: Call existing `complete_bounty(bounty_uuid, winner_id, prize_share)`
3. Handle prize splitting for 'split-winners' prize_distribution
4. Update bounty status to 'completed'

#### Function 3: `mark_prize_paid(bounty_uuid UUID, user_uuid UUID, tx_hash VARCHAR)`
**Purpose:** Records blockchain payment details

**Updates:**
- `prize_paid_at = NOW()`
- `prize_transaction_hash = tx_hash`

#### Trigger: `auto_complete_first_to_solve`
**Purpose:** Automatically completes bounty when first person solves (for first-to-solve criteria)

**Logic:**
```sql
CREATE OR REPLACE FUNCTION auto_complete_first_to_solve_trigger()
RETURNS TRIGGER AS $$
DECLARE
  v_winner_criteria winner_criteria;
  v_prize_distribution prize_distribution;
BEGIN
  -- Only for first completion of a bounty
  SELECT winner_criteria, prize_distribution INTO v_winner_criteria, v_prize_distribution
  FROM bounties
  WHERE id = NEW.bounty_id;

  -- If first-to-solve and prize is winner-take-all
  IF v_winner_criteria = 'first-to-solve'
     AND v_prize_distribution = 'winner-take-all'
     AND NEW.status = 'completed' THEN

    -- Check if this is the first completion
    IF NOT EXISTS (
      SELECT 1 FROM bounty_participants
      WHERE bounty_id = NEW.bounty_id
      AND status = 'completed'
      AND id != NEW.id
    ) THEN
      -- Auto-complete bounty with this winner
      PERFORM complete_bounty_with_winners(NEW.bounty_id);
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
```

### Testing Scenarios:
- [ ] First-to-solve with single winner
- [ ] Time-based with fastest time
- [ ] Attempts-based with fewest attempts
- [ ] Words-correct with most words
- [ ] Split-winners prize distribution
- [ ] Multiple participants completing at same time

### Success Criteria:
- [ ] Migration 020 created and tested in staging
- [ ] All 4 winner criteria types work correctly
- [ ] Prize splitting works for multi-winner scenarios
- [ ] First-to-solve triggers automatically
- [ ] No errors in PostgreSQL logs
- [ ] Existing data not corrupted

### 🎯 PROMPT FOR PHASE 2:

```
EXECUTE PHASE 2: Create Winner Determination Logic

Create migration file 020_winner_determination.sql with all the functions described in PHASE 2 of PHASED_FIX_PLAN.md.

Requirements:
1. Create determine_bounty_winner() function that handles all 4 winner criteria
2. Create complete_bounty_with_winners() function that orchestrates the process
3. Create mark_prize_paid() function for blockchain payment tracking
4. Create auto_complete_first_to_solve trigger
5. Add all necessary error handling and logging
6. Include GRANT statements for authenticated and anon users

Test each function independently before integration. Show me the complete migration file and explain how each function works.
```

---

## PHASE 3: FIX DOUBLE-INCREMENT BUG
### Objective: Prevent participant_count from incrementing twice

**Duration:** 0.5 days
**Risk Level:** LOW
**Can be rolled back:** YES

### Issue:
The `join_bounty()` function manually increments `participant_count`, but there's also a trigger (from migration 015) that auto-increments it. This causes double-counting.

### Solution:
Create migration `021_fix_join_bounty.sql` that removes the manual increment from `join_bounty()`.

### Code Changes:

**BEFORE (Current join_bounty):**
```sql
-- Manual increment (WRONG - causes double count)
UPDATE bounties
SET participant_count = participant_count + 1
WHERE id = bounty_uuid;
```

**AFTER (Fixed join_bounty):**
```sql
-- Let trigger handle it automatically
-- (Remove the manual increment entirely)
```

### Testing:
```sql
-- Test: Join a bounty and verify count increments only once
SELECT participant_count FROM bounties WHERE id = 'test-bounty-id';
-- Should be N before join

INSERT INTO bounty_participants (...);
-- Via join_bounty()

SELECT participant_count FROM bounties WHERE id = 'test-bounty-id';
-- Should be N+1 after join (not N+2)
```

### Success Criteria:
- [ ] join_bounty() function updated
- [ ] Participant count increments exactly once per join
- [ ] Existing counts can be recalculated if needed
- [ ] No regression in join functionality

### 🎯 PROMPT FOR PHASE 3:

```
EXECUTE PHASE 3: Fix Double-Increment Bug

Create migration file 021_fix_join_bounty.sql that removes the manual participant_count increment from the join_bounty() function.

Requirements:
1. Read the current join_bounty() function
2. Remove the manual UPDATE statement for participant_count
3. Keep the trigger from migration 015 active (it handles the increment)
4. Test that participant_count increments exactly once
5. Provide a query to recalculate existing counts if needed

Show me the migration file and test queries.
```

---

## PHASE 4: APPLICATION CODE INTEGRATION
### Objective: Update application to use new database functions

**Duration:** 1 day
**Risk Level:** MEDIUM
**Can be rolled back:** YES

### Files to Update:

#### 1. `CompleteBountyModal.tsx`
**Current Flow:**
```typescript
// Manually calls complete_bounty() on smart contract
// Then manually updates Supabase tables
```

**New Flow:**
```typescript
// After smart contract completion:
1. Call complete_bounty_with_winners(bounty_uuid)
   - This marks all winners automatically
   - Updates all prize fields
   - Updates user stats

2. Call mark_prize_paid(bounty_uuid, winner_uuid, tx_hash)
   - Records blockchain transaction details
```

#### 2. `submit_attempt()` Trigger Integration
**Change:** Add call to check for auto-completion after each successful attempt

**For 'first-to-solve' bounties:**
- Trigger already handles this
- No application code change needed

**For time-based/attempts-based/words-correct:**
- Admin manually completes via CompleteBountyModal
- Modal calls `complete_bounty_with_winners()`

#### 3. Add Expiration Processor (Optional but Recommended)
**New Function:** `process_expired_bounties()`

```typescript
// Cron job or scheduled task
async function processExpiredBounties() {
  const { data } = await supabase.rpc('process_expired_bounties');
  // Returns list of auto-completed bounties
}
```

### Testing Checklist:
- [ ] Complete a bounty via admin modal - verify winner marked
- [ ] Join a bounty - verify count increments once
- [ ] Submit winning attempt - verify status updates
- [ ] Test first-to-solve auto-completion
- [ ] Test prize payment recording
- [ ] Verify all data fields populate correctly

### Success Criteria:
- [ ] CompleteBountyModal uses new functions
- [ ] No duplicate participant counts
- [ ] Winners marked automatically
- [ ] Prize payment tracked properly
- [ ] All existing features still work
- [ ] No console errors

### 🎯 PROMPT FOR PHASE 4:

```
EXECUTE PHASE 4: Application Code Integration

Update the application code to use the new database functions from Phase 2 and Phase 3.

Tasks:
1. Update CompleteBountyModal.tsx to call complete_bounty_with_winners()
2. Update CompleteBountyModal.tsx to call mark_prize_paid() after blockchain payment
3. Verify that submit_attempt trigger works for first-to-solve
4. Test the entire bounty lifecycle end-to-end
5. Check for any errors or regressions

Show me the updated CompleteBountyModal.tsx file and explain the changes made.
```

---

## PHASE 5: DATA CLEANUP & BACKFILL
### Objective: Fix historical data with missing winner information

**Duration:** 1 day
**Risk Level:** MEDIUM
**Can be rolled back:** Partial

### Issue:
Existing completed bounties in the database have no winners marked due to the bug.

### Solution:
Create migration `022_data_cleanup.sql` with cleanup queries.

### Cleanup Queries:

#### Query 1: Identify Affected Bounties
```sql
-- Find completed bounties with participants but no winners
CREATE TEMP TABLE affected_bounties AS
SELECT
  b.id as bounty_id,
  b.name,
  b.winner_criteria,
  b.prize_distribution,
  b.prize_amount
FROM bounties b
WHERE b.status = 'completed'
  AND EXISTS (
    SELECT 1 FROM bounty_participants bp
    WHERE bp.bounty_id = b.id AND bp.status = 'completed'
  )
  AND NOT EXISTS (
    SELECT 1 FROM bounty_participants bp
    WHERE bp.bounty_id = b.id AND bp.is_winner = true
  );
```

#### Query 2: Retroactively Mark Winners
```sql
-- For each affected bounty, determine and mark winners
DO $$
DECLARE
  v_bounty RECORD;
BEGIN
  FOR v_bounty IN SELECT * FROM affected_bounties LOOP
    -- Use the new winner determination function
    PERFORM complete_bounty_with_winners(v_bounty.bounty_id);

    RAISE NOTICE 'Fixed bounty: % (ID: %)', v_bounty.name, v_bounty.bounty_id;
  END LOOP;
END $$;
```

#### Query 3: Recalculate User Statistics
```sql
-- Update total_bounties_won and total_hbar_earned for all users
UPDATE users u
SET
  total_bounties_won = (
    SELECT COUNT(*) FROM bounty_participants
    WHERE user_id = u.id AND is_winner = true
  ),
  total_hbar_earned = (
    SELECT COALESCE(SUM(prize_amount_won), 0)
    FROM bounty_participants
    WHERE user_id = u.id
  ),
  updated_at = NOW()
WHERE EXISTS (
  SELECT 1 FROM bounty_participants bp
  WHERE bp.user_id = u.id AND bp.is_winner = true
);
```

#### Query 4: Verify Cleanup
```sql
-- Verify all completed bounties now have winners
SELECT
  COUNT(*) as remaining_issues
FROM bounties b
WHERE b.status = 'completed'
  AND EXISTS (SELECT 1 FROM bounty_participants WHERE bounty_id = b.id)
  AND NOT EXISTS (SELECT 1 FROM bounty_participants WHERE bounty_id = b.id AND is_winner = true);
-- Should return 0
```

### Safety Measures:
1. Run on staging first
2. Take database snapshot before cleanup
3. Log all changes for audit trail
4. Verify counts match expected values
5. Keep backup of original data

### Success Criteria:
- [ ] All completed bounties have winners marked
- [ ] User statistics recalculated correctly
- [ ] No data lost or corrupted
- [ ] Audit trail maintained
- [ ] Cleanup verified with queries

### 🎯 PROMPT FOR PHASE 5:

```
EXECUTE PHASE 5: Data Cleanup & Backfill

Create migration 022_data_cleanup.sql to retroactively fix historical bounty data.

Tasks:
1. Identify all completed bounties missing winner information
2. Use complete_bounty_with_winners() to retroactively mark winners
3. Recalculate all user statistics (total_bounties_won, total_hbar_earned)
4. Verify that all completed bounties now have winners
5. Create detailed log of all changes made

IMPORTANT: Run this on staging first and show me the results before applying to production.

Show me the migration file and a summary of how many bounties will be affected.
```

---

## PHASE 6: MONITORING & VALIDATION
### Objective: Ensure fixes are working and no regressions

**Duration:** 1 day
**Risk Level:** LOW
**Can be rolled back:** N/A (monitoring only)

### Monitoring Queries:

#### Query 1: Daily Winner Marking Health Check
```sql
-- Run daily to ensure winners are being marked
SELECT
  DATE(b.updated_at) as completion_date,
  COUNT(DISTINCT b.id) as completed_bounties,
  COUNT(DISTINCT CASE WHEN bp.is_winner = true THEN b.id END) as bounties_with_winners,
  ROUND(100.0 * COUNT(DISTINCT CASE WHEN bp.is_winner = true THEN b.id END) / NULLIF(COUNT(DISTINCT b.id), 0), 2) as percentage_marked
FROM bounties b
LEFT JOIN bounty_participants bp ON b.id = bp.bounty_id
WHERE b.status = 'completed'
  AND b.updated_at >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY DATE(b.updated_at)
ORDER BY completion_date DESC;
-- Percentage should be 100%
```

#### Query 2: Participant Count Accuracy
```sql
-- Verify participant counts are accurate
SELECT
  b.id,
  b.name,
  b.participant_count as stored_count,
  COUNT(bp.id) as actual_count,
  CASE
    WHEN b.participant_count = COUNT(bp.id) THEN '✓ OK'
    ELSE '✗ MISMATCH'
  END as status
FROM bounties b
LEFT JOIN bounty_participants bp ON b.id = bp.bounty_id
GROUP BY b.id, b.name, b.participant_count
HAVING b.participant_count != COUNT(bp.id);
-- Should return 0 rows
```

#### Query 3: Prize Payment Tracking
```sql
-- Ensure prize payments are being recorded
SELECT
  COUNT(*) as total_winners,
  COUNT(CASE WHEN prize_paid_at IS NOT NULL THEN 1 END) as prizes_paid,
  COUNT(CASE WHEN prize_transaction_hash IS NOT NULL THEN 1 END) as with_tx_hash,
  ROUND(100.0 * COUNT(CASE WHEN prize_paid_at IS NOT NULL THEN 1 END) / NULLIF(COUNT(*), 0), 2) as payment_rate
FROM bounty_participants
WHERE is_winner = true
  AND completed_at >= CURRENT_DATE - INTERVAL '7 days';
-- Payment rate should be high (>90%)
```

#### Query 4: Function Performance Check
```sql
-- Check function execution times
SELECT
  funcname,
  calls,
  total_time,
  mean_time,
  max_time
FROM pg_stat_user_functions
WHERE funcname IN (
  'determine_bounty_winner',
  'complete_bounty_with_winners',
  'mark_prize_paid',
  'submit_attempt'
)
ORDER BY total_time DESC;
```

### Alerts to Set Up:
1. Alert if any completed bounty has no winner after 1 hour
2. Alert if participant_count mismatches actual count
3. Alert if winner marked but prize_paid_at is NULL after 24 hours
4. Alert if any database function fails
5. Alert if user statistics appear incorrect

### Documentation to Update:
- [ ] Update setup-database.md with new migrations
- [ ] Document winner criteria behavior
- [ ] Update API documentation
- [ ] Create runbook for data integrity checks
- [ ] Document rollback procedures

### Success Criteria:
- [ ] All monitoring queries return healthy results
- [ ] Alerts configured and tested
- [ ] Documentation updated
- [ ] Team trained on new system
- [ ] No data integrity issues detected for 1 week

### 🎯 PROMPT FOR PHASE 6:

```
EXECUTE PHASE 6: Monitoring & Validation

Set up monitoring queries and validate that all fixes are working correctly.

Tasks:
1. Run all 4 monitoring queries and show me the results
2. Check that winners are being marked in real-time
3. Verify participant counts are accurate
4. Confirm prize payments are tracked properly
5. Review function performance metrics

Provide a health report summarizing the current state of the database after all fixes have been applied.
```

---

## ROLLBACK PROCEDURES

### If Phase 2 Needs Rollback:
```sql
-- Remove migration 020
DROP FUNCTION IF EXISTS determine_bounty_winner(UUID);
DROP FUNCTION IF EXISTS complete_bounty_with_winners(UUID);
DROP FUNCTION IF EXISTS mark_prize_paid(UUID, UUID, VARCHAR);
DROP TRIGGER IF EXISTS auto_complete_first_to_solve ON bounty_participants;
DROP FUNCTION IF EXISTS auto_complete_first_to_solve_trigger();
```

### If Phase 3 Needs Rollback:
```sql
-- Restore old join_bounty() function
-- (Re-add manual participant_count increment)
```

### If Phase 5 Needs Rollback:
```sql
-- Restore from database snapshot taken before cleanup
-- Or manually reset affected records to previous state
```

---

## SUCCESS METRICS

### Technical Metrics:
- ✅ 100% of completed bounties have winners marked
- ✅ 0 participant count mismatches
- ✅ >95% of winners have payment details recorded
- ✅ <100ms average function execution time
- ✅ 0 database errors in logs

### Business Metrics:
- ✅ User statistics accurate and updating in real-time
- ✅ Leaderboard reflects actual wins
- ✅ Prize distribution working correctly
- ✅ No user complaints about missing winnings
- ✅ Admin dashboard shows accurate data

---

## RISK ASSESSMENT

| Phase | Risk Level | Impact if Failed | Rollback Ease |
|-------|------------|------------------|---------------|
| Phase 1 | LOW | Minimal - investigation only | N/A |
| Phase 2 | MEDIUM | New functions may have bugs | EASY - drop functions |
| Phase 3 | LOW | Participant counts may be off | EASY - restore old function |
| Phase 4 | MEDIUM | Application errors possible | MEDIUM - revert code changes |
| Phase 5 | MEDIUM | Historical data corruption | HARD - requires snapshot restore |
| Phase 6 | LOW | No direct impact | N/A |

---

## TIMELINE ESTIMATE

```
Week 1:
  Monday:    Phase 1 (Foundation)
  Tuesday:   Phase 2 Part 1 (Core functions)
  Wednesday: Phase 2 Part 2 (Testing)
  Thursday:  Phase 3 (Bug fix)
  Friday:    Phase 4 (Integration)

Week 2:
  Monday:    Phase 5 (Data cleanup)
  Tuesday:   Phase 6 (Monitoring)
  Wed-Fri:   Buffer for issues/refinement
```

**Total: 5-7 business days**

---

## NOTES FOR IMPLEMENTATION

1. **Always test on staging first** - Never run migrations directly on production
2. **Take snapshots before each phase** - Allows quick rollback if needed
3. **Run one phase at a time** - Don't skip ahead even if tempted
4. **Verify each phase completely** - Use the success criteria checklists
5. **Document everything** - Keep notes on what was done and results observed
6. **Communicate with team** - Keep everyone informed of progress and issues

---

## REFERENCES

- DATABASE_AUDIT_REPORT.md - Comprehensive technical analysis
- DATABASE_AUDIT_EXECUTIVE_SUMMARY.md - Quick reference guide
- supabase/migrations/*.sql - All existing migrations
- src/components/CompleteBountyModal.tsx - Bounty completion UI
- src/utils/supabase/api.ts - Database API layer

---

**END OF PHASED FIX PLAN**

*For questions or clarifications, refer to the audit documents or consult with the database auditor.*
