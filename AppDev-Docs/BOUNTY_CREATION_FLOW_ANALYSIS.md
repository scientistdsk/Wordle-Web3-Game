# BOUNTY CREATION FLOW - ISSUE ANALYSIS & SOLUTIONS

**Issue:** Bounty gets created in database BEFORE blockchain payment, leading to orphaned bounties when payment fails.

**Date:** October 8, 2025

---

## 🔴 CURRENT FLOW (PROBLEMATIC)

### What Happens Now (Lines 217-349 in CreateBountyPage.tsx)

```
User clicks "Create Bounty"
         ↓
┌──────────────────────────────────────────┐
│ STEP 1: CREATE IN DATABASE FIRST        │ ← PROBLEM STARTS HERE
│ await createBounty(bountyData)           │
│ Get bounty UUID                          │
│ Status: 'active'                         │
└──────────────────────────────────────────┘
         ↓
┌──────────────────────────────────────────┐
│ STEP 2: BLOCKCHAIN PAYMENT               │ ← CAN FAIL HERE
│ await escrowService.createBounty()       │
│ User approves in wallet...               │
│ - User closes wallet ❌                  │
│ - User rejects transaction ❌            │
│ - Insufficient funds ❌                  │
│ - Network timeout ❌                     │
│ - Wallet crashes ❌                      │
└──────────────────────────────────────────┘
         ↓
    FAILURE! But bounty exists in DB
         ↓
┌──────────────────────────────────────────┐
│ RESULT: ORPHANED BOUNTY                  │
│ - Bounty shows on "Join Bounty" page    │
│ - Prize amount shows (but not in escrow)│
│ - Users can join but can't win          │
│ - Database cluttered with failed bounties│
└──────────────────────────────────────────┘
```

### Code Evidence (Lines 217-241)

```typescript
// FIRST: Create bounty in database to get UUID
console.log('📝 Creating bounty in database first to get UUID...');
const bountyData = {
  // ... bounty details
  status: 'active', // ← Already active!
  prize_amount: parseFloat(form.prizeAmount) || 0,
};

createdBountyData = await createBounty(bountyData);
const bountyUUID = createdBountyData.id;
console.log('✅ Bounty created in database with UUID:', bountyUUID);

// NOW: Use the UUID for the smart contract
// ⚠️ If this fails, bounty is orphaned!
const tx = await escrowService.createBounty(
  bountyUUID,
  solutionWord,
  prizeAmount,
  parseInt(form.duration),
  bountyUUID
);
```

### Why This Happens

**Root Cause:** Need the UUID before calling smart contract, so database creation happens first.

**The Problem:**
1. Database bounty created with `status: 'active'`
2. Smart contract call fails
3. Catch block doesn't delete the bounty
4. Orphaned bounty remains in database

---

## 📊 IMPACT ANALYSIS

### Issue 1a: Stuck on "Creating" Button
**Symptoms:**
- Button shows loader indefinitely
- Transaction succeeds on blockchain
- Success modal never appears
- Bounty exists and is joinable

**Cause:** Line 262-267 timeout or error after transaction sent

### Issue 1b: Wallet Crash Creates Ghost Bounty
**Symptoms:**
- Bounty created in database
- No blockchain transaction
- Prize amount = 0 in escrow
- Users can join but can't win

**Cause:** Bounty created (line 239) before smart contract call (line 251)

### Issue 2: mark_prize_paid() Validation Error
**Error Message:**
```
Error in mark_prize_paid for bounty [...] and user [...]:
new row for relation "payment_transactions" violates check
constraint "check_valid_transaction_status" (SQLSTATE: 23514)
```

**Cause:** The `status` field in payment_transactions INSERT doesn't match allowed values

**Line 217-220 in mark_prize_paid():**
```sql
INSERT INTO payment_transactions (
  ...
  status,  -- 'completed' might not be valid
  ...
) VALUES (..., 'completed', ...);
```

