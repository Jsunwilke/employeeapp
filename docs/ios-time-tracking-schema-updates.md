# iOS Time Tracking Schema Updates

**Date**: December 26, 2025
**Migration**: `005_add_time_tracking_fields.sql`
**Purpose**: Add fields required by iOS app to existing time tracking tables

---

## Overview

The iOS app requires additional fields beyond the basic web app schema to support enhanced time tracking and time off features. This migration adds those fields to the existing `time_entries`, `time_off_requests`, and `pto_balances` tables.

**Important**: All new fields are **nullable/optional** to maintain backward compatibility with existing web app code.

---

## Changes by Table

### 1. time_entries

Added fields for better time entry management and display:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `date` | text | NULL | Date in YYYY-MM-DD format for easy day-based queries |
| `notes` | text | NULL | Optional user notes about the time entry |
| `session_name` | text | NULL | Denormalized session name for display without joins |

**Why These Fields?**
- `date`: Allows iOS to efficiently query "show me all entries for this week" without parsing timestamps
- `notes`: Users can add context like "worked on yearbook proofs" or "traffic delay"
- `session_name`: Faster display without needing to join sessions table every time

**Web App Impact**:
- ✅ No breaking changes - all fields are optional
- ⚠️ Web app should populate `date` field when creating entries for iOS compatibility
- 💡 Consider showing `notes` in web UI if present

**Example Usage**:
```sql
-- iOS creates entry with all fields
INSERT INTO time_entries (id, user_id, organization_id, start_time, date, notes, session_name)
VALUES ('abc123', 'user-1', 'org-1', '2025-01-15 09:00:00', '2025-01-15', 'Morning shoot', 'Lincoln High School');

-- Query entries by date (iOS pattern)
SELECT * FROM time_entries
WHERE user_id = 'user-1'
  AND date >= '2025-01-15'
  AND date <= '2025-01-21'
ORDER BY date, start_time;
```

---

### 2. time_off_requests

Added extensive fields for partial day requests, PTO integration, and approval workflow:

#### Denormalized User Info
| Field | Type | Description |
|-------|------|-------------|
| `photographer_name` | text | Full name (first + last) for display |
| `photographer_email` | text | Email for notifications |

**Migration**: Auto-populated from `users` table for existing records

#### Request Details
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `notes` | text | '' | Additional notes from requester |

#### Partial Day Support
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `is_partial_day` | boolean | false | True if requesting hours instead of full days |
| `start_time` | text | NULL | Start time in "HH:mm" format (e.g., "09:00") |
| `end_time` | text | NULL | End time in "HH:mm" format (e.g., "13:00") |

**Usage Example**:
```sql
-- Full day request (existing pattern)
INSERT INTO time_off_requests (...)
VALUES (..., is_partial_day = false, start_date = '2025-02-01', end_date = '2025-02-03');

-- Partial day request (new iOS feature)
INSERT INTO time_off_requests (...)
VALUES (..., is_partial_day = true, start_date = '2025-02-01', end_date = '2025-02-01', start_time = '09:00', end_time = '13:00');
```

#### PTO Integration
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `is_paid_time_off` | boolean | false | True if this uses PTO balance |
| `pto_hours_requested` | numeric(10,2) | NULL | Hours to deduct from balance |
| `projected_pto_balance` | numeric(10,2) | NULL | Expected balance after approval |

**How PTO Works**:
1. Employee requests time off, marks `is_paid_time_off = true`
2. iOS calculates `pto_hours_requested` based on duration
3. iOS shows `projected_pto_balance` so employee knows impact
4. On approval, hours are deducted from `pto_balances.balance`
5. Pending hours are reserved in `pto_balances.pending_balance`

#### Approval Workflow
| Field | Type | Description |
|-------|------|-------------|
| `approved_by` | text | User ID of approving manager |
| `approver_name` | text | Manager's name for audit trail |
| `approved_at` | timestamptz | Approval timestamp |
| `denied_by` | text | User ID of denying manager |
| `denier_name` | text | Manager's name |
| `denied_at` | timestamptz | Denial timestamp |
| `denial_reason` | text | Reason for denial |
| `reviewed_by` | text | User ID of reviewer |
| `reviewer_name` | text | Reviewer's name |
| `reviewed_at` | timestamptz | Review timestamp |

**Workflow States**:
```
pending → (manager reviews) → approved/denied
                           → (can update to) underReview → approved/denied
```

**Web App Impact**:
- ⚠️ Web app should update approval fields when managers approve/deny
- 💡 Consider adding partial day support to web UI
- ✅ Existing simple requests (just start/end date) continue to work

**Example Approval Flow**:
```sql
-- Manager approves request
UPDATE time_off_requests
SET status = 'approved',
    approved_by = 'manager-123',
    approver_name = 'Jane Smith',
    approved_at = NOW()
WHERE id = 'request-456'
  AND status = 'pending';

-- If PTO request, update balance
UPDATE pto_balances
SET balance = balance - (SELECT pto_hours_requested FROM time_off_requests WHERE id = 'request-456'),
    pending_balance = pending_balance - (SELECT pto_hours_requested FROM time_off_requests WHERE id = 'request-456'),
    used = used + (SELECT pto_hours_requested FROM time_off_requests WHERE id = 'request-456')
WHERE user_id = (SELECT photographer_id FROM time_off_requests WHERE id = 'request-456');
```

---

### 3. pto_balances

