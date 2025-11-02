# PHASE 4: APPLICATION TESTING GUIDE

**File to Test:** [CompleteBountyModal.tsx](../../src/components/CompleteBountyModal.tsx)
**Prerequisites:** Migrations 020 and 021 must be applied

---

## 🎯 TESTING OBJECTIVES

1. Verify automatic winner determination works for all 4 criteria
2. Confirm multi-winner support (split-winners)
3. Test payment recording via `mark_prize_paid()`
4. Verify first-to-solve auto-completion
5. Check error handling and edge cases

---

## 🛠️ SETUP

### 1. Apply Migrations

```bash
# Navigate to your Supabase project dashboard
# SQL Editor → New Query → Paste and run:

# Migration 020 (Winner determination functions)
# Copy from: supabase/migrations/020_winner_determination.sql

# Migration 021 (Fix double-increment bug)
# Copy from: supabase/migrations/021_fix_join_bounty.sql
```

### 2. Start Development Server

```bash
cd "path/to/your/project"
pnpm run dev
```

### 3. Prepare Test Accounts

You'll need:
- 1 admin account (for creating bounties)
- 3-5 user accounts (for participating)
- Test HBAR on Hedera Testnet

**Get test HBAR:** https://portal.hedera.com/faucet

---

## 🧪 TEST SUITE

### TEST 1: Time-Based Winner Detection

**Objective:** Verify fastest time wins

**Steps:**

1. **Create Bounty**
   - Login as admin
   - Create new bounty:
     - Name: "Speed Test Bounty"
     - Winner Criteria: `time`
     - Prize Distribution: `winner-take-all`
     - Prize Amount: 5 HBAR
     - Words: ["REACT"]

2. **Participate as User 1**
   - Join bounty
   - Complete in 30 seconds (intentionally slow)
   - Note: Take breaks between attempts

3. **Participate as User 2**
   - Join bounty
   - Complete in 15 seconds (fastest!)
   - Try to solve quickly

4. **Participate as User 3**
   - Join bounty
   - Complete in 45 seconds (slowest)

5. **Complete Bounty (Admin)**
   - Go to Bounty Details page
   - Click "Complete Bounty"
   - Modal opens showing 3 completed participants
   - Click "Complete Bounty & Distribute Prize"

**Expected Results:**

✅ Progress messages appear:
- "Determining winners based on bounty criteria..."
- "Processing payment 1/1 to User 2..."
- "Recording payment details..."
- "Bounty completed successfully!"

✅ User 2 (15 seconds) wins entire 5 HBAR

✅ Database check:
```sql
SELECT
  u.username,
  bp.total_time_seconds,
  bp.is_winner,
  bp.prize_amount_won,
  bp.prize_paid_at,
  bp.prize_transaction_hash
FROM bounty_participants bp
JOIN users u ON bp.user_id = u.id
WHERE bp.bounty_id = 'your-bounty-id'
ORDER BY bp.total_time_seconds ASC;
```

Expected output:
| username | total_time_seconds | is_winner | prize_amount_won |
|----------|-------------------|-----------|------------------|
| User 2   | 15                | true      | 5.00000000       |
| User 1   | 30                | false     | 0.00000000       |
| User 3   | 45                | false     | 0.00000000       |

---

### TEST 2: Attempts-Based Winner Detection

**Objective:** Verify fewest attempts wins

**Steps:**

1. **Create Bounty**
   - Winner Criteria: `attempts`
   - Prize Distribution: `winner-take-all`
   - Prize Amount: 3 HBAR
   - Words: ["TESTS"]

2. **Participate**
   - User 1: 6 attempts (loses)
   - User 2: 3 attempts (wins!)
   - User 3: 5 attempts (loses)

3. **Complete Bounty**

**Expected Results:**

✅ User 2 wins (fewest attempts)
✅ Prize: 3 HBAR to User 2

