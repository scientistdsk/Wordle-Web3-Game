-- Sample Data and Utility Functions
-- Created: 2025-01-28

-- Insert sample users
INSERT INTO users (wallet_address, username, display_name) VALUES
('0.0.123456', 'wordmaster', 'Word Master'),
('0.0.234567', 'quicksolver', 'Quick Solver'),
('0.0.345678', 'puzzlepro', 'Puzzle Pro'),
('0.0.456789', 'letterlord', 'Letter Lord'),
('0.0.567890', 'guessguru', 'Guess Guru')
ON CONFLICT (wallet_address) DO NOTHING;

-- Insert sample bounties
WITH sample_users AS (
    SELECT id, wallet_address FROM users LIMIT 5
)
INSERT INTO bounties (
    name,
    description,
    creator_id,
    bounty_type,
    words,
    hints,
    prize_amount,
    duration_hours,
    end_time,
    status,
    is_public
)
SELECT
    'Daily Word Challenge',
    'A simple word puzzle to test your vocabulary skills',
    (SELECT id FROM sample_users WHERE wallet_address = '0.0.123456'),
    'Simple'::bounty_type,
    ARRAY['PUZZLE'],
    ARRAY['A challenging game or problem'],
    50.0,
    24,
    NOW() + INTERVAL '24 hours',
    'active'::bounty_status,
    true
UNION ALL
SELECT
    'Speed Demon Challenge',
    'Fast-paced word solving with time pressure',
    (SELECT id FROM sample_users WHERE wallet_address = '0.0.234567'),
    'Time-based'::bounty_type,
    ARRAY['SPEED'],
    ARRAY['Moving very fast'],
    100.0,
    12,
    NOW() + INTERVAL '12 hours',
    'active'::bounty_status,
    true
UNION ALL
SELECT
    'Triple Threat Multistage',
    'Solve three words in sequence to win the prize',
    (SELECT id FROM sample_users WHERE wallet_address = '0.0.345678'),
    'Multistage'::bounty_type,
    ARRAY['TRIPLE', 'THREAT', 'MASTER'],
    ARRAY['Three times', 'A danger', 'Expert level'],
    200.0,
    48,
    NOW() + INTERVAL '48 hours',
    'active'::bounty_status,
    true
UNION ALL
SELECT
    'Mystery Word Hunt',
    'Random word challenge for the brave',
    (SELECT id FROM sample_users WHERE wallet_address = '0.0.456789'),
    'Random words'::bounty_type,
    ARRAY['MYSTERY'],
    ARRAY['Something unknown'],
    75.0,
    72,
    NOW() + INTERVAL '72 hours',
    'active'::bounty_status,
    true
ON CONFLICT DO NOTHING;

