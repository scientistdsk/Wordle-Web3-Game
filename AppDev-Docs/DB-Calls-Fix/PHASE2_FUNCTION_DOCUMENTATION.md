# PHASE 2: WINNER DETERMINATION FUNCTIONS - DOCUMENTATION

**Migration File:** `020_winner_determination.sql`
**Created:** October 8, 2025
**Status:** ✅ READY FOR TESTING

---

## 📋 OVERVIEW

This migration creates a complete automatic winner determination system that:
- ✅ Analyzes participants and determines winners based on 4 criteria types
- ✅ Handles both winner-take-all and split-winners prize distribution
- ✅ Automatically marks winners and distributes prizes
- ✅ Records blockchain payment details
- ✅ Auto-completes first-to-solve bounties in real-time

---

## 🔧 FUNCTION 1: determine_bounty_winner()

### Purpose
Analyzes all participants who completed a bounty and determines who should win based on the bounty's `winner_criteria` setting.

### Signature
```sql
determine_bounty_winner(bounty_uuid UUID)
RETURNS TABLE(
    user_id UUID,
    prize_share DECIMAL(20, 8),
    ranking INTEGER,
    metric_value DECIMAL(20, 4)
)
```

### How It Works

#### Step 1: Load Bounty Configuration
```sql
SELECT winner_criteria, prize_distribution, prize_amount, status
FROM bounties
WHERE id = bounty_uuid;
```
Gets the rules for this bounty: how to determine winners and how to distribute prizes.

#### Step 2: Apply Winner Criteria Logic

The function implements 4 different winner determination algorithms:

##### A. **first-to-solve**
```sql
-- Winner = First person to complete (earliest completed_at timestamp)
SELECT user_id, prize_amount, 1 as ranking
FROM bounty_participants
WHERE bounty_id = bounty_uuid AND status = 'completed'
ORDER BY completed_at ASC
LIMIT 1;
```
**Use Case:** Speed competitions, "first one wins" challenges
**Winner:** Person who completes first
**Prize:** Always winner-take-all (100% of prize)

##### B. **time**
```sql
-- Winner = Fastest total_time_seconds (lowest time)
-- For winner-take-all:
ORDER BY total_time_seconds ASC LIMIT 1;

-- For split-winners (top 3):
ORDER BY total_time_seconds ASC LIMIT 3;
-- Prize split equally: prize_amount / 3
```
**Use Case:** Best time trials, speed challenges
**Winner:** Fastest completion time
**Prize:** Either 100% to fastest, or split among top 3 fastest

##### C. **attempts**
```sql
-- Winner = Fewest total_attempts (lowest attempts)
-- Tie-breaker: If attempts are equal, fastest time wins
ORDER BY total_attempts ASC, total_time_seconds ASC;
```
**Use Case:** Efficiency challenges, "solve with fewest guesses"
**Winner:** Most efficient solver (fewest attempts)
**Prize:** Either 100% to best, or split among top 3

##### D. **words-correct**
```sql
-- Winner = Most words_completed (highest count)
-- Tie-breaker: If counts are equal, fastest time wins
ORDER BY words_completed DESC, total_time_seconds ASC;
```
**Use Case:** Multi-word challenges, progressive difficulty
**Winner:** Most words solved correctly
**Prize:** Either 100% to best, or split among top 3

#### Step 3: Return Winners with Prize Shares

Returns a table with:
- `user_id`: UUID of the winner
- `prize_share`: Exact amount of HBAR they won (after splitting if applicable)
- `ranking`: 1st, 2nd, 3rd place (for split-winners)
- `metric_value`: The actual metric they achieved (time, attempts, or words)

### Error Handling

```sql
-- Bounty not found
IF NOT FOUND THEN
    RAISE EXCEPTION 'Bounty not found: %';
END IF;

-- Invalid status
IF status NOT IN ('completed', 'active', 'expired') THEN
    RAISE EXCEPTION 'Bounty cannot be completed. Current status: %';
END IF;

-- No eligible winners
IF NOT FOUND THEN
    RAISE WARNING 'No eligible winners found for bounty: %';
END IF;
```

### Example Outputs

**Example 1: First-to-solve**
```
user_id                              | prize_share | ranking | metric_value
-------------------------------------|-------------|---------|-------------
a1b2c3d4-e5f6-7890-abcd-ef1234567890 | 10.00000000 | 1       | 1728398400.0
```

