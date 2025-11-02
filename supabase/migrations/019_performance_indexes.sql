-- Performance Indexes and Query Optimization (FIXED VERSION)
-- Created: 2025-10-07
-- Fixed: 2025-10-07 - Removed NOW() from index predicates
-- Purpose: Add composite and partial indexes to optimize frequent query patterns
-- Phase 2, Task 2.2: Database Optimization

-- =============================================================================
-- BOUNTIES TABLE OPTIMIZATIONS
-- =============================================================================

-- Composite index for filtering active bounties by creator
-- Usage: Creator's bounty dashboard, active bounties listing
CREATE INDEX IF NOT EXISTS idx_bounties_creator_status
  ON bounties(creator_id, status)
  WHERE status = 'active';

-- Composite index for filtering bounties by status and end time
-- Usage: Finding expiring or expired bounties
CREATE INDEX IF NOT EXISTS idx_bounties_status_end_time
  ON bounties(status, end_time)
  WHERE status IN ('active', 'paused');

-- Partial index for active bounties ordered by creation
-- Usage: Public bounty listings, homepage featured bounties
CREATE INDEX IF NOT EXISTS idx_bounties_active_created
  ON bounties(created_at DESC)
  WHERE status = 'active' AND is_public = true;

-- Index for finding bounties by end_time (for expiration checks)
-- Usage: Background job to expire old bounties
-- Query: SELECT * FROM bounties WHERE status = 'active' AND end_time < NOW();
CREATE INDEX IF NOT EXISTS idx_bounties_active_end_time
  ON bounties(status, end_time)
  WHERE status = 'active';

-- Composite index for prize amount filtering
-- Usage: Finding high-value bounties
CREATE INDEX IF NOT EXISTS idx_bounties_status_prize
  ON bounties(status, prize_amount DESC)
  WHERE status = 'active';

-- Index for bounty type filtering
-- Usage: Filtering by game type (Simple, Multistage, etc.)
CREATE INDEX IF NOT EXISTS idx_bounties_type_status
  ON bounties(bounty_type, status)
  WHERE status IN ('active', 'paused');

-- Composite index for participant count tracking
-- Usage: Finding popular bounties
CREATE INDEX IF NOT EXISTS idx_bounties_participant_count
  ON bounties(participant_count DESC, created_at DESC)
  WHERE status = 'active';

-- =============================================================================
-- BOUNTY_PARTICIPANTS TABLE OPTIMIZATIONS
-- =============================================================================

-- Composite index for finding user's active participations
-- Usage: User's active games dashboard
CREATE INDEX IF NOT EXISTS idx_participants_user_status
  ON bounty_participants(user_id, status)
  WHERE status IN ('active', 'registered');

-- Composite index for bounty participant listings
-- Usage: Admin dashboard, bounty completion UI
CREATE INDEX IF NOT EXISTS idx_participants_bounty_status
  ON bounty_participants(bounty_id, status, joined_at DESC);

-- Index for finding winners
-- Usage: Prize distribution, leaderboard calculations
CREATE INDEX IF NOT EXISTS idx_participants_winners
  ON bounty_participants(bounty_id, is_winner, completed_at DESC)
  WHERE is_winner = true;

-- Composite index for completed participations
-- Usage: User stats, leaderboard updates
CREATE INDEX IF NOT EXISTS idx_participants_user_completed
  ON bounty_participants(user_id, completed_at DESC)
  WHERE status = 'completed';

-- Index for tracking attempts
-- Usage: Finding users who exceeded max attempts
CREATE INDEX IF NOT EXISTS idx_participants_attempts
  ON bounty_participants(bounty_id, total_attempts DESC)
  WHERE status = 'active';

-- Index for time-based winner determination
-- Usage: Finding fastest completion times
CREATE INDEX IF NOT EXISTS idx_participants_time
  ON bounty_participants(bounty_id, total_time_seconds ASC)
  WHERE status = 'completed' AND total_time_seconds IS NOT NULL;

-- Index for prize tracking
-- Usage: Finding unpaid prizes
CREATE INDEX IF NOT EXISTS idx_participants_unpaid_prizes
  ON bounty_participants(bounty_id, user_id)
  WHERE is_winner = true AND prize_paid_at IS NULL;

-- =============================================================================
-- GAME_ATTEMPTS TABLE OPTIMIZATIONS
-- =============================================================================

