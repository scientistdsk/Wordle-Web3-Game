-- Web3 Wordle Bounty Game Database Schema
-- Created: 2025-01-28

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Users table - stores user profile information
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    wallet_address VARCHAR(255) UNIQUE NOT NULL,
    username VARCHAR(50),
    display_name VARCHAR(100),
    avatar_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    last_seen TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    total_bounties_created INTEGER DEFAULT 0,
    total_bounties_won INTEGER DEFAULT 0,
    total_hbar_earned DECIMAL(20, 8) DEFAULT 0,
    total_hbar_spent DECIMAL(20, 8) DEFAULT 0,
    is_active BOOLEAN DEFAULT true
);

-- Bounty types enum
CREATE TYPE bounty_type AS ENUM (
    'Simple',
    'Multistage',
    'Time-based',
    'Random words',
    'Limited trials'
);

-- Prize distribution types enum
CREATE TYPE prize_distribution AS ENUM (
    'winner-take-all',
    'split-winners',
    'first-to-solve'
);

-- Winner criteria enum
CREATE TYPE winner_criteria AS ENUM (
    'time',
    'attempts',
    'words-correct'
);

-- Bounty status enum
CREATE TYPE bounty_status AS ENUM (
    'draft',
    'active',
    'paused',
    'completed',
    'cancelled',
    'expired'
);

-- Bounties table - stores bounty information
CREATE TABLE bounties (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    creator_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    bounty_type bounty_type NOT NULL DEFAULT 'Simple',

    -- Prize configuration
    prize_amount DECIMAL(20, 8) NOT NULL DEFAULT 0,
    prize_distribution prize_distribution NOT NULL DEFAULT 'winner-take-all',
    prize_currency VARCHAR(10) DEFAULT 'HBAR',

    -- Game configuration
    words TEXT[] NOT NULL, -- Array of secret words
    hints TEXT[] DEFAULT '{}', -- Array of hints
    max_participants INTEGER,
    max_attempts_per_user INTEGER,
    time_limit_seconds INTEGER, -- For time-based bounties

    -- Winner criteria
    winner_criteria winner_criteria NOT NULL DEFAULT 'attempts',

    -- Timing
    start_time TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    end_time TIMESTAMP WITH TIME ZONE,
    duration_hours INTEGER,

    -- Status and metadata
    status bounty_status NOT NULL DEFAULT 'draft',
    is_public BOOLEAN DEFAULT true,
    requires_registration BOOLEAN DEFAULT false,

    -- Tracking
    participant_count INTEGER DEFAULT 0,
    completion_count INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Blockchain
    transaction_hash VARCHAR(255), -- Transaction hash for prize deposit
    escrow_address VARCHAR(255), -- Smart contract address holding funds

    CONSTRAINT valid_prize_amount CHECK (prize_amount >= 0),
    CONSTRAINT valid_max_participants CHECK (max_participants IS NULL OR max_participants > 0),
    CONSTRAINT valid_duration CHECK (duration_hours IS NULL OR duration_hours > 0),
    CONSTRAINT valid_time_limit CHECK (time_limit_seconds IS NULL OR time_limit_seconds > 0),
    CONSTRAINT valid_words CHECK (array_length(words, 1) > 0)
);

-- Participation status enum
CREATE TYPE participation_status AS ENUM (
    'registered',
    'active',
    'completed',
    'failed',
    'disqualified'
);

-- Bounty participants table - tracks who joined which bounties
CREATE TABLE bounty_participants (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bounty_id UUID NOT NULL REFERENCES bounties(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status participation_status NOT NULL DEFAULT 'registered',
    joined_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    completed_at TIMESTAMP WITH TIME ZONE,

    -- Game progress
    current_word_index INTEGER DEFAULT 0,
    total_attempts INTEGER DEFAULT 0,
    total_time_seconds INTEGER DEFAULT 0,
    words_completed INTEGER DEFAULT 0,

    -- Results
    is_winner BOOLEAN DEFAULT false,
    final_score INTEGER,
    prize_amount_won DECIMAL(20, 8) DEFAULT 0,
    prize_paid_at TIMESTAMP WITH TIME ZONE,
    prize_transaction_hash VARCHAR(255),

    UNIQUE(bounty_id, user_id),
    CONSTRAINT valid_word_index CHECK (current_word_index >= 0),
    CONSTRAINT valid_attempts CHECK (total_attempts >= 0),
    CONSTRAINT valid_time CHECK (total_time_seconds >= 0),
    CONSTRAINT valid_words_completed CHECK (words_completed >= 0)
);

-- Game attempt result enum
CREATE TYPE attempt_result AS ENUM (
    'correct',
    'incorrect',
    'partial'
);

-- Game attempts table - tracks individual word guesses
CREATE TABLE game_attempts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    participant_id UUID NOT NULL REFERENCES bounty_participants(id) ON DELETE CASCADE,
    bounty_id UUID NOT NULL REFERENCES bounties(id) ON DELETE CASCADE,

    -- Attempt details
    word_index INTEGER NOT NULL DEFAULT 0, -- Which word in multistage bounties
    attempt_number INTEGER NOT NULL, -- Attempt number for this word
    guessed_word VARCHAR(50) NOT NULL,
    target_word VARCHAR(50) NOT NULL,

    -- Results
    result attempt_result NOT NULL,
    letter_results JSONB, -- Store letter-by-letter results
    time_taken_seconds INTEGER,

    -- Metadata
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    ip_address INET,
    user_agent TEXT,

    CONSTRAINT valid_attempt_number CHECK (attempt_number > 0),
    CONSTRAINT valid_word_index_attempts CHECK (word_index >= 0),
    CONSTRAINT valid_time_taken CHECK (time_taken_seconds IS NULL OR time_taken_seconds >= 0)
);