**Database check:**
```sql
SELECT username, total_attempts, is_winner
FROM bounty_participants bp
JOIN users u ON bp.user_id = u.id
WHERE bp.bounty_id = 'your-bounty-id'
ORDER BY bp.total_attempts ASC;
```

---

### TEST 3: Words-Correct Winner Detection

**Objective:** Verify most words wins

**Steps:**

1. **Create Bounty**
   - Winner Criteria: `words-correct`
   - Prize Distribution: `winner-take-all`
   - Prize Amount: 4 HBAR
   - Words: ["ALPHA", "BETA", "GAMMA"]

2. **Participate**
   - User 1: Completes 1 word (loses)
   - User 2: Completes 3 words (wins!)
   - User 3: Completes 2 words (loses)

3. **Complete Bounty**

**Expected Results:**

✅ User 2 wins (most words completed)
✅ Prize: 4 HBAR

---

### TEST 4: Split-Winners (Top 3)

**Objective:** Verify prize splits correctly among top 3

**Steps:**

1. **Create Bounty**
   - Winner Criteria: `time`
   - Prize Distribution: `split-winners` ← IMPORTANT!
   - Prize Amount: 9 HBAR (divisible by 3)
   - Words: ["SPLIT"]

2. **Participate (5 users)**
   - User 1: 10 seconds (2nd place)
   - User 2: 8 seconds (1st place)
   - User 3: 15 seconds (4th - no prize)
   - User 4: 12 seconds (3rd place)
   - User 5: 20 seconds (5th - no prize)

3. **Complete Bounty**

**Expected Results:**

✅ Progress shows 3 payments:
- "Processing payment 1/3 to User 2..."
- "Processing payment 2/3 to User 1..."
- "Processing payment 3/3 to User 4..."

✅ Prize split:
- User 2: 3 HBAR (1st)
- User 1: 3 HBAR (2nd)
- User 4: 3 HBAR (3rd)
- User 3: 0 HBAR (4th)
- User 5: 0 HBAR (5th)

**Database check:**
```sql
SELECT
  u.username,
  bp.total_time_seconds,
  bp.is_winner,
  bp.prize_amount_won,
  ROW_NUMBER() OVER (ORDER BY bp.total_time_seconds ASC) as rank
FROM bounty_participants bp
JOIN users u ON bp.user_id = u.id
WHERE bp.bounty_id = 'your-bounty-id'
ORDER BY bp.total_time_seconds ASC;
```

Expected:
| username | time | is_winner | prize  | rank |
|----------|------|-----------|--------|------|
| User 2   | 8    | true      | 3.0000 | 1    |
| User 1   | 10   | true      | 3.0000 | 2    |
| User 4   | 12   | true      | 3.0000 | 3    |
| User 3   | 15   | false     | 0.0000 | 4    |
| User 5   | 20   | false     | 0.0000 | 5    |

---

### TEST 5: First-to-Solve Auto-Complete (Trigger Test)

**Objective:** Verify trigger marks winner automatically

**Steps:**

1. **Create Bounty**
   - Winner Criteria: `first-to-solve` ← CRITICAL!
   - Prize Distribution: `winner-take-all`
   - Prize Amount: 10 HBAR
   - Words: ["FIRST"]

2. **Participate as User 1**
   - Join bounty
   - Start playing
   - Complete the word

**Expected Results (AUTOMATIC):**

✅ **Immediately after completing:**
- User 1's `is_winner` = true (check database)
- Bounty `status` = 'completed' (check database)
- No admin intervention needed!

✅ **Admin verifies:**
```sql
SELECT
  b.status,
  bp.is_winner,
  bp.prize_amount_won,
  u.username
FROM bounties b
JOIN bounty_participants bp ON b.id = bp.bounty_id
JOIN users u ON bp.user_id = u.id
WHERE b.id = 'your-bounty-id';
```

Expected:
| status    | is_winner | prize_amount_won | username |
|-----------|-----------|------------------|----------|
| completed | true      | 10.00000000      | User 1   |

✅ **Other users try to join:**
- Should see "Bounty is completed" or cannot join