**Example 2: Time-based, split-winners (10 HBAR prize)**
```
user_id                              | prize_share | ranking | metric_value
-------------------------------------|-------------|---------|-------------
user-1                               | 3.33333333  | 1       | 45.5 (seconds)
user-2                               | 3.33333333  | 2       | 52.3
user-3                               | 3.33333333  | 3       | 58.1
```

**Example 3: Attempts-based, winner-take-all**
```
user_id                              | prize_share | ranking | metric_value
-------------------------------------|-------------|---------|-------------
user-1                               | 10.00000000 | 1       | 4 (attempts)
```

---

## 🎯 FUNCTION 2: complete_bounty_with_winners()

### Purpose
Orchestrates the entire winner marking process. This is the **main function** that should be called to complete a bounty.

### Signature
```sql
complete_bounty_with_winners(bounty_uuid UUID)
RETURNS TABLE(
    winner_user_id UUID,
    prize_awarded DECIMAL(20, 8),
    winner_rank INTEGER
)
```

### How It Works

#### Step 1: Validation
```sql
-- Check if bounty exists
SELECT status, name FROM bounties WHERE id = bounty_uuid;

-- Check if already completed (prevent double-processing)
IF EXISTS (SELECT 1 FROM bounty_participants WHERE bounty_id = bounty_uuid AND is_winner = true) THEN
    RAISE WARNING 'Bounty already has winners marked. Skipping duplicate completion.';
    RETURN existing_winners;
END IF;
```

#### Step 2: Determine All Winners
```sql
FOR winner_record IN
    SELECT * FROM determine_bounty_winner(bounty_uuid)
LOOP
    -- Process each winner...
END LOOP;
```
Calls `determine_bounty_winner()` to get the list of all winners.

#### Step 3: Mark Each Winner

**For the first winner:**
```sql
-- Use existing complete_bounty() function
-- This handles bounty status update automatically
PERFORM complete_bounty(
    bounty_uuid,
    winner_record.user_id,
    winner_record.prize_share
);
```

**For subsequent winners (split-winners scenarios):**
```sql
-- Update participant record directly
UPDATE bounty_participants
SET
    status = 'completed',
    is_winner = true,
    prize_amount_won = winner_record.prize_share,
    completed_at = COALESCE(completed_at, NOW())
WHERE bounty_id = bounty_uuid AND user_id = winner_record.user_id;

-- Update user statistics
UPDATE users
SET
    total_bounties_won = total_bounties_won + 1,
    total_hbar_earned = total_hbar_earned + winner_record.prize_share,
    updated_at = NOW()
WHERE id = winner_record.user_id;
```

Why different handling?
- `complete_bounty()` sets bounty status to 'completed'
- We only want to do this ONCE (for the first winner)
- Subsequent winners just need their records updated

#### Step 4: Final Bounty Status Update
```sql
-- Ensure bounty is marked as completed
UPDATE bounties
SET status = 'completed', updated_at = NOW()
WHERE id = bounty_uuid AND status != 'completed';
```

#### Step 5: Return Summary
```sql
RETURN TABLE of all winners marked
```

### Usage in Application

**Frontend (after admin confirms completion):**
```typescript
const { data: winners, error } = await supabase
  .rpc('complete_bounty_with_winners', {
    bounty_uuid: bounty.id
  });

if (error) {
  console.error('Failed to complete bounty:', error);
} else {
  console.log('Winners marked:', winners);
  // Show success message with winner details
}
```

### Error Handling

```sql
EXCEPTION
    WHEN OTHERS THEN
        RAISE EXCEPTION 'Error in complete_bounty_with_winners for bounty %: % (SQLSTATE: %)',
            bounty_uuid, SQLERRM, SQLSTATE;
```

All errors are caught, logged with context, and re-raised to inform the caller.

### Transaction Safety

The entire function runs in a **single transaction**:
- If any winner marking fails, ALL changes are rolled back
- Ensures data integrity (no partial winner states)
- Atomicity: all-or-nothing execution

---

## 💰 FUNCTION 3: mark_prize_paid()

### Purpose
Records blockchain payment details after prizes have been paid out on-chain. Called by the frontend after successful HBAR transfer.

### Signature
```sql
mark_prize_paid(
    bounty_uuid UUID,
    user_uuid UUID,
    tx_hash VARCHAR(255)
)
RETURNS void
```

### How It Works

#### Step 1: Validate Winner
```sql
SELECT id, is_winner, prize_amount_won
FROM bounty_participants
WHERE bounty_id = bounty_uuid AND user_id = user_uuid;

-- Must be marked as winner
IF NOT is_winner THEN
    RAISE EXCEPTION 'User is not marked as a winner';
END IF;

-- Must have prize amount > 0
IF prize_amount_won <= 0 THEN
    RAISE EXCEPTION 'Prize amount is 0';
END IF;
```

