# Missing Database Fields Tracker

This file tracks database fields that need to be added in Supabase during the Firebase → Supabase migration.

---

## Tasks Table - Missing Fields

### 1. `type` Column
- **Table**: `tasks`
- **Column name**: `type`
- **Type**: `text`
- **Default value**: `'general'`
- **Nullable**: Yes
- **Description**: Stores task type (general/session/workflow)
- **SQL**: `ALTER TABLE tasks ADD COLUMN type TEXT DEFAULT 'general';`
- **Status**: ⏳ Pending

### 2. `watchers` Column
- **Table**: `tasks`
- **Column name**: `watchers`
- **Type**: `jsonb`
- **Default value**: `'[]'::jsonb`
- **Nullable**: No
- **Description**: Array of user IDs watching the task
- **SQL**: `ALTER TABLE tasks ADD COLUMN watchers JSONB DEFAULT '[]'::jsonb;`
- **Status**: ⏳ Pending

---

## Time Tracking Tables - Status ✅

**Phase 4: Time Tracking - FULLY MIGRATED**

All time tracking tables have complete schemas matching the migration guide:

### `time_entries` Table ✅
- All required fields present: id, organization_id, user_id, session_id
- Timestamp fields: start_time, end_time, created_at, updated_at
- Additional fields: total_hours, status, date, notes, session_name
- Migration file: `005_add_time_tracking_fields.sql`
- **Status**: ✅ Complete

### `time_off_requests` Table ✅
- All required fields present: id, organization_id, photographer_id
- Date fields: start_date, end_date, created_at, updated_at
- Enhanced fields: photographer_name, photographer_email, notes
- Partial day support: is_partial_day, start_time, end_time
- PTO fields: is_paid_time_off, pto_hours_requested, projected_pto_balance
- Approval workflow: approved_by, approver_name, approved_at
- Denial workflow: denied_by, denier_name, denied_at, denial_reason
- Review workflow: reviewed_by, reviewer_name, reviewed_at
- **Status**: ✅ Complete

### `pto_balances` Table ✅
- All required fields present: id, organization_id, user_id
- Balance tracking: balance, pending_balance, banking_balance
- Metadata: processed_periods, year, created_at, updated_at
- **Status**: ✅ Complete

### Fixes Applied:
1. ✅ Fixed status value mismatch: Changed `"clocked-in"` → `"active"` in validator
2. ✅ Fixed status references in UI files (EditTimeEntryView, TimeEntryDetailView, TimeEntryListView)
3. ✅ Verified all CodingKeys use correct database field names (`start_time`, `end_time`)
4. ✅ Confirmed migration SQL matches guide schema exactly
5. ✅ Fixed user ID case mismatch: Added `.lowercased()` to match database format

### Issues Found & Fixed:

**1. Status Values - FIXED in iOS**
- Web app uses: `"clocked-in"` / `"clocked-out"`
- iOS now uses: `"clocked-in"` / `"clocked-out"` (was `"active"` / `"completed"`)
- **Status**: ✅ Fixed (iOS updated to match web app)

**2. Date Field Query - FIXED in iOS**
- `date` field is NULL in database
- iOS now queries using `start_time` instead of `date`
- **Status**: ✅ Fixed (query changed to use start_time)

**3. User ID Case - FIXED in iOS**
- Database stores UUIDs in lowercase
- iOS now uses `.lowercased()` when setting user ID
- **Status**: ✅ Fixed

**4. Timezone Query Issue - FIXED in iOS**
- Entries stored in UTC (e.g., `2025-12-28 02:36:00+00`) weren't matching local date queries
- UTC `2025-12-28 02:36:00+00` = Dec 27 8:36 PM Central, but query was looking for Dec 27 without timezone
- iOS now dynamically calculates device timezone offset (e.g., `-06:00` for Central)
- Query now includes offset: `.gte("start_time", value: "2025-12-14T00:00:00-06:00")`
- **Status**: ✅ Fixed (dynamic timezone offset added to queries)

**5. Missing ID on Insert - FIXED in iOS**
- Error: `null value in column "id" of relation "time_entries" violates not-null constraint`
- Database doesn't auto-generate UUIDs for `id` column
- iOS now generates UUID and includes it in insert: `id: UUID().uuidString.lowercased()`
- Fixed in: `clockIn()` and `createManualTimeEntry()` functions
- **Status**: ✅ Fixed (UUID generation added to inserts)

---

## Other Tables - Missing Fields

*(Will be populated as we discover missing fields in other migration phases)*

---

## Notes

- These fields exist in the migration file `006_create_tasks_tables.sql` but are not yet in the live Supabase database
- Custom decoders have been added to the iOS app to handle missing fields gracefully with default values
- Fields should be added via Supabase web dashboard or by running the migration SQL
- Update status to ✅ once added in Supabase

---

**Last Updated**: 2025-12-27
