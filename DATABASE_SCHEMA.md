# Focal Point Supabase Database Schema

**Generated:** 2026-01-11

**Database:** PostgreSQL (Supabase)

---

## Table of Contents

- [blocked_dates](#blocked_dates)
- [class_group_jobs](#class_group_jobs)
- [conversations](#conversations)
- [critique_feedback](#critique_feedback)
- [daily_job_reports](#daily_job_reports)
- [districts](#districts)
- [group_images](#group_images)
- [job_boxes](#job_boxes)
- [messages](#messages)
- [organizations](#organizations)
- [photo_critiques](#photo_critiques)
- [photoshoot_notes](#photoshoot_notes)
- [player_search_index](#player_search_index)
- [proof_activity](#proof_activity)
- [proof_galleries](#proof_galleries)
- [proof_images](#proof_images)
- [proof_revisions](#proof_revisions)
- [proofs](#proofs)
- [pto_adjustments](#pto_adjustments)
- [pto_balances](#pto_balances)
- [records](#records)
- [recurring_tasks](#recurring_tasks)
- [report_templates](#report_templates)
- [roster_entries](#roster_entries)
- [school_advisors](#school_advisors)
- [schools](#schools)
- [sd_cards](#sd_cards)
- [sessions](#sessions)
- [sport_mappings](#sport_mappings)
- [sports_jobs](#sports_jobs)
- [sync_queue](#sync_queue)
- [task_activities](#task_activities)
- [task_attachments](#task_attachments)
- [task_comments](#task_comments)
- [task_dependencies](#task_dependencies)
- [task_notifications](#task_notifications)
- [task_templates](#task_templates)
- [tasks](#tasks)
- [time_entries](#time_entries)
- [time_off_requests](#time_off_requests)
- [users](#users)
- [workflow_templates](#workflow_templates)
- [workflows](#workflows)
- [yearbook_page_assignments](#yearbook_page_assignments)
- [yearbook_proof_activity](#yearbook_proof_activity)
- [yearbook_proof_comments](#yearbook_proof_comments)
- [yearbook_proof_signoffs](#yearbook_proof_signoffs)
- [yearbook_proofs](#yearbook_proofs)
- [yearbook_shoot_lists](#yearbook_shoot_lists)

---

## blocked_dates

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (text) | NO | Note:
This is a Primary Key.<pk/> |
| organization_id | string (text) | YES | Note:
This is a Foreign Key to `organizations.id`.<fk table='organizations' column='id'/> |
| user_id | string (text) | YES | - |
| start_date | string (timestamp with time zone) | YES | - |
| end_date | string (timestamp with time zone) | YES | - |
| reason | string (text) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |
| allow_high_priority | boolean (boolean) | YES | - |

---

## class_group_jobs

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (text) | NO | Note:
This is a Primary Key.<pk/> |
| organization_id | string (text) | NO | - |
| school_id | string (text) | YES | - |
| school_name | string (text) | YES | - |
| session_id | string (text) | YES | - |
| session_date | string (timestamp with time zone) | YES | - |
| job_type | string (text) | YES | - |
| class_groups | unknown (jsonb) | YES | - |
| created_by | string (text) | YES | - |
| last_modified_by | string (text) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |
| updated_at | string (timestamp with time zone) | YES | - |
| notes | string (text) | YES | - |

---

## conversations

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (text) | NO | Note:
This is a Primary Key.<pk/> |
| participants | unknown (jsonb) | YES | - |
| type | string (text) | YES | - |
| name | string (text) | YES | - |
| default_name | string (text) | YES | - |
| last_activity | string (timestamp with time zone) | YES | - |
| last_message | string (text) | YES | - |
| unread_counts | unknown (jsonb) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |

---

## critique_feedback

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (text) | NO | Note:
This is a Primary Key.<pk/> |
| critique_id | string (text) | YES | Note:
This is a Foreign Key to `photo_critiques.id`.<fk table='photo_critiques' column='id'/> |
| organization_id | string (text) | YES | - |
| reviewer_id | string (text) | YES | - |
| reviewer_name | string (text) | YES | - |
| rating | integer (integer) | YES | - |
| comments | string (text) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |
| updated_at | string (timestamp with time zone) | YES | - |

---

## daily_job_reports

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (text) | NO | Note:
This is a Primary Key.<pk/> |
| organization_id | string (text) | YES | Note:
This is a Foreign Key to `organizations.id`.<fk table='organizations' column='id'/> |
| user_id | string (text) | YES | - |
| your_name | string (text) | YES | - |
| date | string (timestamp with time zone) | YES | - |
| total_mileage | number (numeric) | YES | - |
| report_data | unknown (jsonb) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |
| updated_at | string (timestamp with time zone) | YES | - |
| timestamp | string (timestamp with time zone) | YES | - |
| photographer | string (text) | YES | - |
| template_id | string (text) | YES | - |
| template_name | string (text) | YES | - |
| template_version | integer (integer) | YES | - |
| report_type | string (text) | YES | - |
| smart_fields_used | unknown (jsonb) | YES | - |
| notes | string (text) | YES | - |
| school_name | string (text) | YES | - |
| school_id | string (text) | YES | - |
| session_id | string (text) | YES | - |
| school_or_destination | string (text) | YES | - |
| job_descriptions | unknown (jsonb) | YES | - |
| extra_items | unknown (jsonb) | YES | - |
| photoshoot_note_text | string (text) | YES | - |
| job_description_text | string (text) | YES | - |
| job_box_and_camera_cards | string (text) | YES | - |
| sports_background_shot | string (text) | YES | - |
| cards_scanned_choice | string (text) | YES | - |
| photo_urls | unknown (jsonb) | YES | - |

---

## districts

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (text) | NO | Note:
This is a Primary Key.<pk/> |
| organization_id | string (text) | YES | Note:
This is a Foreign Key to `organizations.id`.<fk table='organizations' column='id'/> |
| name | string (text) | YES | - |
| schools | unknown (jsonb) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |
| updated_at | string (timestamp with time zone) | YES | - |

---

## group_images

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (uuid) | NO | Note:
This is a Primary Key.<pk/> |
| sports_job_id | string (uuid) | NO | Note:
This is a Foreign Key to `sports_jobs.id`.<fk table='sports_jobs' column='id'/> |
| description | string (text) | YES | - |
| image_numbers | string (text) | YES | - |
| notes | string (text) | YES | - |
| sport | string (text) | YES | - |
| gender | string (text) | YES | - |
| team_level | string (text) | YES | - |
| sort_order | integer (integer) | YES | - |
| version | integer (integer) | YES | - |
| updated_at | string (timestamp with time zone) | YES | - |
| updated_by | string (uuid) | YES | - |
| locked_by | string (uuid) | YES | - |
| locked_by_name | string (text) | YES | - |
| locked_at | string (timestamp with time zone) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |

---

## job_boxes

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (text) | NO | Note:
This is a Primary Key.<pk/> |
| organization_id | string (text) | YES | Note:
This is a Foreign Key to `organizations.id`.<fk table='organizations' column='id'/> |
| status | string (text) | YES | - |
| photographer | string (text) | YES | - |
| school | string (text) | YES | - |
| box_number | string (text) | YES | - |
| school_id | string (text) | YES | - |
| shift_uid | string (text) | YES | - |
| timestamp | string (timestamp with time zone) | YES | - |
| user_id | string (text) | YES | - |

---

## messages

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (text) | NO | Note:
This is a Primary Key.<pk/> |
| conversation_id | string (text) | YES | - |
| sender_id | string (text) | YES | - |
| sender_name | string (text) | YES | - |
| text | string (text) | YES | - |
| type | string (text) | YES | - |
| file_url | string (text) | YES | - |
| file_data | unknown (jsonb) | YES | - |
| status | string (text) | YES | - |
| read_by | unknown (jsonb) | YES | - |
| timestamp | string (timestamp with time zone) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |

---

## organizations

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (text) | NO | Note:
This is a Primary Key.<pk/> |
| name | string (text) | YES | - |
| logo_url | string (text) | YES | - |
| session_order_colors | unknown (jsonb) | YES | - |
| pay_period_settings | unknown (jsonb) | YES | - |
| is_active | boolean (boolean) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |
| updated_at | string (timestamp with time zone) | YES | - |
| session_types | unknown (jsonb) | YES | - |
| email | string (text) | YES | - |
| phone | string (text) | YES | - |
| website | string (text) | YES | - |
| subscription | unknown (jsonb) | YES | - |
| preferences | unknown (jsonb) | YES | - |
| address | unknown (jsonb) | YES | - |
| operating_hours | unknown (jsonb) | YES | - |
| policies | unknown (jsonb) | YES | - |
| business_info | unknown (jsonb) | YES | - |
| enable_session_publishing | boolean (boolean) | YES | - |
| pto_settings | unknown (jsonb) | YES | - |
| overtime_settings | unknown (jsonb) | YES | - |
| pricing | unknown (jsonb) | YES | - |
| workflow_tab_order | unknown (jsonb) | YES | - |
| yearbook_email | string (text) | YES | - |

---

## photo_critiques

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (text) | NO | Note:
This is a Primary Key.<pk/> |
| organization_id | string (text) | NO | - |
| submitter_id | string (text) | YES | - |
| submitter_name | string (text) | YES | - |
| submitter_email | string (text) | YES | - |
| target_photographer_id | string (text) | YES | - |
| target_photographer_name | string (text) | YES | - |
| photographer_id | string (text) | YES | - |
| photographer_name | string (text) | YES | - |
| image_url | string (text) | YES | - |
| image_urls | unknown (jsonb) | YES | - |
| thumbnail_url | string (text) | YES | - |
| thumbnail_urls | unknown (jsonb) | YES | - |
| image_count | integer (integer) | YES | - |
| manager_notes | string (text) | YES | - |
| notes | string (text) | YES | - |
| example_type | string (text) | YES | - |
| type | string (text) | YES | - |
| status | string (text) | YES | - |
| feedback_count | integer (integer) | YES | - |
| average_rating | number (numeric) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |
| updated_at | string (timestamp with time zone) | YES | - |

---

## photoshoot_notes

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (text) | NO | Note:
This is a Primary Key.<pk/> |
| organization_id | string (text) | YES | - |
| note_data | unknown (jsonb) | YES | - |
| location | unknown (jsonb) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |
| updated_at | string (timestamp with time zone) | YES | - |

---

## player_search_index

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (text) | NO | Note:
This is a Primary Key.<pk/> |
| job_id | string (text) | YES | - |
| organization_id | string (text) | YES | - |
| player_data | unknown (jsonb) | YES | - |
| search_fields | unknown (jsonb) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |

---

## proof_activity

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (text) | NO | Note:
This is a Primary Key.<pk/> |
| gallery_id | string (text) | YES | - |
| action | string (text) | YES | - |
| proof_id | string (text) | YES | - |
| filename | string (text) | YES | - |
| count | integer (integer) | YES | - |
| user_email | string (text) | YES | - |
| timestamp | string (timestamp with time zone) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |

---

## proof_galleries

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (text) | NO | Note:
This is a Primary Key.<pk/> |
| organization_id | string (text) | YES | - |
| name | string (text) | YES | - |
| is_public | boolean (boolean) | YES | - |
| gallery_data | unknown (jsonb) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |
| updated_at | string (timestamp with time zone) | YES | - |
| is_archived | boolean (boolean) | YES | - |
| school_id | string (text) | YES | - |
| school_name | string (text) | YES | - |
| workflow_id | string (text) | YES | - |
| client_name | string (text) | YES | - |
| status | string (text) | YES | - |
| password | string (text) | YES | - |
| total_images | integer (integer) | YES | - |
| approved_count | integer (integer) | YES | - |
| denied_count | integer (integer) | YES | - |
| archived_at | string (timestamp with time zone) | YES | - |
| last_approved_by | string (text) | YES | - |
| is_active | boolean (boolean) | YES | - |
| created_by | string (text) | YES | - |
| created_by_name | string (text) | YES | - |
| deadline | string (timestamp with time zone) | YES | - |
| client_email | string (text) | YES | - |
| last_reviewer_email | string (text) | YES | - |

---

## proof_images

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (text) | NO | Note:
This is a Primary Key.<pk/> |
| gallery_id | string (text) | YES | - |
| image_url | string (text) | YES | - |
| image_data | unknown (jsonb) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |

---

## proof_revisions

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (text) | NO | Note:
This is a Primary Key.<pk/> |
| proof_id | string (text) | YES | - |
| gallery_id | string (text) | YES | - |
| original_image_url | string (text) | YES | - |
| original_filename | string (text) | YES | - |
| new_image_url | string (text) | YES | - |
| new_filename | string (text) | YES | - |
| version_number | integer (integer) | YES | - |
| previous_version | integer (integer) | YES | - |
| is_latest | boolean (boolean) | YES | - |
| is_current | boolean (boolean) | YES | - |
| denial_notes | string (text) | YES | - |
| studio_notes | string (text) | YES | - |
| replaced_by | string (text) | YES | - |
| replaced_at | string (timestamp with time zone) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |

---

## proofs

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (text) | NO | Note:
This is a Primary Key.<pk/> |
| gallery_id | string (text) | YES | - |
| filename | string (text) | YES | - |
| image_url | string (text) | YES | - |
| thumbnail_url | string (text) | YES | - |
| order | integer (integer) | YES | - |
| status | string (text) | YES | - |
| denial_notes | string (text) | YES | - |
| current_version | integer (integer) | YES | - |
| version_count | integer (integer) | YES | - |
| has_versions | boolean (boolean) | YES | - |
| last_revision_id | string (text) | YES | - |
| reviewed_at | string (timestamp with time zone) | YES | - |
| reviewed_by | string (text) | YES | - |
| denied_by | string (text) | YES | - |
| denied_at | string (timestamp with time zone) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |
| updated_at | string (timestamp with time zone) | YES | - |

---

## pto_adjustments

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (text) | NO | Note:
This is a Primary Key.<pk/> |
| organization_id | string (text) | YES | - |
| user_id | string (text) | YES | - |
| amount | number (numeric) | YES | - |
| reason | string (text) | YES | - |
| adjusted_by | string (text) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |

---

## pto_balances

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (text) | NO | Note:
This is a Primary Key.<pk/> |
| organization_id | string (text) | YES | - |
| user_id | string (text) | YES | - |
| balance | number (numeric) | YES | - |
| accrued | number (numeric) | YES | - |
| used | number (numeric) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |
| updated_at | string (timestamp with time zone) | YES | - |
| pending_balance | number (numeric) | YES | Hours reserved for pending time off requests |
| banking_balance | number (numeric) | YES | Excess hours over max accrual cap |
| processed_periods | unknown (jsonb) | YES | Array of processed pay periods ["YYYY-MM", ...] |
| year | integer (integer) | YES | Year for this balance record (supports multi-year tracking) |

---

## records

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (text) | NO | Note:
This is a Primary Key.<pk/> |
| organization_id | string (text) | NO | - |
| card_number | string (text) | YES | - |
| school | string (text) | YES | - |
| status | string (text) | YES | - |
| user_id | string (text) | YES | - |
| timestamp | string (timestamp with time zone) | YES | - |
| uploaded_from_andys_house | boolean (boolean) | YES | - |
| uploaded_from_jasons_house | boolean (boolean) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |

---

## recurring_tasks

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (uuid) | NO | Note:
This is a Primary Key.<pk/> |
| organization_id | string (text) | NO | - |
| created_by | string (uuid) | YES | - |
| title | string (text) | NO | - |
| description | string (text) | YES | - |
| type | string (text) | YES | - |
| priority | string (text) | YES | - |
| assigned_to | string (uuid) | YES | - |
| interval_days | integer (integer) | NO | - |
| days_until_due | integer (integer) | YES | - |
| next_run | string (timestamp with time zone) | YES | - |
| last_run | string (timestamp with time zone) | YES | - |
| is_active | boolean (boolean) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |
| updated_at | string (timestamp with time zone) | YES | - |

---

## report_templates

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (text) | NO | Note:
This is a Primary Key.<pk/> |
| organization_id | string (text) | YES | Note:
This is a Foreign Key to `organizations.id`.<fk table='organizations' column='id'/> |
| name | string (text) | YES | - |
| sections | unknown (jsonb) | YES | - |
| is_active | boolean (boolean) | YES | - |
| updated_at | string (timestamp with time zone) | YES | - |

---

## roster_entries

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (uuid) | NO | Note:
This is a Primary Key.<pk/> |
| sports_job_id | string (uuid) | NO | Note:
This is a Foreign Key to `sports_jobs.id`.<fk table='sports_jobs' column='id'/> |
| last_name | string (text) | YES | - |
| first_name | string (text) | YES | - |
| teacher | string (text) | YES | - |
| group_name | string (text) | YES | - |
| email | string (text) | YES | - |
| phone | string (text) | YES | - |
| image_numbers | string (text) | YES | - |
| notes | string (text) | YES | - |
| sort_order | integer (integer) | YES | - |
| version | integer (integer) | YES | - |
| updated_at | string (timestamp with time zone) | YES | - |
| updated_by | string (uuid) | YES | - |
| locked_by | string (uuid) | YES | - |
| locked_by_name | string (text) | YES | - |
| locked_at | string (timestamp with time zone) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |
| is_filled_blank | boolean (boolean) | YES | - |

---

## school_advisors

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (uuid) | NO | Note:
This is a Primary Key.<pk/> |
| school_id | string (text) | NO | - |
| name | string (text) | NO | - |
| email | string (text) | NO | - |
| created_at | string (timestamp with time zone) | YES | - |
| updated_at | string (timestamp with time zone) | YES | - |

---

## schools

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (text) | NO | Note:
This is a Primary Key.<pk/> |
| organization_id | string (text) | YES | Note:
This is a Foreign Key to `organizations.id`.<fk table='organizations' column='id'/> |
| name | string (text) | YES | - |
| address | string (text) | YES | - |
| city | string (text) | YES | - |
| state | string (text) | YES | - |
| zip | string (text) | YES | - |
| coordinates | unknown (jsonb) | YES | - |
| is_active | boolean (boolean) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |
| updated_at | string (timestamp with time zone) | YES | - |
| street | string (text) | YES | - |
| contact_name | string (text) | YES | - |
| contact_email | string (text) | YES | - |
| contact_phone | string (text) | YES | - |
| notes | string (text) | YES | - |
| district_id | string (text) | YES | - |
| district_name | string (text) | YES | - |

---

## sd_cards

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (text) | NO | Note:
This is a Primary Key.<pk/> |
| organization_id | string (text) | YES | Note:
This is a Foreign Key to `organizations.id`.<fk table='organizations' column='id'/> |
| job_id | string (text) | YES | - |
| status | string (text) | YES | - |
| photographer | string (text) | YES | - |
| updated_at | string (timestamp with time zone) | YES | - |

---

## sessions

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (text) | NO | Note:
This is a Primary Key.<pk/> |
| organization_id | string (text) | YES | Note:
This is a Foreign Key to `organizations.id`.<fk table='organizations' column='id'/> |
| user_id | string (text) | YES | - |
| school_id | string (text) | YES | - |
| date | string (text) | YES | - |
| start_time | string (text) | YES | - |
| end_time | string (text) | YES | - |
| location | string (text) | YES | - |
| session_color | string (text) | YES | - |
| is_time_off | boolean (boolean) | YES | - |
| reason | string (text) | YES | - |
| status | string (text) | YES | - |
| workflow_id | string (text) | YES | - |
| notes | string (text) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |
| updated_at | string (timestamp with time zone) | YES | - |
| school_name | string (text) | YES | - |
| title | string (text) | YES | - |
| photographer_notes | string (text) | YES | - |
| session_type | string (text) | YES | - |
| session_types | unknown (jsonb) | YES | - |
| is_published | boolean (boolean) | YES | - |
| photographers | unknown (jsonb) | YES | - |
| custom_session_type | string (text) | YES | - |
| created_by | unknown (jsonb) | YES | - |
| has_job_box_assigned | boolean (boolean) | YES | - |
| job_box_record_id | string (text) | YES | - |
| published_at | string (timestamp with time zone) | YES | - |

---

## sport_mappings

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (uuid) | NO | Note:
This is a Primary Key.<pk/> |
| organization_id | string (text) | NO | Note:
This is a Foreign Key to `organizations.id`.<fk table='organizations' column='id'/> |
| original_name | string (text) | NO | - |
| category | string (text) | NO | - |
| created_at | string (timestamp with time zone) | YES | - |

---

## sports_jobs

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (uuid) | NO | Note:
This is a Primary Key.<pk/> |
| organization_id | string (text) | NO | - |
| school_name | string (text) | NO | - |
| school_id | string (text) | YES | - |
| sport_name | string (text) | YES | - |
| season_type | string (text) | YES | - |
| shoot_date | string (date) | NO | - |
| location | string (text) | YES | - |
| photographer | string (text) | YES | - |
| additional_notes | string (text) | YES | - |
| session_id | string (text) | YES | - |
| is_archived | boolean (boolean) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |
| updated_at | string (timestamp with time zone) | YES | - |

---

## sync_queue

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (uuid) | NO | Note:
This is a Primary Key.<pk/> |
| user_id | string (uuid) | NO | - |
| user_name | string (text) | YES | - |
| device_id | string (text) | NO | - |
| table_name | string (text) | NO | - |
| record_id | string (uuid) | NO | - |
| operation | string (text) | NO | - |
| payload | unknown (jsonb) | NO | - |
| base_version | integer (integer) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |
| synced_at | string (timestamp with time zone) | YES | - |
| sync_status | string (text) | YES | - |
| conflict_data | unknown (jsonb) | YES | - |
| resolved_at | string (timestamp with time zone) | YES | - |

---

## task_activities

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (uuid) | NO | Note:
This is a Primary Key.<pk/> |
| task_id | string (uuid) | NO | Note:
This is a Foreign Key to `tasks.id`.<fk table='tasks' column='id'/> |
| user_id | string (uuid) | NO | - |
| organization_id | string (text) | YES | - |
| type | string (text) | NO | - |
| data | unknown (jsonb) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |

---

## task_attachments

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (uuid) | NO | Note:
This is a Primary Key.<pk/> |
| task_id | string (uuid) | NO | Note:
This is a Foreign Key to `tasks.id`.<fk table='tasks' column='id'/> |
| file_name | string (text) | NO | - |
| file_url | string (text) | NO | - |
| file_type | string (text) | YES | - |
| file_size | integer (integer) | YES | - |
| uploaded_by | string (uuid) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |

---

## task_comments

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (uuid) | NO | Note:
This is a Primary Key.<pk/> |
| task_id | string (uuid) | NO | Note:
This is a Foreign Key to `tasks.id`.<fk table='tasks' column='id'/> |
| user_id | string (uuid) | NO | - |
| user_name | string (text) | YES | - |
| text | string (text) | NO | - |
| mentions | array (uuid[]) | YES | - |
| attachments | unknown (jsonb) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |

---

## task_dependencies

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (uuid) | NO | Note:
This is a Primary Key.<pk/> |
| task_id | string (uuid) | NO | Note:
This is a Foreign Key to `tasks.id`.<fk table='tasks' column='id'/> |
| depends_on_task_id | string (uuid) | NO | Note:
This is a Foreign Key to `tasks.id`.<fk table='tasks' column='id'/> |
| organization_id | string (text) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |

---

## task_notifications

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (text) | NO | Note:
This is a Primary Key.<pk/> |
| organization_id | string (text) | YES | - |
| user_id | string (text) | YES | - |
| task_id | string (text) | YES | - |
| type | string (text) | YES | - |
| is_read | boolean (boolean) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |
| title | string (text) | YES | - |
| message | string (text) | YES | - |
| data | unknown (jsonb) | YES | - |

---

## task_templates

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (uuid) | NO | Note:
This is a Primary Key.<pk/> |
| organization_id | string (text) | NO | - |
| name | string (text) | NO | - |
| description | string (text) | YES | - |
| type | string (text) | YES | - |
| priority | string (text) | YES | - |
| estimated_hours | number (numeric) | YES | - |
| subtasks | unknown (jsonb) | YES | - |
| is_active | boolean (boolean) | YES | - |
| created_by | string (uuid) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |

---

## tasks

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (uuid) | NO | Note:
This is a Primary Key.<pk/> |
| organization_id | string (text) | NO | - |
| created_by | string (uuid) | NO | - |
| title | string (text) | NO | - |
| description | string (text) | YES | - |
| type | string (text) | YES | - |
| status | string (text) | YES | - |
| priority | string (text) | YES | - |
| assigned_to | array (uuid[]) | YES | - |
| due_date | string (timestamp with time zone) | YES | - |
| estimated_hours | number (numeric) | YES | - |
| session_id | string (uuid) | YES | - |
| workflow_id | string (uuid) | YES | - |
| workflow_step_id | string (text) | YES | - |
| workflow_name | string (text) | YES | - |
| workflow_step_name | string (text) | YES | - |
| subtasks | unknown (jsonb) | YES | - |
| watchers | array (uuid[]) | YES | - |
| comment_count | integer (integer) | YES | - |
| sort_order | integer (integer) | YES | - |
| completed_at | string (timestamp with time zone) | YES | - |
| completed_by | string (uuid) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |
| updated_at | string (timestamp with time zone) | YES | - |

---

## time_entries

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (text) | NO | Note:
This is a Primary Key.<pk/> |
| organization_id | string (text) | YES | Note:
This is a Foreign Key to `organizations.id`.<fk table='organizations' column='id'/> |
| user_id | string (text) | YES | - |
| session_id | string (text) | YES | - |
| start_time | string (timestamp with time zone) | YES | - |
| end_time | string (timestamp with time zone) | YES | - |
| total_hours | number (numeric) | YES | - |
| status | string (text) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |
| updated_at | string (timestamp with time zone) | YES | - |
| date | string (text) | YES | Date in YYYY-MM-DD format for easy querying by day |
| notes | string (text) | YES | Optional user notes about this time entry |
| session_name | string (text) | YES | Denormalized session name for display |
| task_id | string (text) | YES | - |

---

## time_off_requests

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (text) | NO | Note:
This is a Primary Key.<pk/> |
| organization_id | string (text) | YES | Note:
This is a Foreign Key to `organizations.id`.<fk table='organizations' column='id'/> |
| photographer_id | string (text) | YES | - |
| start_date | string (timestamp with time zone) | YES | - |
| end_date | string (timestamp with time zone) | YES | - |
| status | string (text) | YES | - |
| reason | string (text) | YES | - |
| type | string (text) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |
| updated_at | string (timestamp with time zone) | YES | - |
| photographer_name | string (text) | YES | Denormalized user name for display without joins |
| photographer_email | string (text) | YES | Denormalized email for notifications |
| notes | string (text) | YES | - |
| is_partial_day | boolean (boolean) | YES | True if this is a partial day request (hours instead of full day) |
| start_time | string (text) | YES | Start time for partial day requests (HH:mm format) |
| end_time | string (text) | YES | End time for partial day requests (HH:mm format) |
| is_paid_time_off | boolean (boolean) | YES | True if this uses PTO balance |
| pto_hours_requested | number (numeric) | YES | Number of PTO hours to deduct if approved |
| projected_pto_balance | number (numeric) | YES | Expected PTO balance after this request |
| approved_by | string (text) | YES | User ID of manager who approved

Note:
This is a Foreign Key to `users.id`.<fk table='users' column='id'/> |
| approver_name | string (text) | YES | - |
| approved_at | string (timestamp with time zone) | YES | - |
| denied_by | string (text) | YES | User ID of manager who denied

Note:
This is a Foreign Key to `users.id`.<fk table='users' column='id'/> |
| denier_name | string (text) | YES | - |
| denied_at | string (timestamp with time zone) | YES | - |
| denial_reason | string (text) | YES | - |
| reviewed_by | string (text) | YES | User ID of manager who reviewed

Note:
This is a Foreign Key to `users.id`.<fk table='users' column='id'/> |
| reviewer_name | string (text) | YES | - |
| reviewed_at | string (timestamp with time zone) | YES | - |

---

## users

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (text) | NO | Note:
This is a Primary Key.<pk/> |
| email | string (text) | YES | - |
| first_name | string (text) | YES | - |
| last_name | string (text) | YES | - |
| display_name | string (text) | YES | - |
| role | string (text) | YES | - |
| position | string (text) | YES | - |
| organization_id | string (text) | YES | Note:
This is a Foreign Key to `organizations.id`.<fk table='organizations' column='id'/> |
| photo_url | string (text) | YES | - |
| original_photo_url | string (text) | YES | - |
| photo_crop_settings | unknown (jsonb) | YES | - |
| is_active | boolean (boolean) | YES | - |
| is_accountant | boolean (boolean) | YES | - |
| amount_per_mile | number (double precision) | YES | - |
| is_temporary_invite | boolean (boolean) | YES | - |
| invited_at | string (timestamp with time zone) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |
| updated_at | string (timestamp with time zone) | YES | - |
| is_photographer | boolean (boolean) | YES | - |
| address | string (text) | YES | - |
| bio | string (text) | YES | - |
| city | string (text) | YES | - |
| compensation_type | string (text) | YES | - |
| country | string (text) | YES | - |
| ~~fcm_token~~ | **DOES NOT EXIST** — see note below | - | - |
| fcm_token_updated_at | string (timestamp with time zone) | YES | - |
| apns_token | string (text) | YES | - |
| apns_environment | string (text) | YES | - |
| home_address | string (text) | YES | - |
| hourly_rate | number (double precision) | YES | - |
| is_flagged | boolean (boolean) | YES | - |
| flag_note | string (text) | YES | - |
| flagged_by | string (text) | YES | - |
| notify_on_proofing_approval | boolean (boolean) | YES | - |
| overtime_threshold | integer (integer) | YES | - |
| phone | string (text) | YES | - |
| salary_amount | number (double precision) | YES | - |
| state | string (text) | YES | - |
| zip_code | string (text) | YES | - |

> **USERS TABLE CORRECTIONS — verified against the LIVE database 2026-07-27/28 (PSH.1, FLG.1).**
> This file has been wrong about this table, and it was expensive. `fcm_token` was listed here
> and **does not exist**, so code written against this document failed silently for months —
> PSH.1 found four separate mechanisms in that state, every one invisible from the repo because
> the code looked correct while targeting a column that is not there. Only the orphaned
> `fcm_token_updated_at` survives; dropping it is still open.
> `apns_token` / `apns_environment` were added by PSH.1 and were missing here.
> `flag_note` / `flagged_by` were added by FLG.1 — before that, flagging a user could never
> work, because `TeamService` wrote all three flag columns and only `is_flagged` existed.
> **The live database is the authority, not this file.** Query it before trusting a row above;
> the recipe is in the `psh-push-notifications` memory (`psql` does NOT work on this project).
| preferences | unknown (jsonb) | YES | - |
| email_notifications | unknown (jsonb) | YES | - |
| notification_preferences | unknown (jsonb) | YES | - |

---

## workflow_templates

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (text) | NO | Note:
This is a Primary Key.<pk/> |
| organization_id | string (text) | YES | Note:
This is a Foreign Key to `organizations.id`.<fk table='organizations' column='id'/> |
| name | string (text) | YES | - |
| description | string (text) | YES | - |
| session_types | unknown (jsonb) | YES | - |
| is_active | boolean (boolean) | YES | - |
| version | integer (integer) | YES | - |
| fields | unknown (jsonb) | YES | - |
| steps | unknown (jsonb) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |
| updated_at | string (timestamp with time zone) | YES | - |
| is_default | boolean (boolean) | YES | - |
| custom_form_fields | unknown (jsonb) | YES | - |
| is_tracking_template | boolean (boolean) | YES | - |
| estimated_days | integer (integer) | YES | - |
| groups | unknown (jsonb) | YES | - |
| proofing_gallery_mode | string (text) | YES | - |

---

## workflows

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (text) | NO | Note:
This is a Primary Key.<pk/> |
| organization_id | string (text) | YES | Note:
This is a Foreign Key to `organizations.id`.<fk table='organizations' column='id'/> |
| template_id | string (text) | YES | Reference to the workflow template used |
| session_id | string (text) | YES | - |
| status | string (text) | YES | Workflow status: active, completed, archived, etc. |
| assignees | unknown (jsonb) | YES | - |
| current_step | string (text) | YES | - |
| completed_steps | unknown (jsonb) | YES | - |
| data | unknown (jsonb) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |
| updated_at | string (timestamp with time zone) | YES | - |
| hidden | boolean (boolean) | YES | - |
| school_id | string (text) | YES | - |
| school_name | string (text) | YES | - |
| workflow_type | string (text) | YES | - |
| tracking_start_date | string (timestamp with time zone) | YES | - |
| created_by | string (text) | YES | - |
| custom_form_data | unknown (jsonb) | YES | User-entered data for custom form fields (JSONB object) |
| custom_form_fields | unknown (jsonb) | YES | Field definitions copied from template (JSONB array) |
| step_overrides | unknown (jsonb) | YES | Step-specific configuration overrides (JSONB object) |
| notes | string (text) | YES | Additional notes for the workflow |
| auto_create_tasks | boolean (boolean) | YES | Whether to automatically create tasks from workflow steps |
| academic_year | string (text) | YES | Academic year for tracking workflows (e.g., 2024-2025) |
| tracking_end_date | string (timestamp with time zone) | YES | End date for tracking workflows |
| linked_gallery_id | string (text) | YES | - |

---

## yearbook_page_assignments

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (uuid) | NO | Note:
This is a Primary Key.<pk/> |
| proof_id | string (uuid) | NO | Note:
This is a Foreign Key to `yearbook_proofs.id`.<fk table='yearbook_proofs' column='id'/> |
| advisor_email | string (text) | NO | - |
| advisor_name | string (text) | YES | - |
| start_page | integer (integer) | NO | - |
| end_page | integer (integer) | NO | - |
| approved_at | string (timestamp with time zone) | YES | - |
| approved_by | string (text) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |
| updated_at | string (timestamp with time zone) | YES | - |

---

## yearbook_proof_activity

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (uuid) | NO | Note:
This is a Primary Key.<pk/> |
| proof_id | string (uuid) | NO | Note:
This is a Foreign Key to `yearbook_proofs.id`.<fk table='yearbook_proofs' column='id'/> |
| event_type | string (text) | NO | - |
| event_data | unknown (jsonb) | YES | - |
| actor_email | string (text) | YES | - |
| actor_name | string (text) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |

---

## yearbook_proof_comments

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (uuid) | NO | Note:
This is a Primary Key.<pk/> |
| proof_id | string (uuid) | NO | Note:
This is a Foreign Key to `yearbook_proofs.id`.<fk table='yearbook_proofs' column='id'/> |
| page_number | integer (integer) | NO | - |
| x_position | number (numeric) | NO | - |
| y_position | number (numeric) | NO | - |
| text | string (text) | NO | - |
| author | string (text) | YES | - |
| author_email | string (text) | YES | - |
| resolved | boolean (boolean) | YES | - |
| resolved_at | string (timestamp with time zone) | YES | - |
| resolved_by | string (text) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |
| updated_at | string (timestamp with time zone) | YES | - |

---

## yearbook_proof_signoffs

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (uuid) | NO | Note:
This is a Primary Key.<pk/> |
| proof_id | string (uuid) | NO | Note:
This is a Foreign Key to `yearbook_proofs.id`.<fk table='yearbook_proofs' column='id'/> |
| advisor_email | string (text) | NO | - |
| advisor_name | string (text) | YES | - |
| signed_off_at | string (timestamp with time zone) | YES | - |
| signed_off_by | string (text) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |

---

## yearbook_proofs

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (uuid) | NO | Note:
This is a Primary Key.<pk/> |
| organization_id | string (text) | NO | - |
| school_id | string (text) | YES | - |
| school_name | string (text) | YES | - |
| name | string (text) | NO | - |
| file_url | string (text) | NO | - |
| file_name | string (text) | NO | - |
| file_size | integer (integer) | YES | - |
| page_count | integer (integer) | YES | - |
| version | integer (integer) | YES | - |
| parent_id | string (uuid) | YES | Note:
This is a Foreign Key to `yearbook_proofs.id`.<fk table='yearbook_proofs' column='id'/> |
| status | string (text) | YES | - |
| password | string (text) | YES | - |
| client_email | string (text) | YES | - |
| created_by | string (text) | YES | - |
| created_by_name | string (text) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |
| updated_at | string (timestamp with time zone) | YES | - |
| academic_year | string (text) | YES | - |
| district_id | string (text) | YES | - |
| district_name | string (text) | YES | - |
| current_version_id | string (uuid) | YES | Note:
This is a Foreign Key to `yearbook_proofs.id`.<fk table='yearbook_proofs' column='id'/> |
| latest_version | integer (integer) | YES | - |

---

## yearbook_shoot_lists

| Column | Type | Nullable | Description |
|--------|------|----------|-------------|
| id | string (text) | NO | Note:
This is a Primary Key.<pk/> |
| organization_id | string (text) | NO | - |
| school_id | string (text) | YES | - |
| school_name | string (text) | YES | - |
| school_year | string (text) | YES | - |
| start_date | string (timestamp with time zone) | YES | - |
| end_date | string (timestamp with time zone) | YES | - |
| is_active | boolean (boolean) | YES | - |
| copied_from_id | string (text) | YES | - |
| completed_count | integer (integer) | YES | - |
| total_count | integer (integer) | YES | - |
| items | unknown (jsonb) | YES | - |
| created_at | string (timestamp with time zone) | YES | - |
| updated_at | string (timestamp with time zone) | YES | - |

---