**Fix:** Check what values are allowed in the constraint.

---

## ✅ SOLUTION OPTIONS

### OPTION 1: Draft-Then-Activate Pattern (RECOMMENDED)

**Concept:** Create bounty with `status: 'draft'`, only activate after payment succeeds.

**Advantages:**
- ✅ Orphaned bounties stay hidden (draft status)
- ✅ Can implement auto-cleanup for old drafts
- ✅ Minimal code changes
- ✅ Backward compatible
- ✅ Clear audit trail

**Implementation:**

```typescript
// STEP 1: Create bounty as DRAFT
const bountyData = {
  ...
  status: 'draft', // ← Changed from 'active'
  prize_amount: parseFloat(form.prizeAmount) || 0,
};

createdBountyData = await createBounty(bountyData);
const bountyUUID = createdBountyData.id;

try {
  // STEP 2: Process blockchain payment
  const tx = await escrowService.createBounty(...);
  await tx.wait();

  // STEP 3: Only NOW activate the bounty
  await supabase
    .from('bounties')
    .update({
      status: 'active',
      transaction_hash: tx.hash,
      escrow_address: contractAddress,
      updated_at: new Date().toISOString()
    })
    .eq('id', bountyUUID);

  console.log('✅ Bounty activated after successful payment');

} catch (error) {
  // Payment failed - bounty stays in draft
  console.log('⚠️ Payment failed - bounty remains in draft status');

  // Optional: Delete draft after X minutes
  setTimeout(async () => {
    await supabase
      .from('bounties')
      .delete()
      .eq('id', bountyUUID)
      .eq('status', 'draft'); // Only delete if still draft
  }, 5 * 60 * 1000); // 5 minutes
}
```

**Database Query Filter:**
```typescript
// In BountyHuntPage, only show active bounties
const { data: bounties } = await supabase
  .from('bounties')
  .select('*')
  .eq('status', 'active') // ← Filters out drafts
  .gte('end_time', new Date().toISOString());
```

**Cleanup Job (Optional):**
```sql
-- Run periodically to clean up old drafts
DELETE FROM bounties
WHERE status = 'draft'
  AND created_at < NOW() - INTERVAL '1 hour';
```

---

### OPTION 2: Pending-Payment Status

**Concept:** Add new status `'pending-payment'` to track payment-in-progress state.

**Advantages:**
- ✅ Explicit payment state tracking
- ✅ Better UX (can show "Payment pending..." in UI)
- ✅ Easy to query for stuck payments
- ✅ Can retry payment without recreating bounty

**Implementation:**

```typescript
// Add to bounty_status enum in database
ALTER TYPE bounty_status ADD VALUE 'pending-payment';

// Create bounty with pending-payment status
const bountyData = {
  ...
  status: 'pending-payment', // ← New status
};

// After successful payment
await supabase
  .from('bounties')
  .update({ status: 'active' })
  .eq('id', bountyUUID);

// UI can show different states
if (bounty.status === 'pending-payment') {
  return <Badge>⏳ Payment Pending</Badge>;
}
```

**Cleanup:**
```sql
-- Auto-cancel pending payments after 10 minutes
UPDATE bounties
SET status = 'cancelled'
WHERE status = 'pending-payment'
  AND created_at < NOW() - INTERVAL '10 minutes';
```

---

### OPTION 3: Transaction-Based Rollback

**Concept:** Delete bounty from database if payment fails.

**Advantages:**
- ✅ No orphaned bounties
- ✅ Clean database
- ✅ Simple to understand

**Disadvantages:**
- ❌ Lose audit trail
- ❌ Can't retry payment
- ❌ Need to recreate everything on retry

**Implementation:**

