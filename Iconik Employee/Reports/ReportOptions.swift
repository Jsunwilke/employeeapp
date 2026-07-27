//  ReportOptions.swift
//  Iconik Employee — the daily job report's two fixed option lists
//
//  PRODUCTION CODE, and the lab imports it. Same direction as ReportFormKit and
//  ReportRules: the design lives here, so the converted screen cannot drift from
//  the mockup the operator approved because both draw from this one list.
//
//  WHAT THE OPTIONS ARE
//      Twenty-two job descriptions and twelve extra items, VERBATIM and in the
//      order the app has always shipped them. Not one word is edited here — a
//      redesign does not get to rename what a photographer is reporting.
//
//  WHAT THE GROUPING IS
//      A presentation layer over those same lists, approved with the v3 design.
//      One option per row on a shared left edge, under a real bold subheading,
//      two columns. The operator's verdict on the ungrouped version was that it
//      was "still just very confusing looking and not grouped and separated
//      well".
//
//      THE ORDER NEVER CHANGES — not by recency, not by frequency. A controlled
//      study (Findlater & McGrenere, CHI 2004) measured adaptive menus as SLOWER
//      than static ones because frequent users learn where things are, and a
//      photographer files this report roughly 200 times a year.
//
//  GROUPING MUST LOSE NOTHING, AND THAT IS CHECKED RATHER THAN PROMISED
//      Every option in the flat list appears exactly once across the groups, and
//      nothing appears in a group that is not in the flat list.
//      scripts/test_report_rules.sh compiles THIS file and asserts both
//      directions — so a typo in a group cannot silently drop an option a
//      photographer needs, which is the entire failure mode this arc keeps
//      finding.

import Foundation

enum ReportOptions {

    // MARK: - Job descriptions

    /// The 22 job descriptions, verbatim and in shipped order. This is the list
    /// that is stored in `daily_job_reports.job_descriptions`.
    static let jobDescriptions: [String] = [
        "Fall Original Day",
        "Fall Makeup Day",
        "Classroom Groups",
        "Fall Sports",
        "Winter Sports",
        "Spring Sports",
        "Spring Photos",
        "Homecoming",
        "Prom",
        "Graduation",
        "Yearbook Candid's",
        "Yearbook Groups and Clubs",
        "Sports League",
        "District Office Photos",
        "Banner Photos",
        "In Studio Photos",
        "School Board Photos",
        "Dr. Office Head Shots",
        "Dr. Office Cards",
        "Dr. Office Candid's",
        "Deliveries",
        "NONE"
    ]

    /// The same 22, grouped for reading. Approved with the v3 design.
    static let jobDescriptionGroups: [(String, [String])] = [
        ("Portraits", ["Fall Original Day", "Fall Makeup Day", "Spring Photos", "In Studio Photos"]),
        ("Sports", ["Fall Sports", "Winter Sports", "Spring Sports", "Sports League"]),
        ("Groups and yearbook", ["Classroom Groups", "Yearbook Candid's", "Yearbook Groups and Clubs"]),
        ("Events", ["Homecoming", "Prom", "Graduation"]),
        ("Commercial", ["District Office Photos", "Banner Photos", "School Board Photos",
                        "Dr. Office Head Shots", "Dr. Office Cards", "Dr. Office Candid's"]),
        ("Other", ["Deliveries", "NONE"]),
    ]

    // MARK: - Extra items

    /// The 12 extra items, verbatim and in shipped order. Stored in
    /// `daily_job_reports.extra_items`.
    static let extraItems: [String] = [
        "Underclass Makeup",
        "Staff Makeup",
        "ID card Images",
        "Sports Makeup",
        "Class Groups",
        "Yearbook Groups and Clubs",
        "Class Candids",
        "Students from other schools",
        "Siblings",
        "Office Staff Photos",
        "Deliveries",
        "NONE"
    ]

    /// The same 12, grouped on the same terms.
    static let extraItemGroups: [(String, [String])] = [
        ("Makeup", ["Underclass Makeup", "Staff Makeup", "Sports Makeup"]),
        ("Additional shoots", ["ID card Images", "Class Groups", "Yearbook Groups and Clubs", "Class Candids"]),
        ("People", ["Students from other schools", "Siblings", "Office Staff Photos"]),
        ("Other", ["Deliveries", "NONE"]),
    ]

    // MARK: - Scan status

    /// The three scan questions, with their real options in shipped order.
    /// Cards Scanned has no NA; the other two do. None can be cleared once set,
    /// which is `ReportChoiceRow`'s behaviour and the live form's.
    static let yesNo = ["Yes", "No"]
    static let yesNoNA = ["Yes", "No", "NA"]

    // MARK: - The grouping check, runnable

    /// Flattened groups, in group order. Used by the test suite and by nothing
    /// in the UI — the UI walks the groups directly.
    static func flattened(_ groups: [(String, [String])]) -> [String] {
        groups.flatMap { $0.1 }
    }

    /// Does a grouping cover its flat list exactly once, with nothing extra?
    ///
    /// This is a function rather than a comment so the test can RUN it against
    /// the same values the app draws. See scripts/test_report_rules.swift.
    static func groupingIsFaithful(flat: [String], groups: [(String, [String])]) -> Bool {
        let grouped = flattened(groups)
        return grouped.count == flat.count && Set(grouped) == Set(flat)
    }
}
