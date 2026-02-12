-- Create photoshoot_notes table for standalone note submission
-- Migration: 009_create_photoshoot_notes_table
-- Created: 2026-02-07
-- Purpose: Allow photographers to submit photoshoot notes independently from daily reports

-- Drop table if it exists (for clean slate)
DROP TABLE IF EXISTS photoshoot_notes CASCADE;

-- Create photoshoot_notes table
CREATE TABLE photoshoot_notes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    -- Metadata
    date DATE NOT NULL,
    photographer_id UUID NOT NULL REFERENCES auth.users(id),
    photographer_name TEXT NOT NULL,
    organization_id TEXT NOT NULL,

    -- Content
    school TEXT NOT NULL,
    shoot_type TEXT NOT NULL,
    notes TEXT NOT NULL,
    photo_urls TEXT[] DEFAULT '{}',

    -- Status
    status TEXT DEFAULT 'draft' CHECK (status IN ('draft', 'submitted')),
    submitted_at TIMESTAMPTZ,

    -- Optional: Link to daily report if attached
    daily_report_id TEXT REFERENCES daily_job_reports(id),

    -- Soft delete
    deleted_at TIMESTAMPTZ
);

-- Create indexes for performance
CREATE INDEX idx_photoshoot_notes_photographer
    ON photoshoot_notes(photographer_id);

CREATE INDEX idx_photoshoot_notes_date
    ON photoshoot_notes(date);

CREATE INDEX idx_photoshoot_notes_organization
    ON photoshoot_notes(organization_id);

CREATE INDEX idx_photoshoot_notes_status
    ON photoshoot_notes(status);

CREATE INDEX idx_photoshoot_notes_daily_report
    ON photoshoot_notes(daily_report_id)
    WHERE daily_report_id IS NOT NULL;

-- Add trigger for updated_at timestamp
CREATE OR REPLACE FUNCTION update_photoshoot_notes_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_photoshoot_notes_updated_at
    BEFORE UPDATE ON photoshoot_notes
    FOR EACH ROW
    EXECUTE FUNCTION update_photoshoot_notes_updated_at();

-- Enable Row Level Security
ALTER TABLE photoshoot_notes ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can view their own notes
CREATE POLICY "Users can view own notes"
    ON photoshoot_notes FOR SELECT
    USING (auth.uid() = photographer_id AND deleted_at IS NULL);

-- RLS Policy: Users can create their own notes
CREATE POLICY "Users can create own notes"
    ON photoshoot_notes FOR INSERT
    WITH CHECK (auth.uid() = photographer_id);

-- RLS Policy: Users can update their own notes (drafts or linking to reports)
CREATE POLICY "Users can update own notes"
    ON photoshoot_notes FOR UPDATE
    USING (auth.uid() = photographer_id);

-- RLS Policy: Managers can view all notes in their organization
CREATE POLICY "Managers can view organization notes"
    ON photoshoot_notes FOR SELECT
    USING (
        deleted_at IS NULL AND
        EXISTS (
            SELECT 1 FROM users
            WHERE users.id = auth.uid()::text
            AND users.organization_id = photoshoot_notes.organization_id
            AND users.role IN ('admin', 'manager')
        )
    );

-- Add comments to table for documentation
COMMENT ON TABLE photoshoot_notes IS 'Stores photoshoot notes that can be submitted independently or attached to daily reports';
COMMENT ON COLUMN photoshoot_notes.status IS 'draft: editable, submitted: read-only';
COMMENT ON COLUMN photoshoot_notes.daily_report_id IS 'NULL if standalone, set if attached to a daily report';
COMMENT ON COLUMN photoshoot_notes.deleted_at IS 'Soft delete timestamp';