```typescript
let bountyUUID: string | null = null;

try {
  // Create bounty
  createdBountyData = await createBounty(bountyData);
  bountyUUID = createdBountyData.id;

  // Process payment
  const tx = await escrowService.createBounty(...);
  await tx.wait();

  // Update with transaction info
  await updateBountyTransactionInfo(bountyUUID, tx.hash, contractAddress);

} catch (error) {
  // ROLLBACK: Delete bounty if payment failed
  if (bountyUUID) {
    console.log('🔄 Rolling back - deleting bounty from database');
    await supabase
      .from('bounties')
      .delete()
      .eq('id', bountyUUID);
  }
  throw error;
}
```

---

### OPTION 4: Two-Phase Commit Pattern

**Concept:** Reserve bounty ID, complete payment, then finalize bounty creation.

**Advantages:**
- ✅ Most robust
- ✅ Can handle complex scenarios
- ✅ Best for production systems

**Disadvantages:**
- ❌ Most complex to implement
- ❌ Requires new database tables
- ❌ Overkill for current use case

**Implementation:**

```typescript
// Phase 1: Reserve ID
const reservationId = crypto.randomUUID();
await supabase.from('bounty_reservations').insert({
  id: reservationId,
  creator_id: walletAddress,
  expires_at: new Date(Date.now() + 10 * 60 * 1000) // 10 min
});

// Phase 2: Process payment
const tx = await escrowService.createBounty(reservationId, ...);
await tx.wait();

// Phase 3: Commit - create actual bounty
await supabase.from('bounties').insert({
  id: reservationId, // Use same ID
  ...bountyData,
  status: 'active'
});

// Clean up reservation
await supabase.from('bounty_reservations').delete().eq('id', reservationId);
```

---

### OPTION 5: Optimistic UI with Reversal

**Concept:** Show bounty immediately, mark as "verifying", activate only after payment.

**Advantages:**
- ✅ Best UX (instant feedback)
- ✅ User sees bounty while payment processes
- ✅ Can show payment progress

**Disadvantages:**
- ❌ Complex state management
- ❌ Can confuse users if payment fails
- ❌ Need real-time updates

**Implementation:**

```typescript
// Create with verifying status
const bountyData = {
  ...
  status: 'verifying', // Special status
  payment_verified: false
};

// Show in UI immediately
setCreatedBounty({...}); // User sees success

// Process payment in background
(async () => {
  try {
    const tx = await escrowService.createBounty(...);
    await tx.wait();

    // Mark as verified
    await supabase
      .from('bounties')
      .update({
        status: 'active',
        payment_verified: true
      })
      .eq('id', bountyUUID);

  } catch (error) {
    // Show reversal message
    NotificationService.error('Payment failed - bounty cancelled');

    await supabase
      .from('bounties')
      .delete()
      .eq('id', bountyUUID);
  }
})();
```

---

## 🎯 RECOMMENDATION

### Best Solution: **OPTION 1 (Draft-Then-Activate)** + **OPTION 3 (Auto-Cleanup)**

**Why:**
1. ✅ Simple to implement
2. ✅ Minimal database changes
3. ✅ Backward compatible
4. ✅ Clean database (orphans auto-deleted)
5. ✅ Clear audit trail (can see failed attempts if needed)
6. ✅ Handles free bounties correctly (skip payment, activate immediately)

**Implementation Plan:**

```typescript
async function handleCreateBounty() {
  const prizeAmount = parseFloat(form.prizeAmount) || 0;
  const isFree = prizeAmount === 0;

  let bountyUUID: string | null = null;

  try {
    // STEP 1: Create bounty as DRAFT (or active if free)
    const bountyData = {
      ...formData,
      status: isFree ? 'active' : 'draft', // Free bounties skip payment
      prize_amount: prizeAmount,
    };

    const createdBounty = await createBounty(bountyData);
    bountyUUID = createdBounty.id;

    // STEP 2: If free, we're done!
    if (isFree) {
      showSuccessModal();
      return;
    }

    // STEP 3: Process payment (only for paid bounties)
    const tx = await escrowService.createBounty(bountyUUID, ...);
    await tx.wait();

    // STEP 4: Activate bounty after successful payment
    await supabase
      .from('bounties')
      .update({
        status: 'active',
        transaction_hash: tx.hash,
        escrow_address: contractAddress,
        updated_at: new Date().toISOString()
      })
      .eq('id', bountyUUID);

    showSuccessModal();

  } catch (error) {
    console.error('Bounty creation failed:', error);

    // CLEANUP: Delete draft bounty if payment failed
    if (bountyUUID && !isFree) {
      console.log('🔄 Cleaning up failed bounty...');
      await supabase
        .from('bounties')
        .delete()
        .eq('id', bountyUUID)
        .eq('status', 'draft'); // Only delete drafts
    }

    throw error; // Re-throw for error handling
  }
}
```