#### Step 2: Update Payment Details
```sql
UPDATE bounty_participants
SET
    prize_paid_at = NOW(),
    prize_transaction_hash = tx_hash
WHERE bounty_id = bounty_uuid AND user_id = user_uuid;
```

#### Step 3: Record Transaction (if table exists)
```sql
INSERT INTO payment_transactions (
    bounty_id,
    user_id,
    transaction_type,
    amount,
    currency,
    transaction_hash,
    status,
    created_at
) VALUES (
    bounty_uuid,
    user_uuid,
    'prize_payout',
    prize_amount_won,
    'HBAR',
    tx_hash,
    'completed',
    NOW()
);
```

### Usage in Application

**Frontend (after successful blockchain transaction):**
```typescript
// After smart contract completeBounty() succeeds
const txHash = receipt.transactionHash;

const { error } = await supabase.rpc('mark_prize_paid', {
  bounty_uuid: bounty.id,
  user_uuid: winner.id,
  tx_hash: txHash
});

if (error) {
  console.error('Failed to record payment:', error);
} else {
  console.log('Payment recorded successfully');
}
```

### When to Call This Function

```typescript
// Payment Flow:
// 1. Admin/System completes bounty (marks winners)
await supabase.rpc('complete_bounty_with_winners', { bounty_uuid });

// 2. Smart contract sends HBAR to winner
const tx = await escrowContract.completeBounty(bountyId, winnerAddress, amount);
await tx.wait();

// 3. Record the blockchain transaction hash
await supabase.rpc('mark_prize_paid', {
  bounty_uuid,
  user_uuid: winnerId,
  tx_hash: tx.hash
});
```

### Error Handling

```sql
-- Participant not found
IF NOT FOUND THEN
    RAISE EXCEPTION 'Participant not found for bounty % and user %';
END IF;

-- Not a winner
IF NOT is_winner THEN
    RAISE EXCEPTION 'User is not marked as a winner';
END IF;

-- Already paid (warning, not error)
IF prize_paid_at IS NOT NULL THEN
    RAISE WARNING 'Prize already marked as paid. Updating tx_hash.';
END IF;
```

---

## ⚡ FUNCTION 4: auto_complete_first_to_solve_trigger()

### Purpose
Automatically completes a bounty the **instant** the first person solves it. No admin intervention needed.

### Trigger Setup
```sql
CREATE TRIGGER auto_complete_first_to_solve
AFTER UPDATE OF status ON bounty_participants
FOR EACH ROW
WHEN (NEW.status = 'completed' AND OLD.status != 'completed')
EXECUTE FUNCTION auto_complete_first_to_solve_trigger();
```

**Fires when:** A participant's status changes from anything → 'completed'
**Executes:** After the status update (AFTER UPDATE)
**Scope:** Per row (FOR EACH ROW)

### How It Works

#### Step 1: Detect Status Change
```sql
-- Only process if status changed to 'completed'
IF NEW.status != 'completed' OR OLD.status = 'completed' THEN
    RETURN NEW;  -- Skip processing
END IF;
```

#### Step 2: Check Bounty Type
```sql
SELECT winner_criteria, prize_distribution, status
FROM bounties
WHERE id = NEW.bounty_id;

-- Only proceed if first-to-solve
IF winner_criteria != 'first-to-solve' THEN
    RETURN NEW;  -- Not first-to-solve, skip
END IF;
```

#### Step 3: Check If Already Completed
```sql
-- Don't double-process
IF bounty_status = 'completed' THEN
    RETURN NEW;
END IF;
```

#### Step 4: Verify This is the First Completion
```sql
SELECT COUNT(*) INTO existing_completions
FROM bounty_participants
WHERE bounty_id = NEW.bounty_id
  AND status = 'completed'
  AND id != NEW.id;

IF existing_completions > 0 THEN
    RETURN NEW;  -- Not the first, someone already completed
END IF;
```

#### Step 5: Auto-Complete the Bounty
```sql
-- This is the first completion!
PERFORM complete_bounty_with_winners(NEW.bounty_id);
```

Automatically calls the orchestration function to mark the winner and complete the bounty.

### Real-World Flow Example

**User perspective:**
1. User plays Wordle bounty
2. User enters final correct word
3. Frontend calls `submit_attempt()` with result='correct'
4. `submit_attempt()` updates participant status to 'completed'
5. **TRIGGER FIRES AUTOMATICALLY** ⚡
6. Winner is marked, prize recorded, bounty completed
7. User sees "You won!" message instantly

