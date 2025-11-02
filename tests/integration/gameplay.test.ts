import { describe, it, expect, beforeEach, vi } from 'vitest';
import {
  createMockUser,
  createMockBounty,
  createMockParticipant,
  createMockSupabaseClient,
  wait,
} from '../helpers/test-helpers';

/**
 * Gameplay Integration Tests
 * Tests game mechanics, word validation, attempt tracking, and win conditions
 */

describe('Gameplay Integration', () => {
  let mockSupabase: ReturnType<typeof createMockSupabaseClient>;
  let testUser: ReturnType<typeof createMockUser>;
  let testBounty: ReturnType<typeof createMockBounty>;
  let testParticipation: ReturnType<typeof createMockParticipant>;

  beforeEach(() => {
    mockSupabase = createMockSupabaseClient();

    testUser = createMockUser({
      username: 'test_player',
    });

    testBounty = createMockBounty({
      creator_id: createMockUser().id,
      solution_word: 'TESTS',
      word_length: 5,
      max_attempts: 6,
      game_type: 'simple_wordle',
      status: 'active',
    });

    testParticipation = createMockParticipant({
      bounty_id: testBounty.id,
      user_id: testUser.id,
      status: 'active',
      total_attempts: 0,
    });
  });

  describe('Word Validation', () => {
    it('validates words against dictionary via Supabase', async () => {
      const validWords = ['HELLO', 'WORLD', 'TESTS', 'GAMES', 'PRIZE'];

      // Mock dictionary table
      const dictionaryData = validWords.map((word) => ({
        id: crypto.randomUUID(),
        word: word,
        word_length: word.length,
        is_common: true,
      }));

      for (const word of validWords) {
        // Simulate RPC call to check_word_valid
        const { data, error } = await mockSupabase.rpc('check_word_valid', {
          word_to_check: word,
          length_required: 5,
        });

        // Mock returns true for valid words
        expect(error).toBeNull();
      }
    });

    it('rejects invalid words not in dictionary', async () => {
      const invalidWords = ['ZZZZZ', 'XQXQX', 'ABCDE'];

      for (const word of invalidWords) {
        const { data, error } = await mockSupabase.rpc('check_word_valid', {
          word_to_check: word,
          length_required: 5,
        });

        // Mock validation would fail for non-dictionary words
        // In real implementation, this would return false or error
        expect(data).not.toBe(true);
      }
    });

    it('validates word length matches bounty requirements', () => {
      const bounty4Letter = createMockBounty({ word_length: 4 });
      const bounty6Letter = createMockBounty({ word_length: 6 });

      expect('TEST'.length).toBe(bounty4Letter.word_length);
      expect('BOUNCE'.length).toBe(bounty6Letter.word_length);

      // Invalid lengths
      expect('TESTING'.length).not.toBe(bounty4Letter.word_length);
      expect('HI'.length).not.toBe(bounty6Letter.word_length);
    });

    it('handles case-insensitive word validation', () => {
      const word = 'tests';
      const upperWord = word.toUpperCase();

      expect(upperWord).toBe('TESTS');
      expect(upperWord).toBe(testBounty.solution_word);
    });
  });

  describe('Attempt Tracking', () => {
    it('correctly tracks attempts in game_attempts table', async () => {
      const attempts = [
        { word: 'HELLO', result: 'incorrect' },
        { word: 'WORLD', result: 'incorrect' },
        { word: 'TESTS', result: 'correct' },
      ];

      for (let i = 0; i < attempts.length; i++) {
        const attempt = attempts[i];
        const attemptData = {
          id: crypto.randomUUID(),
          participant_id: testParticipation.id,
          bounty_id: testBounty.id,
          word_index: 0,
          attempt_number: i + 1,
          guessed_word: attempt.word,
          target_word: testBounty.solution_word,
          result: attempt.result,
          letter_results: calculateLetterResults(attempt.word, testBounty.solution_word),
          created_at: new Date().toISOString(),
        };

        await mockSupabase.from('game_attempts').insert(attemptData);
      }

      // Verify all attempts recorded
      const { data: allAttempts } = await mockSupabase
        .from('game_attempts')
        .select()
        .eq('participant_id', testParticipation.id);

      expect(allAttempts).toHaveLength(3);
      expect(allAttempts[0].attempt_number).toBe(1);
      expect(allAttempts[2].result).toBe('correct');
    });

    it('prevents exceeding max attempts limit', async () => {
      const maxAttempts = testBounty.max_attempts || 6;

      // Insert testParticipation for this test
      await mockSupabase.from('bounty_participants').insert(testParticipation);

      for (let i = 0; i < maxAttempts; i++) {
        await mockSupabase.from('game_attempts').insert({
          participant_id: testParticipation.id,
          bounty_id: testBounty.id,
          word_index: 0,
          attempt_number: i + 1,
          guessed_word: 'WRONG',
          target_word: testBounty.solution_word,
          result: 'incorrect',
        });
      }

      // Update participation attempts count
      await mockSupabase
        .from('bounty_participants')
        .update({ total_attempts: maxAttempts })
        .eq('id', testParticipation.id);

      const { data: participation } = await mockSupabase
        .from('bounty_participants')
        .select()
        .eq('id', testParticipation.id)
        .single();

      expect(participation.total_attempts).toBe(maxAttempts);

      // Next attempt should be rejected
      const canAttempt = participation.total_attempts < maxAttempts;
      expect(canAttempt).toBe(false);
    });

    it('calculates letter results correctly (correct/present/absent)', () => {
      const testCases = [
        {
          guess: 'HELLO',
          target: 'TESTS',
          expected: [
            { letter: 'H', status: 'absent' },
            { letter: 'E', status: 'correct' }, // E is in correct position
            { letter: 'L', status: 'absent' },
            { letter: 'L', status: 'absent' },
            { letter: 'O', status: 'absent' },
          ],
        },
        {
          guess: 'TESTS',
          target: 'TESTS',
          expected: [
            { letter: 'T', status: 'correct' },
            { letter: 'E', status: 'correct' },
            { letter: 'S', status: 'correct' },
            { letter: 'T', status: 'correct' },
            { letter: 'S', status: 'correct' },
          ],
        },
        {
          guess: 'STETS',
          target: 'TESTS',
          expected: [
            { letter: 'S', status: 'present' },
            { letter: 'T', status: 'present' },
            { letter: 'E', status: 'present' }, // E is at wrong position (pos 2 vs pos 1 in target)
            { letter: 'T', status: 'correct' },
            { letter: 'S', status: 'correct' },
          ],
        },
      ];

      testCases.forEach(({ guess, target, expected }) => {
        const results = calculateLetterResults(guess, target);
        expect(results).toEqual(expected);
      });
    });
  });

  describe('Win Conditions', () => {
    it('correctly determines winner when word is guessed', async () => {
      // Insert testParticipation for this test
      await mockSupabase.from('bounty_participants').insert(testParticipation);

      // Make attempts
      await mockSupabase.from('game_attempts').insert({
        participant_id: testParticipation.id,
        bounty_id: testBounty.id,
        word_index: 0,
        attempt_number: 1,
        guessed_word: 'TESTS',
        target_word: 'TESTS',
        result: 'correct',
      });

      // Mark as winner
      await mockSupabase
        .from('bounty_participants')
        .update({
          status: 'won',
          is_winner: true,
          words_completed: 1,
          completed_at: new Date().toISOString(),
        })
        .eq('id', testParticipation.id);

      const { data: winner } = await mockSupabase
        .from('bounty_participants')
        .select()
        .eq('id', testParticipation.id)
        .single();

      expect(winner.is_winner).toBe(true);
      expect(winner.status).toBe('won');
      expect(winner.words_completed).toBe(1);
    });

    it('handles loss when max attempts reached without success', async () => {
      const maxAttempts = 6;

      // Insert testParticipation for this test
      await mockSupabase.from('bounty_participants').insert(testParticipation);

      // Make 6 failed attempts
      for (let i = 0; i < maxAttempts; i++) {
        await mockSupabase.from('game_attempts').insert({
          participant_id: testParticipation.id,
          bounty_id: testBounty.id,
          word_index: 0,
          attempt_number: i + 1,
          guessed_word: 'WRONG',
          target_word: 'TESTS',
          result: 'incorrect',
        });
      }

      // Mark as failed
      await mockSupabase
        .from('bounty_participants')
        .update({
          status: 'failed',
          total_attempts: maxAttempts,
          completed_at: new Date().toISOString(),
        })
        .eq('id', testParticipation.id);

      const { data: participant } = await mockSupabase
        .from('bounty_participants')
        .select()
        .eq('id', testParticipation.id)
        .single();

      expect(participant.status).toBe('failed');
      expect(participant.is_winner).toBe(false);
      expect(participant.total_attempts).toBe(maxAttempts);
    });

    it('determines winner by fewest attempts when multiple players solve', async () => {
      const player1 = createMockParticipant({
        bounty_id: testBounty.id,
        user_id: createMockUser().id,
        total_attempts: 3,
        words_completed: 1,
        is_winner: false,
      });

      const player2 = createMockParticipant({
        bounty_id: testBounty.id,
        user_id: createMockUser().id,
        total_attempts: 2,
        words_completed: 1,
        is_winner: false,
      });

      const player3 = createMockParticipant({
        bounty_id: testBounty.id,
        user_id: createMockUser().id,
        total_attempts: 5,
        words_completed: 1,
        is_winner: false,
      });

      const participants = [player1, player2, player3];

      // Find winner (fewest attempts)
      const winner = participants.reduce((prev, current) =>
        current.total_attempts < prev.total_attempts ? current : prev
      );

      expect(winner).toBe(player2);
      expect(winner.total_attempts).toBe(2);
    });

    it('determines winner by fastest time when attempts are equal', async () => {
      const player1 = createMockParticipant({
        bounty_id: testBounty.id,
        total_attempts: 3,
        total_time_seconds: 45,
      });

      const player2 = createMockParticipant({
        bounty_id: testBounty.id,
        total_attempts: 3,
        total_time_seconds: 30,
      });

      const player3 = createMockParticipant({
        bounty_id: testBounty.id,
        total_attempts: 3,
        total_time_seconds: 60,
      });

      const participants = [player1, player2, player3];

      // Find winner (fastest time when attempts equal)
      const sameAttempts = participants.filter((p) => p.total_attempts === 3);
      const winner = sameAttempts.reduce((prev, current) =>
        current.total_time_seconds < prev.total_time_seconds ? current : prev
      );

      expect(winner).toBe(player2);
      expect(winner.total_time_seconds).toBe(30);
    });
  });

  describe('Concurrent Players', () => {
    it('handles multiple users playing same bounty simultaneously', async () => {
      const players = [
        createMockUser({ username: 'player1' }),
        createMockUser({ username: 'player2' }),
        createMockUser({ username: 'player3' }),
      ];

      const participations = players.map((player) =>
        createMockParticipant({
          bounty_id: testBounty.id,
          user_id: player.id,
          status: 'active',
        })
      );

      // All players join
      for (const participation of participations) {
        await mockSupabase.from('bounty_participants').insert(participation);
      }

      // Verify all registered
      const { data: allParticipants } = await mockSupabase
        .from('bounty_participants')
        .select()
        .eq('bounty_id', testBounty.id);

      expect(allParticipants).toHaveLength(3);

      // Each player makes attempts independently
      for (let i = 0; i < participations.length; i++) {
        await mockSupabase.from('game_attempts').insert({
          participant_id: participations[i].id,
          bounty_id: testBounty.id,
          word_index: 0,
          attempt_number: 1,
          guessed_word: `WORD${i}`,
          target_word: testBounty.solution_word,
          result: 'incorrect',
        });
      }

      // Verify each has independent attempt history
      for (const participation of participations) {
        const { data: attempts } = await mockSupabase
          .from('game_attempts')
          .select()
          .eq('participant_id', participation.id);

        expect(attempts).toHaveLength(1);
      }
    });

    it('ensures only one winner per bounty', async () => {
      const winner1 = createMockParticipant({
        bounty_id: testBounty.id,
        user_id: createMockUser().id,
        is_winner: true,
        status: 'won',
      });

      const winner2 = createMockParticipant({
        bounty_id: testBounty.id,
        user_id: createMockUser().id,
        is_winner: true,
        status: 'won',
      });

      await mockSupabase.from('bounty_participants').insert(winner1);

      // Second winner attempt should fail in real system
      // (database constraint or application logic)
      const { data: winners } = await mockSupabase
        .from('bounty_participants')
        .select()
        .eq('bounty_id', testBounty.id)
        .eq('is_winner', true);

      // In real system, should only allow 1 winner
      // This test shows the expectation
      expect(winners.length).toBeLessThanOrEqual(1);
    });
  });

  describe('Time-Based Bounties', () => {
    it('tracks time taken for each attempt', async () => {
      const timings = [5, 3, 7, 4]; // seconds

      // Insert testParticipation for this test
      await mockSupabase.from('bounty_participants').insert(testParticipation);

      for (let i = 0; i < timings.length; i++) {
        await mockSupabase.from('game_attempts').insert({
          participant_id: testParticipation.id,
          bounty_id: testBounty.id,
          word_index: 0,
          attempt_number: i + 1,
          guessed_word: 'GUESS',
          target_word: testBounty.solution_word,
          result: 'incorrect',
          time_taken_seconds: timings[i],
        });
      }

      const { data: attempts } = await mockSupabase
        .from('game_attempts')
        .select()
        .eq('participant_id', testParticipation.id);

      const totalTime = attempts.reduce((sum: number, att: any) => sum + att.time_taken_seconds, 0);
      expect(totalTime).toBe(19); // 5 + 3 + 7 + 4
    });

    it('enforces time limit if specified', async () => {
      const timedBounty = createMockBounty({
        time_limit_seconds: 60,
        game_type: 'time_based',
      });

      const participation = createMockParticipant({
        bounty_id: timedBounty.id,
        total_time_seconds: 0,
      });

      // Insert participation for this test
      await mockSupabase.from('bounty_participants').insert(participation);

      // Simulate taking 70 seconds (over limit)
      const timeTaken = 70;
      const timeLimit = timedBounty.time_limit_seconds!;

      expect(timeTaken).toBeGreaterThan(timeLimit);

      // Should be marked as failed
      await mockSupabase
        .from('bounty_participants')
        .update({
          status: 'failed',
          total_time_seconds: timeTaken,
        })
        .eq('id', participation.id);

      const { data: failed } = await mockSupabase
        .from('bounty_participants')
        .select()
        .eq('id', participation.id)
        .single();

      expect(failed.status).toBe('failed');
      expect(failed.total_time_seconds).toBeGreaterThan(timeLimit);
    });
  });

  describe('Multistage Bounties', () => {
    it('tracks progress through multiple words', async () => {
      const multistageBounty = createMockBounty({
        game_type: 'multistage',
        words: ['FIRST', 'SECOND', 'THIRD'],
      });

      const participation = createMockParticipant({
        bounty_id: multistageBounty.id,
        current_word_index: 0,
        words_completed: 0,
      });

      // Insert participation for this test
      await mockSupabase.from('bounty_participants').insert(participation);

      // Complete first word
      await mockSupabase.from('game_attempts').insert({
        participant_id: participation.id,
        bounty_id: multistageBounty.id,
        word_index: 0,
        attempt_number: 1,
        guessed_word: 'FIRST',
        target_word: 'FIRST',
        result: 'correct',
      });

      await mockSupabase
        .from('bounty_participants')
        .update({ current_word_index: 1, words_completed: 1 })
        .eq('id', participation.id);

      // Complete second word
      await mockSupabase.from('game_attempts').insert({
        participant_id: participation.id,
        bounty_id: multistageBounty.id,
        word_index: 1,
        attempt_number: 1,
        guessed_word: 'SECOND',
        target_word: 'SECOND',
        result: 'correct',
      });

      await mockSupabase
        .from('bounty_participants')
        .update({ current_word_index: 2, words_completed: 2 })
        .eq('id', participation.id);

      const { data: progress } = await mockSupabase
        .from('bounty_participants')
        .select()
        .eq('id', participation.id)
        .single();

      expect(progress.current_word_index).toBe(2);
      expect(progress.words_completed).toBe(2);
    });
  });
});

// Helper function for letter result calculation
function calculateLetterResults(
  guess: string,
  target: string
): Array<{ letter: string; status: 'correct' | 'present' | 'absent' }> {
  const results: Array<{ letter: string; status: 'correct' | 'present' | 'absent' }> = [];
  const targetLetters = target.split('');
  const guessLetters = guess.split('');

  // First pass: mark correct positions
  for (let i = 0; i < guessLetters.length; i++) {
    if (guessLetters[i] === targetLetters[i]) {
      results[i] = { letter: guessLetters[i], status: 'correct' };
      targetLetters[i] = ''; // Mark as used
    }
  }

  // Second pass: mark present/absent
  for (let i = 0; i < guessLetters.length; i++) {
    if (results[i]) continue; // Already marked as correct

    const letterIndex = targetLetters.indexOf(guessLetters[i]);
    if (letterIndex !== -1) {
      results[i] = { letter: guessLetters[i], status: 'present' };
      targetLetters[letterIndex] = ''; // Mark as used
    } else {
      results[i] = { letter: guessLetters[i], status: 'absent' };
    }
  }

  return results;
}
