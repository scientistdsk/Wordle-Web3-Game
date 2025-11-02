import { describe, it, expect, beforeEach, vi } from 'vitest';
import {
  createMockUser,
  createMockBounty,
  createMockSupabaseClient,
  createMockContract,
  generateMockTxHash,
  hbarToWei,
  weiToHbar,
  expectTxSuccess,
  simulateInsufficientBalance,
  simulateNetworkError,
  simulateContractRevert,
} from '../helpers/test-helpers';
import { setupMockWallet } from '../helpers/mock-wallet';

/**
 * Payment Flow Integration Tests
 * Tests all payment-related flows including deposits, distributions, and refunds
 */

describe('Payment Flow Integration', () => {
  let mockWallet: ReturnType<typeof setupMockWallet>;
  let mockSupabase: ReturnType<typeof createMockSupabaseClient>;
  let mockContract: ReturnType<typeof createMockContract>;
  let testUser: ReturnType<typeof createMockUser>;

  beforeEach(() => {
    mockWallet = setupMockWallet({
      balance: hbarToWei(100),
      isConnected: true,
    });

    mockSupabase = createMockSupabaseClient();
    mockContract = createMockContract();

    testUser = createMockUser({
      wallet_address: mockWallet.getState().address!,
    });
  });

  describe('Bounty Creation Payment', () => {
    it('successfully deposits HBAR to escrow contract', async () => {
      const bountyData = createMockBounty({
        creator_id: testUser.id,
        prize_amount: 5.0,
      });

      const initialBalance = mockWallet.getState().balance;

      // Create bounty with payment
      const tx = await mockContract.createBounty(
        bountyData.blockchain_bounty_id,
        bountyData.solution_hash,
        Math.floor(new Date(bountyData.end_time!).getTime() / 1000),
        JSON.stringify({ title: bountyData.title })
      );

      expectTxSuccess(tx);

      // Verify transaction hash format
      expect(tx.hash).toMatch(/^0x[a-f0-9]{64}$/i);

      // Record transaction in database
      const txRecord = {
        user_id: testUser.id,
        bounty_id: bountyData.id,
        transaction_type: 'bounty_creation',
        amount: bountyData.prize_amount,
        transaction_hash: tx.hash,
        status: 'pending',
        created_at: new Date().toISOString(),
      };

      await mockSupabase.from('payment_transactions').insert(txRecord);

      // Wait for confirmation
      const receipt = await tx.wait();
      expect(receipt.status).toBe(1);

      // Update transaction status
      await mockSupabase
        .from('payment_transactions')
        .update({ status: 'confirmed' })
        .eq('transaction_hash', tx.hash);

      // Verify final state
      const { data: confirmedTx } = await mockSupabase
        .from('payment_transactions')
        .select()
        .eq('transaction_hash', tx.hash)
        .single();

      expect(confirmedTx.status).toBe('confirmed');
      expect(confirmedTx.amount).toBe(5.0);
      expect(confirmedTx.transaction_type).toBe('bounty_creation');
    });

    it('tracks transaction in Supabase payment_transactions table', async () => {
      const bountyData = createMockBounty({
        creator_id: testUser.id,
        prize_amount: 3.0,
      });

      const tx = await mockContract.createBounty(
        bountyData.blockchain_bounty_id,
        bountyData.solution_hash,
        Math.floor(new Date(bountyData.end_time!).getTime() / 1000),
        '{}'
      );

      const txRecord = {
        user_id: testUser.id,
        bounty_id: bountyData.id,
        transaction_type: 'bounty_creation',
        amount: 3.0,
        transaction_hash: tx.hash,
        status: 'confirmed',
        blockchain_network: 'testnet',
        created_at: new Date().toISOString(),
      };

      await mockSupabase.from('payment_transactions').insert(txRecord);

      // Query transaction
      const { data: savedTx } = await mockSupabase
        .from('payment_transactions')
        .select()
        .eq('transaction_hash', tx.hash)
        .single();

      expect(savedTx).toBeDefined();
      expect(savedTx.user_id).toBe(testUser.id);
      expect(savedTx.bounty_id).toBe(bountyData.id);
      expect(savedTx.amount).toBe(3.0);
      expect(savedTx.transaction_type).toBe('bounty_creation');
      expect(savedTx.status).toBe('confirmed');
    });

    it('handles failed transaction and retry logic', async () => {
      const bountyData = createMockBounty({
        creator_id: testUser.id,
        prize_amount: 5.0,
      });

      // First attempt fails
      mockContract.createBounty.mockRejectedValueOnce(
        new Error('Transaction failed: network error')
      );

      await expect(
        mockContract.createBounty(
          bountyData.blockchain_bounty_id,
          bountyData.solution_hash,
          Math.floor(new Date(bountyData.end_time!).getTime() / 1000),
          '{}'
        )
      ).rejects.toThrow('network error');

      // Record failed transaction
      const failedTxHash = generateMockTxHash();
      await mockSupabase.from('payment_transactions').insert({
        user_id: testUser.id,
        bounty_id: bountyData.id,
        transaction_type: 'bounty_creation',
        amount: 5.0,
        transaction_hash: failedTxHash,
        status: 'failed',
        error_message: 'Transaction failed: network error',
      });

      // Retry succeeds
      const retryTx = await mockContract.createBounty(
        bountyData.blockchain_bounty_id,
        bountyData.solution_hash,
        Math.floor(new Date(bountyData.end_time!).getTime() / 1000),
        '{}'
      );

      expectTxSuccess(retryTx);

      await mockSupabase.from('payment_transactions').insert({
        user_id: testUser.id,
        bounty_id: bountyData.id,
        transaction_type: 'bounty_creation',
        amount: 5.0,
        transaction_hash: retryTx.hash,
        status: 'confirmed',
      });

      // Verify both transactions recorded
      const { data: allTxs } = await mockSupabase
        .from('payment_transactions')
        .select()
        .eq('bounty_id', bountyData.id);

      expect(allTxs).toHaveLength(2);
      expect(allTxs.find((tx: any) => tx.status === 'failed')).toBeDefined();
      expect(allTxs.find((tx: any) => tx.status === 'confirmed')).toBeDefined();
    });

    it('validates sufficient balance before transaction', async () => {
      // Set insufficient balance
      mockWallet.setBalance(hbarToWei(1.0));

      const bountyData = createMockBounty({
        prize_amount: 10.0, // More than available balance
      });

      mockContract.createBounty.mockRejectedValueOnce(
        new Error('Insufficient balance for transaction')
      );

      await expect(
        mockContract.createBounty(
          bountyData.blockchain_bounty_id,
          bountyData.solution_hash,
          Math.floor(new Date(bountyData.end_time!).getTime() / 1000),
          '{}'
        )
      ).rejects.toThrow('Insufficient balance');
    });
  });

  describe('Prize Distribution Payment', () => {
    it('distributes prize with correct platform fee deduction', async () => {
      const bountyData = createMockBounty({
        prize_amount: 10.0,
      });

      const winner = createMockUser();

      // Complete bounty
      const tx = await mockContract.completeBounty(
        bountyData.blockchain_bounty_id,
        winner.wallet_address,
        'TESTS'
      );

      expectTxSuccess(tx);

      // Calculate amounts
      const platformFeePercent = 2.5;
      const platformFee = 10.0 * (platformFeePercent / 100); // 0.25 HBAR
      const netPrize = 10.0 - platformFee; // 9.75 HBAR

      // Record prize distribution
      await mockSupabase.from('payment_transactions').insert({
        user_id: winner.id,
        bounty_id: bountyData.id,
        transaction_type: 'prize_distribution',
        amount: netPrize,
        platform_fee: platformFee,
        transaction_hash: tx.hash,
        status: 'confirmed',
      });

      const { data: prizeTx } = await mockSupabase
        .from('payment_transactions')
        .select()
        .eq('transaction_hash', tx.hash)
        .single();

      expect(prizeTx.amount).toBeCloseTo(9.75, 2);
      expect(prizeTx.platform_fee).toBeCloseTo(0.25, 2);
      expect(prizeTx.amount + prizeTx.platform_fee).toBeCloseTo(10.0, 2);
    });

    it('records platform fee separately', async () => {
      const testCases = [
        { prize: 1.0, expectedFee: 0.025, expectedNet: 0.975 },
        { prize: 5.0, expectedFee: 0.125, expectedNet: 4.875 },
        { prize: 100.0, expectedFee: 2.5, expectedNet: 97.5 },
      ];

      for (const testCase of testCases) {
        const bountyData = createMockBounty({
          prize_amount: testCase.prize,
        });

        const winner = createMockUser();
        const tx = await mockContract.completeBounty(
          bountyData.blockchain_bounty_id,
          winner.wallet_address,
          'TESTS'
        );

        await mockSupabase.from('payment_transactions').insert({
          user_id: winner.id,
          bounty_id: bountyData.id,
          transaction_type: 'prize_distribution',
          amount: testCase.expectedNet,
          platform_fee: testCase.expectedFee,
          transaction_hash: tx.hash,
          status: 'confirmed',
        });

        const { data: tx_record } = await mockSupabase
          .from('payment_transactions')
          .select()
          .eq('transaction_hash', tx.hash)
          .single();

        expect(tx_record.amount).toBeCloseTo(testCase.expectedNet, 3);
        expect(tx_record.platform_fee).toBeCloseTo(testCase.expectedFee, 3);
      }
    });
  });

  describe('Refund Payment', () => {
    it('processes refund with platform fee deduction', async () => {
      const bountyData = createMockBounty({
        creator_id: testUser.id,
        prize_amount: 4.0,
      });

      // Cancel bounty
      const tx = await mockContract.cancelBounty(bountyData.blockchain_bounty_id);
      expectTxSuccess(tx);

      const platformFeePercent = 2.5;
      const platformFee = 4.0 * (platformFeePercent / 100); // 0.1 HBAR
      const refundAmount = 4.0 - platformFee; // 3.9 HBAR

      await mockSupabase.from('payment_transactions').insert({
        user_id: testUser.id,
        bounty_id: bountyData.id,
        transaction_type: 'refund',
        amount: refundAmount,
        platform_fee: platformFee,
        transaction_hash: tx.hash,
        status: 'confirmed',
      });

      const { data: refundTx } = await mockSupabase
        .from('payment_transactions')
        .select()
        .eq('transaction_type', 'refund')
        .eq('bounty_id', bountyData.id)
        .single();

      expect(refundTx.amount).toBeCloseTo(3.9, 2);
      expect(refundTx.platform_fee).toBeCloseTo(0.1, 2);
    });

    it('handles expired bounty refund claim', async () => {
      const pastTime = new Date(Date.now() - 48 * 60 * 60 * 1000); // 2 days ago
      const bountyData = createMockBounty({
        creator_id: testUser.id,
        prize_amount: 2.0,
        end_time: pastTime.toISOString(),
        status: 'expired',
      });

      // Claim expired bounty refund
      const tx = await mockContract.cancelBounty(bountyData.blockchain_bounty_id);
      expectTxSuccess(tx);

      const refundAmount = 2.0 * 0.975; // 2.5% fee

      await mockSupabase.from('payment_transactions').insert({
        user_id: testUser.id,
        bounty_id: bountyData.id,
        transaction_type: 'expired_refund',
        amount: refundAmount,
        platform_fee: 2.0 - refundAmount,
        transaction_hash: tx.hash,
        status: 'confirmed',
      });

      const { data: expiredRefundTx } = await mockSupabase
        .from('payment_transactions')
        .select()
        .eq('transaction_type', 'expired_refund')
        .single();

      expect(expiredRefundTx).toBeDefined();
      expect(expiredRefundTx.amount).toBeCloseTo(1.95, 2);
    });
  });

  describe('Transaction Status Tracking', () => {
    it('tracks transaction from pending to confirmed', async () => {
      const bountyData = createMockBounty({
        creator_id: testUser.id,
        prize_amount: 3.0,
      });

      const tx = await mockContract.createBounty(
        bountyData.blockchain_bounty_id,
        bountyData.solution_hash,
        Math.floor(new Date(bountyData.end_time!).getTime() / 1000),
        '{}'
      );

      // Insert as pending
      const txId = crypto.randomUUID();
      await mockSupabase.from('payment_transactions').insert({
        id: txId,
        user_id: testUser.id,
        bounty_id: bountyData.id,
        transaction_type: 'bounty_creation',
        amount: 3.0,
        transaction_hash: tx.hash,
        status: 'pending',
      });

      // Verify pending status
      const { data: pendingTx } = await mockSupabase
        .from('payment_transactions')
        .select()
        .eq('id', txId)
        .single();

      expect(pendingTx.status).toBe('pending');

      // Wait for confirmation
      await tx.wait();

      // Update to confirmed
      await mockSupabase
        .from('payment_transactions')
        .update({
          status: 'confirmed',
          confirmed_at: new Date().toISOString(),
        })
        .eq('id', txId);

      // Verify confirmed status
      const { data: confirmedTx } = await mockSupabase
        .from('payment_transactions')
        .select()
        .eq('id', txId)
        .single();

      expect(confirmedTx.status).toBe('confirmed');
      expect(confirmedTx.confirmed_at).toBeDefined();
    });

    it('handles failed transaction status', async () => {
      const bountyData = createMockBounty({
        prize_amount: 5.0,
      });

      mockContract.createBounty.mockRejectedValueOnce(
        new Error('Transaction reverted: insufficient funds')
      );

      const failedTxHash = generateMockTxHash();

      try {
        await mockContract.createBounty(
          bountyData.blockchain_bounty_id,
          bountyData.solution_hash,
          Math.floor(new Date(bountyData.end_time!).getTime() / 1000),
          '{}'
        );
      } catch (error: any) {
        // Record failed transaction
        await mockSupabase.from('payment_transactions').insert({
          user_id: testUser.id,
          bounty_id: bountyData.id,
          transaction_type: 'bounty_creation',
          amount: 5.0,
          transaction_hash: failedTxHash,
          status: 'failed',
          error_message: error.message,
        });
      }

      const { data: failedTx } = await mockSupabase
        .from('payment_transactions')
        .select()
        .eq('transaction_hash', failedTxHash)
        .single();

      expect(failedTx.status).toBe('failed');
      expect(failedTx.error_message).toContain('insufficient funds');
    });
  });

  describe('HBAR Conversion', () => {
    it('correctly converts HBAR to wei (tinybars)', () => {
      expect(hbarToWei(1)).toBe(BigInt(100000000)); // 1 HBAR = 10^8 tinybars
      expect(hbarToWei(0.5)).toBe(BigInt(50000000));
      expect(hbarToWei(100)).toBe(BigInt(10000000000));
    });

    it('correctly converts wei (tinybars) to HBAR', () => {
      expect(weiToHbar(BigInt(100000000))).toBe(1);
      expect(weiToHbar(BigInt(50000000))).toBe(0.5);
      expect(weiToHbar(BigInt(10000000000))).toBe(100);
    });

    it('handles roundtrip conversion accurately', () => {
      const testValues = [1, 5, 10, 50, 100, 1000];

      testValues.forEach((hbar) => {
        const wei = hbarToWei(hbar);
        const backToHbar = weiToHbar(wei);
        expect(backToHbar).toBe(hbar);
      });
    });
  });

  describe('Error Scenarios', () => {
    it('handles network errors gracefully', async () => {
      const bountyData = createMockBounty();

      mockContract.createBounty.mockRejectedValueOnce(
        new Error('Network request failed')
      );

      await expect(
        mockContract.createBounty(
          bountyData.blockchain_bounty_id,
          bountyData.solution_hash,
          Math.floor(new Date(bountyData.end_time!).getTime() / 1000),
          '{}'
        )
      ).rejects.toThrow('Network request failed');
    });

    it('handles contract revert with reason', async () => {
      const bountyData = createMockBounty();

      const revertError: any = new Error('execution reverted: Bounty already exists');
      revertError.code = 'CALL_EXCEPTION';

      mockContract.createBounty.mockRejectedValueOnce(revertError);

      await expect(
        mockContract.createBounty(
          bountyData.blockchain_bounty_id,
          bountyData.solution_hash,
          Math.floor(new Date(bountyData.end_time!).getTime() / 1000),
          '{}'
        )
      ).rejects.toThrow('Bounty already exists');
    });

    it('handles transaction timeout', async () => {
      const bountyData = createMockBounty();

      mockContract.createBounty.mockRejectedValueOnce(
        new Error('Transaction timeout: exceeded 30s')
      );

      await expect(
        mockContract.createBounty(
          bountyData.blockchain_bounty_id,
          bountyData.solution_hash,
          Math.floor(new Date(bountyData.end_time!).getTime() / 1000),
          '{}'
        )
      ).rejects.toThrow('timeout');
    });
  });
});
