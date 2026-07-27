//  ReportSchoolItem.swift
//  Iconik Employee — one way to turn a School into a SchoolItem
//
//  It lives in its own file because five screens and a sheet depend on it. AMB.6
//  deleted a mockup and broke the build because a shared helper was hidden
//  inside it; a type this many callers need is not a detail of whichever file
//  happened to declare it first.

import Foundation

/// ONE way to turn a `School` into the `SchoolItem` the report screens hold.
///
/// This exists because there were two, and they disagreed. The screens compose
/// the address from `street, city, state, zip`; a refresh inside the picker
/// took the nullable `address` COLUMN instead — a different column, often
/// empty — and wrote it into the same array. A school with no coordinates and
/// an empty address is then dropped from the mileage route entirely, so a
/// refresh could quietly shorten a reimbursement.
enum ReportSchoolItem {
    static func make(from school: School) -> SchoolItem {
        let parts = [school.street, school.city, school.state, school.zip]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        let composed = parts.joined(separator: ", ")
        // NO FALLBACK TO THE NAME. An address is used for two things — showing
        // it under the school, and GEOCODING — and a bare name geocodes to
        // whatever the world has most of. Location Photos then announces "You
        // are at X" about a school it matched by name alone, and the daily
        // report would measure a leg to it. An empty address is honest: both
        // callers already skip one.
        let composedOrStored = composed.isEmpty ? (school.address ?? "") : composed
        let address = composedOrStored
        return SchoolItem(id: school.id, name: school.name,
                          address: address, coordinates: school.coordinates)
    }

    static func make(from schools: [School]) -> [SchoolItem] {
        schools.map(make(from:)).sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
}