-- Composite index for participant's attempts ordered by time
-- Usage: Gameplay history, attempt replay
CREATE INDEX IF NOT EXISTS idx_attempts_participant_created
  ON game_attempts(participant_id, created_at DESC);

-- Composite index for bounty attempts analysis
-- Usage: Bounty analytics, difficulty analysis
CREATE INDEX IF NOT EXISTS idx_attempts_bounty_result
  ON game_attempts(bounty_id, result, created_at DESC);

-- Index for finding correct attempts
-- Usage: Winner verification, solution validation
CREATE INDEX IF NOT EXISTS idx_attempts_correct
  ON game_attempts(participant_id, word_index, result)
  WHERE result = 'correct';

-- Index for multistage bounty progress
-- Usage: Tracking which word a user is on
CREATE INDEX IF NOT EXISTS idx_attempts_word_index
  ON game_attempts(participant_id, word_index, attempt_number);

-- Index for time-based analysis
-- Usage: Finding fastest solves, time analytics
CREATE INDEX IF NOT EXISTS idx_attempts_time_taken
  ON game_attempts(bounty_id, time_taken_seconds ASC)
  WHERE time_taken_seconds IS NOT NULL;

-- =============================================================================
-- PAYMENT_TRANSACTIONS TABLE OPTIMIZATIONS
-- =============================================================================

-- Composite index for user transaction history
-- Usage: Profile page transaction history
CREATE INDEX IF NOT EXISTS idx_transactions_user_created
  ON payment_transactions(user_id, created_at DESC);

-- Composite index for bounty transaction tracking
-- Usage: Bounty payment audit trail
CREATE INDEX IF NOT EXISTS idx_transactions_bounty_type
  ON payment_transactions(bounty_id, transaction_type, created_at DESC);

-- Index for pending transactions
-- Usage: Finding transactions that need confirmation
CREATE INDEX IF NOT EXISTS idx_transactions_pending
  ON payment_transactions(status, created_at)
  WHERE status = 'pending';

-- Index for failed transactions
-- Usage: Retry logic, error monitoring
CREATE INDEX IF NOT EXISTS idx_transactions_failed
  ON payment_transactions(status, created_at DESC)
  WHERE status = 'failed';

-- Composite index for transaction type filtering
-- Usage: Filtering by deposit, prize_payout, refund
CREATE INDEX IF NOT EXISTS idx_transactions_type_status
  ON payment_transactions(transaction_type, status, created_at DESC);

-- Index for blockchain confirmations
-- Usage: Tracking confirmed transactions
CREATE INDEX IF NOT EXISTS idx_transactions_confirmed
  ON payment_transactions(confirmed_at DESC)
  WHERE status = 'confirmed';

-- Index for amount-based queries
-- Usage: High-value transaction monitoring
CREATE INDEX IF NOT EXISTS idx_transactions_amount
  ON payment_transactions(amount DESC, created_at DESC)
  WHERE status = 'confirmed';

-- =============================================================================
-- USERS TABLE OPTIMIZATIONS
-- =============================================================================

-- Index for wallet address lookups (case-insensitive)
-- Usage: Case-insensitive wallet searches
CREATE INDEX IF NOT EXISTS idx_users_wallet_lower
  ON users(LOWER(wallet_address));

-- Index for username searches (case-insensitive)
-- Usage: User search, profile lookups
CREATE INDEX IF NOT EXISTS idx_users_username_lower
  ON users(LOWER(username))
  WHERE username IS NOT NULL;

-- Index for active users
-- Usage: Active user statistics
CREATE INDEX IF NOT EXISTS idx_users_active
  ON users(created_at DESC)
  WHERE is_active = true;

-- Index for user stats - top creators
-- Usage: Finding top bounty creators
CREATE INDEX IF NOT EXISTS idx_users_bounties_created
  ON users(total_bounties_created DESC)
  WHERE total_bounties_created > 0;

-- Index for user stats - top winners
-- Usage: Finding top winners
CREATE INDEX IF NOT EXISTS idx_users_bounties_won
  ON users(total_bounties_won DESC)
  WHERE total_bounties_won > 0;

-- Index for user stats - top earners
-- Usage: Finding highest earners
CREATE INDEX IF NOT EXISTS idx_users_hbar_earned
  ON users(total_hbar_earned DESC)
  WHERE total_hbar_earned > 0;

