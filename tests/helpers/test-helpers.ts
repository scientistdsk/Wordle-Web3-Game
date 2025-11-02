import { vi } from 'vitest';
import type { Bounty, User, BountyParticipant } from '@/utils/supabase/types';

/**
 * Test Helpers for Web3 Wordle Bounty Game
 * Common utilities for integration tests
 */

// Mock Data Generators
export const createMockUser = (overrides?: Partial<User>): User => ({
  id: crypto.randomUUID(),
  wallet_address: '0x' + Math.random().toString(16).substring(2, 42),
  username: `user_${Math.random().toString(36).substring(7)}`,
  created_at: new Date().toISOString(),
  updated_at: new Date().toISOString(),
  total_winnings: 0,
  bounties_won: 0,
  bounties_created: 0,
  ...overrides,
});

export const createMockBounty = (overrides?: Partial<Bounty>): Bounty => ({
  id: crypto.randomUUID(),
  blockchain_bounty_id: Math.floor(Math.random() * 1000000).toString(),
  creator_id: crypto.randomUUID(),
  title: 'Test Bounty',
  description: 'Test bounty description',
  prize_amount: 3.0,
  status: 'active',
  game_type: 'simple_wordle',
  word_length: 5,
  max_attempts: 6,
  time_limit_seconds: null,
  solution_word: 'TESTS',
  solution_hash: '0x' + 'a'.repeat(64),
  start_time: new Date().toISOString(),
  end_time: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
  participant_count: 0,
  winner_id: null,
  created_at: new Date().toISOString(),
  updated_at: new Date().toISOString(),
  ...overrides,
});

export const createMockParticipant = (
  overrides?: Partial<BountyParticipant>
): BountyParticipant => ({
  id: crypto.randomUUID(),
  bounty_id: crypto.randomUUID(),
  user_id: crypto.randomUUID(),
  status: 'active',
  total_attempts: 0,
  is_winner: false,
  joined_at: new Date().toISOString(),
  completed_at: null,
  ...overrides,
});

// Mock Transaction Hash Generator
export const generateMockTxHash = (): string => {
  return '0x' + Array.from({ length: 64 }, () =>
    Math.floor(Math.random() * 16).toString(16)
  ).join('');
};

// Mock Wallet Address Generator
export const generateMockAddress = (): string => {
  return '0x' + Array.from({ length: 40 }, () =>
    Math.floor(Math.random() * 16).toString(16)
  ).join('');
};

// Time Helpers
export const wait = (ms: number): Promise<void> =>
  new Promise((resolve) => setTimeout(resolve, ms));

export const advanceTime = async (ms: number): Promise<void> => {
  vi.useFakeTimers();
  vi.advanceTimersByTime(ms);
  await vi.runAllTimersAsync();
  vi.useRealTimers();
};

// HBAR Conversion Helpers
export const hbarToWei = (hbar: number): bigint => {
  return BigInt(Math.floor(hbar * 1e8));
};

export const weiToHbar = (wei: bigint): number => {
  return Number(wei) / 1e8;
};

// Mock Supabase Client
export const createMockSupabaseClient = () => {
  const mockData: any = {
    users: [],
    bounties: [],
    bounty_participants: [],
    game_attempts: [],
    payment_transactions: [],
  };

  const createQueryBuilder = (table: string, filters: Array<{column: string, value: any}> = []) => {
    const applyFilters = (data: any[]) => {
      return data.filter(item =>
        filters.every(f => item[f.column] === f.value)
      );
    };

    return {
      eq: (column: string, value: any) => {
        const newFilters = [...filters, { column, value }];
        return createQueryBuilder(table, newFilters);
      },
      single: async () => {
        const filtered = applyFilters(mockData[table]);
        return { data: filtered[0] || null, error: null };
      },
      then: (resolve: any) => {
        const filtered = applyFilters(mockData[table]);
        return Promise.resolve({ data: filtered, error: null }).then(resolve);
      },
    };
  };

  return {
    from: (table: string) => ({
      select: (columns = '*') => createQueryBuilder(table),
      insert: (data: any) => {
        const newItem = Array.isArray(data) ? data : [data];
        mockData[table].push(...newItem);
        return Promise.resolve({ data: newItem, error: null });
      },
      update: (data: any) => ({
        eq: (column: string, value: any) => {
          const index = mockData[table].findIndex((item: any) => item[column] === value);
          if (index !== -1) {
            mockData[table][index] = { ...mockData[table][index], ...data };
          }
          return Promise.resolve({ data: mockData[table][index], error: null });
        },
      }),
      delete: () => ({
        eq: (column: string, value: any) => {
          mockData[table] = mockData[table].filter((item: any) => item[column] !== value);
          return Promise.resolve({ error: null });
        },
      }),
    }),
    rpc: (fnName: string, params: any) => {
      // Mock RPC function responses
      if (fnName === 'get_or_create_user') {
        return Promise.resolve({
          data: createMockUser({ wallet_address: params.wallet_addr }),
          error: null,
        });
      }
      if (fnName === 'submit_attempt') {
        return Promise.resolve({ data: { is_correct: true }, error: null });
      }
      if (fnName === 'get_user_stats') {
        return Promise.resolve({
          data: {
            total_winnings: 0,
            bounties_won: 0,
            bounties_created: 0,
            total_attempts: 0,
          },
          error: null,
        });
      }
      return Promise.resolve({ data: null, error: null });
    },
    auth: {
      getSession: () => Promise.resolve({ data: { session: null }, error: null }),
    },
  };
};

