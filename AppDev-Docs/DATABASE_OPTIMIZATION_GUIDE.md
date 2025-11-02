# Database Optimization Guide

**Created:** 2025-10-07
**Phase:** 2, Task 2.2
**Purpose:** Performance optimization strategies for the Web3 Wordle Bounty Game database

---

## 📊 Overview

This guide documents database optimization strategies, index usage, and query patterns for optimal performance. All optimizations are implemented in migration `019_performance_indexes.sql`.

---

## 🎯 Performance Indexes Summary

### Total Indexes Added: 40+

#### By Table:
- **Bounties:** 8 composite/partial indexes
- **Bounty Participants:** 7 composite/partial indexes
- **Game Attempts:** 5 composite indexes
- **Payment Transactions:** 7 composite/partial indexes
- **Users:** 6 indexes
- **Dictionary:** 3 composite indexes

---

## 🔍 Index Types Explained

### 1. Composite Indexes
Indexes on multiple columns for complex query patterns.

**Example:**
```sql
CREATE INDEX idx_bounties_creator_status
  ON bounties(creator_id, status)
  WHERE status = 'active';
```

**Usage:**
```sql
-- Efficiently finds active bounties by creator
SELECT * FROM bounties
WHERE creator_id = ? AND status = 'active';
```

### 2. Partial Indexes
Indexes that only include rows matching a condition, saving space.

**Example:**
```sql
CREATE INDEX idx_bounties_active_created
  ON bounties(created_at DESC)
  WHERE status = 'active' AND is_public = true;
```

**Usage:**
```sql
-- Efficiently finds recent active public bounties
SELECT * FROM bounties
WHERE status = 'active' AND is_public = true
ORDER BY created_at DESC;
```

### 3. Expression Indexes
Indexes on computed values for case-insensitive searches.

**Example:**
```sql
CREATE INDEX idx_users_wallet_lower
  ON users(LOWER(wallet_address));
```

**Usage:**
```sql
-- Case-insensitive wallet lookup
SELECT * FROM users
WHERE LOWER(wallet_address) = LOWER(?);
```

---

## 📈 Common Query Patterns & Optimizations

### 1. Homepage - Active Bounties Listing

**Query:**
```sql
SELECT b.*, u.username as creator_username
FROM bounties b
JOIN users u ON b.creator_id = u.id
WHERE b.status = 'active'
  AND b.is_public = true
ORDER BY b.created_at DESC
LIMIT 20;
```

**Indexes Used:**
- `idx_bounties_active_created` (partial index)
- `users.id` (primary key)

**Performance:** O(1) for index scan, O(log n) for joins

---

### 2. User Dashboard - Active Games

**Query:**
```sql
SELECT bp.*, b.name, b.prize_amount
FROM bounty_participants bp
JOIN bounties b ON bp.bounty_id = b.id
WHERE bp.user_id = ?
  AND bp.status IN ('active', 'registered')
ORDER BY bp.joined_at DESC;
```

**Indexes Used:**
- `idx_participants_user_status` (composite)
- `bounties.id` (primary key)

**Performance:** O(log n) for user lookup, O(1) per game

---

### 3. Admin Dashboard - Bounty Completion

**Query:**
```sql
SELECT bp.*, u.username, u.wallet_address
FROM bounty_participants bp
JOIN users u ON bp.user_id = u.id
WHERE bp.bounty_id = ?
  AND bp.status = 'completed'
ORDER BY bp.total_attempts ASC, bp.total_time_seconds ASC;
```

**Indexes Used:**
- `idx_participants_bounty_status` (composite)
- `users.id` (primary key)

**Performance:** O(log n) for bounty lookup, O(n log n) for sorting

---

### 4. Profile Page - Transaction History

**Query:**
```sql
SELECT *
FROM payment_transactions
WHERE user_id = ?
ORDER BY created_at DESC
LIMIT 50 OFFSET ?;
```

**Indexes Used:**
- `idx_transactions_user_created` (composite)

**Performance:** O(log n) with pagination

**Optimization Note:** Use keyset pagination for very large result sets:
```sql
-- Keyset pagination (more efficient)
SELECT *
FROM payment_transactions
WHERE user_id = ? AND created_at < ?
ORDER BY created_at DESC
LIMIT 50;
```

---

### 5. Gameplay - Attempt History

**Query:**
```sql
SELECT *
FROM game_attempts
WHERE participant_id = ?
ORDER BY created_at DESC;
```

**Indexes Used:**
- `idx_attempts_participant_created` (composite)

**Performance:** O(log n) lookup, O(1) per attempt

---

### 6. Leaderboard - Top Winners

