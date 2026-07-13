-- DRAFT — NOT a live migration. Kept out of supabase/migrations/ on purpose so
-- `supabase db push` won't apply it. Review, then promote to a timestamped
-- migration when ready. See RLS_AUDIT.md §A / §C.
--
-- Fix: acquire_lock (20250115_atomic_locks.sql) is SECURITY DEFINER and trusts the
-- caller-supplied p_user_id / p_user_name, so a user can take a lock AS someone else
-- (and, with no org check, in another org). This adds an identity check: the claimed
-- p_user_id must equal the authenticated caller (auth.uid()). Legit clients already
-- pass their own id (users.id = auth.uid()::text in this app), so this does not change
-- the online happy path; it only rejects impersonation.
--
-- ⚠️ Touches PROTECTED Captura roster locking used by other photographers in
-- production. Deploy only after confirming (a) users.id === auth.uid()::text holds for
-- all callers, and (b) online lock acquisition still succeeds in a live test.
-- Org-scoping (reject locking a row whose organization_id != caller's org) is left as a
-- follow-up because it needs the confirmed org-column layout on roster_entries /
-- group_images.

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
    -- Re-authorize: the caller may only lock AS themselves. auth.uid() is the
    -- authenticated principal; p_user_id is what the client claims to be.
    IF auth.uid() IS NULL OR lower(p_user_id::text) <> lower(auth.uid()::text) THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Not authorized to lock as this user'
        );
    END IF;

    v_lock_expiry := NOW() - (p_lock_timeout_minutes || ' minutes')::INTERVAL;

    IF p_table_name = 'roster_entries' THEN
        SELECT locked_by_name, locked_at INTO v_current_lock_by, v_current_lock_at
        FROM roster_entries
        WHERE id = p_record_id
        FOR UPDATE;

        IF v_current_lock_by IS NULL
           OR v_current_lock_by = p_user_name
           OR v_current_lock_at < v_lock_expiry THEN

            UPDATE roster_entries
            SET locked_by = p_user_id,
                locked_by_name = p_user_name,
                locked_at = NOW()
            WHERE id = p_record_id;

            v_result := jsonb_build_object('success', true, 'message', 'Lock acquired');
        ELSE
            v_result := jsonb_build_object(
                'success', false,
                'message', 'Locked by ' || v_current_lock_by,
                'locked_by', v_current_lock_by,
                'locked_at', v_current_lock_at
            );
        END IF;

    ELSIF p_table_name = 'group_images' THEN
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

            v_result := jsonb_build_object('success', true, 'message', 'Lock acquired');
        ELSE
            v_result := jsonb_build_object(
                'success', false,
                'message', 'Locked by ' || v_current_lock_by,
                'locked_by', v_current_lock_by,
                'locked_at', v_current_lock_at
            );
        END IF;
    ELSE
        v_result := jsonb_build_object('success', false, 'message', 'Unknown table');
    END IF;

    RETURN v_result;
END;
$$;
