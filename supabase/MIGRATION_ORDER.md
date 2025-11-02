# Supabase Migration Order

## Quick Reference

Run migrations in this exact order for a fresh Supabase setup:

```
001_initial_schema.sql                    - Core database tables
002_rls_policies.sql                     - Row-level security
003_sample_data.sql                      - Sample/seed data
004b_payment_functions_fixed.sql         - Payment functions (use 004b, not 004)
005_fix_user_creation.sql                - User creation fixes
006_fix_payment_transactions_rls.sql     - Payment RLS policies
007_fix_bounty_update_policies.sql       - Bounty update policies
008_fix_bounty_details_function.sql      - Bounty details function
009_fix_function_overloading.sql         - Function overloading fixes
010_fix_leaderboard_materialized_view.sql - Leaderboard view
011_fix_leaderboard_triggers.sql         - Leaderboard triggers
012_dictionary_system.sql                - Word validation tables
013_dictionary_seed.sql                  - Word list seed data
014_update_prize_and_criteria_enums.sql  - Prize/criteria enums
015_add_participant_count_triggers.sql   - Auto-increment participant count
016_fix_get_bounty_details_add_words.sql - Bounty details with words
017_debug_submit_attempt.sql             - Submit attempt debugging
018_user_stats_function.sql              - User statistics
019_performance_indexes.sql              - Database indexes
020_winner_determination_complete.sql    - ✅ Winner logic (CONSOLIDATED)
021_fix_join_bounty.sql                  - Fix double-increment bug
022_fix_payment_transaction_status.sql   - Fix payment status
023_cleanup_draft_bounties.sql           - Auto-cleanup draft bounties
```

## Notes

### Migration 004
- Use `004b_payment_functions_fixed.sql` (not `004_payment_functions.sql`)
- The original 004 has known issues

### Migration 020
- **NEW**: `020_winner_determination_complete.sql` is a consolidated version
- Replaces old migrations 020, 023-027 which are now in `deprecated/` folder
- Includes all fixes for SQLSTATE 42804 errors
- Contains:
  - `determine_bounty_winner()` with type casting fixes
  - `complete_bounty_with_winners()` with RETURN QUERY fixes
  - `mark_prize_paid()` for blockchain payment tracking

### Deprecated Migrations
The following migrations are in `supabase/migrations/deprecated/` and should **NOT** be run:
- `020_winner_determination.sql` (broken - type casting issues)
- `023_fix_complete_bounty_return_type.sql` (failed fix attempt)
- `024_fix_complete_bounty_proper.sql` (failed fix attempt)
- `025_diagnostic_and_fix.sql` (failed fix attempt)
- `026_final_fix_complete_bounty.sql` (partial fix)
- `027_fix_determine_bounty_winner_types.sql` (final fix)

These were consolidated into `020_winner_determination_complete.sql`.

## Running Migrations

### Option 1: Supabase Dashboard
1. Go to **SQL Editor** in Supabase Dashboard
2. Copy and paste each migration file content in order
3. Execute each migration one by one

### Option 2: Supabase CLI (if configured)
```bash
supabase db push
```

### Option 3: Manual SQL Execution
```bash
# Using psql (if you have direct database access)
psql -h YOUR_DB_HOST -U YOUR_USER -d YOUR_DB -f supabase/migrations/001_initial_schema.sql
psql -h YOUR_DB_HOST -U YOUR_USER -d YOUR_DB -f supabase/migrations/002_rls_policies.sql
# ... continue for all migrations
```

## Verification

After running all migrations, verify with:

```sql
-- Check tables exist
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;

-- Check functions exist
SELECT routine_name FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_type = 'FUNCTION'
ORDER BY routine_name;

-- Test winner determination (use a real bounty UUID)
SELECT * FROM determine_bounty_winner('YOUR-BOUNTY-UUID');
SELECT * FROM complete_bounty_with_winners('YOUR-BOUNTY-UUID');
```

## Troubleshooting

### "Function already exists" Error
This means the migration was already run. Skip to the next migration.

### SQLSTATE 42804 Error
If you get this error in `determine_bounty_winner` or `complete_bounty_with_winners`:
- ✅ Make sure you ran `020_winner_determination_complete.sql` (NOT the old 020)
- ❌ Do NOT run migrations from `deprecated/` folder

### Duplicate Key Error
This means sample data already exists. You can skip migration 003 or modify it to avoid duplicates.

---

**Last Updated**: 2025-10-10
**Total Migrations**: 23 (001-023)
**Deprecated**: 6 migrations in `deprecated/` folder
