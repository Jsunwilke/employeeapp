-- Atomic Lock Acquisition Function
-- Uses SELECT ... FOR UPDATE to prevent race conditions
-- Returns JSON with success/failure and lock holder info

CREATE OR REPLACE FUNCTION acquire_lock(
    p_table_name TEXT,
    p_record_id UUID,
    p_user_id UUID,
    p_user_name TEXT,
    p_lock_timeout_minutes INT DEFAULT 2
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result JSONB;
    v_current_lock_by TEXT;
    v_current_lock_at TIMESTAMPTZ;
    v_lock_expiry TIMESTAMPTZ;
BEGIN
    v_lock_expiry := NOW() - (p_lock_timeout_minutes || ' minutes')::INTERVAL;

    IF p_table_name = 'roster_entries' THEN
        -- Use FOR UPDATE to lock the row during this transaction
        SELECT locked_by_name, locked_at INTO v_current_lock_by, v_current_lock_at
        FROM roster_entries
        WHERE id = p_record_id
        FOR UPDATE;

        -- Check if we can acquire the lock
        IF v_current_lock_by IS NULL
           OR v_current_lock_by = p_user_name
           OR v_current_lock_at < v_lock_expiry THEN

            -- Acquire the lock
            UPDATE roster_entries
            SET locked_by = p_user_id,
                locked_by_name = p_user_name,
                locked_at = NOW()
            WHERE id = p_record_id;

            v_result := jsonb_build_object(
                'success', true,
                'message', 'Lock acquired'
            );
        ELSE
            -- Lock held by someone else
            v_result := jsonb_build_object(
                'success', false,
                'message', 'Locked by ' || v_current_lock_by,
                'locked_by', v_current_lock_by,
                'locked_at', v_current_lock_at
            );
        END IF;

    ELSIF p_table_name = 'group_images' THEN
        -- Same logic for group_images
        SELECT locked_by_name, locked_at INTO v_current_lock_by, v_current_lock_at
        FROM group_images
        WHERE id = p_record_id
        FOR UPDATE;

        IF v_current_lock_by IS NULL
           OR v_current_lock_by = p_user_name
           OR v_current_lock_at < v_lock_expiry THEN

            UPDATE group_images
            SET locked_by = p_user_id,
                locked_by_name = p_user_name,
                locked_at = NOW()
            WHERE id = p_record_id;

            v_result := jsonb_build_object(
                'success', true,
                'message', 'Lock acquired'
            );
        ELSE
            v_result := jsonb_build_object(
                'success', false,
                'message', 'Locked by ' || v_current_lock_by,
                'locked_by', v_current_lock_by,
                'locked_at', v_current_lock_at
            );
        END IF;
    ELSE
        v_result := jsonb_build_object(
            'success', false,
            'message', 'Unknown table'
        );
    END IF;

    RETURN v_result;
END;
$$;

-- Grant execute permission to authenticated users
GRANT EXECUTE ON FUNCTION acquire_lock(TEXT, UUID, UUID, TEXT, INT) TO authenticated;

-- Enable pg_cron extension (if not already enabled)
-- Note: This requires superuser privileges and may already be enabled
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Schedule stale lock cleanup every minute
-- This ensures locks are cleared even if clients go offline
SELECT cron.schedule(
    'clear-stale-locks',
    '* * * * *',
    $$
    UPDATE roster_entries
    SET locked_by = NULL, locked_by_name = NULL, locked_at = NULL
    WHERE locked_at < NOW() - INTERVAL '2 minutes' AND locked_at IS NOT NULL;

    UPDATE group_images
    SET locked_by = NULL, locked_by_name = NULL, locked_at = NULL
    WHERE locked_at < NOW() - INTERVAL '2 minutes' AND locked_at IS NOT NULL;
    $$
);
