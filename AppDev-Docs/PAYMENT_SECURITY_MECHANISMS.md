# Payment Security & Failsafe Mechanisms

**Created:** 2025-10-09
**Purpose:** Document all security measures and failsafe mechanisms for payment flows

---

## Overview

This document outlines the comprehensive security mechanisms implemented to prevent payment exploits, handle wallet crashes, and ensure data consistency between blockchain and database.

---

## 1. Bounty Creation Payment Flow

### Security Measures

#### 1.1 Transaction Verification
```typescript
// Step 1: Wait for transaction confirmation with timeout (120s)
const receipt = await Promise.race([
  tx.wait(),
  new Promise((_, reject) =>
    setTimeout(() => reject(new Error('Transaction timeout')), 120000)
  )
]);

// Step 2: Verify transaction succeeded on blockchain
if (!receipt || receipt.status === 0) {
  throw new Error('Transaction failed on blockchain');
}

// Step 3: Verify bounty exists on smart contract
const bountyInfo = await escrowService.getBountyInfo(bountyUUID);
if (!bountyInfo || Number(bountyInfo.prizeAmount) === 0) {
  throw new Error('Bounty not found on blockchain after transaction');
}
```

#### 1.2 Database-Blockchain Consistency Check
```typescript
// After all operations, verify state consistency
if (prizeAmount > 0) {
  if (!transactionHash) {
    throw new Error('Payment verification failed - no transaction hash recorded');
  }
  if (!contractAddress) {
    throw new Error('Payment verification failed - no contract address recorded');
  }
}
```

#### 1.3 Blockchain Finalization Delay
```typescript
// Wait for Hedera blockchain to finalize (2-3 seconds typical)
await new Promise(resolve => setTimeout(resolve, 3000));

// Then refresh balance to show accurate state
await refreshBalance();
```

### Exploit Prevention

**Scenario 1: User creates bounty but wallet crashes before payment**
- **Protection:** Bounty is created in database FIRST to get UUID
- **Detection:** If payment fails, transaction verification will throw error
- **Result:** User sees error message, bounty in database but marked as unpaid
- **Recovery:** Admin can manually verify and clean up unpaid bounties

**Scenario 2: Payment succeeds but success modal never shows**
- **Protection:** Success modal only shows after full verification chain
- **Detection:** Console logs show where failure occurred
- **Result:** Bounty is actually created and valid, just UI didn't update
- **Recovery:** User can refresh page to see created bounty

**Scenario 3: User tries to exploit by avoiding payment**
- **Protection:** Database consistency check requires both:
  - `transactionHash` (proof of payment)
  - `contractAddress` (proof on blockchain)
- **Detection:** Verification fails if either is missing for paid bounties
- **Result:** Transaction is rolled back, error shown to user
- **Recovery:** Bounty creation fails completely

---

## 2. Prize Distribution Payment Flow

### Security Measures

#### 2.1 Winner Verification
```sql
-- Database function ensures only valid winners receive payment
IF NOT v_is_winner THEN
  RAISE EXCEPTION 'User % is not marked as a winner', user_uuid;
END IF;

IF v_prize_amount <= 0 THEN
  RAISE EXCEPTION 'Prize amount is 0 for user %', user_uuid;
END IF;
```

#### 2.2 Duplicate Payment Prevention
```sql
-- Check if prize already paid
IF EXISTS (
  SELECT 1 FROM bounty_participants
  WHERE bounty_id = bounty_uuid
    AND user_id = user_uuid
    AND prize_paid_at IS NOT NULL
) THEN
  RAISE WARNING 'Prize already marked as paid. Updating tx_hash.';
END IF;
```

#### 2.3 Payment Recording with Delay
```typescript
// Step 1: Ensure blockchain has time to propagate
await new Promise(resolve => setTimeout(resolve, 1000));

// Step 2: Record payment in database
const { error } = await supabase.rpc('mark_prize_paid', {
  bounty_uuid: bounty.id,
  user_uuid: winner.id,
  tx_hash: transactionHash
});

// Step 3: Don't throw if recording fails - payment already succeeded
if (error) {
  console.error('⚠️ Warning: Failed to record payment details:', error);
  // Payment succeeded, just logging failed
}
```

#### 2.4 Balance Refresh with Finalization Delay
```typescript
// Wait for blockchain finalization before balance refresh
console.log('⏳ Waiting 30 seconds for blockchain finalization...');
await new Promise(resolve => setTimeout(resolve, 30000));

// Now refresh balance
await refreshBalance();
```

### Exploit Prevention

**Scenario 1: Admin completes bounty but wallet crashes during payment**
- **Protection:** Each winner payment is independent transaction
- **Detection:** Error handling catches wallet crash for specific winner
- **Result:** Previous winners already paid, only crashed payment fails
- **Recovery:** Admin can retry completion for remaining winners

**Scenario 2: Payment succeeds but database recording fails**
- **Protection:** Payment recording errors don't throw, only log warning
- **Detection:** Console shows warning about failed recording
- **Result:** Winner receives payment on blockchain, just database out of sync
- **Recovery:** Can manually verify transaction hash and update database

**Scenario 3: Trying to pay same winner twice**
- **Protection:** Database check for existing `prize_paid_at` timestamp
- **Detection:** Warning logged if duplicate payment attempted
- **Result:** Second payment updates transaction hash but doesn't duplicate
- **Recovery:** No recovery needed, prevented by database logic

---

## 3. Transaction Status Constraints

