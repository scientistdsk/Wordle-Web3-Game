-- ============================================================================
-- PHASE 3: CORRECTED QUERIES
-- Fixed column names based on actual schema
-- ============================================================================
-- bounty_participants table has:
--   - joined_at (not created_at)
--   - completed_at
-- Use these corrected queries instead
-- ============================================================================

-- ============================================================================
-- CORRECTED: Check recent bounty joins
-- ============================================================================

SELECT
    b.name,
    b.participant_count,
    bp.joined_at as last_join,
    COUNT(bp.id) as total_participants
FROM bounties b
JOIN bounty_participants bp ON b.id = bp.bounty_id
WHERE bp.joined_at >= NOW() - INTERVAL '1 hour'
GROUP BY b.id, b.name, b.participant_count, bp.joined_at
ORDER BY bp.joined_at DESC
LIMIT 10;

-- Verify participant_count matches COUNT(bp.id) for recent joins

-- ============================================================================
-- ALTERNATIVE: Show all recent joins with accurate counts
-- ============================================================================

SELECT
    b.id,
    b.name,
    b.participant_count as stored_count,
    COUNT(bp.id) as actual_count,
    MAX(bp.joined_at) as most_recent_join,
    CASE
        WHEN b.participant_count = COUNT(bp.id) THEN '✓ ACCURATE'
        ELSE '✗ MISMATCH'
    END as status
FROM bounties b
JOIN bounty_participants bp ON b.id = bp.bounty_id
WHERE bp.joined_at >= NOW() - INTERVAL '24 hours'
GROUP BY b.id, b.name, b.participant_count
ORDER BY MAX(bp.joined_at) DESC
LIMIT 20;

-- ============================================================================
-- CORRECTED: List all participants with join times
-- ============================================================================

SELECT
    b.name as bounty_name,
    u.username,
    u.wallet_address,
    bp.status,
    bp.joined_at,
    bp.completed_at,
    bp.is_winner,
    bp.prize_amount_won
FROM bounty_participants bp
JOIN bounties b ON bp.bounty_id = b.id
JOIN users u ON bp.user_id = u.id
WHERE bp.joined_at >= NOW() - INTERVAL '24 hours'
ORDER BY bp.joined_at DESC
LIMIT 50;

-- ============================================================================
-- CORRECTED: Count joins per hour (activity tracking)
-- ============================================================================

SELECT
    DATE_TRUNC('hour', bp.joined_at) as hour,
    COUNT(*) as joins_in_hour,
    COUNT(DISTINCT bp.bounty_id) as unique_bounties,
    COUNT(DISTINCT bp.user_id) as unique_users
FROM bounty_participants bp
WHERE bp.joined_at >= NOW() - INTERVAL '24 hours'
GROUP BY DATE_TRUNC('hour', bp.joined_at)
ORDER BY hour DESC;

-- ============================================================================
-- CORRECTED: Participant count accuracy report
-- ============================================================================

SELECT
    b.id,
    b.name,
    b.status,
    b.participant_count as stored_count,
    COUNT(bp.id) as actual_count,
    b.participant_count - COUNT(bp.id) as difference,
    CASE
        WHEN b.participant_count = COUNT(bp.id) THEN '✓ OK'
        WHEN b.participant_count > COUNT(bp.id) THEN '✗ OVER-COUNTED'
        WHEN b.participant_count < COUNT(bp.id) THEN '✗ UNDER-COUNTED'
    END as status,
    MIN(bp.joined_at) as first_join,
    MAX(bp.joined_at) as last_join,
    b.created_at as bounty_created
FROM bounties b
LEFT JOIN bounty_participants bp ON b.id = bp.bounty_id
GROUP BY b.id, b.name, b.status, b.participant_count, b.created_at
HAVING COUNT(bp.id) > 0  -- Only bounties with participants
ORDER BY ABS(b.participant_count - COUNT(bp.id)) DESC;

