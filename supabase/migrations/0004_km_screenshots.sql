-- KM Screenshots storage foundation
-- Stores metadata for day/KM screenshot files uploaded to Supabase Storage.

-- 1. Metadata table
CREATE TABLE IF NOT EXISTS km_screenshots (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    date_str      text NOT NULL,               -- '2026-04-12' format, links to KM day
    file_name     text NOT NULL,               -- original filename from user
    storage_path  text NOT NULL UNIQUE,        -- full path inside 'km-screenshots' bucket
    file_size     integer,
    mime_type     text,
    created_by    uuid NOT NULL REFERENCES auth.users(id),
    updated_by    uuid REFERENCES auth.users(id),
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now()
);

-- Indexes for common lookups
CREATE INDEX IF NOT EXISTS idx_km_screenshots_user_date
    ON km_screenshots(user_id, date_str);

CREATE INDEX IF NOT EXISTS idx_km_screenshots_storage_path
    ON km_screenshots(storage_path);

-- Auto-update updated_at on row change
CREATE TRIGGER set_km_screenshots_updated_at
    BEFORE UPDATE ON km_screenshots
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 2. Storage bucket (run via Supabase dashboard or supabase CLI)
-- INSERT INTO storage.buckets (id, name, public)
-- VALUES ('km-screenshots', 'km-screenshots', false)
-- ON CONFLICT (id) DO NOTHING;

-- 3. RLS policies — owner-first model
ALTER TABLE km_screenshots ENABLE ROW LEVEL SECURITY;

-- Owner can read own screenshots
CREATE POLICY km_screenshots_select_own ON km_screenshots
    FOR SELECT USING (auth.uid() = user_id);

-- Owner can insert own screenshots
CREATE POLICY km_screenshots_insert_own ON km_screenshots
    FOR INSERT WITH CHECK (auth.uid() = user_id AND auth.uid() = created_by);

-- Owner can delete own screenshots
CREATE POLICY km_screenshots_delete_own ON km_screenshots
    FOR DELETE USING (auth.uid() = user_id);

-- Owner can update own screenshots (e.g. updated_by)
CREATE POLICY km_screenshots_update_own ON km_screenshots
    FOR UPDATE USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Admin can read all screenshots (safe read-only expansion)
-- Uses profiles.role check — same pattern as existing admin gates
CREATE POLICY km_screenshots_select_admin ON km_screenshots
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin')
    );

-- 4. Storage RLS (apply via Supabase dashboard > Storage > Policies)
-- Bucket: km-screenshots
-- Path convention: {user_id}/{date_str}/{uuid}.{ext}
--
-- SELECT (download): auth.uid()::text = (storage.foldername(name))[1]
-- INSERT (upload):   auth.uid()::text = (storage.foldername(name))[1]
-- DELETE:            auth.uid()::text = (storage.foldername(name))[1]
--
-- Admin SELECT all:
--   EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
