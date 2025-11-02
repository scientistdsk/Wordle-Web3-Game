# Deprecated Migrations

**DO NOT RUN THESE MIGRATIONS ON A FRESH SETUP!**

These migrations are kept for historical reference only. They have been consolidated into the main migration files.

## Why These Were Deprecated

### Migration 020 (Original)
- **File**: `020_winner_determination.sql`
- **Issue**: Had type casting bugs (INTEGER vs DECIMAL mismatch)
- **Replaced by**: `020_winner_determination_complete.sql` (consolidated version)

### Migrations 023-027 (Failed Fix Attempts)
These were iterative attempts to fix the SQLSTATE 42804 error in the winner determination functions:

- **023_fix_complete_bounty_return_type.sql**: Attempted to fix RETURN NEXT issue - FAILED
- **024_fix_complete_bounty_proper.sql**: Another RETURN NEXT fix attempt - FAILED
- **025_diagnostic_and_fix.sql**: Diagnostic version with nested BEGIN blocks - FAILED
- **026_final_fix_complete_bounty.sql**: Fixed complete_bounty_with_winners - PARTIAL SUCCESS
- **027_fix_determine_bounty_winner_types.sql**: Fixed type casting in determine_bounty_winner - SUCCESS

### What Happened

The actual issues were:
1. **Type mismatch**: `total_time_seconds`, `total_attempts`, `words_completed` are INTEGER in schema, but function expected DECIMAL(20, 4)
2. **RETURN NEXT incompatibility**: Using RETURN NEXT with RETURNS TABLE caused structure mismatch errors

### The Solution

All fixes were consolidated into:
- **020_winner_determination_complete.sql** - Single working version with all fixes applied

## For Fresh Database Setup

**Use only:**
```
001 to 019 (existing migrations)
020_winner_determination_complete.sql  ✅
021_fix_join_bounty.sql               ✅
022_fix_payment_transaction_status.sql ✅
023_cleanup_draft_bounties.sql        ✅
```

**Do NOT use migrations in this deprecated folder!**

---

**Date Deprecated**: 2025-10-10
**Reason**: Consolidated into single working migration (020_winner_determination_complete.sql)