**All in a single database transaction!**

### Safety Features

```sql
EXCEPTION
    WHEN OTHERS THEN
        -- Log error but don't block the participant update
        RAISE WARNING 'Error in auto_complete_first_to_solve_trigger: %';
        RETURN NEW;  -- Allow participant update to succeed even if trigger fails
```

If the trigger fails for any reason:
- Participant's completion is still saved ✅
- Error is logged for debugging
- Bounty can be manually completed by admin

### When This Trigger Does NOT Fire

- ❌ Bounty is time-based (not first-to-solve)
- ❌ Bounty is attempts-based
- ❌ Bounty is words-correct-based
- ❌ Bounty is already completed
- ❌ This is the 2nd, 3rd, etc. completion (not first)

---

## 🎁 BONUS FUNCTION: get_bounty_winner_summary()

### Purpose
Administrative/debugging function to get a complete winner summary for any bounty.

### Signature
```sql
get_bounty_winner_summary(bounty_uuid UUID)
RETURNS TABLE(
    bounty_name TEXT,
    bounty_status VARCHAR(20),
    winner_criteria winner_criteria,
    prize_distribution prize_distribution,
    total_prize DECIMAL(20, 8),
    winner_count INTEGER,
    total_distributed DECIMAL(20, 8),
    winners JSONB
)
```

### Output Example

```json
{
  "bounty_name": "Speed Challenge #42",
  "bounty_status": "completed",
  "winner_criteria": "time",
  "prize_distribution": "split-winners",
  "total_prize": 10.00000000,
  "winner_count": 3,
  "total_distributed": 9.99999999,
  "winners": [
    {
      "user_id": "uuid-1",
      "wallet_address": "0.0.12345",
      "username": "speedster",
      "prize_amount": 3.33333333,
      "total_attempts": 5,
      "total_time_seconds": 45.2,
      "words_completed": 3,
      "completed_at": "2025-10-08T12:34:56Z",
      "prize_paid": true,
      "prize_tx_hash": "0xabc123..."
    },
    // ... more winners
  ]
}
```

### Usage

**Admin Dashboard:**
```typescript
const { data, error } = await supabase
  .rpc('get_bounty_winner_summary', {
    bounty_uuid: selectedBounty.id
  });

// Display winner details in admin panel
```

**Debugging:**
```sql
-- Check winner status for a bounty
SELECT * FROM get_bounty_winner_summary('your-bounty-id');
```

---

## 🔐 PERMISSIONS

All functions have proper permission grants:

```sql
-- Authenticated users can call winner determination functions
GRANT EXECUTE ON FUNCTION determine_bounty_winner(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION complete_bounty_with_winners(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION mark_prize_paid(UUID, UUID, VARCHAR) TO authenticated;

-- Both authenticated and anonymous users can view winner summaries
GRANT EXECUTE ON FUNCTION get_bounty_winner_summary(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_bounty_winner_summary(UUID) TO anon;
```

**Security Model:**
- `SECURITY DEFINER`: Functions run with owner privileges (bypass RLS)
- Required because functions need to update user statistics and bounty status
- Safe because all functions validate inputs and check permissions internally

---

## 🧪 TESTING CHECKLIST

After running this migration, test each scenario:

### Test 1: First-to-Solve Auto-Completion
```sql
-- 1. Create a first-to-solve bounty
-- 2. Have a user complete it
-- 3. Verify trigger auto-completes the bounty
-- 4. Verify winner is marked instantly
```

### Test 2: Time-Based Winner-Take-All
```sql
-- 1. Create a time-based bounty
-- 2. Have 3 users complete with different times
-- 3. Manually call complete_bounty_with_winners()
-- 4. Verify fastest user wins entire prize
```

### Test 3: Attempts-Based Split-Winners
```sql
-- 1. Create attempts-based bounty with split-winners
-- 2. Have 5 users complete with different attempt counts
-- 3. Call complete_bounty_with_winners()
-- 4. Verify top 3 users win and prize is split equally
```

### Test 4: Words-Correct Criteria
```sql
-- 1. Create words-correct bounty
-- 2. Have users complete different numbers of words
-- 3. Call complete_bounty_with_winners()
-- 4. Verify user with most words wins
```

### Test 5: Prize Payment Recording
```sql
-- 1. Complete a bounty (mark winners)
-- 2. Simulate blockchain payment
-- 3. Call mark_prize_paid() with tx hash
-- 4. Verify prize_paid_at and prize_transaction_hash are set
```

