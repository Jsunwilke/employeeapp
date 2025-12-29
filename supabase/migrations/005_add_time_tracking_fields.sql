-- Migration: Add Missing Time Tracking Fields for iOS App
-- Date: 2025-12-26
-- Description: Adds fields needed by iOS app to existing time tracking tables

-- =====================================================
-- TIME ENTRIES - Add iOS-specific fields
-- =====================================================

-- Add date field for easy date-based queries (YYYY-MM-DD format)
ALTER TABLE time_entries
ADD COLUMN IF NOT EXISTS date text;

-- Add notes field for user comments on time entries
ALTER TABLE time_entries
ADD COLUMN IF NOT EXISTS notes text;

-- Add session_name for denormalized session display
ALTER TABLE time_entries
ADD COLUMN IF NOT EXISTS session_name text;

-- Add index for date queries
CREATE INDEX IF NOT EXISTS idx_time_entries_date ON time_entries(date);

-- =====================================================
-- TIME OFF REQUESTS - Add enhanced fields
-- =====================================================

-- Denormalized user information for display without joins
ALTER TABLE time_off_requests
ADD COLUMN IF NOT EXISTS photographer_name text,
ADD COLUMN IF NOT EXISTS photographer_email text;

-- Additional notes field
ALTER TABLE time_off_requests
ADD COLUMN IF NOT EXISTS notes text DEFAULT '';

-- Partial day support
ALTER TABLE time_off_requests
ADD COLUMN IF NOT EXISTS is_partial_day boolean DEFAULT false,
ADD COLUMN IF NOT EXISTS start_time text, -- Format: "HH:mm" e.g., "09:00"
ADD COLUMN IF NOT EXISTS end_time text;   -- Format: "HH:mm" e.g., "17:00"

-- PTO (Paid Time Off) fields
ALTER TABLE time_off_requests
ADD COLUMN IF NOT EXISTS is_paid_time_off boolean DEFAULT false,
ADD COLUMN IF NOT EXISTS pto_hours_requested numeric(10, 2),
ADD COLUMN IF NOT EXISTS projected_pto_balance numeric(10, 2);

-- Approval workflow fields
ALTER TABLE time_off_requests
ADD COLUMN IF NOT EXISTS approved_by text REFERENCES users(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS approver_name text,
ADD COLUMN IF NOT EXISTS approved_at timestamptz;

-- Denial workflow fields
ALTER TABLE time_off_requests
ADD COLUMN IF NOT EXISTS denied_by text REFERENCES users(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS denier_name text,
ADD COLUMN IF NOT EXISTS denied_at timestamptz,
ADD COLUMN IF NOT EXISTS denial_reason text;

-- Review workflow fields
ALTER TABLE time_off_requests
ADD COLUMN IF NOT EXISTS reviewed_by text REFERENCES users(id) ON DELETE SET NULL,
ADD COLUMN IF NOT EXISTS reviewer_name text,
ADD COLUMN IF NOT EXISTS reviewed_at timestamptz;

-- Add indexes for new fields
CREATE INDEX IF NOT EXISTS idx_time_off_approved_by ON time_off_requests(approved_by);
CREATE INDEX IF NOT EXISTS idx_time_off_denied_by ON time_off_requests(denied_by);
CREATE INDEX IF NOT EXISTS idx_time_off_partial_day ON time_off_requests(is_partial_day) WHERE is_partial_day = true;

-- =====================================================
-- PTO BALANCES - Add enhanced tracking
-- =====================================================

-- Pending balance for reserved hours in pending requests
ALTER TABLE pto_balances
ADD COLUMN IF NOT EXISTS pending_balance numeric(10, 2) DEFAULT 0;

-- Banking balance for excess hours over max accrual
ALTER TABLE pto_balances
ADD COLUMN IF NOT EXISTS banking_balance numeric(10, 2) DEFAULT 0;

-- Array of processed pay periods (e.g., ["2024-01", "2024-02"])
ALTER TABLE pto_balances
ADD COLUMN IF NOT EXISTS processed_periods jsonb DEFAULT '[]'::jsonb;

-- Year tracking for annual balances
ALTER TABLE pto_balances
ADD COLUMN IF NOT EXISTS year integer DEFAULT EXTRACT(YEAR FROM CURRENT_DATE);

-- Add computed column for available balance (balance - pending)
-- Note: PostgreSQL doesn't support GENERATED ALWAYS AS for existing tables in all versions
-- So we'll create a view or use a function instead
CREATE OR REPLACE FUNCTION pto_available_balance(balance_row pto_balances)
RETURNS numeric AS $$
BEGIN
  RETURN GREATEST(0, balance_row.balance - COALESCE(balance_row.pending_balance, 0));
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Add index for year queries
CREATE INDEX IF NOT EXISTS idx_pto_balances_year ON pto_balances(year);
CREATE INDEX IF NOT EXISTS idx_pto_balances_user_year ON pto_balances(user_id, year);

-- =====================================================
-- UPDATE RLS POLICIES (if needed)
-- =====================================================

-- The existing RLS policies should still work, but we can add specific ones for approval workflow

-- Drop policy if it exists, then recreate
DROP POLICY IF EXISTS "Managers can approve time off requests" ON time_off_requests;

-- Allow managers to update approval fields
CREATE POLICY "Managers can approve time off requests"
ON time_off_requests FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM users
    WHERE users.id = auth.uid()::text
    AND users.organization_id = time_off_requests.organization_id
    AND users.role IN ('admin', 'manager')
  )
);