**Note:** For first-to-solve, admin still needs to go to CompleteBountyModal to process blockchain payment. The database marking happens automatically, but HBAR transfer requires admin action.

---

### TEST 6: No Completed Participants (Error Handling)

**Objective:** Verify error handling when no one completed

**Steps:**

1. **Create Bounty**
   - Any settings

2. **Participate but DON'T complete**
   - User 1: Join but don't finish
   - User 2: Join but don't finish

3. **Try to Complete Bounty (Admin)**

**Expected Results:**

✅ Modal shows: "No participants have completed this bounty yet"
✅ "Complete Bounty" button is disabled
✅ Cannot proceed until someone completes

---

### TEST 7: Blockchain Payment Failure

**Objective:** Test error handling when payment fails

**Steps:**

1. **Create Bounty** (any settings)

2. **Participate and complete** (any user)

3. **Simulate Payment Failure:**
   - Disconnect wallet during payment, OR
   - Use insufficient HBAR balance, OR
   - Network timeout

4. **Try to Complete Bounty**

**Expected Results:**

✅ Error message appears in red box
✅ Shows specific error (e.g., "Insufficient balance")
✅ Database state is NOT partially updated
✅ Can retry after fixing issue
✅ No winners marked if payment failed

**Verify rollback:**
```sql
-- Should still be false if payment failed
SELECT is_winner, prize_amount_won
FROM bounty_participants
WHERE bounty_id = 'your-bounty-id';
```

---

### TEST 8: Payment Recording Verification

**Objective:** Verify `mark_prize_paid()` works correctly

**Steps:**

1. **Complete any bounty** (follow TEST 1)

2. **Check payment was recorded:**

```sql
SELECT
  bp.id,
  bp.is_winner,
  bp.prize_amount_won,
  bp.prize_paid_at,
  bp.prize_transaction_hash,
  u.username
FROM bounty_participants bp
JOIN users u ON bp.user_id = u.id
WHERE bp.bounty_id = 'your-bounty-id'
  AND bp.is_winner = true;
```

**Expected Results:**

✅ `prize_paid_at` is NOT NULL (has timestamp)
✅ `prize_transaction_hash` is NOT NULL (has 0x... hash)
✅ Timestamp is recent (within last few minutes)

**Also check payment_transactions table:**

```sql
SELECT
  transaction_type,
  amount,
  currency,
  transaction_hash,
  created_at
FROM payment_transactions
WHERE bounty_id = 'your-bounty-id'
  AND transaction_type = 'prize_payout';
```

Expected: 1 row per winner with matching tx_hash

---

### TEST 9: Multiple Winners Progress Tracking

**Objective:** Verify progress UI for split-winners

**Steps:**

1. **Create split-winners bounty** (follow TEST 4)

2. **Watch modal during completion**

**Expected Progress Messages (in order):**

1. "Determining winners based on bounty criteria..."
2. "Preparing blockchain transactions..."
3. "Processing payment 1/3 to User 2..."
4. "Recording payment 1/3 details..."
5. "Processing payment 2/3 to User 1..."
6. "Recording payment 2/3 details..."
7. "Processing payment 3/3 to User 4..."
8. "Recording payment 3/3 details..."
9. "Refreshing balance..."
10. "Bounty completed successfully!"

✅ Each message displays for 2-5 seconds
✅ Progress indicator (spinner) shows during processing
✅ No freezing or hanging
✅ Total time < 60 seconds

---

### TEST 10: UI Elements Verification

**Objective:** Check all UI changes are correct

**Steps:**

1. **Open CompleteBountyModal** for any bounty

**Verify UI Elements:**

✅ Info box shows:
```
ℹ️ Automatic Winner Selection: The system will automatically
determine the winner(s) based on the bounty's [criteria] criteria.
```

✅ Bounty info shows 3 columns:
- Prize Amount
- Completed (participants)
- Winner Criteria

✅ Participants list is READ-ONLY (no checkboxes/radio buttons)

