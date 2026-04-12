-- =============================================================================
-- Migration 0005 — Ownership columns + RLS for calendar_events, km_sessions,
--                  km_session_player_stats. Replaces direct profiles-join in
--                  km_screenshots admin policy with private.is_admin() helper.
--
-- Source of truth: docs/ownership-model.md
-- Prereqs: 0001 (base schema), 0002 (user_app_data), 0003 (profiles.role), 0004 (km_screenshots)
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. private.is_admin() helper
--    Lives in `private` schema → not callable directly by Supabase client.
--    SECURITY DEFINER → runs as definer, bypasses caller RLS on profiles.
--    Used in every admin-read policy.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE SCHEMA IF NOT EXISTS private;

CREATE OR REPLACE FUNCTION private.is_admin(uid uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
AS $$
    SELECT EXISTS (
        SELECT 1 FROM profiles WHERE id = uid AND role = 'admin'
    );
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Fix km_screenshots admin policy (0004 used direct profiles join)
--    Drop old policy, replace with private.is_admin() call.
-- ─────────────────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS km_screenshots_select_admin ON km_screenshots;

CREATE POLICY km_screenshots_select_admin ON km_screenshots
    FOR SELECT USING (private.is_admin(auth.uid()));

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. calendar_events — add ownership columns
--
--    Added as NULLABLE to preserve any existing rows from pre-auth schema (0001).
--    RLS below makes rows without user_id invisible to all non-admin users —
--    which is correct and safe. When ready for NOT NULL:
--      1. Backfill: UPDATE calendar_events SET user_id = '<system-uid>',
--         created_by = '<system-uid>' WHERE user_id IS NULL;
--      2. ALTER TABLE calendar_events ALTER COLUMN user_id SET NOT NULL;
--         ALTER TABLE calendar_events ALTER COLUMN created_by SET NOT NULL;
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE calendar_events
    ADD COLUMN IF NOT EXISTS user_id    uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS created_by uuid REFERENCES auth.users(id),
    ADD COLUMN IF NOT EXISTS updated_by uuid REFERENCES auth.users(id);

CREATE INDEX IF NOT EXISTS idx_calendar_events_user_id
    ON calendar_events(user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. calendar_events — enable RLS + standard policies
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE calendar_events ENABLE ROW LEVEL SECURITY;

-- Owner: select own
CREATE POLICY calendar_events_select_own ON calendar_events
    FOR SELECT USING (auth.uid() = user_id);

-- Owner: insert own (caller must supply matching user_id + created_by)
CREATE POLICY calendar_events_insert_own ON calendar_events
    FOR INSERT WITH CHECK (auth.uid() = user_id AND auth.uid() = created_by);

-- Owner: update own
CREATE POLICY calendar_events_update_own ON calendar_events
    FOR UPDATE USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Owner: delete own
CREATE POLICY calendar_events_delete_own ON calendar_events
    FOR DELETE USING (auth.uid() = user_id);

-- Admin: read-only access to all rows
CREATE POLICY calendar_events_select_admin ON calendar_events
    FOR SELECT USING (private.is_admin(auth.uid()));

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. km_sessions — add ownership columns
--    Same nullable approach as calendar_events (see note above).
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE km_sessions
    ADD COLUMN IF NOT EXISTS user_id    uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS created_by uuid REFERENCES auth.users(id),
    ADD COLUMN IF NOT EXISTS updated_by uuid REFERENCES auth.users(id);

CREATE INDEX IF NOT EXISTS idx_km_sessions_user_id
    ON km_sessions(user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. km_sessions — enable RLS + standard policies
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE km_sessions ENABLE ROW LEVEL SECURITY;

-- Owner: select own
CREATE POLICY km_sessions_select_own ON km_sessions
    FOR SELECT USING (auth.uid() = user_id);

-- Owner: insert own
CREATE POLICY km_sessions_insert_own ON km_sessions
    FOR INSERT WITH CHECK (auth.uid() = user_id AND auth.uid() = created_by);

-- Owner: update own
CREATE POLICY km_sessions_update_own ON km_sessions
    FOR UPDATE USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Owner: delete own (CASCADE to km_session_player_stats via FK)
CREATE POLICY km_sessions_delete_own ON km_sessions
    FOR DELETE USING (auth.uid() = user_id);

-- Admin: read-only access to all rows
CREATE POLICY km_sessions_select_admin ON km_sessions
    FOR SELECT USING (private.is_admin(auth.uid()));

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. km_session_player_stats — child RLS via parent km_sessions.user_id
--    No user_id column on this table. Access derived from parent FK (session_id).
--    Delete on parent CASCADEs to child — no separate delete policy needed.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE km_session_player_stats ENABLE ROW LEVEL SECURITY;

-- Owner via parent: select
CREATE POLICY km_session_player_stats_select_own ON km_session_player_stats
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM km_sessions
            WHERE km_sessions.id = km_session_player_stats.session_id
              AND km_sessions.user_id = auth.uid()
        )
    );

-- Owner via parent: insert
CREATE POLICY km_session_player_stats_insert_own ON km_session_player_stats
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM km_sessions
            WHERE km_sessions.id = km_session_player_stats.session_id
              AND km_sessions.user_id = auth.uid()
        )
    );

-- Owner via parent: update
CREATE POLICY km_session_player_stats_update_own ON km_session_player_stats
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM km_sessions
            WHERE km_sessions.id = km_session_player_stats.session_id
              AND km_sessions.user_id = auth.uid()
        )
    );

-- Owner via parent: delete
CREATE POLICY km_session_player_stats_delete_own ON km_session_player_stats
    FOR DELETE USING (
        EXISTS (
            SELECT 1 FROM km_sessions
            WHERE km_sessions.id = km_session_player_stats.session_id
              AND km_sessions.user_id = auth.uid()
        )
    );

-- Admin: read-only access via is_admin helper
CREATE POLICY km_session_player_stats_select_admin ON km_session_player_stats
    FOR SELECT USING (private.is_admin(auth.uid()));
