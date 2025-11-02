-- Fix RLS policies for payment_transactions table (Fixed version)
-- Created: 2025-01-28

-- Drop existing function if it exists
DROP FUNCTION IF EXISTS public.record_payment_transaction(UUID, UUID, VARCHAR, DECIMAL, VARCHAR, VARCHAR);

-- Ensure payment_transactions table exists with proper structure
CREATE TABLE IF NOT EXISTS payment_transactions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  bounty_id UUID REFERENCES bounties(id) ON DELETE CASCADE,
  user_id UUID REFERENCES users(id) ON DELETE CASCADE,
  transaction_type VARCHAR(20) NOT NULL CHECK (transaction_type IN ('deposit', 'prize_payment', 'refund')),
  amount DECIMAL(20, 8) NOT NULL,
  currency VARCHAR(10) NOT NULL DEFAULT 'HBAR',
  transaction_hash VARCHAR(255) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'failed')),
  created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  confirmed_at TIMESTAMPTZ
);

-- Enable RLS on payment_transactions
ALTER TABLE payment_transactions ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Anyone can insert payment transactions" ON payment_transactions;
DROP POLICY IF EXISTS "Anyone can view payment transactions" ON payment_transactions;
DROP POLICY IF EXISTS "Anyone can update payment transactions" ON payment_transactions;

-- Create permissive RLS policies for payment_transactions
-- Allow anonymous and authenticated users to insert payment records
CREATE POLICY "Anyone can insert payment transactions"
  ON payment_transactions FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

-- Allow viewing of payment transactions
CREATE POLICY "Anyone can view payment transactions"
  ON payment_transactions FOR SELECT
  TO anon, authenticated
  USING (true);

-- Allow updates to payment transactions (for status changes)
CREATE POLICY "Anyone can update payment transactions"
  ON payment_transactions FOR UPDATE
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

-- Create a public function for recording transactions that bypasses RLS
CREATE OR REPLACE FUNCTION public.record_payment_transaction(
  bounty_uuid UUID,
  user_uuid UUID,
  tx_type VARCHAR(20),
  tx_amount DECIMAL(20, 8),
  tx_currency VARCHAR(10),
  tx_hash VARCHAR(255)
) RETURNS UUID AS $$
DECLARE
  transaction_uuid UUID;
BEGIN
  INSERT INTO payment_transactions (
    bounty_id,
    user_id,
    transaction_type,
    amount,
    currency,
    transaction_hash,
    status,
    created_at
  ) VALUES (
    bounty_uuid,
    user_uuid,
    tx_type,
    tx_amount,
    tx_currency,
    tx_hash,
    'pending',
    NOW()
  ) RETURNING id INTO transaction_uuid;

  RETURN transaction_uuid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.record_payment_transaction(UUID, UUID, VARCHAR, DECIMAL, VARCHAR, VARCHAR) TO anon;
GRANT EXECUTE ON FUNCTION public.record_payment_transaction(UUID, UUID, VARCHAR, DECIMAL, VARCHAR, VARCHAR) TO authenticated;

-- Drop existing confirm function if it exists
DROP FUNCTION IF EXISTS public.confirm_payment_transaction(UUID);

-- Create function to confirm transaction status
CREATE OR REPLACE FUNCTION public.confirm_payment_transaction(
  transaction_uuid UUID
) RETURNS VOID AS $$
BEGIN
  UPDATE payment_transactions
  SET
    status = 'confirmed',
    confirmed_at = NOW()
  WHERE id = transaction_uuid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.confirm_payment_transaction(UUID) TO anon;
GRANT EXECUTE ON FUNCTION public.confirm_payment_transaction(UUID) TO authenticated;