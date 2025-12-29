-- Phase 5: Reports & Templates Migration
-- Creates report_templates and daily_job_reports tables

-- =====================================================
-- Table: report_templates
-- =====================================================
CREATE TABLE IF NOT EXISTS report_templates (
    id TEXT PRIMARY KEY NOT NULL,
    organization_id TEXT NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    shoot_type TEXT NOT NULL,  -- sports, general, etc.
    fields JSONB NOT NULL DEFAULT '[]',  -- Array of TemplateField objects
    is_default BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    version INTEGER DEFAULT 1,
    created_by TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT fk_report_templates_org FOREIGN KEY (organization_id)
        REFERENCES organizations(id) ON DELETE CASCADE
);

-- Indexes for report_templates
CREATE INDEX IF NOT EXISTS idx_report_templates_org ON report_templates(organization_id);
CREATE INDEX IF NOT EXISTS idx_report_templates_active ON report_templates(is_active);
CREATE INDEX IF NOT EXISTS idx_report_templates_shoot_type ON report_templates(shoot_type);

-- =====================================================
-- Table: daily_job_reports
-- =====================================================
CREATE TABLE IF NOT EXISTS daily_job_reports (
    id TEXT PRIMARY KEY NOT NULL,
    organization_id TEXT NOT NULL,
    user_id TEXT NOT NULL,

    -- Report date and metadata
    date DATE NOT NULL,  -- The date of the job
    your_name TEXT NOT NULL,  -- Photographer's first name (legacy support)

    -- School/Location
    school_or_destination TEXT,  -- Comma-separated school names

    -- Mileage
    total_mileage NUMERIC DEFAULT 0,

    -- Job details (multi-select arrays)
    job_descriptions JSONB DEFAULT '[]',  -- Array of strings
    extra_items JSONB DEFAULT '[]',  -- Array of strings

    -- Yes/No/NA selections
    cards_scanned_choice TEXT,  -- Yes, No, or empty
    job_box_and_camera_cards TEXT,  -- Yes, No, NA, or empty
    sports_background_shot TEXT,  -- Yes, No, NA, or empty

    -- Notes
    job_description_text TEXT,  -- Free-text job notes

    -- Photoshoot note reference
    photoshoot_note_id TEXT,
    photoshoot_note_text TEXT,

    -- Photos
    photo_urls JSONB DEFAULT '[]',  -- Array of URL strings

    -- Template reference (for template-based reports)
    template_id TEXT,
    template_name TEXT,
    template_version INTEGER,
    report_type TEXT DEFAULT 'standard',  -- standard or template
    smart_fields_used JSONB DEFAULT '[]',  -- Array of field IDs
    form_data JSONB DEFAULT '{}',  -- Dynamic form field values

    -- Timestamps
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),

    CONSTRAINT fk_daily_job_reports_org FOREIGN KEY (organization_id)
        REFERENCES organizations(id) ON DELETE CASCADE,
    CONSTRAINT fk_daily_job_reports_user FOREIGN KEY (user_id)
        REFERENCES users(id) ON DELETE CASCADE
);

-- Indexes for common queries on daily_job_reports
CREATE INDEX IF NOT EXISTS idx_daily_job_reports_org ON daily_job_reports(organization_id);
CREATE INDEX IF NOT EXISTS idx_daily_job_reports_user ON daily_job_reports(user_id);
CREATE INDEX IF NOT EXISTS idx_daily_job_reports_date ON daily_job_reports(date);
CREATE INDEX IF NOT EXISTS idx_daily_job_reports_your_name ON daily_job_reports(your_name);
CREATE INDEX IF NOT EXISTS idx_daily_job_reports_org_date ON daily_job_reports(organization_id, date);
CREATE INDEX IF NOT EXISTS idx_daily_job_reports_user_date ON daily_job_reports(user_id, date);

-- =====================================================
-- Triggers for updated_at (using existing function from 006)
-- =====================================================

-- Apply trigger to report_templates
DROP TRIGGER IF EXISTS update_report_templates_updated_at ON report_templates;
CREATE TRIGGER update_report_templates_updated_at
    BEFORE UPDATE ON report_templates
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Apply trigger to daily_job_reports
DROP TRIGGER IF EXISTS update_daily_job_reports_updated_at ON daily_job_reports;
CREATE TRIGGER update_daily_job_reports_updated_at
    BEFORE UPDATE ON daily_job_reports
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- =====================================================
-- Row Level Security (RLS)
-- =====================================================

-- Enable RLS on all tables
ALTER TABLE report_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_job_reports ENABLE ROW LEVEL SECURITY;

-- =====================================================
-- RLS Policies for report_templates
-- Users can view/modify templates in their organization
-- =====================================================

CREATE POLICY "Users can view templates in their organization" ON report_templates
    FOR SELECT USING (
        organization_id IN (
            SELECT organization_id FROM users WHERE id = auth.uid()::text
        )
    );

CREATE POLICY "Users can insert templates in their organization" ON report_templates
    FOR INSERT WITH CHECK (
        organization_id IN (
            SELECT organization_id FROM users WHERE id = auth.uid()::text
        )
    );

CREATE POLICY "Users can update templates in their organization" ON report_templates
    FOR UPDATE USING (
        organization_id IN (
            SELECT organization_id FROM users WHERE id = auth.uid()::text
        )
    );

CREATE POLICY "Users can delete templates they created" ON report_templates
    FOR DELETE USING (
        created_by = auth.uid()::text
    );

-- =====================================================
-- RLS Policies for daily_job_reports
-- Users can view reports in their organization, modify their own
-- =====================================================

CREATE POLICY "Users can view reports in their organization" ON daily_job_reports
    FOR SELECT USING (
        organization_id IN (
            SELECT organization_id FROM users WHERE id = auth.uid()::text
        )
    );

CREATE POLICY "Users can insert their own reports" ON daily_job_reports
    FOR INSERT WITH CHECK (
        user_id = auth.uid()::text
    );

CREATE POLICY "Users can update their own reports" ON daily_job_reports
    FOR UPDATE USING (
        user_id = auth.uid()::text
    );

CREATE POLICY "Users can delete their own reports" ON daily_job_reports
    FOR DELETE USING (
        user_id = auth.uid()::text
    );
