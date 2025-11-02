-- Migration: Add triggers to automatically manage participant_count
-- Created: 2025-10-05
-- Purpose: Automatically increment/decrement participant_count when users join/leave bounties

-- Function to increment participant count when a user joins
CREATE OR REPLACE FUNCTION increment_participant_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE bounties
    SET participant_count = participant_count + 1
    WHERE id = NEW.bounty_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Function to decrement participant count when a participant is removed
CREATE OR REPLACE FUNCTION decrement_participant_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE bounties
    SET participant_count = participant_count - 1
    WHERE id = OLD.bounty_id AND participant_count > 0;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

-- Trigger to increment count after insert
CREATE TRIGGER auto_increment_participant_count
AFTER INSERT ON bounty_participants
FOR EACH ROW
EXECUTE FUNCTION increment_participant_count();

-- Trigger to decrement count after delete
CREATE TRIGGER auto_decrement_participant_count
AFTER DELETE ON bounty_participants
FOR EACH ROW
EXECUTE FUNCTION decrement_participant_count();

-- Add comment
COMMENT ON TRIGGER auto_increment_participant_count ON bounty_participants IS
'Automatically increments bounties.participant_count when a new participant joins';

COMMENT ON TRIGGER auto_decrement_participant_count ON bounty_participants IS
'Automatically decrements bounties.participant_count when a participant is removed';
