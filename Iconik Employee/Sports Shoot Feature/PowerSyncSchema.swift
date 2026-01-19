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
            .text("captura_coach_gallery_id")
        ]
    ),
    Table(
        name: "roster_entries",
        columns: [
            .text("sports_job_id"),
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
            .integer("is_filled_blank")
        ]
    ),
    Table(
        name: "group_images",
        columns: [
            .text("sports_job_id"),
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
            .text("created_at")
        ]
    )
)
