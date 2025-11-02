-- Payment and transaction management functions (FIXED VERSION)
-- Created: 2025-01-28
-- This version works with VARCHAR transaction types instead of enums

-- First, let's create the enum types if they don't exist
DO $$
BEGIN
    -- Create transaction_type enum if it doesn't exist
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'transaction_type') THEN
        CREATE TYPE transaction_type AS ENUM (
            'deposit',
            'prize_payment',
            'refund'
        );
    END IF;

    -- Create transaction_status enum if it doesn't exist
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'transaction_status') THEN
        CREATE TYPE transaction_status AS ENUM (
            'pending',
            'confirmed',
            'failed'
        );
    END IF;
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Function to complete a bounty and mark winner
CREATE OR REPLACE FUNCTION complete_bounty(
  bounty_uuid UUID,
  winner_user_id UUID,
  prize_amount DECIMAL(20, 8)
) RETURNS void AS $$
BEGIN
  -- Update bounty status to completed
  UPDATE bounties
  SET
    status = 'completed',
    completion_count = completion_count + 1,
    updated_at = NOW()
  WHERE id = bounty_uuid;

  -- Update the winner's participation record
  UPDATE bounty_participants
  SET
    status = 'completed',
    is_winner = true,
    prize_amount_won = prize_amount,
    completed_at = NOW()
  WHERE bounty_id = bounty_uuid AND user_id = winner_user_id;

  -- Update user statistics
  UPDATE users
  SET
    total_bounties_won = total_bounties_won + 1,
    total_hbar_earned = total_hbar_earned + prize_amount,
    updated_at = NOW()
  WHERE id = winner_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to record a payment transaction (using VARCHAR instead of enum)
CREATE OR REPLACE FUNCTION record_payment_transaction(
  bounty_uuid UUID,
  user_uuid UUID,
  tx_type VARCHAR(50),
  amount DECIMAL(20, 8),
  currency VARCHAR(10),
  tx_hash VARCHAR(255)
) RETURNS UUID AS $$
DECLARE
  transaction_id UUID;
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
    tx_type,  -- Using VARCHAR directly
    amount,
    currency,
    tx_hash,
    'pending',  -- Using VARCHAR directly
    NOW()
  ) RETURNING id INTO transaction_id;

  RETURN transaction_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to confirm a payment transaction
CREATE OR REPLACE FUNCTION confirm_payment_transaction(
  transaction_uuid UUID
) RETURNS void AS $$
BEGIN
  UPDATE payment_transactions
  SET
    status = 'confirmed',
    confirmed_at = NOW()
  WHERE id = transaction_uuid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get user payment history (using VARCHAR types)
