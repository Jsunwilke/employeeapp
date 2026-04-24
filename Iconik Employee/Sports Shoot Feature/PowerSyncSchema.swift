//
//  PowerSyncSchema.swift
//  Iconik Employee
//
//  PowerSync schema definition for offline-first sync
//

import PowerSync

let powerSyncSchema = Schema(
    Table(
        name: "sports_jobs",
        columns: [
            .text("organization_id"),
            .text("school_name"),
            .text("school_id"),
            .text("sport_name"),
            .text("season_type"),
            .text("shoot_date"),
            .text("location"),
            .text("photographer"),
            .text("additional_notes"),
            .text("session_id"),
            .integer("is_archived"),
            .text("created_at"),
            .text("updated_at"),
            .text("captura_gallery_id"),
            .text("captura_coach_gallery_id"),
            .text("gallery_id")             // FK to Production galleries (iPad sync)
        ]
    ),
    Table(
        name: "roster_entries",
        columns: [
            .text("sports_job_id"),
            .text("organization_id"),
            .text("last_name"),
            .text("first_name"),
            .text("teacher"),
            .text("group_name"),
            .text("email"),
            .text("phone"),
            .text("image_numbers"),
            .text("notes"),
            .integer("sort_order"),
            .integer("version"),
            .text("updated_at"),
            .text("updated_by"),
            .text("locked_by"),
            .text("locked_by_name"),
            .text("locked_at"),
            .text("created_at"),
            .integer("is_filled_blank"),
            .text("subject_id"),            // FK to Production subjects (iPad sync)
            .text("roster_id")              // Dedicated roster/jersey ID (replaces firstName hack)
        ]
    ),
    Table(
        name: "group_images",
        columns: [
            // Renamed from sports_job_id to gallery_id in the 20260423
            // Supabase migration. The Swift property on GroupImage stays
            // sportsJobId for backward compatibility with Captura (which
            // we don't touch); CodingKeys maps the property to this
            // column name.
            .text("gallery_id"),
            .text("organization_id"),
            .text("description"),
            .text("image_numbers"),
            .text("notes"),
            .text("sport"),
            .text("gender"),
            .text("team_level"),
            .integer("sort_order"),
            .integer("version"),
            .text("updated_at"),
            .text("updated_by"),
            .text("locked_by"),
            .text("locked_by_name"),
            .text("locked_at"),
            .text("created_at"),
            .text("photographer_id")
        ]
    ),

    // MARK: - FP Sports tables (Production subjects accessed directly via PowerSync)

    Table(
        name: "subjects",
        columns: [
            .text("gallery_id"),
            .text("organization_id"),
            .text("school_id"),
            .text("first_name"),
            .text("last_name"),
            .text("grade"),
            .text("teacher"),
            .text("homeroom"),
            .text("student_id"),
            .text("roster_id"),
            .text("jersey_number"),
            .text("sport"),
            .text("position"),
            .text("email"),
            .text("phone"),
            .text("qr_code"),
            .integer("image_count"),
            .integer("has_order"),
            .text("notes"),
            .text("extra_data"),
            .text("created_at"),
            .text("updated_at"),
            .text("online_code"),
            .text("reference_number"),
            .text("year"),
            .text("organization_name"),
            .text("subject_type"),
            .text("title"),
            .text("address1"),
            .text("address2"),
            .text("city"),
            .text("state"),
            .text("zip"),
            .text("country"),
            .text("phone2"),
            .text("mother"),
            .text("father"),
            .text("personalization"),
            .text("photographer"),
            .text("photo_session_date"),
            .text("expiration_date"),
            .integer("is_absent"),
            .integer("needs_retake"),
            .text("checked_in_at"),
            .integer("is_photographed"),
            .integer("pose_pick"),
            .text("image_numbers"),
            .text("primary_image_url"),
            .text("thumbnail_url"),
            .text("discount_code"),
            .real("order_total"),
            .text("custom1"),
            .text("custom2"),
            .text("custom3"),
            .text("custom4"),
            .text("custom5"),
            .text("custom6"),
            .text("custom7"),
            .text("custom8"),
            .text("custom9"),
            .text("custom10"),
            .text("custom11"),
            .text("custom12"),
            .text("custom13"),
            .text("custom14"),
            .text("custom15"),
            .text("custom16"),
            .text("custom17"),
            .text("custom18"),
            .text("custom19"),
            .text("custom20"),
            .text("roster_entry_id"),
            .text("locked_by"),
            .text("locked_by_name"),
            .text("locked_at"),
            .text("is_deleted"),
            .text("deleted_at")
        ]
    ),

    Table(
        name: "synced_galleries",
        columns: [
            .text("gallery_id"),
            .text("user_id"),
            .text("organization_id"),
            .text("synced_at")
        ]
    ),

    // MARK: - Gallery metadata (synced org-wide via by_org bucket — offline-first for FP Sports)

    Table(
        name: "galleries",
        columns: [
            .text("organization_id"),
            .text("name"),
            .text("school_year"),
            .text("status"),
            .text("notes"),
            .text("school_id"),
            .text("shoot_type"),
            .text("photo_day"),
            .text("display_config"),
            .text("is_deleted"),
            .text("created_at"),
            .text("updated_at")
        ]
    )
)