-- ============================================================================
-- SCHEMA REFERENCE
-- ============================================================================
-- bounty_participants table columns (from 001_initial_schema.sql):
--
-- id                        UUID PRIMARY KEY
-- bounty_id                 UUID (references bounties)
-- user_id                   UUID (references users)
-- status                    participation_status ENUM
-- joined_at                 TIMESTAMP WITH TIME ZONE (use this for join time!)
-- completed_at              TIMESTAMP WITH TIME ZONE
-- current_word_index        INTEGER
-- total_attempts            INTEGER
-- total_time_seconds        INTEGER
-- words_completed           INTEGER
-- is_winner                 BOOLEAN
-- final_score               INTEGER
-- prize_amount_won          DECIMAL(20, 8)
-- prize_paid_at             TIMESTAMP WITH TIME ZONE
-- prize_transaction_hash    VARCHAR(255)
-- ============================================================================

-- ============================================================================
-- USEFUL QUERIES FOR MONITORING
-- ============================================================================

-- Query 1: Check for any participants without joined_at (data integrity)
SELECT
    bp.id,
    bp.bounty_id,
    bp.user_id,
    bp.joined_at,
    bp.status
FROM bounty_participants bp
WHERE bp.joined_at IS NULL;

-- Expected: 0 rows (joined_at should always be set)

-- Query 2: Find bounties with recent activity
SELECT
    b.id,
    b.name,
    b.status,
    COUNT(bp.id) as total_participants,
    COUNT(CASE WHEN bp.status = 'completed' THEN 1 END) as completed,
    MIN(bp.joined_at) as first_join,
    MAX(bp.joined_at) as last_join,
    EXTRACT(EPOCH FROM (MAX(bp.joined_at) - MIN(bp.joined_at))) / 60 as duration_minutes
FROM bounties b
JOIN bounty_participants bp ON b.id = bp.bounty_id
GROUP BY b.id, b.name, b.status
HAVING MAX(bp.joined_at) >= NOW() - INTERVAL '24 hours'
ORDER BY MAX(bp.joined_at) DESC;

-- Query 3: User activity report (recent joins)
SELECT
    u.id,
    u.username,
    u.wallet_address,
    COUNT(bp.id) as bounties_joined,
    MIN(bp.joined_at) as first_join,
    MAX(bp.joined_at) as last_join,
    COUNT(CASE WHEN bp.status = 'completed' THEN 1 END) as completed,
    COUNT(CASE WHEN bp.is_winner THEN 1 END) as won
FROM users u
JOIN bounty_participants bp ON u.id = bp.user_id
WHERE bp.joined_at >= NOW() - INTERVAL '7 days'
GROUP BY u.id, u.username, u.wallet_address
ORDER BY MAX(bp.joined_at) DESC
LIMIT 20;

-- Query 4: Bounty timeline (all joins in chronological order)
SELECT
    b.name,
    u.username,
    bp.joined_at,
    bp.status,
    bp.completed_at,
    EXTRACT(EPOCH FROM (bp.completed_at - bp.joined_at)) / 60 as minutes_to_complete
FROM bounty_participants bp
JOIN bounties b ON bp.bounty_id = b.id
JOIN users u ON bp.user_id = u.id
WHERE b.id = 'your-bounty-id-here'
ORDER BY bp.joined_at ASC;

-- Query 5: Test if double-increment bug is fixed
-- Run this before and after a user joins to verify count increments by exactly 1
SELECT
    id,
    name,
    participant_count,
    (SELECT COUNT(*) FROM bounty_participants WHERE bounty_id = bounties.id) as actual_count,
    participant_count - (SELECT COUNT(*) FROM bounty_participants WHERE bounty_id = bounties.id) as difference
FROM bounties
WHERE status = 'active'
ORDER BY created_at DESC
LIMIT 10;

-- ============================================================================
-- END OF CORRECTED QUERIES
-- ============================================================================