// Mock Ethers Provider
export const createMockProvider = () => {
  return {
    getNetwork: vi.fn().mockResolvedValue({ chainId: 296 }),
    getBalance: vi.fn().mockResolvedValue(hbarToWei(100)),
    getSigner: vi.fn().mockReturnValue({
      getAddress: vi.fn().mockResolvedValue(generateMockAddress()),
      signMessage: vi.fn().mockResolvedValue('0xsignature'),
    }),
    estimateGas: vi.fn().mockResolvedValue(BigInt(100000)),
    call: vi.fn(),
  };
};

// Mock Smart Contract
export const createMockContract = () => {
  const mockBounties = new Map();

  return {
    createBounty: vi.fn().mockImplementation(async (bountyId, hash, deadline, metadata) => {
      const tx = { hash: generateMockTxHash(), wait: vi.fn().mockResolvedValue({ status: 1 }) };
      mockBounties.set(bountyId, {
        creator: generateMockAddress(),
        prizeAmount: hbarToWei(3),
        isActive: true,
        participantCount: 0,
      });
      return tx;
    }),
    joinBounty: vi.fn().mockImplementation(async (bountyId) => {
      const bounty = mockBounties.get(bountyId);
      if (bounty) {
        bounty.participantCount++;
      }
      return { hash: generateMockTxHash(), wait: vi.fn().mockResolvedValue({ status: 1 }) };
    }),
    completeBounty: vi.fn().mockImplementation(async (bountyId, winner, solution) => {
      const bounty = mockBounties.get(bountyId);
      if (bounty) {
        bounty.isActive = false;
        bounty.winner = winner;
      }
      return { hash: generateMockTxHash(), wait: vi.fn().mockResolvedValue({ status: 1 }) };
    }),
    cancelBounty: vi.fn().mockImplementation(async (bountyId) => {
      mockBounties.delete(bountyId);
      return { hash: generateMockTxHash(), wait: vi.fn().mockResolvedValue({ status: 1 }) };
    }),
    getBounty: vi.fn().mockImplementation((bountyId) => {
      return mockBounties.get(bountyId) || null;
    }),
    owner: vi.fn().mockResolvedValue(generateMockAddress()),
    paused: vi.fn().mockResolvedValue(false),
    PLATFORM_FEE_PERCENTAGE: vi.fn().mockResolvedValue(250), // 2.5%
  };
};

// Assertion Helpers
export const expectTxSuccess = (tx: any) => {
  expect(tx).toBeDefined();
  expect(tx.hash).toBeDefined();
  expect(typeof tx.hash).toBe('string');
  expect(tx.hash).toMatch(/^0x[a-f0-9]{64}$/i);
};

export const expectValidAddress = (address: string) => {
  expect(address).toBeDefined();
  expect(typeof address).toBe('string');
  expect(address).toMatch(/^0x[a-f0-9]{40}$/i);
};

export const expectValidBounty = (bounty: Bounty) => {
  expect(bounty).toBeDefined();
  expect(bounty.id).toBeDefined();
  expect(bounty.prize_amount).toBeGreaterThan(0);
  expect(['active', 'completed', 'cancelled']).toContain(bounty.status);
};

// Error Simulation
export const simulateNetworkError = () => {
  throw new Error('Network request failed');
};

export const simulateInsufficientBalance = () => {
  throw new Error('Insufficient balance for transaction');
};

export const simulateContractRevert = (reason: string) => {
  const error: any = new Error(`execution reverted: ${reason}`);
  error.code = 'CALL_EXCEPTION';
  throw error;
};
