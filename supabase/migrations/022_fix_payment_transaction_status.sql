-- ============================================================================
-- Migration 021: Fix payment_transactions status constraint
-- Created: 2025-10-09
-- Purpose: Update payment_transactions status constraint to include 'completed'
-- ============================================================================

-- Drop existing constraint
ALTER TABLE payment_transactions
DROP CONSTRAINT IF EXISTS check_valid_transaction_status;

-- Add updated constraint with 'completed' status
ALTER TABLE payment_transactions
ADD CONSTRAINT check_valid_transaction_status
CHECK (status IN ('pending', 'confirmed', 'failed', 'completed'));

-- Add comment
COMMENT ON CONSTRAINT check_valid_transaction_status ON payment_transactions IS
'Valid transaction statuses: pending (awaiting confirmation), confirmed (blockchain confirmed), completed (fully processed), failed (transaction failed)';