### Database Constraint
```sql
ALTER TABLE payment_transactions
ADD CONSTRAINT check_valid_transaction_status
CHECK (status IN ('pending', 'confirmed', 'failed', 'completed'));
```

### Status Flow
1. **pending** - Payment initiated, waiting for wallet confirmation
2. **confirmed** - Blockchain confirmed transaction
3. **completed** - Fully processed, database updated
4. **failed** - Transaction failed or rejected

### Migration Fix
- **File:** `021_fix_payment_transaction_status.sql`
- **Reason:** Migration 020 used 'completed' status but constraint only allowed 'confirmed'
- **Solution:** Updated constraint to include 'completed' status

---

## 4. Wallet Context Error Recovery

### Connection Error Handling
```typescript
// Check for existing connection before requesting new one
const existingAccounts = await window.ethereum.request({
  method: 'eth_accounts'
});

if (existingAccounts && existingAccounts.length > 0) {
  // Wallet already connected, just update state
  await updateWalletState();
  return;
}
```

### Error Code Handling
```typescript
if (error.code === -32603) {
  // Wallet connected but app state out of sync
  console.log('Attempting to update wallet state...');
  await updateWalletState();
}
```

---

## 5. Balance Refresh Strategy

### Multi-Attempt Refresh
```typescript
// Retry up to 3 times with fresh provider each time
for (let attempt = 1; attempt <= 3; attempt++) {
  const freshProvider = new BrowserProvider(window.ethereum);
  const balanceWei = await freshProvider.getBalance(walletAddress);
  const balanceHBAR = (Number(balanceWei) / 1e18).toFixed(4);

  if (balanceHBAR !== oldBalance) {
    setBalance(balanceHBAR);
    return; // Success
  }

  if (attempt < 3) {
    await new Promise(resolve => setTimeout(resolve, 1000));
  }
}
```

### Why Multiple Attempts?
- Hedera blockchain can cache balances for 1-2 seconds
- Creating fresh provider bypasses RPC caching
- 1 second delay between attempts allows propagation

---

## 6. Monitoring & Debugging

### Console Logging Strategy
All payment flows include comprehensive logging:

```typescript
console.log('💰 Processing payment first: Depositing', prizeAmount, 'HBAR');
console.log('✅ Transaction confirmed:', transactionHash);
console.log('✅ Transaction status:', receipt.status, '(1 = success)');
console.log('✅ Bounty verified on blockchain:', bountyInfo);
console.log('⏳ Waiting 30 seconds for blockchain finalization...');
console.log('✅ Payment verification complete');
```

### Error Messages
User-friendly errors with actionable information:

```typescript
if (errorMessage.includes('insufficient funds')) {
  errorMessage = `Insufficient HBAR balance. You need at least ${prizeAmount} HBAR`;
} else if (errorMessage.includes('user rejected')) {
  errorMessage = 'Transaction was rejected in your wallet';
} else if (errorMessage.includes('timeout')) {
  errorMessage = 'Transaction timeout. Please check your wallet';
}
```

---

## 7. Known Limitations & Future Improvements

### Current Limitations
1. **No automatic cleanup:** Unpaid bounties remain in database until manual cleanup
2. **No payment retry mechanism:** Users must manually retry failed payments
3. **Limited transaction monitoring:** Can't detect if user closed wallet mid-transaction

### Planned Improvements
1. **Automated cleanup job:** Background service to identify and archive unpaid bounties
2. **Payment queue system:** Retry failed payments automatically
3. **Webhook integration:** Real-time blockchain event monitoring
4. **Admin dashboard:** Tools to manually resolve payment inconsistencies

---

## 8. Testing Checklist

### Create Bounty Tests
- [ ] Create bounty with 0 HBAR (free bounty)
- [ ] Create bounty with prize, confirm payment
- [ ] Create bounty but reject wallet transaction
- [ ] Create bounty but close wallet during transaction
- [ ] Verify bounty appears on blockchain
- [ ] Verify balance updates correctly

### Complete Bounty Tests
- [ ] Complete bounty with single winner
- [ ] Complete bounty with multiple winners (split)
- [ ] Complete bounty but reject wallet transaction
- [ ] Complete bounty but close wallet during payment
- [ ] Verify all winners receive payment
- [ ] Verify balance updates correctly

### Error Recovery Tests
- [ ] Wallet disconnects during transaction
- [ ] Network error during transaction
- [ ] Insufficient balance error
- [ ] Transaction timeout
- [ ] Database error after successful payment

---

## 9. Security Best Practices

### For Developers
1. **Always verify blockchain state** after transactions
2. **Never trust client-side data** - verify on contract
3. **Use delays** for blockchain finalization (2-3 seconds)
4. **Log everything** for debugging and auditing
5. **Fail gracefully** - don't crash on payment failures

### For Users
1. **Keep wallet connected** throughout transaction
2. **Don't close wallet** until success confirmation
3. **Check HashScan** if transaction seems stuck
4. **Contact support** if payment fails but balance deducted

---

## 10. Emergency Procedures

### If Payment Stuck
1. Check console logs for transaction hash
2. Verify transaction on HashScan
3. If confirmed, manually update database
4. If failed, retry transaction

### If Database Out of Sync
1. Query blockchain for ground truth
2. Update database to match blockchain state
3. Notify affected users
4. Document incident for future prevention

---

**Last Updated:** 2025-10-09
**Maintainer:** Development Team
**Review Schedule:** After each payment-related change
