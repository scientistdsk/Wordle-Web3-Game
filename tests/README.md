# Integration Tests - Web3 Wordle Bounty Game

Comprehensive integration test suite for the Web3 Wordle Bounty Game, covering bounty lifecycle, payment flows, and game mechanics.

## 📁 Test Structure

```
tests/
├── README.md                          # This file
├── setup.ts                           # Global test configuration
├── helpers/
│   ├── test-helpers.ts               # Common utilities & mocks
│   └── mock-wallet.ts                # Wallet mock implementation
└── integration/
    ├── bounty-lifecycle.test.ts      # Bounty flow tests (12 tests)
    ├── payment-flow.test.ts          # Payment tests (17 tests)
    └── gameplay.test.ts              # Game mechanic tests (15 tests)
```

## 🚀 Quick Start

### Install Dependencies
```bash
pnpm install
```

### Run Tests

```bash
# Run all tests in watch mode
pnpm test

# Run integration tests only
pnpm test:integration

# Run with UI dashboard
pnpm test:ui

# Generate coverage report
pnpm test:coverage
```

## 📊 Test Coverage

**Total Test Suites:** 3
**Total Test Cases:** 40+
**Target Coverage:** >70%

### Coverage by Area:
- ✅ Smart contract interactions
- ✅ Database operations
- ✅ Payment processing
- ✅ Game mechanics
- ✅ Edge cases
- ✅ Error scenarios

## 🧪 Test Suites

### 1. Bounty Lifecycle Tests (`bounty-lifecycle.test.ts`)

Tests the complete flow from bounty creation to prize distribution.

**Test Cases (12):**
- Complete bounty workflow (create → join → play → complete)
- HBAR locking in escrow
- Bounty cancellation before participants join
- Expired bounty refunds
- Multiple concurrent participants
- Winner determination
- Prize distribution with platform fee (2.5%)
- Edge cases (insufficient balance, invalid bounties, etc.)

**Example:**
```typescript
it('completes full bounty lifecycle', async () => {
  // 1. Creator creates bounty (3 HBAR)
  // 2. Verify bounty in Supabase
  // 3. Verify HBAR locked in contract
  // 4. Player joins bounty
  // 5. Player plays and wins
  // 6. Admin completes bounty
  // 7. Verify prize distributed (2.925 HBAR to winner)
  // 8. Verify platform fee (0.075 HBAR)
  // 9. Verify database updated
});
```

### 2. Payment Flow Tests (`payment-flow.test.ts`)

Tests all payment-related flows including deposits, distributions, and refunds.

**Test Cases (17):**
- Bounty creation payment (HBAR deposit)
- Transaction tracking (pending → confirmed → failed)
- Retry logic for failed transactions
- Balance validation
- Prize distribution with fee calculation
- Refund processing
- Transaction status lifecycle
- HBAR ↔ Wei conversions
- Error handling (network errors, contract reverts, timeouts)

**Example:**
```typescript
it('distributes prize with correct platform fee', async () => {
  const platformFeePercent = 2.5;
  const platformFee = 10.0 * (platformFeePercent / 100); // 0.25 HBAR
  const netPrize = 10.0 - platformFee; // 9.75 HBAR

  // Verify prize distribution
  expect(netPrize).toBeCloseTo(9.75, 2);
  expect(platformFee).toBeCloseTo(0.25, 2);
});
```

### 3. Gameplay Tests (`gameplay.test.ts`)

Tests game mechanics, word validation, attempt tracking, and win conditions.

**Test Cases (15):**
- Word validation against dictionary
- Invalid word rejection
- Attempt tracking in database
- Max attempts enforcement
- Letter result calculation (correct/present/absent)
- Win/loss conditions
- Winner determination (fewest attempts, fastest time)
- Concurrent players
- Time-based bounties
- Multistage bounties

**Example:**
```typescript
it('calculates letter results correctly', () => {
  const results = calculateLetterResults('HELLO', 'TESTS');
  expect(results[1]).toEqual({ letter: 'E', status: 'present' });
  expect(results[0]).toEqual({ letter: 'H', status: 'absent' });
});
```

## 🛠️ Test Helpers

### Mock Data Generators

```typescript
import { createMockUser, createMockBounty, createMockParticipant } from './helpers/test-helpers';

const user = createMockUser({ username: 'test_user' });
const bounty = createMockBounty({ prize_amount: 5.0 });
const participant = createMockParticipant({ bounty_id: bounty.id });
```

### Mock Wallet

```typescript
import { setupMockWallet } from './helpers/mock-wallet';

const mockWallet = setupMockWallet({
  balance: hbarToWei(100),
  isConnected: true,
});

// Connect wallet
await mockWallet.connect();

// Send transaction
const txHash = await mockWallet.sendTransaction({ value: hbarToWei(5) });

// Simulate events
mockWallet.simulateAccountChange('0x1234...');
mockWallet.simulateNetworkChange('0x129'); // Mainnet
```

### Mock Supabase Client

