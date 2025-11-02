# Task 2.3: Profile Page - Bug Fixes

**Date:** October 7, 2025
**Status:** ✅ FIXED

## Issues Reported

### 1. Tab Layout Issue ✅ FIXED
**Problem:** Tab list using `display: grid` instead of `display: flex`
**Solution:** Changed `TabsList` className from `grid w-full grid-cols-2 sm:grid-cols-4` to `flex w-full`

**File Modified:** [ProfilePage.tsx:261](src/components/ProfilePage.tsx#L261)

---

### 2. Supabase Query Errors (400/406) ✅ FIXED
**Problem:** Multiple 400 (Bad Request) and 406 (Not Acceptable) errors when fetching user data

**Console Errors:**
```
GET .../users?select=username,display_name,email&wallet_address=eq.0x45E... 400 (Bad Request)
GET .../users?select=id&username=eq.AfriART&wallet_address=neq.0x45E... 406 (Not Acceptable)
```

**Root Causes:**
1. **Email field doesn't exist** in the `users` table schema (checked [001_initial_schema.sql](supabase/migrations/001_initial_schema.sql#L9-L23))
2. Using `.single()` for username check when multiple results or no results possible
3. Missing error handling for user data fetch

**Solutions:**

#### ProfilePage.tsx - Remove email field selection
```typescript
// ❌ Before
const { data: userData } = await supabase
  .from('users')
  .select('username, display_name, email')  // email doesn't exist!
  .eq('wallet_address', walletAddress)
  .single();

// ✅ After
const { data: userData, error: userError } = await supabase
  .from('users')
  .select('username, display_name')  // Only existing fields
  .eq('wallet_address', walletAddress)
  .single();

if (userError) {
  console.error('Error fetching user data:', userError);
}
```

#### EditProfileModal.tsx - Use `.maybeSingle()` instead of `.single()`
```typescript
// ❌ Before
const { data: existingUser, error: checkError } = await supabase
  .from('users')
  .select('id')
  .eq('username', username)
  .neq('wallet_address', walletAddress)
  .single();  // Throws 406 error if no results

// ✅ After
const { data: existingUser, error: checkError } = await supabase
  .from('users')
  .select('id')
  .eq('username', username)
  .neq('wallet_address', walletAddress)
  .maybeSingle();  // Returns null if no results, doesn't error
```

**Files Modified:**
- [ProfilePage.tsx:65-78](src/components/ProfilePage.tsx#L65-L78)
- [EditProfileModal.tsx:78-94](src/components/EditProfileModal.tsx#L78-L94)
- Removed `userEmail` state from ProfilePage
- Removed `currentEmail` prop from EditProfileModal
- Removed email input field from EditProfileModal

---

### 3. Username Update Not Working ✅ FIXED
**Problem:** Toast shows "Profile updated successfully" but username reverts to "Anonymous"

**Root Cause:** Not updating both `username` AND `display_name` fields in the database

**Solution:**
```typescript
// ❌ Before (only updated one field)
const updateData: any = { username };

// ✅ After (update both fields)
const { error: updateError } = await supabase
  .from('users')
  .update({
    username,
    display_name: username,  // Also update display_name
    updated_at: new Date().toISOString()
  })
  .eq('wallet_address', walletAddress);
```

**File Modified:** [EditProfileModal.tsx:97-104](src/components/EditProfileModal.tsx#L97-L104)

---

### 4. Stats Data Not Updating ✅ FIXED
**Problem:** All advanced stats showing 0 or N/A:
- Bounties Won: 0
- Win Rate: 0.0%
- Total Earned: 0.00 HBAR
- Total Spent: 0.00 HBAR
- Avg Attempts: 0
- Best Word Length: N/A

**Root Cause Analysis:**

Checked database RPC function `get_user_stats` ([018_user_stats_function.sql](supabase/migrations/018_user_stats_function.sql)):
```sql
RETURNS TABLE (
  total_bounty_created INTEGER,
  total_bounty_entered INTEGER,
  total_tries INTEGER,
  total_wins INTEGER,
  total_losses INTEGER,
  success_rate DECIMAL(5, 2)
)
```

**Missing fields:**
- ❌ `total_prize_money_earned`
- ❌ `total_prize_money_spent`
- ❌ `average_attempts`
- ❌ `best_word_length`

**Solution:** Enhanced `fetchUserData()` to fetch missing data from `users` table and `bounty_participants` table:

```typescript
const fetchUserData = async () => {
  // 1. Get basic stats from get_user_stats RPC function
  const { data: statsData } = await supabase.rpc('get_user_stats', {
    wallet_addr: walletAddress
  });

  // 2. Get user ID and HBAR totals from users table
  const { data: userIdData } = await supabase
    .from('users')
    .select('id, total_hbar_earned, total_hbar_spent')
    .eq('wallet_address', walletAddress)
    .single();

  // 3. Calculate average attempts from winning participations
  const { data: avgAttemptsData } = await supabase
    .from('bounty_participants')
    .select('total_attempts')
    .eq('user_id', userId)
    .eq('is_winner', true);

  const avgAttempts = avgAttemptsData && avgAttemptsData.length > 0
    ? avgAttemptsData.reduce((sum, p) => sum + (p.total_attempts || 0), 0) / avgAttemptsData.length
    : 0;

  // 4. Get best word length from won bounties
  const { data: bestWordData } = await supabase
    .from('bounty_participants')
    .select('bounty:bounties(words)')
    .eq('user_id', userId)
    .eq('is_winner', true);

  let bestWordLength = 0;
  if (bestWordData && bestWordData.length > 0) {
    bestWordData.forEach((item: any) => {
      if (item.bounty?.words && Array.isArray(item.bounty.words)) {
        item.bounty.words.forEach((word: string) => {
          if (word.length > bestWordLength) {
            bestWordLength = word.length;
          }
        });
      }
    });
  }

  // 5. Combine all stats
  setUserStats({
    total_bounties_created: stats.total_bounty_created || 0,
    total_bounties_participated: stats.total_bounty_entered || 0,
    total_bounties_won: stats.total_wins || 0,
    total_prize_money_earned: parseFloat(userIdData?.total_hbar_earned || '0'),
    total_prize_money_spent: parseFloat(userIdData?.total_hbar_spent || '0'),
    win_rate: parseFloat(stats.success_rate || '0'),
    average_attempts: avgAttempts,
    best_word_length: bestWordLength,
  });
};
```

**File Modified:** [ProfilePage.tsx:61-146](src/components/ProfilePage.tsx#L61-L146)

---

### 5. BountyHistory Rendering Error ✅ FIXED
**Problem:** React error when clicking Bounties tab

**Error Message:**
```
Error: Objects are not valid as a React child (found: object with keys {count})
```

**Root Cause:** Supabase `.select()` with `count` aggregate returns an array of objects `[{count: N}]`, not a simple number

**Original Query:**
```typescript
// ❌ Returns: participants_count = [{count: 5}]
const { data } = await supabase
  .from('bounties')
  .select(`
    *,
    participants_count:bounty_participants(count)  // Returns object!
  `)
```

**Solution:** Use the `participant_count` field that already exists in the `bounties` table:

```typescript
// ✅ Use existing field from bounties table
const { data } = await supabase
  .from('bounties')
  .select('*')  // participant_count is already in the table
  .eq('creator_id', userData.id)
```

**Files Modified:**
- [BountyHistory.tsx:94-106](src/components/BountyHistory.tsx#L94-L106) - Fixed query
- [BountyHistory.tsx:30](src/components/BountyHistory.tsx#L30) - Fixed interface `participants_count → participant_count`
- [BountyHistory.tsx:173-176](src/components/BountyHistory.tsx#L173-L176) - Fixed `canCancelBounty()` function
- [BountyHistory.tsx:242](src/components/BountyHistory.tsx#L242) - Fixed display

---

### 6. Missing Fields in Bounty Display ✅ FIXED
**Problem:** Accessing `bounty.word_length` and `bounty.max_attempts` which don't exist in schema

**Database Schema:**
```sql
-- bounties table has:
words TEXT[] NOT NULL          -- Array of words
max_attempts_per_user INTEGER  -- Not max_attempts!
-- NO word_length field (calculated from words[0].length)
```

**Solution:** Calculate word length from `words` array and use correct field name:

```typescript
// ❌ Before
<span>{bounty.word_length} letters</span>
<span>{bounty.max_attempts} attempts</span>

// ✅ After
{bounty.words && bounty.words.length > 0 && (
  <span>{bounty.words[0].length} letters</span>
)}
{bounty.max_attempts_per_user && (
  <span>{bounty.max_attempts_per_user} attempts</span>
)}
```

**File Modified:** [BountyHistory.tsx:246-257](src/components/BountyHistory.tsx#L246-L257)

---

## Database Schema Analysis

### Users Table Structure
```sql
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
    total_hbar_earned DECIMAL(20, 8) DEFAULT 0,      -- ✅ Exists!
    total_hbar_spent DECIMAL(20, 8) DEFAULT 0,       -- ✅ Exists!
    is_active BOOLEAN DEFAULT true
);
```

**Key Findings:**
- ❌ NO `email` field
- ✅ HAS `total_hbar_earned` and `total_hbar_spent`
- ✅ HAS both `username` and `display_name`

### Bounties Table Structure
```sql
CREATE TABLE bounties (
    id UUID PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    prize_amount DECIMAL(20, 8) NOT NULL,
    words TEXT[] NOT NULL,                           -- ✅ Array of words
    max_attempts_per_user INTEGER,                   -- ✅ Not max_attempts!
    participant_count INTEGER DEFAULT 0,             -- ✅ Updated by trigger
    ...
);
```

**Key Findings:**
- ❌ NO `word_length` field (calculate from `words[0].length`)
- ❌ NO `max_attempts` field (use `max_attempts_per_user`)
- ✅ HAS `participant_count` (auto-updated by trigger from migration 015)

### RPC Function: get_user_stats
**Returns:**
- `total_bounty_created` ✅
- `total_bounty_entered` ✅
- `total_tries` ✅
- `total_wins` ✅
- `total_losses` ✅
- `success_rate` ✅

**Does NOT return:**
- `total_prize_money_earned` ❌ (get from `users.total_hbar_earned`)
- `total_prize_money_spent` ❌ (get from `users.total_hbar_spent`)
- `average_attempts` ❌ (calculate from `bounty_participants`)
- `best_word_length` ❌ (calculate from won bounties)

---

## Files Modified Summary

| File | Lines | Changes |
|------|-------|---------|
| [ProfilePage.tsx](src/components/ProfilePage.tsx) | 61-146, 261, 294-300 | Fixed user data fetch, removed email, improved stats calculation, fixed tab layout |
| [EditProfileModal.tsx](src/components/EditProfileModal.tsx) | 1-212 | Complete rewrite - removed email, fixed username check with `.maybeSingle()`, update both username and display_name |
| [BountyHistory.tsx](src/components/BountyHistory.tsx) | 20-37, 94-106, 173-176, 242-257 | Fixed interface, query, participant_count usage, word_length calculation |

---

## Testing Checklist

- [x] Profile page loads without 400/406 errors
- [x] Username edit modal opens
- [x] Username update saves correctly
- [x] Username displays after save (not reverting to Anonymous)
- [x] Stats show correct data (earned, spent, win rate, avg attempts, best word length)
- [x] Bounties tab displays without React error
- [x] Participant count shows correctly
- [x] Word length displays (calculated from words array)
- [x] Max attempts displays (from max_attempts_per_user)
- [x] Tab layout uses flex display
- [x] No console errors

---

## Future Recommendations

### 1. Add Email Field to Database
If email functionality is needed in the future, add migration:
```sql
ALTER TABLE users ADD COLUMN email VARCHAR(255);
CREATE INDEX idx_users_email ON users(email);
```

### 2. Enhance get_user_stats RPC Function
Update to return all stats in one call:
```sql
CREATE OR REPLACE FUNCTION get_user_stats(wallet_addr TEXT)
RETURNS TABLE (
  -- Existing fields
  total_bounty_created INTEGER,
  total_bounty_entered INTEGER,
  total_wins INTEGER,
  success_rate DECIMAL(5, 2),
  -- Add these
  total_hbar_earned DECIMAL(20, 8),
  total_hbar_spent DECIMAL(20, 8),
  average_attempts DECIMAL(5, 2),
  best_word_length INTEGER
) AS $$
-- Implementation with calculations
$$ LANGUAGE plpgsql;
```

### 3. Add Computed Columns to Bounties
Consider adding computed columns for common calculations:
```sql
ALTER TABLE bounties
  ADD COLUMN word_length INTEGER GENERATED ALWAYS AS (LENGTH(words[1])) STORED;
```

### 4. Improve Error Handling
Add try-catch blocks and user-friendly error messages for all Supabase queries.

---

**Status:** ✅ ALL ISSUES RESOLVED

**Next Steps:** Test in production environment and monitor for any edge cases.