-- =====================================================
-- COMMENTS
-- =====================================================

COMMENT ON COLUMN time_entries.date IS 'Date in YYYY-MM-DD format for easy querying by day';
COMMENT ON COLUMN time_entries.notes IS 'Optional user notes about this time entry';
COMMENT ON COLUMN time_entries.session_name IS 'Denormalized session name for display';

COMMENT ON COLUMN time_off_requests.photographer_name IS 'Denormalized user name for display without joins';
COMMENT ON COLUMN time_off_requests.photographer_email IS 'Denormalized email for notifications';
COMMENT ON COLUMN time_off_requests.is_partial_day IS 'True if this is a partial day request (hours instead of full day)';
COMMENT ON COLUMN time_off_requests.start_time IS 'Start time for partial day requests (HH:mm format)';
COMMENT ON COLUMN time_off_requests.end_time IS 'End time for partial day requests (HH:mm format)';
COMMENT ON COLUMN time_off_requests.is_paid_time_off IS 'True if this uses PTO balance';
COMMENT ON COLUMN time_off_requests.pto_hours_requested IS 'Number of PTO hours to deduct if approved';
COMMENT ON COLUMN time_off_requests.projected_pto_balance IS 'Expected PTO balance after this request';
COMMENT ON COLUMN time_off_requests.approved_by IS 'User ID of manager who approved';
COMMENT ON COLUMN time_off_requests.denied_by IS 'User ID of manager who denied';
COMMENT ON COLUMN time_off_requests.reviewed_by IS 'User ID of manager who reviewed';

COMMENT ON COLUMN pto_balances.pending_balance IS 'Hours reserved for pending time off requests';
COMMENT ON COLUMN pto_balances.banking_balance IS 'Excess hours over max accrual cap';
COMMENT ON COLUMN pto_balances.processed_periods IS 'Array of processed pay periods ["YYYY-MM", ...]';
COMMENT ON COLUMN pto_balances.year IS 'Year for this balance record (supports multi-year tracking)';

-- =====================================================
-- DATA MIGRATION (Populate new fields from existing data)
-- =====================================================

-- Populate photographer_name and photographer_email from users table
UPDATE time_off_requests tor
SET
  photographer_name = u.first_name || ' ' || u.last_name,
  photographer_email = u.email
FROM users u
WHERE tor.photographer_id = u.id
  AND tor.photographer_name IS NULL;

-- Populate date field in time_entries from start_time
UPDATE time_entries
SET date = TO_CHAR(start_time, 'YYYY-MM-DD')
WHERE date IS NULL AND start_time IS NOT NULL;

-- Set default year for existing pto_balances
UPDATE pto_balances
SET year = EXTRACT(YEAR FROM CURRENT_DATE)
WHERE year IS NULL;