**Query:**
```sql
SELECT u.username,
       COUNT(DISTINCT bp.bounty_id) as bounties_won,
       SUM(bp.prize_amount_won) as total_winnings
FROM users u
JOIN bounty_participants bp ON u.id = bp.user_id
WHERE bp.is_winner = true
GROUP BY u.id, u.username
ORDER BY bounties_won DESC, total_winnings DESC
LIMIT 100;
```

**Indexes Used:**
- `idx_participants_winners` (partial)
- Materialized view `leaderboard` (pre-computed)

**Performance:** O(1) from materialized view

**Recommendation:** Use materialized view for leaderboard:
```sql
REFRESH MATERIALIZED VIEW CONCURRENTLY leaderboard;
SELECT * FROM leaderboard LIMIT 100;
```

---

### 7. Background Job - Expire Old Bounties

**Query:**
```sql
UPDATE bounties
SET status = 'expired'
WHERE status = 'active'
  AND end_time < NOW()
RETURNING id;
```

**Indexes Used:**
- `idx_bounties_expired` (partial)

**Performance:** O(k) where k = number of expired bounties

**Cron Job:** Run every 5 minutes:
```sql
-- Find and expire old bounties
WITH expired AS (
  UPDATE bounties
  SET status = 'expired', updated_at = NOW()
  WHERE status = 'active' AND end_time < NOW()
  RETURNING id
)
SELECT COUNT(*) as expired_count FROM expired;
```

---

### 8. Word Validation - Dictionary Lookup

**Query:**
```sql
SELECT EXISTS(
  SELECT 1 FROM dictionary
  WHERE word = UPPER(?)
) as is_valid;
```

**Indexes Used:**
- `dictionary.word` (primary key)

**Performance:** O(1) hash lookup

**Optimization:** Use prepared statements and connection pooling.

---

## 🚀 Query Optimization Best Practices

### 1. Use EXPLAIN ANALYZE

Before optimizing, understand the query plan:

```sql
EXPLAIN ANALYZE
SELECT * FROM bounties
WHERE status = 'active' AND prize_amount > 10
ORDER BY created_at DESC
LIMIT 20;
```

**Look for:**
- ✅ Index Scan (good)
- ✅ Bitmap Index Scan (good for multiple conditions)
- ⚠️ Seq Scan (bad for large tables)
- ❌ Nested Loop with high cost (bad)

### 2. Avoid SELECT *

**Bad:**
```sql
SELECT * FROM bounties WHERE id = ?;
```

**Good:**
```sql
SELECT id, name, prize_amount, status FROM bounties WHERE id = ?;
```

**Benefits:**
- Reduces I/O
- Enables covering indexes
- Faster network transfer

### 3. Use Covering Indexes

Create indexes that include all needed columns:

```sql
CREATE INDEX idx_bounties_covering
  ON bounties(status, created_at DESC)
  INCLUDE (id, name, prize_amount);
```

### 4. Batch Operations

**Bad (N queries):**
```javascript
for (const participantId of participantIds) {
  await supabase.from('bounty_participants')
    .select()
    .eq('id', participantId)
    .single();
}
```

**Good (1 query):**
```javascript
const { data } = await supabase.from('bounty_participants')
  .select()
  .in('id', participantIds);
```

### 5. Use Prepared Statements

**Node.js Example:**
```javascript
// Supabase automatically uses prepared statements
const { data } = await supabase
  .from('bounties')
  .select()
  .eq('status', 'active')
  .order('created_at', { ascending: false });
```

### 6. Pagination

**Use LIMIT/OFFSET for small datasets:**
```sql
SELECT * FROM bounties
ORDER BY created_at DESC
LIMIT 20 OFFSET 40;
```

**Use keyset pagination for large datasets:**
```sql
-- More efficient for large offsets
SELECT * FROM bounties
WHERE created_at < ?
ORDER BY created_at DESC
LIMIT 20;
```

---

## 🔧 Connection Pooling

### Recommended Settings (pgBouncer)

```ini
[databases]
wordle_db = host=localhost port=5432 dbname=wordle

[pgbouncer]
pool_mode = transaction
max_client_conn = 100
default_pool_size = 20
min_pool_size = 5
reserve_pool_size = 5
reserve_pool_timeout = 3
max_db_connections = 50
```

### Supabase Built-in Pooling

Supabase provides connection pooling automatically:
- **Connection Mode:** Transaction pooling
- **Pool Size:** Scales with plan
- **Max Connections:** Managed automatically