Added fields for better PTO tracking and management:

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `pending_balance` | numeric(10,2) | 0 | Hours reserved for pending requests |
| `banking_balance` | numeric(10,2) | 0 | Excess hours over max accrual cap |
| `processed_periods` | jsonb | [] | Array of pay periods processed ["2024-01", ...] |
| `year` | integer | Current year | Year for this balance (multi-year tracking) |

**Balance Relationships**:
```
Total Accrued = balance + banking_balance + used
Available = balance - pending_balance
```

**How It Works**:
1. **Regular Balance** (`balance`): Current available PTO hours
2. **Pending Balance** (`pending_balance`): Hours reserved for pending requests
3. **Banking Balance** (`banking_balance`): Hours earned beyond max cap (if org allows banking)
4. **Used** (`used`): Hours used this year
5. **Accrued** (`accrued`): Total hours earned this year

**Example Scenario**:
```
Employee has:
- balance: 80 hours (10 days)
- pending_balance: 16 hours (2 days for pending request)
- banking_balance: 8 hours (excess over 80-hour cap)
- used: 24 hours (3 days used so far this year)
- accrued: 112 hours (total earned = 80 + 8 + 24)

Available to request: 80 - 16 = 64 hours (8 days)
```

**Processed Periods**:
```json
["2024-01", "2024-02", "2024-03"]
```
Tracks which pay periods have had PTO accrued to prevent double-accrual.

**Web App Impact**:
- ⚠️ When creating time off requests, reserve hours:
  ```sql
  UPDATE pto_balances
  SET pending_balance = pending_balance + [hours]
  WHERE user_id = [user];
  ```
- ⚠️ When approving, move from pending to used:
  ```sql
  UPDATE pto_balances
  SET balance = balance - [hours],
      pending_balance = pending_balance - [hours],
      used = used + [hours]
  WHERE user_id = [user];
  ```
- ⚠️ When denying, release reserved hours:
  ```sql
  UPDATE pto_balances
  SET pending_balance = pending_balance - [hours]
  WHERE user_id = [user];
  ```

---

## Migration Script

**File**: `supabase/migrations/005_add_time_tracking_fields.sql`

**What it does**:
1. Adds all new columns as nullable/optional
2. Creates indexes for performance
3. Updates RLS policies for approval workflow
4. Populates denormalized fields from existing data:
   - `photographer_name` and `photographer_email` from `users` table
   - `date` field from `start_time` in time_entries
   - `year` field with current year

**To run**:
```bash
supabase db reset  # Or apply migration to production
```

**Rollback** (if needed):
```sql
-- Drop new columns
ALTER TABLE time_entries DROP COLUMN date, DROP COLUMN notes, DROP COLUMN session_name;
ALTER TABLE time_off_requests DROP COLUMN photographer_name, /* ... all new columns ... */;
ALTER TABLE pto_balances DROP COLUMN pending_balance, /* ... all new columns ... */;
```

---

## Testing Checklist

### For Web Developers

- [ ] Verify existing time entries still display correctly
- [ ] Verify existing time off requests still work
- [ ] Test creating new time entries (with and without new fields)
- [ ] Test creating time off requests (ensure `photographer_name` is populated)
- [ ] Test manager approval flow (populate approval fields)
- [ ] Test PTO balance updates when approving requests
- [ ] Check that queries still perform well with new indexes

### Optional Enhancements for Web App

1. **Show Notes in Time Entries**: Display `notes` field if present
2. **Partial Day Requests**: Add UI for requesting half days with start/end times
3. **Approval Workflow**: Show who approved/denied and when
4. **PTO Projections**: Show `projected_pto_balance` when creating requests
5. **Banking Balance**: Display banked hours separately in PTO balance view

---

## Data Examples

### Complete Time Entry (iOS format)
```json
{
  "id": "entry-123",
  "user_id": "user-1",
  "organization_id": "org-1",
  "session_id": "session-456",
  "start_time": "2025-01-15T09:00:00Z",
  "end_time": "2025-01-15T17:00:00Z",
  "total_hours": 8.0,
  "status": "completed",
  "date": "2025-01-15",
  "notes": "Yearbook photo day at Lincoln High",
  "session_name": "Lincoln High School - Yearbook",
  "created_at": "2025-01-15T09:00:00Z",
  "updated_at": "2025-01-15T17:00:00Z"
}
```

### Partial Day Time Off Request (iOS format)
```json
{
  "id": "request-789",
  "organization_id": "org-1",
  "photographer_id": "user-1",
  "photographer_name": "John Doe",
  "photographer_email": "john@example.com",
  "start_date": "2025-02-10T00:00:00Z",
  "end_date": "2025-02-10T00:00:00Z",
  "status": "pending",
  "reason": "Medical Appointment",
  "type": "sick",
  "notes": "Doctor appointment",
  "is_partial_day": true,
  "start_time": "13:00",
  "end_time": "17:00",
  "is_paid_time_off": true,
  "pto_hours_requested": 4.0,
  "projected_pto_balance": 76.0,
  "created_at": "2025-02-01T10:00:00Z",
  "updated_at": "2025-02-01T10:00:00Z"
}
```

### Enhanced PTO Balance (iOS format)
```json
{
  "id": "balance-1",
  "organization_id": "org-1",
  "user_id": "user-1",
  "balance": 80.0,
  "accrued": 112.0,
  "used": 24.0,
  "pending_balance": 16.0,
  "banking_balance": 8.0,
  "processed_periods": ["2024-01", "2024-02", "2024-03"],
  "year": 2025,
  "created_at": "2024-01-01T00:00:00Z",
  "updated_at": "2025-01-15T00:00:00Z"
}
```

---

## Questions?

Contact the iOS team if you need clarification on any of these changes or want to discuss web app integration.