-- =============================================================================
-- DICTIONARY TABLE OPTIMIZATIONS
-- =============================================================================

-- Composite index for word length and common words
-- Usage: Getting random words for bounty creation
CREATE INDEX IF NOT EXISTS idx_dictionary_length_common
  ON dictionary(word_length, is_common DESC, usage_count DESC);

-- Index for word prefix searches (for autocomplete)
-- Usage: Word suggestion, autocomplete features
CREATE INDEX IF NOT EXISTS idx_dictionary_word_prefix
  ON dictionary(word text_pattern_ops);

-- Index for popular words by length
-- Usage: Featured words, common word suggestions
CREATE INDEX IF NOT EXISTS idx_dictionary_popular
  ON dictionary(word_length, usage_count DESC)
  WHERE is_common = true;

-- =============================================================================
-- QUERY OPTIMIZATION COMMENTS
-- =============================================================================

-- Common Query Patterns and Their Indexes:
--
-- 1. Find active bounties for homepage:
--    Uses: idx_bounties_active_created
--    Query: SELECT * FROM bounties WHERE status = 'active' AND is_public = true ORDER BY created_at DESC;
--
-- 2. Get user's active games:
--    Uses: idx_participants_user_status
--    Query: SELECT * FROM bounty_participants WHERE user_id = ? AND status = 'active';
--
-- 3. Find winners for a bounty:
--    Uses: idx_participants_winners
--    Query: SELECT * FROM bounty_participants WHERE bounty_id = ? AND is_winner = true;
--
-- 4. Get user transaction history:
--    Uses: idx_transactions_user_created
--    Query: SELECT * FROM payment_transactions WHERE user_id = ? ORDER BY created_at DESC;
--
-- 5. Find expired bounties (application filters with NOW()):
--    Uses: idx_bounties_active_end_time
--    Query: SELECT * FROM bounties WHERE status = 'active' AND end_time < NOW();
--
-- 6. Get participant attempts:
--    Uses: idx_attempts_participant_created
--    Query: SELECT * FROM game_attempts WHERE participant_id = ? ORDER BY created_at DESC;
--
-- 7. Validate word:
--    Uses: dictionary primary key (word)
--    Query: SELECT * FROM dictionary WHERE word = UPPER(?);
--
-- 8. Find pending transactions:
--    Uses: idx_transactions_pending
--    Query: SELECT * FROM payment_transactions WHERE status = 'pending';

-- =============================================================================
-- MAINTENANCE QUERIES
-- =============================================================================

-- To analyze index usage:
-- SELECT schemaname, tablename, indexname, idx_scan, idx_tup_read, idx_tup_fetch
-- FROM pg_stat_user_indexes
-- WHERE schemaname = 'public'
-- ORDER BY idx_scan DESC;

-- To find unused indexes:
-- SELECT schemaname, tablename, indexname
-- FROM pg_stat_user_indexes
-- WHERE idx_scan = 0 AND schemaname = 'public'
-- ORDER BY tablename, indexname;

-- To get table sizes:
-- SELECT
--   schemaname,
--   tablename,
--   pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
-- FROM pg_tables
-- WHERE schemaname = 'public'
-- ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- To refresh materialized view (should be done periodically):
-- REFRESH MATERIALIZED VIEW CONCURRENTLY leaderboard;

-- =============================================================================
-- PERFORMANCE RECOMMENDATIONS
-- =============================================================================

-- 1. Run ANALYZE after bulk data imports:
--    ANALYZE bounties;
--    ANALYZE bounty_participants;
--    ANALYZE game_attempts;
--    ANALYZE payment_transactions;
--
-- 2. Consider partitioning large tables by date if they grow beyond 1M rows:
--    - game_attempts (partition by created_at)
--    - payment_transactions (partition by created_at)
--
-- 3. Set up connection pooling with pgBouncer (recommended settings):
--    - pool_mode = transaction
--    - max_client_conn = 100
--    - default_pool_size = 20
--
-- 4. Monitor slow queries with pg_stat_statements:
--    CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
--
-- 5. Consider setting work_mem for complex queries:
--    SET work_mem = '64MB'; -- for session, or configure globally
--
-- 6. Enable query plan logging for optimization:
--    SET auto_explain.log_min_duration = 1000; -- log queries > 1s

COMMENT ON SCHEMA public IS 'Performance indexes added 2025-10-07 for Phase 2 optimization (fixed version)';