**Database Cleanup (Background Job):**
```sql
-- Create a database function to auto-cleanup
CREATE OR REPLACE FUNCTION cleanup_draft_bounties()
RETURNS void AS $$
BEGIN
  DELETE FROM bounties
  WHERE status = 'draft'
    AND created_at < NOW() - INTERVAL '15 minutes';

  RAISE NOTICE 'Cleaned up % draft bounties', ROW_COUNT;
END;
$$ LANGUAGE plpgsql;

-- Schedule via cron or call periodically from app
```

---

## 🐛 FIX FOR ISSUE 2: mark_prize_paid() Error

### Problem
```
violates check constraint "check_valid_transaction_status"
```

### Root Cause
The `status` value `'completed'` doesn't match allowed enum values.

### Solution
Check the payment_transactions table schema:

```sql
-- Find the constraint
SELECT
  conname,
  pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conname = 'check_valid_transaction_status';
```

**Likely Fix Options:**

**Option A: Use 'success' instead of 'completed'**
```typescript
// In mark_prize_paid function (line 217)
status,  -- Change from 'completed' to 'success'
```

**Option B: Update the constraint to allow 'completed'**
```sql
ALTER TABLE payment_transactions
DROP CONSTRAINT check_valid_transaction_status;

ALTER TABLE payment_transactions
ADD CONSTRAINT check_valid_transaction_status
CHECK (status IN ('pending', 'success', 'failed', 'completed'));
```

**Option C: Check migration 001 for correct enum**
```sql
-- Look for payment_status or transaction_status enum
SELECT enumlabel
FROM pg_enum
WHERE enumtypid = (
  SELECT oid FROM pg_type WHERE typname = 'transaction_status'
);
```

---

## 📋 IMPLEMENTATION CHECKLIST

To implement Option 1 (Recommended):

- [ ] Update CreateBountyPage.tsx to use `status: 'draft'`
- [ ] Add activation step after successful payment
- [ ] Add cleanup in catch block (delete draft on failure)
- [ ] Update BountyHuntPage query to filter `status = 'active'`
- [ ] Handle free bounties (skip payment, activate immediately)
- [ ] Test payment failure scenarios
- [ ] Test wallet rejection scenarios
- [ ] Test network timeout scenarios
- [ ] Create database cleanup function
- [ ] Fix mark_prize_paid() status value
- [ ] Test complete flow end-to-end

---

## 🧪 TEST SCENARIOS

### Test 1: User Cancels Payment
1. Create bounty with prize
2. Cancel in wallet when prompted
3. **Expected:** Bounty deleted from database, not visible

### Test 2: Wallet Crashes
1. Create bounty with prize
2. Simulate wallet crash during transaction
3. **Expected:** Bounty remains as draft, auto-deleted after 15 min

### Test 3: Insufficient Funds
1. Create bounty with prize > wallet balance
2. **Expected:** Bounty deleted, clear error message

### Test 4: Network Timeout
1. Create bounty with prize
2. Disconnect network after transaction sent
3. **Expected:** Bounty deleted after timeout

### Test 5: Free Bounty
1. Create bounty with prize = 0
2. **Expected:** Immediately active, no payment prompt

---

## 🎯 IMPLEMENTATION PROMPTS