-- Utility function to create a new user or get existing one
CREATE OR REPLACE FUNCTION upsert_user(
    wallet_addr TEXT,
    user_name TEXT DEFAULT NULL,
    display_name TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    user_id UUID;
BEGIN
    INSERT INTO users (wallet_address, username, display_name)
    VALUES (wallet_addr, user_name, display_name)
    ON CONFLICT (wallet_address)
    DO UPDATE SET
        username = COALESCE(EXCLUDED.username, users.username),
        display_name = COALESCE(EXCLUDED.display_name, users.display_name),
        last_seen = NOW()
    RETURNING id INTO user_id;

    RETURN user_id;
END;
$$ LANGUAGE plpgsql;

-- Function to join a bounty
CREATE OR REPLACE FUNCTION join_bounty(
    bounty_uuid UUID,
    wallet_addr TEXT
)
RETURNS UUID AS $$
DECLARE
    user_uuid UUID;
    participant_id UUID;
    bounty_record RECORD;
BEGIN
    -- Get or create user
    user_uuid := upsert_user(wallet_addr);

    -- Check if bounty exists and is joinable
    SELECT * INTO bounty_record
    FROM bounties
    WHERE id = bounty_uuid
    AND status = 'active'
    AND is_public = true
    AND (end_time IS NULL OR end_time > NOW())
    AND (max_participants IS NULL OR participant_count < max_participants);

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Bounty not found or not joinable';
    END IF;

    -- Check if user already joined
    SELECT id INTO participant_id
    FROM bounty_participants
    WHERE bounty_id = bounty_uuid AND user_id = user_uuid;

    IF FOUND THEN
        RAISE EXCEPTION 'User already joined this bounty';
    END IF;

    -- Join the bounty
    INSERT INTO bounty_participants (bounty_id, user_id, status)
    VALUES (bounty_uuid, user_uuid, 'active')
    RETURNING id INTO participant_id;

    -- Update participant count
    UPDATE bounties
    SET participant_count = participant_count + 1
    WHERE id = bounty_uuid;

    RETURN participant_id;
END;
$$ LANGUAGE plpgsql;

-- Function to submit a word attempt
CREATE OR REPLACE FUNCTION submit_attempt(
    bounty_uuid UUID,
    wallet_addr TEXT,
    word_idx INTEGER,
    guessed_word TEXT,
    time_taken INTEGER DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    user_uuid UUID;
    participant_record RECORD;
    bounty_record RECORD;
    target_word TEXT;
    attempt_num INTEGER;
    letter_results JSONB;
    is_correct BOOLEAN;
    attempt_result attempt_result;
    result JSONB;
BEGIN
    -- Get user
    SELECT id INTO user_uuid FROM users WHERE wallet_address = wallet_addr;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User not found';
    END IF;

    -- Get participant record
    SELECT * INTO participant_record
    FROM bounty_participants
    WHERE bounty_id = bounty_uuid AND user_id = user_uuid AND status = 'active';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'User not participating in this bounty or already completed';
    END IF;

    -- Get bounty and target word
    SELECT * INTO bounty_record FROM bounties WHERE id = bounty_uuid;
    IF NOT FOUND OR word_idx >= array_length(bounty_record.words, 1) THEN
        RAISE EXCEPTION 'Invalid bounty or word index';
    END IF;

    target_word := bounty_record.words[word_idx + 1]; -- Arrays are 1-indexed in PostgreSQL

    -- Get next attempt number for this word
    SELECT COALESCE(MAX(attempt_number), 0) + 1 INTO attempt_num
    FROM game_attempts
    WHERE participant_id = participant_record.id AND word_index = word_idx;

    -- Check if word is correct
    is_correct := UPPER(guessed_word) = UPPER(target_word);

    -- Calculate letter results (simplified - in real implementation this would be more complex)
    letter_results := jsonb_build_object(
        'word', UPPER(guessed_word),
        'target', UPPER(target_word),
        'correct', is_correct
    );

    -- Determine attempt result
    IF is_correct THEN
        attempt_result := 'correct';
    ELSE
        attempt_result := 'incorrect';
    END IF;

    -- Insert attempt
    INSERT INTO game_attempts (
        participant_id,
        bounty_id,
        word_index,
        attempt_number,
        guessed_word,
        target_word,
        result,
        letter_results,
        time_taken_seconds
    ) VALUES (
        participant_record.id,
        bounty_uuid,
        word_idx,
        attempt_num,
        UPPER(guessed_word),
        UPPER(target_word),
        attempt_result,
        letter_results,
        time_taken
    );

    -- Update participant progress
    UPDATE bounty_participants
    SET
        total_attempts = total_attempts + 1,
        total_time_seconds = COALESCE(total_time_seconds, 0) + COALESCE(time_taken, 0),
        words_completed = CASE
            WHEN is_correct THEN GREATEST(words_completed, word_idx + 1)
            ELSE words_completed
        END,
        current_word_index = CASE
            WHEN is_correct AND word_idx + 1 >= array_length(bounty_record.words, 1) THEN word_idx
            WHEN is_correct THEN word_idx + 1
            ELSE current_word_index
        END,
        status = CASE
            WHEN is_correct AND word_idx + 1 >= array_length(bounty_record.words, 1) THEN 'completed'::participation_status
            ELSE status
        END,
        completed_at = CASE
            WHEN is_correct AND word_idx + 1 >= array_length(bounty_record.words, 1) THEN NOW()
            ELSE completed_at
        END
    WHERE id = participant_record.id;

    -- Build result
    result := jsonb_build_object(
        'correct', is_correct,
        'attempt_number', attempt_num,
        'letter_results', letter_results,
        'completed_bounty', is_correct AND word_idx + 1 >= array_length(bounty_record.words, 1)
    );

    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Function to get bounty with participation info
CREATE OR REPLACE FUNCTION get_bounty_details(
    bounty_uuid UUID,
    wallet_addr TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    bounty_record RECORD;
    participation_record RECORD;
    user_uuid UUID;
    result JSONB;
BEGIN
    -- Get bounty
    SELECT
        b.*,
        u.username as creator_username,
        u.display_name as creator_display_name
    INTO bounty_record
    FROM bounties b
    JOIN users u ON b.creator_id = u.id
    WHERE b.id = bounty_uuid;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Bounty not found';
    END IF;

    -- Get user participation if wallet provided
    participation_record := NULL;
    IF wallet_addr IS NOT NULL THEN
        SELECT id INTO user_uuid FROM users WHERE wallet_address = wallet_addr;
        IF FOUND THEN
            SELECT * INTO participation_record
            FROM bounty_participants
            WHERE bounty_id = bounty_uuid AND user_id = user_uuid;
        END IF;
    END IF;

    -- Build result
    result := jsonb_build_object(
        'id', bounty_record.id,
        'name', bounty_record.name,
        'description', bounty_record.description,
        'bounty_type', bounty_record.bounty_type,
        'prize_amount', bounty_record.prize_amount,
        'prize_currency', bounty_record.prize_currency,
        'status', bounty_record.status,
        'is_public', bounty_record.is_public,
        'participant_count', bounty_record.participant_count,
        'max_participants', bounty_record.max_participants,
        'start_time', bounty_record.start_time,
        'end_time', bounty_record.end_time,
        'duration_hours', bounty_record.duration_hours,
        'created_at', bounty_record.created_at,
        'creator', jsonb_build_object(
            'username', bounty_record.creator_username,
            'display_name', bounty_record.creator_display_name
        ),
        'words_count', array_length(bounty_record.words, 1),
        'hints', bounty_record.hints,
        'participation', CASE
            WHEN participation_record IS NOT NULL THEN
                jsonb_build_object(
                    'status', participation_record.status,
                    'joined_at', participation_record.joined_at,
                    'current_word_index', participation_record.current_word_index,
                    'total_attempts', participation_record.total_attempts,
                    'words_completed', participation_record.words_completed,
                    'is_winner', participation_record.is_winner
                )
            ELSE NULL
        END
    );

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Refresh the leaderboard initially
SELECT refresh_leaderboard();