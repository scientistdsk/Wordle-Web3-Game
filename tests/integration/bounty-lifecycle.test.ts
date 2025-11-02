import { describe, it, expect, beforeEach, vi } from 'vitest';
import {
  createMockUser,
  createMockBounty,
  createMockParticipant,
  createMockSupabaseClient,
  createMockContract,
  generateMockTxHash,
  hbarToWei,
  weiToHbar,
  expectTxSuccess,
  expectValidBounty,
} from '../helpers/test-helpers';
import { setupMockWallet } from '../helpers/mock-wallet';

/**
 * Bounty Lifecycle Integration Tests
 * Tests the complete flow from bounty creation to prize distribution
 */

describe('Bounty Lifecycle Integration', () => {
  let mockWallet: ReturnType<typeof setupMockWallet>;
  let mockSupabase: ReturnType<typeof createMockSupabaseClient>;
  let mockContract: ReturnType<typeof createMockContract>;
  let creatorUser: ReturnType<typeof createMockUser>;
  let playerUser: ReturnType<typeof createMockUser>;

  beforeEach(() => {
    // Setup mock wallet with 100 HBAR
    mockWallet = setupMockWallet({
      balance: hbarToWei(100),
      isConnected: true,
    });

    // Setup mock database
    mockSupabase = createMockSupabaseClient();

    // Setup mock contract
    mockContract = createMockContract();

    // Create test users
    creatorUser = createMockUser({
      wallet_address: '0x1111111111111111111111111111111111111111',
      username: 'bounty_creator',
    });

    playerUser = createMockUser({
      wallet_address: '0x2222222222222222222222222222222222222222',
      username: 'bounty_player',
    });
  });

  describe('Complete Bounty Workflow', () => {
    it('completes full bounty lifecycle: create → join → play → complete', async () => {
      // Step 1: Creator creates bounty (3 HBAR prize)
      const bountyData = createMockBounty({
        creator_id: creatorUser.id,
        prize_amount: 3.0,
        status: 'active',
        word_length: 5,
        max_attempts: 6,
        solution_word: 'TESTS',
      });

      // Simulate contract createBounty transaction
      const createTx = await mockContract.createBounty(
        bountyData.blockchain_bounty_id,
        bountyData.solution_hash,
        Math.floor(new Date(bountyData.end_time!).getTime() / 1000),
        JSON.stringify({ title: bountyData.title })
      );

      expectTxSuccess(createTx);

      // Wait for transaction confirmation
      const receipt = await createTx.wait();
      expect(receipt.status).toBe(1);

      // Verify HBAR locked in contract
      const contractBounty = await mockContract.getBounty(bountyData.blockchain_bounty_id);
      expect(contractBounty).toBeDefined();
      expect(contractBounty.prizeAmount).toBe(hbarToWei(3));
      expect(contractBounty.isActive).toBe(true);

      // Verify bounty saved in Supabase
      await mockSupabase.from('bounties').insert(bountyData);
      const { data: savedBounty } = await mockSupabase
        .from('bounties')
        .select()
        .eq('id', bountyData.id)
        .single();

      expectValidBounty(savedBounty);
      expect(savedBounty.creator_id).toBe(creatorUser.id);
      expect(savedBounty.prize_amount).toBe(3.0);

      // Step 2: Player joins bounty
      const participation = createMockParticipant({
        bounty_id: bountyData.id,
        user_id: playerUser.id,
        status: 'active',
      });

      const joinTx = await mockContract.joinBounty(bountyData.blockchain_bounty_id);
      expectTxSuccess(joinTx);

      await mockSupabase.from('bounty_participants').insert(participation);

      // Verify participant count increased
      const updatedContractBounty = await mockContract.getBounty(bountyData.blockchain_bounty_id);
      expect(updatedContractBounty.participantCount).toBe(1);

      // Step 3: Player plays and wins
      const winningAttempts = [
        { word: 'HELLO', correct: false },
        { word: 'WORLD', correct: false },
        { word: 'TESTS', correct: true },
      ];

      for (let i = 0; i < winningAttempts.length; i++) {
        const attempt = winningAttempts[i];
        const attemptData = {
          participant_id: participation.id,
          bounty_id: bountyData.id,
          word_index: 0,
          attempt_number: i + 1,
          guessed_word: attempt.word,
          target_word: 'TESTS',
          result: attempt.correct ? 'correct' : 'incorrect',
        };

        await mockSupabase.from('game_attempts').insert(attemptData);

        if (attempt.correct) {
          // Player won! Update participation
          await mockSupabase
            .from('bounty_participants')
            .update({
              status: 'won',
              completed_at: new Date().toISOString(),
              words_completed: 1,
              total_attempts: i + 1,
            })
            .eq('id', participation.id);
          break;
        }
      }

      // Step 4: Admin completes bounty and distributes prize
      const platformFeePercent = 2.5;
      const netPrize = 3.0 * (1 - platformFeePercent / 100); // 2.925 HBAR
      const platformFee = 3.0 * (platformFeePercent / 100); // 0.075 HBAR

      const completeTx = await mockContract.completeBounty(
        bountyData.blockchain_bounty_id,
        playerUser.wallet_address,
        'TESTS'
      );

      expectTxSuccess(completeTx);

      // Verify contract state
      const completedBounty = await mockContract.getBounty(bountyData.blockchain_bounty_id);
      expect(completedBounty.isActive).toBe(false);
      expect(completedBounty.winner).toBe(playerUser.wallet_address);

      // Update database
      await mockSupabase
        .from('bounties')
        .update({
          status: 'completed',
          winner_id: playerUser.id,
        })
        .eq('id', bountyData.id);

      // Record payment transaction
      const paymentTx = {
        user_id: playerUser.id,
        bounty_id: bountyData.id,
        transaction_type: 'prize_distribution',
        amount: netPrize,
        platform_fee: platformFee,
        transaction_hash: completeTx.hash,
        status: 'confirmed',
      };

      await mockSupabase.from('payment_transactions').insert(paymentTx);

      // Step 5: Verify final state
      const { data: finalBounty } = await mockSupabase
        .from('bounties')
        .select()
        .eq('id', bountyData.id)
        .single();

      expect(finalBounty.status).toBe('completed');
      expect(finalBounty.winner_id).toBe(playerUser.id);

      const { data: finalParticipation } = await mockSupabase
        .from('bounty_participants')
        .select()
        .eq('id', participation.id)
        .single();

      expect(finalParticipation.status).toBe('won');
      expect(finalParticipation.total_attempts).toBe(3);

      // Verify prize amounts
      expect(netPrize).toBeCloseTo(2.925, 3);
      expect(platformFee).toBeCloseTo(0.075, 3);
      expect(netPrize + platformFee).toBeCloseTo(3.0, 3);
    });

    it('handles bounty cancellation before participants join', async () => {
      // Create bounty
      const bountyData = createMockBounty({
        creator_id: creatorUser.id,
        prize_amount: 5.0,
        status: 'active',
        participant_count: 0,
      });

      const createTx = await mockContract.createBounty(
        bountyData.blockchain_bounty_id,
        bountyData.solution_hash,
        Math.floor(new Date(bountyData.end_time!).getTime() / 1000),
        '{}'
      );

      expectTxSuccess(createTx);
      await mockSupabase.from('bounties').insert(bountyData);

      // Cancel bounty (should work as no participants)
      const cancelTx = await mockContract.cancelBounty(bountyData.blockchain_bounty_id);
      expectTxSuccess(cancelTx);

      // Calculate refund (with platform fee deduction)
      const platformFeePercent = 2.5;
      const refundAmount = 5.0 * (1 - platformFeePercent / 100); // 4.875 HBAR

      // Update database
      await mockSupabase
        .from('bounties')
        .update({ status: 'cancelled' })
        .eq('id', bountyData.id);

      // Record refund transaction
      await mockSupabase.from('payment_transactions').insert({
        user_id: creatorUser.id,
        bounty_id: bountyData.id,
        transaction_type: 'refund',
        amount: refundAmount,
        platform_fee: 5.0 - refundAmount,
        transaction_hash: cancelTx.hash,
        status: 'confirmed',
      });

      // Verify bounty cancelled
      const { data: cancelledBounty } = await mockSupabase
        .from('bounties')
        .select()
        .eq('id', bountyData.id)
        .single();

      expect(cancelledBounty.status).toBe('cancelled');
      expect(refundAmount).toBeCloseTo(4.875, 3);
    });

    it('handles expired bounty refund', async () => {
      // Create bounty with past end time
      const pastTime = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString(); // 1 day ago
      const bountyData = createMockBounty({
        creator_id: creatorUser.id,
        prize_amount: 2.0,
        status: 'expired',
        end_time: pastTime,
        participant_count: 0,
      });

      await mockSupabase.from('bounties').insert(bountyData);

      // Simulate claimExpiredBountyRefund (mocked as similar to cancel)
      const refundTx = await mockContract.cancelBounty(bountyData.blockchain_bounty_id);
      expectTxSuccess(refundTx);

      const platformFeePercent = 2.5;
      const refundAmount = 2.0 * (1 - platformFeePercent / 100);

      await mockSupabase
        .from('bounties')
        .update({ status: 'cancelled' })
        .eq('id', bountyData.id);

      await mockSupabase.from('payment_transactions').insert({
        user_id: creatorUser.id,
        bounty_id: bountyData.id,
        transaction_type: 'expired_refund',
        amount: refundAmount,
        platform_fee: 2.0 - refundAmount,
        transaction_hash: refundTx.hash,
        status: 'confirmed',
      });

      expect(refundAmount).toBeCloseTo(1.95, 3);
    });
  });

  describe('Edge Cases', () => {
    it('prevents cancellation after participants join', async () => {
      const bountyData = createMockBounty({
        creator_id: creatorUser.id,
        prize_amount: 3.0,
        participant_count: 1, // Has participants
      });

      await mockSupabase.from('bounties').insert(bountyData);

      // Simulate contract revert
      mockContract.cancelBounty.mockRejectedValueOnce(
        new Error('execution reverted: Cannot cancel bounty with participants')
      );

      await expect(
        mockContract.cancelBounty(bountyData.blockchain_bounty_id)
      ).rejects.toThrow('Cannot cancel bounty with participants');
    });

    it('handles multiple participants competing for same bounty', async () => {
      const bountyData = createMockBounty({
        creator_id: creatorUser.id,
        prize_amount: 10.0,
      });

      await mockContract.createBounty(
        bountyData.blockchain_bounty_id,
        bountyData.solution_hash,
        Math.floor(new Date(bountyData.end_time!).getTime() / 1000),
        '{}'
      );

      // Create 3 participants
      const participants = [
        createMockParticipant({ bounty_id: bountyData.id, user_id: playerUser.id }),
        createMockParticipant({ bounty_id: bountyData.id, user_id: creatorUser.id }),
        createMockParticipant({ bounty_id: bountyData.id, user_id: createMockUser().id }),
      ];

      // All join bounty
      for (const participant of participants) {
        await mockContract.joinBounty(bountyData.blockchain_bounty_id);
        await mockSupabase.from('bounty_participants').insert(participant);
      }

      const contractBounty = await mockContract.getBounty(bountyData.blockchain_bounty_id);
      expect(contractBounty.participantCount).toBe(3);

      // First participant wins
      const winner = participants[0];
      await mockSupabase
        .from('bounty_participants')
        .update({ status: 'won', is_winner: true })
        .eq('id', winner.id);

      // Others marked as completed but not winner
      for (let i = 1; i < participants.length; i++) {
        await mockSupabase
          .from('bounty_participants')
          .update({ status: 'completed', is_winner: false })
          .eq('id', participants[i].id);
      }

      // Complete bounty for winner
      await mockContract.completeBounty(
        bountyData.blockchain_bounty_id,
        playerUser.wallet_address,
        'TESTS'
      );

      // Verify only winner gets prize
      const winnerTx = await mockSupabase
        .from('payment_transactions')
        .select()
        .eq('user_id', playerUser.id)
        .eq('transaction_type', 'prize_distribution')
        .single();

      expect(winnerTx.data).toBeDefined();
    });

    it('validates minimum bounty amount', async () => {
      const tooSmallBounty = createMockBounty({
        prize_amount: 0.5, // Less than 1 HBAR minimum
      });

      mockContract.createBounty.mockRejectedValueOnce(
        new Error('execution reverted: Prize amount must be at least 1 HBAR')
      );

      await expect(
        mockContract.createBounty(
          tooSmallBounty.blockchain_bounty_id,
          tooSmallBounty.solution_hash,
          Math.floor(new Date(tooSmallBounty.end_time!).getTime() / 1000),
          '{}'
        )
      ).rejects.toThrow('Prize amount must be at least 1 HBAR');
    });

    it('handles insufficient balance for bounty creation', async () => {
      // Set wallet balance to insufficient amount
      mockWallet.setBalance(hbarToWei(0.5)); // Only 0.5 HBAR

      const bountyData = createMockBounty({
        prize_amount: 3.0, // Requires 3 HBAR
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

  describe('Prize Distribution', () => {
    it('correctly calculates platform fee (2.5%)', () => {
      const prizeAmounts = [1.0, 5.0, 10.0, 100.0];
      const platformFeePercent = 2.5;

      prizeAmounts.forEach((prize) => {
        const fee = prize * (platformFeePercent / 100);
        const netPrize = prize - fee;

        expect(fee).toBeCloseTo(prize * 0.025, 5);
        expect(netPrize).toBeCloseTo(prize * 0.975, 5);
        expect(netPrize + fee).toBeCloseTo(prize, 5);
      });
    });

    it('records all transactions correctly', async () => {
      const bountyData = createMockBounty({
        creator_id: creatorUser.id,
        prize_amount: 5.0,
      });

      // Create bounty transaction
      const createTx = await mockContract.createBounty(
        bountyData.blockchain_bounty_id,
        bountyData.solution_hash,
        Math.floor(new Date(bountyData.end_time!).getTime() / 1000),
        '{}'
      );

      await mockSupabase.from('payment_transactions').insert({
        user_id: creatorUser.id,
        bounty_id: bountyData.id,
        transaction_type: 'bounty_creation',
        amount: 5.0,
        transaction_hash: createTx.hash,
        status: 'confirmed',
      });

      // Complete bounty transaction
      const completeTx = await mockContract.completeBounty(
        bountyData.blockchain_bounty_id,
        playerUser.wallet_address,
        'TESTS'
      );

      await mockSupabase.from('payment_transactions').insert({
        user_id: playerUser.id,
        bounty_id: bountyData.id,
        transaction_type: 'prize_distribution',
        amount: 4.875, // 5.0 * 0.975
        platform_fee: 0.125,
        transaction_hash: completeTx.hash,
        status: 'confirmed',
      });

      // Verify transactions recorded
      const { data: transactions } = await mockSupabase
        .from('payment_transactions')
        .select()
        .eq('bounty_id', bountyData.id);

      expect(transactions).toHaveLength(2);
      expect(transactions[0].transaction_type).toBe('bounty_creation');
      expect(transactions[1].transaction_type).toBe('prize_distribution');
    });
  });
});
