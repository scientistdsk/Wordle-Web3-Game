# Web3 Wordle Bounty Game

A decentralized Wordle-style game with bounty mechanics built on React + Vite, integrating Hedera blockchain, Supabase backend, and Reown AppKit wallet connectivity.

## 🎯 Quick Start

```bash
# Install dependencies
pnpm install

# Start development server
pnpm run dev

# Compile smart contracts
pnpm run compile

# Run contract tests
pnpm run test:contracts

# Deploy to Hedera Testnet
pnpm run deploy:testnet
```

## 📋 Prerequisites

- Node.js 20.x or higher
- pnpm package manager
- Hedera testnet account (get from [Hedera Portal](https://portal.hedera.com))
- Test HBAR from [Hedera Faucet](https://portal.hedera.com/faucet)
- Reown Project ID from [Reown Cloud](https://cloud.reown.com)

## 🔧 Environment Setup

### 1. Frontend Configuration (`.env.local`)

```bash
# Reown AppKit Project ID
VITE_REOWN_PROJECT_ID=your_reown_project_id

# Network (testnet or mainnet)
VITE_HEDERA_NETWORK=testnet

# RPC URLs
VITE_HEDERA_TESTNET_RPC=https://testnet.hashio.io/api

# Contract Address (after deployment)
VITE_ESCROW_CONTRACT_ADDRESS=0x...
```

### 2. Smart Contract Deployment (`.env`)

```bash
# Hedera Account (must use ECDSA key, not ED25519)
HEDERA_TESTNET_OPERATOR_ID=0.0.xxxxx
HEDERA_TESTNET_OPERATOR_KEY=0xabc...

# RPC URL
HEDERA_TESTNET_RPC_URL=https://testnet.hashio.io/api
```

## 🏗️ Project Structure

```
├── contracts/                  # Solidity smart contracts
│   └── WordleBountyEscrow.sol # Main escrow contract
├── src/
│   ├── components/            # React components
│   │   ├── WalletContext.tsx  # Wallet integration
│   │   ├── BountyHuntPage.tsx
│   │   ├── CreateBountyPage.tsx
│   │   ├── GameplayPage.tsx
│   │   └── ...
│   ├── contracts/             # Contract services
│   │   └── EscrowService.ts   # Contract interaction layer
│   └── utils/
│       ├── payment/           # Payment processing
│       │   ├── payment-service.ts
│       │   └── payment-hooks.ts
│       └── supabase/          # Database integration
├── scripts/                   # Deployment scripts
│   ├── deploy.js
│   └── verify.js
├── tests/                     # Smart contract tests
├── supabase/migrations/       # Database migrations
└── hardhat.config.js          # Hardhat configuration
```

## 🚀 Features

### Blockchain Integration
- **Hedera Hashgraph** testnet/mainnet support
- **Smart Contracts** for escrow and prize distribution
- **Wallet Connect** via Reown AppKit
- **HBAR** deposits and automated prize distribution
- **2.5% platform fee** on prizes

### Game Features
- Create bounties with custom prizes
- Join and compete in active bounties
- Wordle-style gameplay with 6 attempts
- Leaderboard and player profiles
- Transaction history tracking

### Technical Features
- React 18 + TypeScript
- Vite for fast development
- Tailwind CSS + shadcn/ui components
- Supabase for backend and database
- Hardhat for smart contract development
- ethers.js v6 for blockchain interaction

## 📝 Smart Contract Commands

```bash
# Compile contracts
pnpm run compile

# Run all contract tests
pnpm run test:contracts

# Run escrow tests only
pnpm run test:escrow

# Deploy to testnet
pnpm run deploy:testnet

# Verify on HashScan
pnpm run verify:testnet

# Clean build artifacts
pnpm run clean

# Flatten contract for verification
pnpm run flatten
```

## 🎮 How to Play

### As a Bounty Creator:
1. Connect your Hedera wallet
2. Navigate to "Create Bounty"
3. Set your word, prize amount, and deadline
4. Deposit HBAR and create the bounty
5. Wait for players to compete
6. Winner automatically receives prize (minus 2.5% fee)

### As a Player:
1. Connect your Hedera wallet
2. Browse active bounties
3. Join a bounty you want to play
4. Play Wordle - guess the word in 6 attempts
5. If you win, claim your prize!

## 🔒 Security Features

- Smart contract access control (Ownable pattern)
- Emergency pause functionality
- Reentrancy protection
- Minimum bounty amounts (1 HBAR)
- Platform fee cap (10% maximum)
- Row-level security on database

## 📊 Testing

### Smart Contract Tests
All contract functionality is tested including:
- Bounty creation and deposits
- Participant management
- Prize distribution with fees
- Refund mechanisms
- Access control

Run tests:
```bash
pnpm run test:contracts
```

### Integration Testing
See [PHASE_3.md](./PHASE_3.md) for comprehensive integration test plans.

## 🛠️ Development Workflow

1. **Make changes** to frontend or contracts
2. **Test locally** with `pnpm run dev`
3. **Test contracts** with `pnpm run test:contracts`
4. **Deploy to testnet** when ready
5. **Verify contract** on HashScan
6. **Test with real HBAR** on testnet

## 📚 Documentation

- **[PHASE_1.md](./PHASE_1.md)** - Core blockchain integration (COMPLETE ✅)
- **[PHASE_2.md](./PHASE_2.md)** - Smart contract infrastructure
- **[PHASE_3.md](./PHASE_3.md)** - Integration testing & QA
- **[PHASE_4.md](./PHASE_4.md)** - Production deployment
- **[IMPLEMENTATION_SUMMARY.md](./IMPLEMENTATION_SUMMARY.md)** - Implementation details

## 🌐 Useful Links

- **Hedera Faucet:** https://portal.hedera.com/faucet (Get 10,000 test HBAR daily)
- **HashScan Explorer:** https://hashscan.io/testnet
- **Hedera Docs:** https://docs.hedera.com
- **Reown Cloud:** https://cloud.reown.com
- **Supabase:** https://supabase.com

## 🐛 Troubleshooting

### Wallet won't connect
- Ensure `VITE_REOWN_PROJECT_ID` is set in `.env.local`
- Check that you're using a supported wallet (HashPack, Blade, etc.)

### Contract deployment fails
- Verify you have enough test HBAR (get from faucet)
- Ensure your key is ECDSA format, not ED25519
- Check that `HEDERA_TESTNET_OPERATOR_KEY` is set correctly

### Transaction fails
- Check you have sufficient HBAR balance
- Verify you're on the correct network (testnet/mainnet)
- Ensure contract address is correct in `.env.local`

### Frontend can't find contract
- Run `pnpm run deploy:testnet` to deploy contract
- Update `VITE_ESCROW_CONTRACT_ADDRESS` in `.env.local`
- Restart dev server: `pnpm run dev`

## 🤝 Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md) (to be created) for development guidelines.

## 📄 License

MIT License - see LICENSE file for details

## 🎯 Current Status

**Phase 1: COMPLETE ✅**
- ✅ Wallet integration (Reown AppKit)
- ✅ Smart contract (WordleBountyEscrow.sol)
- ✅ Contract service layer (EscrowService.ts)
- ✅ Payment processing (payment-service.ts, payment-hooks.ts)
- ✅ Deployment scripts and configuration

**Next:** Phase 2 - Smart Contract Infrastructure Enhancement

## 💡 Tech Stack

- **Frontend:** React 18, TypeScript, Vite, Tailwind CSS
- **UI Components:** Radix UI, shadcn/ui
- **Blockchain:** Hedera Hashgraph (Testnet/Mainnet)
- **Smart Contracts:** Solidity 0.8.19, Hardhat
- **Wallet:** Reown AppKit, WalletConnect v2
- **Backend:** Supabase (PostgreSQL)
- **Package Manager:** pnpm

---

**Built for Hedera Hackathon 2025** 🚀

For questions or support, please open an issue on GitHub.