-- Payment transactions table - tracks all HBAR transactions
CREATE TABLE payment_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bounty_id UUID REFERENCES bounties(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- Transaction details
    transaction_hash VARCHAR(255) UNIQUE NOT NULL,
    transaction_type VARCHAR(50) NOT NULL, -- 'deposit', 'prize_payout', 'refund'
    amount DECIMAL(20, 8) NOT NULL,
    currency VARCHAR(10) DEFAULT 'HBAR',

    -- Blockchain details
    from_address VARCHAR(255),
    to_address VARCHAR(255),
    block_number BIGINT,
    block_timestamp TIMESTAMP WITH TIME ZONE,
    gas_used BIGINT,
    gas_price DECIMAL(20, 8),

    -- Status
    status VARCHAR(50) DEFAULT 'pending', -- 'pending', 'confirmed', 'failed'
    confirmed_at TIMESTAMP WITH TIME ZONE,

    -- Metadata
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    CONSTRAINT valid_amount CHECK (amount > 0)
);

-- Leaderboard view materialized for performance
CREATE MATERIALIZED VIEW leaderboard AS
SELECT
    u.id as user_id,
    u.wallet_address,
    u.username,
    u.display_name,
    u.avatar_url,
    COUNT(DISTINCT bp.bounty_id) as bounties_participated,
    COUNT(DISTINCT CASE WHEN bp.is_winner THEN bp.bounty_id END) as bounties_won,
    COALESCE(SUM(bp.prize_amount_won), 0) as total_hbar_won,
    AVG(bp.total_attempts) as avg_attempts,
    AVG(bp.total_time_seconds) as avg_time_seconds,
    MAX(bp.completed_at) as last_win_date,
    RANK() OVER (ORDER BY COUNT(DISTINCT CASE WHEN bp.is_winner THEN bp.bounty_id END) DESC, COALESCE(SUM(bp.prize_amount_won), 0) DESC) as global_rank
FROM users u
LEFT JOIN bounty_participants bp ON u.id = bp.user_id AND bp.status = 'completed'
WHERE u.is_active = true
GROUP BY u.id, u.wallet_address, u.username, u.display_name, u.avatar_url
ORDER BY global_rank;

-- Indexes for performance
CREATE INDEX idx_bounties_status ON bounties(status);
CREATE INDEX idx_bounties_creator ON bounties(creator_id);
CREATE INDEX idx_bounties_type ON bounties(bounty_type);
CREATE INDEX idx_bounties_end_time ON bounties(end_time);
CREATE INDEX idx_bounties_created_at ON bounties(created_at);

CREATE INDEX idx_participants_bounty ON bounty_participants(bounty_id);
CREATE INDEX idx_participants_user ON bounty_participants(user_id);
CREATE INDEX idx_participants_status ON bounty_participants(status);
CREATE INDEX idx_participants_winner ON bounty_participants(is_winner);

CREATE INDEX idx_attempts_participant ON game_attempts(participant_id);
CREATE INDEX idx_attempts_bounty ON game_attempts(bounty_id);
CREATE INDEX idx_attempts_created_at ON game_attempts(created_at);

CREATE INDEX idx_transactions_bounty ON payment_transactions(bounty_id);
CREATE INDEX idx_transactions_user ON payment_transactions(user_id);
CREATE INDEX idx_transactions_hash ON payment_transactions(transaction_hash);
CREATE INDEX idx_transactions_status ON payment_transactions(status);

CREATE INDEX idx_users_wallet ON users(wallet_address);
CREATE INDEX idx_users_active ON users(is_active);

-- Triggers for updated_at timestamps
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_bounties_updated_at BEFORE UPDATE ON bounties
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_transactions_updated_at BEFORE UPDATE ON payment_transactions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Function to refresh leaderboard
CREATE OR REPLACE FUNCTION refresh_leaderboard()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW leaderboard;
END;
$$ LANGUAGE plpgsql;