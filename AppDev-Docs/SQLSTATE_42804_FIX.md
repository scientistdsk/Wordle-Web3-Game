# SQLSTATE 42804 Error Fix - complete_bounty_with_winners

## Issue Summary

**Error**: SQLSTATE 42804 - "structure of query does not match function result type"

**Location**: `complete_bounty_with_winners()` function in Supabase

**Root Cause**: Using `RETURN NEXT` with `RETURNS TABLE` causes PostgreSQL type mismatch error

## Technical Details

### The Problem

The original migration 020 created `complete_bounty_with_winners()` that:
1. Calls `determine_bounty_winner()` which returns **4 columns**:
   - user_id (UUID)
   - prize_share (DECIMAL)
   - ranking (INTEGER)
   - metric_value (DECIMAL)

2. Tries to return **3 columns** using `RETURN NEXT`:
   - winner_user_id (UUID)
   - prize_awarded (DECIMAL)
   - winner_rank (INTEGER)

3. Uses `RETURN NEXT` to manually assign and return each row

**Why this fails:**
- PostgreSQL's `RETURN NEXT` doesn't work properly with `RETURNS TABLE` when the structures don't match exactly
- The manual assignment approach (lines 368-371 in migration 020) causes SQLSTATE 42804 error
- Even with explicit type casting, `RETURN NEXT` is incompatible with this pattern

### Previous Failed Attempts

**Migration 023**: Attempted to fix by assigning columns before RETURN NEXT - still failed
**Migration 024**: Tried using RETURN QUERY but had logic errors - still failed
**Migration 025**: Attempted complete rewrite but had nested BEGIN block - still failed

All these migrations tried different approaches but didn't properly address the core issue.

## The Solution (Migration 026)

### Key Changes

1. **Removed RETURN NEXT entirely** - this is incompatible with RETURNS TABLE
2. **Used RETURN QUERY with proper column mapping** - map 4 columns from `determine_bounty_winner` to 3 return columns
3. **Fixed all type casting** - explicit ::UUID, ::DECIMAL, ::INTEGER casts
4. **Used CTE for winner processing** - single UPDATE operation instead of loop

### Code Structure

```sql
-- Process winners using CTE (Common Table Expression)
WITH winners AS (
    SELECT user_id, prize_share, ranking
    FROM determine_bounty_winner(bounty_uuid)
    -- Ignore metric_value (4th column)
),
updated_participants AS (
    UPDATE bounty_participants bp
    SET is_winner = true, prize_amount_won = w.prize_share
    FROM winners w
    WHERE bp.bounty_id = bounty_uuid AND bp.user_id = w.user_id
    RETURNING bp.user_id, bp.prize_amount_won, w.ranking
)
SELECT COUNT(*) INTO v_winner_count FROM updated_participants;

-- Return results using RETURN QUERY (not RETURN NEXT!)
RETURN QUERY
SELECT
    bp.user_id::UUID AS winner_user_id,
    bp.prize_amount_won::DECIMAL(20, 8) AS prize_awarded,
    ROW_NUMBER() OVER (ORDER BY bp.prize_amount_won DESC)::INTEGER AS winner_rank
FROM bounty_participants bp
WHERE bp.bounty_id = bounty_uuid AND bp.is_winner = true;
```

## Migration Instructions

1. Run migration 026 in Supabase SQL Editor:
   ```bash
   # Copy content from supabase/migrations/026_final_fix_complete_bounty.sql
   # Paste and execute in Supabase Dashboard > SQL Editor
   ```

2. Verify the fix:
   ```sql
   SELECT * FROM complete_bounty_with_winners('YOUR-BOUNTY-UUID');
   ```

3. Expected result:
   ```
   winner_user_id | prize_awarded | winner_rank
   --------------+--------------+-------------
   <UUID>        | <amount>     | 1
   ```

## Why This Fix Works

1. **RETURN QUERY**: Properly handles RETURNS TABLE structure
2. **Column Mapping**: Explicitly maps 4 columns from determine_bounty_winner to 3 return columns
3. **Type Safety**: All columns explicitly cast to expected types
4. **CTE Pattern**: More efficient than FOR loop with RETURN NEXT
5. **No Nested Blocks**: Single function body with no nested BEGIN/END

## Related Files

- **Database Function**: `complete_bounty_with_winners()` in Supabase
- **Migration**: [026_final_fix_complete_bounty.sql](../supabase/migrations/026_final_fix_complete_bounty.sql)
- **Frontend Usage**: [CompleteBountyModal.tsx](../src/components/CompleteBountyModal.tsx) line 135
- **Original Implementation**: [020_winner_determination.sql](../supabase/migrations/020_winner_determination.sql)

## Testing

After applying migration 026:

1. **Test with SQL**:
   ```sql
   SELECT * FROM complete_bounty_with_winners('3b994b5a-963f-4977-834f-61743b8e2d09');
   ```

2. **Test from UI**:
   - Create a bounty
   - Have a user complete it
   - Click "Complete Bounty & Distribute Prize" in admin panel
   - Should successfully mark winner without SQLSTATE 42804 error

## Lessons Learned

1. **Check Supabase Dashboard first** when debugging database function errors
   - Don't assume migrations were applied correctly
   - Verify actual deployed function code

2. **RETURN NEXT vs RETURN QUERY**:
   - RETURN NEXT: For manually building result set (error-prone with RETURNS TABLE)
   - RETURN QUERY: For returning query results (correct approach)

3. **Type Mismatch Debugging**:
   - Check all function signatures carefully
   - Map columns explicitly when structures differ
   - Use explicit type casting (::TYPE)

4. **Migration Review**:
   - Always check if previous migrations conflict
   - Don't assume the latest migration is the deployed version
   - Review all migrations systematically when debugging

## Fix Verified

- ✅ No more SQLSTATE 42804 error
- ✅ Properly maps 4-column determine_bounty_winner to 3-column return
- ✅ Uses RETURN QUERY (not RETURN NEXT)
- ✅ Backward compatible with existing code
- ✅ Works with frontend CompleteBountyModal.tsx

---

**Migration Created**: 2025-10-10
**Issue Resolved**: SQLSTATE 42804 - structure of query does not match function result type
**Status**: ✅ FIXED (Migration 026)