CREATE OR REPLACE FUNCTION get_user_payment_history(
  wallet_addr VARCHAR(255),
  limit_count INTEGER DEFAULT 50
) RETURNS TABLE (
  id UUID,
  bounty_id UUID,
  bounty_name VARCHAR(255),
  transaction_type VARCHAR(50),
  amount DECIMAL(20, 8),
  currency VARCHAR(10),
  transaction_hash VARCHAR(255),
  status VARCHAR(50),
  created_at TIMESTAMP WITH TIME ZONE,
  confirmed_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    pt.id,
    pt.bounty_id,
    b.name as bounty_name,
    pt.transaction_type,
    pt.amount,
    pt.currency,
    pt.transaction_hash,
    pt.status,
    pt.created_at,
    pt.confirmed_at
  FROM payment_transactions pt
  JOIN users u ON pt.user_id = u.id
  LEFT JOIN bounties b ON pt.bounty_id = b.id
  WHERE u.wallet_address = wallet_addr
  ORDER BY pt.created_at DESC
  LIMIT limit_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get bounty payment summary
CREATE OR REPLACE FUNCTION get_bounty_payment_summary(
  bounty_uuid UUID
) RETURNS TABLE (
  total_deposits DECIMAL(20, 8),
  total_prizes_paid DECIMAL(20, 8),
  total_refunds DECIMAL(20, 8),
  pending_transactions INTEGER,
  confirmed_transactions INTEGER
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    COALESCE(SUM(CASE WHEN transaction_type = 'deposit' THEN amount ELSE 0 END), 0) as total_deposits,
    COALESCE(SUM(CASE WHEN transaction_type = 'prize_payment' THEN amount ELSE 0 END), 0) as total_prizes_paid,
    COALESCE(SUM(CASE WHEN transaction_type = 'refund' THEN amount ELSE 0 END), 0) as total_refunds,
    COUNT(CASE WHEN status = 'pending' THEN 1 END)::INTEGER as pending_transactions,
    COUNT(CASE WHEN status = 'confirmed' THEN 1 END)::INTEGER as confirmed_transactions
  FROM payment_transactions
  WHERE bounty_id = bounty_uuid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to update bounty with transaction hash
CREATE OR REPLACE FUNCTION update_bounty_transaction(
  bounty_uuid UUID,
  tx_hash VARCHAR(255),
  escrow_addr VARCHAR(255) DEFAULT NULL
) RETURNS void AS $$
BEGIN
  UPDATE bounties
  SET
    transaction_hash = tx_hash,
    escrow_address = COALESCE(escrow_addr, escrow_address),
    updated_at = NOW()
  WHERE id = bounty_uuid;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get platform statistics
CREATE OR REPLACE FUNCTION get_platform_payment_stats() RETURNS TABLE (
  total_bounties_created INTEGER,
  total_prize_pool DECIMAL(20, 8),
  total_prizes_distributed DECIMAL(20, 8),
  active_bounty_count INTEGER,
  completed_bounty_count INTEGER
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    COUNT(*)::INTEGER as total_bounties_created,
    COALESCE(SUM(prize_amount), 0) as total_prize_pool,
    COALESCE(SUM(CASE WHEN status = 'completed' THEN prize_amount ELSE 0 END), 0) as total_prizes_distributed,
    COUNT(CASE WHEN status = 'active' THEN 1 END)::INTEGER as active_bounty_count,
    COUNT(CASE WHEN status = 'completed' THEN 1 END)::INTEGER as completed_bounty_count
  FROM bounties;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger to automatically refresh leaderboard when bounty is completed
CREATE OR REPLACE FUNCTION refresh_leaderboard_on_completion()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'completed' AND OLD.status != 'completed' THEN
    REFRESH MATERIALIZED VIEW CONCURRENTLY leaderboard;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Drop trigger if exists and recreate
DROP TRIGGER IF EXISTS bounty_completion_trigger ON bounties;
CREATE TRIGGER bounty_completion_trigger
  AFTER UPDATE ON bounties
  FOR EACH ROW
  EXECUTE FUNCTION refresh_leaderboard_on_completion();

-- Grant necessary permissions
GRANT EXECUTE ON FUNCTION complete_bounty(UUID, UUID, DECIMAL) TO authenticated;
GRANT EXECUTE ON FUNCTION record_payment_transaction(UUID, UUID, VARCHAR, DECIMAL, VARCHAR, VARCHAR) TO authenticated;
GRANT EXECUTE ON FUNCTION confirm_payment_transaction(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_user_payment_history(VARCHAR, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION get_bounty_payment_summary(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION update_bounty_transaction(UUID, VARCHAR, VARCHAR) TO authenticated;
GRANT EXECUTE ON FUNCTION get_platform_payment_stats() TO authenticated;

-- Add a helper function to check transaction type validity
CREATE OR REPLACE FUNCTION is_valid_transaction_type(tx_type VARCHAR(50))
RETURNS BOOLEAN AS $$
BEGIN
  RETURN tx_type IN ('deposit', 'prize_payment', 'refund');
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Add a helper function to check transaction status validity
CREATE OR REPLACE FUNCTION is_valid_transaction_status(tx_status VARCHAR(50))
RETURNS BOOLEAN AS $$
BEGIN
  RETURN tx_status IN ('pending', 'confirmed', 'failed');
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Add check constraints to payment_transactions table if not exists
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'check_valid_transaction_type'
    AND conrelid = 'payment_transactions'::regclass
  ) THEN
    ALTER TABLE payment_transactions
    ADD CONSTRAINT check_valid_transaction_type
    CHECK (transaction_type IN ('deposit', 'prize_payment', 'refund'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'check_valid_transaction_status'
    AND conrelid = 'payment_transactions'::regclass
  ) THEN
    ALTER TABLE payment_transactions
    ADD CONSTRAINT check_valid_transaction_status
    CHECK (status IN ('pending', 'confirmed', 'failed'));
  END IF;
END $$;