### PROMPT FOR OPTION 1: Draft-Then-Activate (RECOMMENDED)

```
IMPLEMENT OPTION 1: Draft-Then-Activate Pattern for Bounty Creation

Fix the bounty creation flow to prevent orphaned bounties when payment fails.

Tasks:
1. Update CreateBountyPage.tsx to create bounties with status='draft' for paid bounties
2. Add activation step after successful blockchain payment
3. Add cleanup in catch block to delete draft bounties on payment failure
4. Update BountyHuntPage.tsx to only show bounties with status='active'
5. Handle free bounties (prize_amount = 0) by immediately setting status='active'
6. Fix mark_prize_paid() function to use correct status enum value
7. Create migration 022_cleanup_draft_bounties.sql for background cleanup

Requirements:
- Free bounties (0 HBAR) should skip payment and be immediately active
- Failed payment should delete the draft bounty
- Users should never see draft bounties in the Join Bounty page
- Auto-cleanup old draft bounties (>15 minutes) via database function

Show me the updated CreateBountyPage.tsx and any new migration files.
```

### PROMPT FOR OPTION 2: Pending-Payment Status

```
IMPLEMENT OPTION 2: Pending-Payment Status for Bounty Creation

Add explicit payment state tracking to bounty creation flow.

Tasks:
1. Create migration to add 'pending-payment' to bounty_status enum
2. Update CreateBountyPage.tsx to set status='pending-payment' during payment
3. Update to status='active' after successful payment
4. Update BountyHuntPage.tsx to show pending-payment bounties with special badge
5. Create database function to auto-cancel stuck pending-payment bounties (>10 minutes)
6. Add retry payment functionality for pending-payment bounties
7. Update UI to show "Payment Pending..." state

Show me the migration file and updated CreateBountyPage.tsx.
```

### PROMPT FOR OPTION 3: Transaction-Based Rollback

```
IMPLEMENT OPTION 3: Transaction Rollback for Failed Payments

Delete bounties from database if blockchain payment fails.

Tasks:
1. Update CreateBountyPage.tsx to track bounty UUID in try-catch block
2. Add rollback logic in catch block to delete bounty if payment fails
3. Ensure no orphaned bounties remain after payment failure
4. Handle edge cases (network timeout, wallet rejection, insufficient funds)
5. Add logging for audit trail before deletion
6. Update error messages to indicate no bounty was created

Show me the updated CreateBountyPage.tsx with complete error handling.
```

### PROMPT FOR OPTION 4: Two-Phase Commit Pattern

```
IMPLEMENT OPTION 4: Two-Phase Commit for Bounty Creation

Implement robust two-phase commit pattern for bounty creation.

Tasks:
1. Create migration for bounty_reservations table
2. Update CreateBountyPage.tsx to reserve bounty ID first
3. Process payment with reserved ID
4. Commit bounty creation after successful payment
5. Clean up reservations table
6. Add expiration logic for old reservations (>10 minutes)
7. Handle all edge cases and race conditions

Show me the migration file and updated CreateBountyPage.tsx.
```

### PROMPT FOR OPTION 5: Optimistic UI with Reversal

```
IMPLEMENT OPTION 5: Optimistic UI for Bounty Creation

Show instant success to user, verify payment in background.

Tasks:
1. Update CreateBountyPage.tsx to create bounty with status='verifying'
2. Show success modal immediately while payment processes in background
3. Update bounty to status='active' after payment verification
4. Add real-time status updates via websockets or polling
5. Handle payment reversal if blockchain transaction fails
6. Add UI notifications for verification status changes
7. Update BountyHuntPage to show verifying status

Show me the updated CreateBountyPage.tsx with background payment processing.
```

---

## 🔧 IMPLEMENTING OPTION 1 NOW

**Following the prompt above, implementing Draft-Then-Activate pattern...**

---

**End of Analysis**

**Recommendation:** Implement Option 1 for the best balance of simplicity, robustness, and user experience.
