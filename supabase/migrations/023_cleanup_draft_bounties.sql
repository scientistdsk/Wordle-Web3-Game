-- ============================================================================
-- Migration 022: Cleanup Draft Bounties
-- Created: 2025-10-10
-- Purpose: Auto-cleanup orphaned draft bounties that never got activated
-- ============================================================================

-- Function to delete old draft bounties (>15 minutes old)
CREATE OR REPLACE FUNCTION cleanup_old_draft_bounties()
RETURNS TABLE(
    deleted_count INTEGER,
    deleted_bounty_ids UUID[]
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    deleted_ids UUID[];
    delete_count INTEGER;
BEGIN
    -- Delete draft bounties created more than 15 minutes ago
    -- These are likely orphaned (payment failed or wallet crashed)
    DELETE FROM bounties
    WHERE status = 'draft'
      AND created_at < NOW() - INTERVAL '15 minutes'
    RETURNING id INTO deleted_ids;

    -- Get count and array of deleted IDs
    GET DIAGNOSTICS delete_count = ROW_COUNT;

    -- Log the cleanup
    IF delete_count > 0 THEN
        RAISE NOTICE 'Cleaned up % orphaned draft bounties: %', delete_count, deleted_ids;
    END IF;

    -- Return results
    RETURN QUERY SELECT delete_count, deleted_ids;
END;
$$;

-- Add comment
COMMENT ON FUNCTION cleanup_old_draft_bounties() IS
'Deletes draft bounties that are older than 15 minutes. These are likely orphaned bounties where payment failed or was cancelled. Can be called manually or via cron job.';

-- ============================================================================
-- USAGE INSTRUCTIONS
-- ============================================================================
/*
To manually run cleanup:
    SELECT * FROM cleanup_old_draft_bounties();

To set up automatic cleanup (optional - requires pg_cron extension):
    -- First enable pg_cron extension (Supabase: enable in Database > Extensions)
    -- Then create a cron job to run every hour:
    SELECT cron.schedule(
        'cleanup-draft-bounties',
        '0 * * * *',  -- Every hour at minute 0
        $$SELECT cleanup_old_draft_bounties()$$
    );

To view cron jobs:
    SELECT * FROM cron.job;

To unschedule the cron job:
    SELECT cron.unschedule('cleanup-draft-bounties');

To view recent cleanup results:
    SELECT * FROM cleanup_old_draft_bounties();
*/