✅ Top participant has:
- Primary border color
- "Top Performer" badge
- Award icon

✅ Button text: "Complete Bounty & Distribute Prize"

✅ During processing:
- Button shows "Processing..."
- Progress indicator appears
- Cancel button disabled

✅ After success:
- Button shows "Completed" with checkmark
- Success message: "Winners have been marked and prizes distributed"

---

## 🐛 COMMON ISSUES & FIXES

### Issue 1: "Function complete_bounty_with_winners does not exist"

**Cause:** Migration 020 not applied

**Fix:**
```sql
-- Run migration 020 in Supabase SQL Editor
```

### Issue 2: Winner marked but no HBAR received

**Cause:** Blockchain payment failed after database update

**Check:**
```sql
SELECT prize_paid_at, prize_transaction_hash
FROM bounty_participants
WHERE bounty_id = '...' AND is_winner = true;
```

If `prize_paid_at` is NULL, payment didn't happen.

**Fix:** Re-run completion or manually pay via smart contract.

### Issue 3: Modal shows no participants

**Cause:** Query filters by status = 'completed', but participants have different status

**Check:**
```sql
SELECT user_id, status
FROM bounty_participants
WHERE bounty_id = '...';
```

If status != 'completed', users haven't finished yet.

### Issue 4: Duplicate winners marked

**Cause:** Clicked "Complete Bounty" multiple times

**Prevention:** The function checks for existing winners and skips if found.

**Verify:**
```sql
SELECT COUNT(*) as winner_count
FROM bounty_participants
WHERE bounty_id = '...' AND is_winner = true;
```

Should match expected winner count (1 or 3).

---

## ✅ TEST COMPLETION CHECKLIST

After running all tests, verify:

- [ ] Time-based winner determination works
- [ ] Attempts-based winner determination works
- [ ] Words-correct winner determination works
- [ ] First-to-solve auto-completes correctly
- [ ] Split-winners divides prize correctly (top 3)
- [ ] Payment recording works (`mark_prize_paid`)
- [ ] Error handling works (no completed participants)
- [ ] Error handling works (payment failure)
- [ ] Progress tracking displays correctly
- [ ] UI elements match specifications
- [ ] No console errors
- [ ] Database state is consistent
- [ ] All winners have `prize_paid_at` set
- [ ] All winners have `prize_transaction_hash` set
- [ ] User statistics updated correctly

---

## 📊 VERIFICATION QUERIES

### Quick Health Check

```sql
-- Check recent bounty completions
SELECT
  b.name,
  b.winner_criteria,
  b.prize_distribution,
  COUNT(CASE WHEN bp.is_winner THEN 1 END) as winners,
  SUM(bp.prize_amount_won) as total_distributed
FROM bounties b
JOIN bounty_participants bp ON b.id = bp.bounty_id
WHERE b.status = 'completed'
  AND b.updated_at >= NOW() - INTERVAL '1 hour'
GROUP BY b.id
ORDER BY b.updated_at DESC;
```

### Verify Payment Recording

```sql
-- All winners should have payment details
SELECT
  COUNT(*) as total_winners,
  COUNT(CASE WHEN prize_paid_at IS NOT NULL THEN 1 END) as paid_recorded,
  COUNT(CASE WHEN prize_transaction_hash IS NOT NULL THEN 1 END) as with_tx_hash
FROM bounty_participants
WHERE is_winner = true
  AND completed_at >= NOW() - INTERVAL '1 hour';
```

Expected: All three counts should be equal.

---

## 🎯 SUCCESS CRITERIA

Phase 4 testing is **COMPLETE** when:

✅ All 10 tests pass without errors
✅ All 4 winner criteria work correctly
✅ Split-winners functionality works
✅ First-to-solve trigger works
✅ Payment recording works for all winners
✅ Error handling prevents data corruption
✅ UI displays correct information
✅ No regressions in existing functionality

---

**Ready to test Phase 4 integration!** 🚀

If all tests pass, proceed to Phase 5 (Data Cleanup & Backfill).
