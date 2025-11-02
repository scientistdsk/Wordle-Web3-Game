-- Migration: Move 'first-to-solve' from prize_distribution to winner_criteria
-- Created: 2025-10-05
-- Purpose: Refactor to correctly categorize 'first-to-solve' as a winning criteria rather than prize distribution
-- NOTE: This migration assumes a clean database. If you have existing data with 'first-to-solve',
--       you may need to manually migrate that data first.

-- Step 1: Add 'first-to-solve' to winner_criteria enum
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_enum
        WHERE enumlabel = 'first-to-solve'
        AND enumtypid = 'winner_criteria'::regtype
    ) THEN
        ALTER TYPE winner_criteria ADD VALUE 'first-to-solve';
    END IF;
END $$;

-- Step 2: Drop the default constraint FIRST
ALTER TABLE bounties
    ALTER COLUMN prize_distribution DROP DEFAULT;

-- Step 3: Create a new prize_distribution enum without 'first-to-solve'
CREATE TYPE prize_distribution_new AS ENUM (
    'winner-take-all',
    'split-winners'
);

-- Step 4: Update the bounties table to use the new enum
-- This will convert any existing data to the new structure
ALTER TABLE bounties
    ALTER COLUMN prize_distribution TYPE prize_distribution_new
    USING prize_distribution::text::prize_distribution_new;

-- Step 5: Drop the old enum and rename the new one
DROP TYPE prize_distribution;
ALTER TYPE prize_distribution_new RENAME TO prize_distribution;

-- Step 6: Re-add the default value with the correct enum type
ALTER TABLE bounties
    ALTER COLUMN prize_distribution SET DEFAULT 'winner-take-all'::prize_distribution;

-- Add comments to document the change
COMMENT ON TYPE prize_distribution IS 'Prize distribution methods: winner-take-all or split-winners';
COMMENT ON TYPE winner_criteria IS 'Winning criteria: first-to-solve, time, attempts, or words-correct';
