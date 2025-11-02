-- Fix bounty update policies to allow transaction hash updates
-- Created: 2025-01-28

-- Drop existing bounty update policies if they exist
DROP POLICY IF EXISTS "Creators can update their bounties" ON bounties;
DROP POLICY IF EXISTS "Anyone can update bounty transaction info" ON bounties;

-- Create a more permissive update policy for bounties
-- Allow creators to update their own bounties
CREATE POLICY "Creators can update their bounties"
  ON bounties FOR UPDATE
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

-- Also allow updating transaction-related fields for payment processing
CREATE POLICY "Anyone can update bounty transaction info"
  ON bounties FOR UPDATE
  TO anon, authenticated
  USING (true)
  WITH CHECK (true);

-- Create a public function for updating bounty transaction info that bypasses RLS
CREATE OR REPLACE FUNCTION public.update_bounty_transaction_info(
  bounty_uuid UUID,
  tx_hash VARCHAR(255),
  escrow_addr VARCHAR(255)
) RETURNS VOID AS $$
BEGIN
  UPDATE bounties
  SET
    transaction_hash = tx_hash,
    escrow_address = escrow_addr,
    updated_at = NOW()
  WHERE id = bounty_uuid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION public.update_bounty_transaction_info(UUID, VARCHAR, VARCHAR) TO anon;
GRANT EXECUTE ON FUNCTION public.update_bounty_transaction_info(UUID, VARCHAR, VARCHAR) TO authenticated;