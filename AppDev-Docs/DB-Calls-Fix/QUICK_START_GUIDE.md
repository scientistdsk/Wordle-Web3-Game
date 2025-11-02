# QUICK START GUIDE
## Database Fix Implementation

**Use this guide to quickly execute each phase of the fix plan.**

---

## 📋 PROMPTS FOR EACH PHASE

Copy and paste these prompts exactly as shown to execute each phase:

### PHASE 1: Foundation & Understanding
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

### PHASE 2: Create Winner Determination Logic
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

### PHASE 3: Fix Double-Increment Bug
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

### PHASE 4: Application Code Integration
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

### PHASE 5: Data Cleanup & Backfill
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

### PHASE 6: Monitoring & Validation
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

## ⚡ QUICK COMMAND REFERENCE

### To view the full plan:
```bash
cat AppDev-Docs/DB-Calls-Fix/PHASED_FIX_PLAN.md
```

### To view audit reports:
```bash
cat DATABASE_AUDIT_EXECUTIVE_SUMMARY.md
cat DATABASE_AUDIT_REPORT.md
```

### To apply a migration:
1. Go to Supabase SQL Editor: `https://supabase.com/dashboard/project/YOUR_PROJECT_ID/sql`
2. Copy the migration SQL content
3. Paste and click **Run**
4. Verify results

---

## 📊 PROGRESS TRACKER

Use this checklist to track your progress:

- [ ] **PHASE 1** - Foundation & Understanding
  - [ ] Diagnostic queries run
  - [ ] Issues confirmed
  - [ ] Database backed up

- [ ] **PHASE 2** - Winner Determination Logic
  - [ ] Migration 020 created
  - [ ] Functions tested
  - [ ] Trigger verified

- [ ] **PHASE 3** - Fix Double-Increment
  - [ ] Migration 021 created
  - [ ] join_bounty() fixed
  - [ ] Counts verified

- [ ] **PHASE 4** - Application Integration
  - [ ] CompleteBountyModal updated
  - [ ] End-to-end testing complete
  - [ ] No regressions

- [ ] **PHASE 5** - Data Cleanup
  - [ ] Migration 022 created
  - [ ] Historical data fixed
  - [ ] Stats recalculated

- [ ] **PHASE 6** - Monitoring
  - [ ] Health checks passing
  - [ ] Alerts configured
  - [ ] Documentation updated

---

## 🚨 TROUBLESHOOTING

### If a migration fails:
1. Check PostgreSQL error logs
2. Verify all dependencies exist
3. Review syntax carefully
4. Try running parts of the migration separately
5. Consult PHASED_FIX_PLAN.md rollback procedures

### If data looks incorrect:
1. Run diagnostic queries from Phase 1
2. Check monitoring queries from Phase 6
3. Review audit logs
4. Restore from snapshot if needed

### If application breaks:
1. Check browser console for errors
2. Review Supabase function logs
3. Verify RLS policies
4. Revert code changes if needed

---

## 📞 SUPPORT

For issues or questions:
1. Review the detailed PHASED_FIX_PLAN.md
2. Check DATABASE_AUDIT_REPORT.md for technical details
3. Reference DATABASE_AUDIT_EXECUTIVE_SUMMARY.md for overview

---

**Ready to start? Begin with Phase 1!**
