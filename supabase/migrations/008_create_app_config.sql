-- App-wide configuration table for storing shared secrets and settings
-- This table is designed to have exactly one row (id = 1)

CREATE TABLE IF NOT EXISTS app_config (
    id INTEGER PRIMARY KEY DEFAULT 1 CHECK (id = 1),
    claude_api_key TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert the single config row (key will be added via dashboard)
INSERT INTO app_config (id) VALUES (1) ON CONFLICT DO NOTHING;

-- Enable Row Level Security
ALTER TABLE app_config ENABLE ROW LEVEL SECURITY;

-- Policy: Only authenticated users can read the config
CREATE POLICY "Authenticated users can read app_config"
    ON app_config
    FOR SELECT
    TO authenticated
    USING (true);

-- Policy: No one can insert/update/delete via API (admin only via dashboard)
-- This ensures the key can only be managed through Supabase dashboard

-- Trigger to auto-update updated_at
CREATE OR REPLACE FUNCTION update_app_config_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER app_config_updated_at
    BEFORE UPDATE ON app_config
    FOR EACH ROW
    EXECUTE FUNCTION update_app_config_updated_at();