```typescript
import { createMockSupabaseClient } from './helpers/test-helpers';

const mockSupabase = createMockSupabaseClient();

// Insert data
await mockSupabase.from('bounties').insert(bountyData);

// Query data
const { data } = await mockSupabase
  .from('bounties')
  .select()
  .eq('id', bountyId)
  .single();
```

### Mock Smart Contract

```typescript
import { createMockContract } from './helpers/test-helpers';

const mockContract = createMockContract();

// Create bounty
const tx = await mockContract.createBounty(bountyId, hash, deadline, metadata);
await tx.wait();

// Complete bounty
await mockContract.completeBounty(bountyId, winner, solution);
```

## 🎯 Assertion Helpers

```typescript
import { expectTxSuccess, expectValidBounty, expectValidAddress } from './helpers/test-helpers';

// Validate transaction
expectTxSuccess(tx);

// Validate bounty
expectValidBounty(bounty);

// Validate address
expectValidAddress('0x1234...');
```

## 🔄 HBAR Conversion Utilities

```typescript
import { hbarToWei, weiToHbar } from './helpers/test-helpers';

const wei = hbarToWei(5); // BigInt(500000000)
const hbar = weiToHbar(BigInt(500000000)); // 5
```

## 🐛 Error Simulation

```typescript
import { simulateNetworkError, simulateInsufficientBalance, simulateContractRevert } from './helpers/test-helpers';

// Simulate network error
mockContract.createBounty.mockRejectedValueOnce(simulateNetworkError());

// Simulate insufficient balance
mockContract.createBounty.mockRejectedValueOnce(simulateInsufficientBalance());

// Simulate contract revert
mockContract.createBounty.mockRejectedValueOnce(simulateContractRevert('Invalid bounty'));
```

## 📝 Writing New Tests

### Test Template

```typescript
import { describe, it, expect, beforeEach } from 'vitest';
import { createMockUser, createMockBounty } from '../helpers/test-helpers';

describe('Feature Name', () => {
  let testUser: ReturnType<typeof createMockUser>;
  let testBounty: ReturnType<typeof createMockBounty>;

  beforeEach(() => {
    testUser = createMockUser();
    testBounty = createMockBounty();
  });

  describe('Subfeature', () => {
    it('should do something', async () => {
      // Arrange
      const expectedValue = 5;

      // Act
      const result = await someFunction();

      // Assert
      expect(result).toBe(expectedValue);
    });
  });
});
```

### Best Practices

1. **Use descriptive test names**: Clearly state what is being tested
2. **Follow AAA pattern**: Arrange, Act, Assert
3. **Test one thing at a time**: Each test should verify a single behavior
4. **Use beforeEach for setup**: Keep tests independent
5. **Mock external dependencies**: Use provided mock helpers
6. **Test edge cases**: Don't just test happy paths
7. **Clean up after tests**: Vitest automatically cleans up after each test

## 🔍 Debugging Tests

### Run Specific Test File
```bash
pnpm test tests/integration/bounty-lifecycle.test.ts
```

### Run Specific Test
```bash
pnpm test -t "completes full bounty workflow"
```

### Debug Mode
```bash
pnpm test --inspect-brk
```

### View Test UI
```bash
pnpm test:ui
```

## 📊 Coverage Report

Generate and view coverage:

```bash
# Generate coverage
pnpm test:coverage

# Coverage files are in coverage/ directory
# Open coverage/index.html in browser to view detailed report
```

### Coverage Targets
- **Lines:** 70%
- **Functions:** 70%
- **Branches:** 70%
- **Statements:** 70%

## 🔧 Configuration

### Vitest Config (`vitest.config.ts`)

```typescript
export default defineConfig({
  test: {
    globals: true,
    environment: 'happy-dom',
    setupFiles: ['./tests/setup.ts'],
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      lines: 70,
      functions: 70,
      branches: 70,
      statements: 70,
    },
  },
});
```

### Test Setup (`tests/setup.ts`)

- Mocks window.ethereum
- Mocks matchMedia
- Mocks IntersectionObserver
- Sets environment variables
- Configures cleanup

## 📚 Resources

- [Vitest Documentation](https://vitest.dev/)
- [Testing Library](https://testing-library.com/)
- [Happy DOM](https://github.com/capricorn86/happy-dom)

## 🤝 Contributing

When adding new tests:

1. Place integration tests in `tests/integration/`
2. Add reusable mocks to `tests/helpers/`
3. Update this README if adding new test categories
4. Ensure all tests pass: `pnpm test`
5. Verify coverage: `pnpm test:coverage`

## ⚠️ Known Issues

- Smart contract tests are separate (use `pnpm test:contracts`)
- Some UI component tests may require additional setup
- Coverage may not include smart contract code

## 📞 Support

For issues or questions about tests:
1. Check this README first
2. Review existing test examples
3. Check Phase 2 documentation in `AppDev-Docs/`

---

**Last Updated:** 2025-10-07
**Test Framework:** Vitest v3.2.4
**Coverage Tool:** V8
**Total Tests:** 40+
