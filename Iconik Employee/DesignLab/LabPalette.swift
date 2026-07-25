//  LabPalette.swift
//  Iconik Employee — the D11 palette proposal
//
//  ARC SCAFFOLDING. Deleted with the rest of the lab at AMB.12.
//
//  D11 (operator, 2026-07-25): the ambient wash takes each screen's FEATURE
//  colour, and the schedule keeps its data-driven tint as the exception. That
//  only works if the feature colours are actually distinct, and today they are
//  not — 27 features share 11 colours, with five of them blue.
//
//  THIS LIVES IN THE LAB, NOT IN FeatureTheme, ON PURPOSE.
//  FeatureTheme has three LIVE consumers — the home tiles, the All Features
//  grid and the bottom bar — so re-cutting it changes screens that have not
//  been converted yet, the moment it lands. D10 says nothing real is touched
//  before the operator has approved the mockup. So the proposal is drawn here
//  first, judged on a device beside the batch-1 mockups, and only then moved
//  into FeatureTheme as its own visible change with its own line in a closeout.

import SwiftUI

enum LabPalette {

    /// A family of features that belong together, drawn from adjacent hues so
    /// the group reads as a group while staying far from every other family.
    struct Family {
        let name: String
        let rationale: String
        let features: [Feature]
    }

    struct Feature: Identifiable {
        let id: String
        let title: String
        let proposed: String

        var proposedColor: Color { Color(hex: proposed) }
        /// What the app ships today, straight from the real source of truth.
        var currentColor: Color { FeatureTheme.color(for: id) }
    }

    static let families: [Family] = [
        Family(name: "Planning",
               rationale: "What is coming, and what needs attention.",
               features: [
                .init(id: "schedule", title: "Schedule", proposed: "#E5484D"),
                .init(id: "flagUser", title: "Flag User", proposed: "#C62A2F"),
               ]),
        Family(name: "On the road",
               rationale: "Getting there and being paid for it.",
               features: [
                .init(id: "routePlanner", title: "Route Planner", proposed: "#F76B15"),
                .init(id: "mileageReports", title: "Mileage Reports", proposed: "#E8830C"),
               ]),
        Family(name: "Shoot day",
               rationale: "The camera work itself.",
               features: [
                .init(id: "capture", title: "Capture", proposed: "#F5B70A"),
                .init(id: "sportsShoot", title: "Sports Shoots", proposed: "#C9A227"),
                .init(id: "focalPointSports", title: "FP Sports", proposed: "#A3B818"),
               ]),
        Family(name: "Groups & delivery",
               rationale: "Work organised around a list of people or images.",
               features: [
                .init(id: "classGroups", title: "Groups", proposed: "#46A758"),
                .init(id: "yearbookChecklists", title: "Yearbook Checklists", proposed: "#2E9B4F"),
                .init(id: "galleryCreator", title: "Gallery Creator", proposed: "#3DB88B"),
               ]),
        Family(name: "Time & pay",
               rationale: "Hours, and time away from them.",
               features: [
                .init(id: "timeTracking", title: "Time Tracking", proposed: "#12A594"),
                .init(id: "timeOffRequests", title: "Time Off Requests", proposed: "#0D9B8A"),
                .init(id: "timeOffApprovals", title: "Time Off Approvals", proposed: "#0C8577"),
               ]),
        Family(name: "Gear",
               rationale: "Physical things that get signed in and out.",
               features: [
                .init(id: "equipment", title: "Equipment", proposed: "#00A2C7"),
                .init(id: "jobBoxTracker", title: "Job Box Tracker", proposed: "#0B8BA8"),
                .init(id: "scan", title: "Scan", proposed: "#2AA7D8"),
               ]),
        Family(name: "Paperwork",
               rationale: "Forms filled in after the job.",
               features: [
                .init(id: "dailyJobReport", title: "Daily Job Report", proposed: "#3E63DD"),
                .init(id: "customDailyReports", title: "Custom Daily Reports", proposed: "#5471E0"),
                .init(id: "myDailyJobReports", title: "My Daily Job Reports", proposed: "#7189E8"),
               ]),
        Family(name: "Notes & photos",
               rationale: "What you wrote down and what you photographed for reference.",
               features: [
                .init(id: "photoshootNotes", title: "Photoshoot Notes", proposed: "#6E56CF"),
                .init(id: "locationPhotos", title: "Location Photos", proposed: "#8E4EC6"),
               ]),
        Family(name: "People",
               rationale: "Talking to each other and to the work.",
               features: [
                .init(id: "chat", title: "Chat", proposed: "#D6409F"),
                .init(id: "tasks", title: "Tasks", proposed: "#E93D82"),
                .init(id: "training", title: "Training", proposed: "#C43B6D"),
               ]),
        Family(name: "Manager tools",
               rationale: "Deliberately desaturated — these are not daily photographer work, and the palette can say so without a label.",
               features: [
                .init(id: "stats", title: "Stats", proposed: "#7A7FA6"),
                .init(id: "unflagUser", title: "Unflag User", proposed: "#5F8A6E"),
                .init(id: "managerMileage", title: "Manager Mileage", proposed: "#8A7A5F"),
               ]),
    ]

    static var allFeatures: [Feature] { families.flatMap(\.features) }

    static func proposedColor(for id: String) -> Color? {
        allFeatures.first { $0.id == id }?.proposedColor
    }

    /// Feature ids that currently share a colour with at least one other, which
    /// is the whole reason D11 needs a re-cut. Computed from the LIVE
    /// FeatureTheme rather than typed out, so it cannot go stale.
    static var currentCollisions: [(color: String, titles: [String])] {
        var buckets: [String: [String]] = [:]
        for feature in allFeatures {
            buckets[feature.currentColor.description, default: []].append(feature.title)
        }
        return buckets
            .filter { $0.value.count > 1 }
            .map { (color: $0.key, titles: $0.value.sorted()) }
            .sorted { $0.titles.count > $1.titles.count }
    }
}
