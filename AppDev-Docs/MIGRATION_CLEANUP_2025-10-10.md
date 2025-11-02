# Migration Cleanup - October 10, 2025

## Summary

Consolidated migrations 020-027 into a cleaner structure for fresh database setups.

## What Changed

### Before (Messy)
```
020_winner_determination.sql (BROKEN - type casting issues)
021_fix_join_bounty.sql
021_fix_payment_transaction_status.sql (DUPLICATE NUMBER!)
022_cleanup_draft_bounties.sql
023_fix_complete_bounty_return_type.sql (FAILED FIX ATTEMPT)
024_fix_complete_bounty_proper.sql (FAILED FIX ATTEMPT)
025_diagnostic_and_fix.sql (FAILED FIX ATTEMPT)
026_final_fix_complete_bounty.sql (PARTIAL FIX)
027_fix_determine_bounty_winner_types.sql (FINAL FIX)
```

### After (Clean)
```
020_winner_determination_complete.sql ✅ (consolidated working version)
021_fix_join_bounty.sql ✅
022_fix_payment_transaction_status.sql ✅ (renumbered from 021)
023_cleanup_draft_bounties.sql ✅ (renumbered from 022)
```

### Deprecated (moved to `supabase/migrations/deprecated/`)
- `020_winner_determination.sql` (original broken version)
- `023_fix_complete_bounty_return_type.sql` (failed attempt)
- `024_fix_complete_bounty_proper.sql` (failed attempt)
- `025_diagnostic_and_fix.sql` (failed attempt)
- `026_final_fix_complete_bounty.sql` (partial fix)
- `027_fix_determine_bounty_winner_types.sql` (final fix)

## Fresh Database Setup Instructions

### For New Supabase Project

Run migrations in order:
```bash
# Core schema and features
001_initial_schema.sql
002_rls_policies.sql
003_sample_data.sql
004_payment_functions.sql  # or 004b_payment_functions_fixed.sql
005_fix_user_creation.sql
006_fix_payment_transactions_rls.sql
007_fix_bounty_update_policies.sql
008_fix_bounty_details_function.sql
009_fix_function_overloading.sql
010_fix_leaderboard_materialized_view.sql
011_fix_leaderboard_triggers.sql
012_dictionary_system.sql
013_dictionary_seed.sql
014_update_prize_and_criteria_enums.sql
015_add_participant_count_triggers.sql
016_fix_get_bounty_details_add_words.sql
017_debug_submit_attempt.sql
018_user_stats_function.sql
019_performance_indexes.sql

# Winner determination and fixes (consolidated)
020_winner_determination_complete.sql ✅
021_fix_join_bounty.sql
022_fix_payment_transaction_status.sql
023_cleanup_draft_bounties.sql
```

### For Existing Database (Already Has Migrations 020-027)

**DO NOTHING** - Your database already has the fixes applied. The deprecated migrations were moved to preserve git history, but your database functions are already correct.

To verify:
```sql
-- Should work without errors
SELECT * FROM determine_bounty_winner('YOUR-BOUNTY-UUID');
SELECT * FROM complete_bounty_with_winners('YOUR-BOUNTY-UUID');
```

## What's in 020_winner_determination_complete.sql

This consolidated migration includes:

### 1. `determine_bounty_winner(UUID)`
- Returns: `(user_id, prize_share, ranking, metric_value)`
- Handles all 4 winner criteria: `first-to-solve`, `time`, `attempts`, `words-correct`
- Handles both prize distributions: `winner-take-all`, `split-winners`
- **FIX**: Explicit type casting `INTEGER::DECIMAL(20, 4)` for metric_value

### 2. `complete_bounty_with_winners(UUID)`
- Returns: `(winner_user_id, prize_awarded, winner_rank)`
- Determines winners automatically
- Marks winners in `bounty_participants` table
- Updates user statistics
- **FIX**: Uses `RETURN QUERY` instead of `RETURN NEXT`

### 3. `mark_prize_paid(UUID, UUID, VARCHAR, DECIMAL)`
- Records blockchain payment details
- Logs transaction in `payment_transactions` table

## Technical Details

### Root Cause of SQLSTATE 42804 Error

**Problem 1: Type Mismatch in determine_bounty_winner**
```sql
-- Schema definition (001_initial_schema.sql)
total_time_seconds INTEGER
total_attempts INTEGER
words_completed INTEGER

-- Function return type
metric_value DECIMAL(20, 4)

-- Error: INTEGER doesn't match DECIMAL(20, 4)
```

**Solution:**
```sql
bp.total_time_seconds::DECIMAL(20, 4) AS metric_value
bp.total_attempts::DECIMAL(20, 4) AS metric_value
bp.words_completed::DECIMAL(20, 4) AS metric_value
```

**Problem 2: RETURN NEXT with RETURNS TABLE**
```sql
-- BROKEN (old code)
FOR v_winner_record IN SELECT * FROM determine_bounty_winner(...)
    winner_user_id := v_winner_record.user_id;
    RETURN NEXT;  -- ❌ Causes SQLSTATE 42804
END LOOP;

-- FIXED (new code)
RETURN QUERY
SELECT
    bp.user_id::UUID AS winner_user_id,
    bp.prize_amount_won::DECIMAL(20, 8) AS prize_awarded,
    ROW_NUMBER() OVER (...)::INTEGER AS winner_rank
FROM bounty_participants bp;  -- ✅ Works correctly
```

## Files Updated

### New Files
- `supabase/migrations/020_winner_determination_complete.sql`
- `supabase/migrations/deprecated/README.md`
- `AppDev-Docs/MIGRATION_CLEANUP_2025-10-10.md` (this file)

### Renamed Files
- `021_fix_payment_transaction_status.sql` → `022_fix_payment_transaction_status.sql`
- `022_cleanup_draft_bounties.sql` → `023_cleanup_draft_bounties.sql`

### Moved to Deprecated
- `020_winner_determination.sql`
- `023_fix_complete_bounty_return_type.sql`
- `024_fix_complete_bounty_proper.sql`
- `025_diagnostic_and_fix.sql`
- `026_final_fix_complete_bounty.sql`
- `027_fix_determine_bounty_winner_types.sql`

## Testing

Verify the consolidated migration works:

```sql
-- Test 1: determine_bounty_winner
SELECT * FROM determine_bounty_winner('YOUR-BOUNTY-UUID');
-- Expected: Returns rows with user_id, prize_share, ranking, metric_value

-- Test 2: complete_bounty_with_winners
SELECT * FROM complete_bounty_with_winners('YOUR-BOUNTY-UUID');
-- Expected: Returns rows with winner_user_id, prize_awarded, winner_rank

-- Both should run without SQLSTATE 42804 errors
```

## Lessons Learned

1. ✅ **Check Supabase Dashboard first** when debugging database errors
2. ✅ **Test functions independently** to isolate issues
3. ✅ **Read full error messages** - they contain exact line numbers and SQL statements
4. ✅ **Verify deployed code** instead of assuming migrations worked
5. ✅ **Consolidate migrations** before they become too messy
6. ✅ **Use explicit type casting** when column types don't match return types
7. ✅ **RETURN QUERY > RETURN NEXT** for RETURNS TABLE functions

---

**Cleanup Date**: 2025-10-10
**Status**: ✅ COMPLETE
**Impact**: Fresh setups now need only 23 migrations instead of 27
**Backward Compatible**: Yes - existing databases unaffected
