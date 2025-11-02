-- Migration: Add debugging to submit_attempt and ensure stats update correctly
-- This replaces the submit_attempt function with better error handling and logging

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
    rows_updated INTEGER;
BEGIN
    -- Get user
    SELECT id INTO user_uuid FROM users WHERE wallet_address = wallet_addr;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'User not found for wallet: %', wallet_addr;
    END IF;

    -- Get participant record (allow any active status, including 'completed' for multi-word bounties)
    SELECT * INTO participant_record
    FROM bounty_participants
    WHERE bounty_id = bounty_uuid AND user_id = user_uuid;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'User % not participating in bounty %', wallet_addr, bounty_uuid;
    END IF;

    -- Check if participation is active or completed
    IF participant_record.status NOT IN ('registered', 'active', 'completed') THEN
        RAISE EXCEPTION 'User participation status is %', participant_record.status;
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

    -- Check how many rows were actually updated
    GET DIAGNOSTICS rows_updated = ROW_COUNT;

    IF rows_updated = 0 THEN
        RAISE WARNING 'No rows updated for participant % in bounty %', participant_record.id, bounty_uuid;
    END IF;

    -- Build result
    result := jsonb_build_object(
        'correct', is_correct,
        'attempt_number', attempt_num,
        'letter_results', letter_results,
        'completed_bounty', is_correct AND word_idx + 1 >= array_length(bounty_record.words, 1),
        'participant_id', participant_record.id,
        'rows_updated', rows_updated
    );

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