### Test 6: Duplicate Completion Prevention
```sql
-- 1. Complete a bounty (mark winners)
-- 2. Try calling complete_bounty_with_winners() again
-- 3. Verify it skips and returns existing winners
-- 4. Verify no duplicate prize amounts
```

### Test 7: Error Handling
```sql
-- Test with invalid bounty_uuid
-- Test with bounty that has no completions
-- Test marking prize paid for non-winner
-- Verify all errors are caught and logged properly
```

---

## 📊 MONITORING QUERIES

After deployment, use these queries to monitor system health:

### Query 1: Check Recent Winner Markings
```sql
SELECT
    b.name,
    COUNT(bp.id) as winner_count,
    SUM(bp.prize_amount_won) as total_distributed,
    b.prize_amount as expected_prize,
    b.updated_at
FROM bounties b
JOIN bounty_participants bp ON b.id = bp.bounty_id AND bp.is_winner = true
WHERE b.status = 'completed'
  AND b.updated_at >= NOW() - INTERVAL '24 hours'
GROUP BY b.id
ORDER BY b.updated_at DESC;
```

### Query 2: Check Unpaid Prizes
```sql
SELECT
    b.name,
    u.username,
    u.wallet_address,
    bp.prize_amount_won,
    bp.completed_at,
    NOW() - bp.completed_at as time_since_completion
FROM bounty_participants bp
JOIN bounties b ON bp.bounty_id = b.id
JOIN users u ON bp.user_id = u.id
WHERE bp.is_winner = true
  AND bp.prize_paid_at IS NULL
  AND bp.prize_amount_won > 0
ORDER BY bp.completed_at ASC;
```

### Query 3: Verify Auto-Completion Working
```sql
SELECT
    COUNT(*) as first_to_solve_bounties,
    COUNT(CASE WHEN status = 'completed' THEN 1 END) as completed_count,
    ROUND(100.0 * COUNT(CASE WHEN status = 'completed' THEN 1 END) / NULLIF(COUNT(*), 0), 2) as auto_complete_rate
FROM bounties
WHERE winner_criteria = 'first-to-solve'
  AND created_at >= NOW() - INTERVAL '7 days';
```

---

## 🚀 DEPLOYMENT CHECKLIST

Before running this migration in production:

- [ ] Backup database
- [ ] Test on staging environment first
- [ ] Run all 7 test scenarios
- [ ] Verify trigger fires correctly
- [ ] Check function performance (should be < 100ms)
- [ ] Verify no conflicts with existing functions
- [ ] Test with real bounty data
- [ ] Verify GRANT permissions work
- [ ] Update application code to call new functions
- [ ] Document API usage for frontend team

---

## 📚 INTEGRATION WITH EXISTING CODE

### Functions This Migration Uses (Already Exist)
- `complete_bounty(bounty_uuid, winner_id, prize_share)` - Used by `complete_bounty_with_winners()`
- `submit_attempt(...)` - Trigger watches for status changes from this

### Functions That Will Call These (Phase 4)
- [CompleteBountyModal.tsx](../../src/components/CompleteBountyModal.tsx) - Will call `complete_bounty_with_winners()`
- [payment-service.ts](../../src/services/payment-service.ts) - Will call `mark_prize_paid()`

### Database Tables Modified
- `bounty_participants` - Winner marking, prize amounts, payment details
- `bounties` - Status updates to 'completed'
- `users` - Statistics updates (total_bounties_won, total_hbar_earned)
- `payment_transactions` - New payment records (if table exists)

---

## ⚠️ IMPORTANT NOTES

1. **Transaction Safety**: All functions use transactions. If any step fails, everything rolls back.

2. **Idempotency**: `complete_bounty_with_winners()` checks if winners are already marked to prevent double-processing.

3. **Logging**: Extensive `RAISE NOTICE` statements for debugging. Check Postgres logs to trace execution.

4. **Platform Fee**: The existing `complete_bounty()` function handles platform fees (2.5%). These new functions don't need to worry about it.

5. **First-to-Solve is Special**: It's the only criteria that auto-completes. All others require manual completion via admin.

6. **Split-Winners Limit**: Currently set to top 3 winners. Can be adjusted in the SQL if needed.

7. **Tie-Breaking**: Time-based uses `completed_at`, attempts uses `total_time_seconds`, words-correct uses `total_time_seconds`.

---

**END OF PHASE 2 DOCUMENTATION**

*Ready for testing and integration into application code.*