**Access pooled connection:**
```javascript
// Use the pooler endpoint
const supabase = createClient(
  'https://your-project.supabase.co',
  'your-anon-key',
  {
    db: {
      schema: 'public',
    },
    global: {
      headers: { 'x-connection-type': 'pooler' }
    }
  }
);
```

---

## 📊 Monitoring & Maintenance

### 1. Check Index Usage

```sql
SELECT
  schemaname,
  tablename,
  indexname,
  idx_scan as scans,
  idx_tup_read as tuples_read,
  idx_tup_fetch as tuples_fetched
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan DESC;
```

### 2. Find Unused Indexes

```sql
SELECT
  schemaname,
  tablename,
  indexname,
  pg_size_pretty(pg_relation_size(indexrelid)) as size
FROM pg_stat_user_indexes
WHERE idx_scan = 0
  AND schemaname = 'public'
  AND indexname NOT LIKE 'pg_toast%'
ORDER BY pg_relation_size(indexrelid) DESC;
```

### 3. Table Sizes

```sql
SELECT
  schemaname,
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
  pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) -
                 pg_relation_size(schemaname||'.'||tablename)) AS index_size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

### 4. Slow Query Monitoring

**Enable pg_stat_statements:**
```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Find slowest queries
SELECT
  query,
  calls,
  total_exec_time,
  mean_exec_time,
  max_exec_time
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%'
ORDER BY mean_exec_time DESC
LIMIT 10;
```

### 5. Refresh Materialized Views

```sql
-- Refresh leaderboard (run daily or on-demand)
REFRESH MATERIALIZED VIEW CONCURRENTLY leaderboard;

-- Check last refresh time
SELECT
  schemaname,
  matviewname,
  last_vacuum,
  last_autovacuum,
  last_analyze
FROM pg_stat_user_tables
WHERE schemaname = 'public'
  AND relname = 'leaderboard';
```

### 6. Vacuum and Analyze

```sql
-- Run after bulk operations
VACUUM ANALYZE bounties;
VACUUM ANALYZE bounty_participants;
VACUUM ANALYZE game_attempts;
VACUUM ANALYZE payment_transactions;

-- Full vacuum (requires table lock, run during maintenance)
VACUUM FULL ANALYZE bounties;
```

---

## 🎯 Performance Targets

### Query Performance Goals

| Query Type | Target Time | Index Strategy |
|-----------|-------------|----------------|
| Primary key lookup | < 1ms | Primary key index |
| Single table filter | < 10ms | Composite index |
| Join queries (2 tables) | < 50ms | Foreign key indexes |
| Join queries (3+ tables) | < 100ms | Multiple indexes + query optimization |
| Aggregations | < 200ms | Materialized views for complex ones |
| Full-text search | < 100ms | GiST/GIN indexes (if needed) |

### Throughput Goals

- **Read queries:** 1,000 QPS per connection
- **Write queries:** 500 QPS per connection
- **Concurrent users:** 10,000+ with proper pooling

---

## 🔄 Maintenance Schedule

### Daily
- ✅ Monitor slow query log
- ✅ Check for failed transactions
- ✅ Verify backup completion

### Weekly
- ✅ Review index usage statistics
- ✅ Refresh materialized views
- ✅ Check table bloat
- ✅ Run ANALYZE on large tables

### Monthly
- ✅ Review and optimize slow queries
- ✅ Archive old data (if partitioning)
- ✅ Update statistics
- ✅ Performance baseline comparison

### Quarterly
- ✅ Full database optimization review
- ✅ Consider adding/removing indexes
- ✅ Evaluate partitioning strategy
- ✅ Capacity planning

---

## 📚 Additional Resources

- [PostgreSQL Performance Tuning](https://www.postgresql.org/docs/current/performance-tips.html)
- [Supabase Performance Best Practices](https://supabase.com/docs/guides/database/postgres/performance)
- [pgBouncer Connection Pooling](https://www.pgbouncer.org/)
- [pg_stat_statements Documentation](https://www.postgresql.org/docs/current/pgstatstatements.html)

---

## 📝 Migration Notes

**Migration:** `019_performance_indexes.sql`
**Applied:** 2025-10-07
**Indexes Added:** 40+
**Expected Performance Improvement:** 10-50x for indexed queries
**Disk Space Impact:** ~5-10% increase (indexes are smaller than tables)

**To apply:**
```bash
# Run migration
psql -d wordle_db -f supabase/migrations/019_performance_indexes.sql

# Verify indexes created
psql -d wordle_db -c "SELECT indexname FROM pg_indexes WHERE schemaname = 'public' ORDER BY indexname;"
```

---

**Last Updated:** 2025-10-07
**Phase:** 2, Task 2.2
**Status:** Complete
