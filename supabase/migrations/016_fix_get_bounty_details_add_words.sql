-- Migration: Fix get_bounty_details to return words array
-- This is critical for GameplayPage to know what word to play

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

    -- Build result (FIXED: added 'words' array)
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
        'max_attempts_per_user', bounty_record.max_attempts_per_user,
        'time_limit_seconds', bounty_record.time_limit_seconds,
        'start_time', bounty_record.start_time,
        'end_time', bounty_record.end_time,
        'duration_hours', bounty_record.duration_hours,
        'created_at', bounty_record.created_at,
        'creator', jsonb_build_object(
            'username', bounty_record.creator_username,
            'display_name', bounty_record.creator_display_name
        ),
        'words', bounty_record.words,  -- CRITICAL FIX: Return actual words array
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
                    'total_time_seconds', participation_record.total_time_seconds,  -- Also added this
                    'is_winner', participation_record.is_winner
                )
            ELSE NULL
        END
    );

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
