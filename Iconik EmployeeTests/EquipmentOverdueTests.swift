//
//  EquipmentOverdueTests.swift
//  Iconik EmployeeTests
//
//  Pins when a piece of equipment counts as LATE.
//
//  /code-review found during AMB.3 that `EquipmentAssignment.isOverdue` compared
//  `Date() > startOfDay(expected_return_date)`, so an item due today was overdue
//  from midnight of the day it was due — and, because "due back" excluded anything
//  overdue, the one day it was actually due was the one day it never showed as due.
//  The rule was corrected after the operator asked for it as its own change, since
//  what counts as "late" is a business rule rather than a restyle's decision.
//
//  These are here because date-boundary logic is exactly where reasoning is least
//  trustworthy: every case below is one that reads as obviously correct in prose and
//  is easy to get wrong in code. They construct assignments by DECODING, because
//  EquipmentAssignment has no memberwise init — which also exercises the real date
//  parsing rather than sidestepping it.
//

import Testing
import Foundation
@testable import Iconik_Employee

struct EquipmentOverdueTests {

    // MARK: - Fixtures

    /// Build a real `EquipmentAssignment` through its decoder.
    ///
    /// `dueOffsetDays` is relative to today; nil means a permanent assignment.
    private static func assignment(dueOffsetDays: Int?,
                                   status: String? = "active",
                                   checkedIn: Bool = false) throws -> EquipmentAssignment {
        var json: [String: Any] = [
            "id": UUID().uuidString.lowercased(),
            "organization_id": "test-org",
            "equipment_id": UUID().uuidString.lowercased(),
            "assigned_to": UUID().uuidString.lowercased(),
            "checked_out_at": "2026-01-01T00:00:00Z",
        ]
        if let status { json["status"] = status }
        if let dueOffsetDays {
            let due = Calendar.current.date(byAdding: .day, value: dueOffsetDays, to: Date())!
            // Date-only, which is how a return date is realistically stored.
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            json["expected_return_date"] = formatter.string(from: due)
        }
        if checkedIn { json["checked_in_at"] = "2026-06-01T00:00:00Z" }

        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(EquipmentAssignment.self, from: data)
    }

    // MARK: - The boundary

    @Test func dueToday_isNotOverdue() throws {
        let today = try Self.assignment(dueOffsetDays: 0)
        // The whole point of the fix: you have until the end of the day it is due.
        #expect(today.isOverdue == false)
        #expect(today.daysOverdue == nil)
    }

    @Test func dueToday_countsAsDueBackRatherThanVanishing() throws {
        let today = try Self.assignment(dueOffsetDays: 0)
        // The old rule made this simultaneously "overdue" AND excluded from "due
        // back", so an item due today appeared in neither column honestly.
        #expect(today.isOverdue == false)
        #expect(today.daysUntilDue == 0)
    }

    @Test func dueYesterday_isOneDayOverdue() throws {
        let yesterday = try Self.assignment(dueOffsetDays: -1)
        #expect(yesterday.isOverdue == true)
        #expect(yesterday.daysOverdue == 1)
    }

    @Test func dueTomorrow_isNotOverdueAndCountsOneDayOut() throws {
        let tomorrow = try Self.assignment(dueOffsetDays: 1)
        #expect(tomorrow.isOverdue == false)
        #expect(tomorrow.daysUntilDue == 1)
    }

    @Test func longOverdue_countsWholeDays() throws {
        let old = try Self.assignment(dueOffsetDays: -9)
        #expect(old.isOverdue == true)
        #expect(old.daysOverdue == 9)
    }

    // MARK: - The other branches

    @Test func permanentAssignment_isNeverOverdue() throws {
        let permanent = try Self.assignment(dueOffsetDays: nil)
        #expect(permanent.isPermanent == true)
        #expect(permanent.isOverdue == false)
        #expect(permanent.daysOverdue == nil)
    }

    @Test func serverFlaggedOverdue_winsRegardlessOfDate() throws {
        // The web app and Captura share this table. A status they wrote is not this
        // client's to overrule, even for an item due next week.
        let flagged = try Self.assignment(dueOffsetDays: 7, status: "overdue")
        #expect(flagged.isOverdue == true)
    }

    @Test func serverFlaggedOverdue_withNoDueDate_hasNoDayCount() throws {
        // This is the case `KitDueBadge` renders as a bare "OVERDUE": flagged late,
        // with nothing to measure the lateness against. A `?? 0` here is what
        // produced "0D OVERDUE" on screen.
        let flagged = try Self.assignment(dueOffsetDays: nil, status: "overdue")
        #expect(flagged.isOverdue == true)
        #expect(flagged.daysOverdue == nil)
    }

    @Test func returnedAssignment_isNotOverdueEvenIfLongPastDue() throws {
        let returned = try Self.assignment(dueOffsetDays: -30, status: "returned", checkedIn: true)
        #expect(returned.isActive == false)
        #expect(returned.isOverdue == false)
    }
}
