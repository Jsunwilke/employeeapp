//  DesignLabSampleData.swift
//  Iconik Employee — the design lab's sample data
//
//  ARC SCAFFOLDING. Built in AMB.2, extended by each phase as new surfaces need
//  shapes, and DELETED WHOLE AT AMB.12 along with the rest of the lab.
//
//  Why sample data rather than the live org: a mockup is judged on the shapes
//  that BREAK layouts, and the live org will not reliably contain them on the
//  day the operator looks. The schedule's lab learned this — its set was built
//  around three overlapping jobs, a three-day job, a draft, all-day and partial
//  time off, a six-person crew and an empty day, because those are the cases
//  that decide a design. Sample data also means the lab touches no service and
//  cannot interfere with anything running in production.
//
//  Each phase adds its surface's shapes here. Keep the hard cases: the longest
//  name that must truncate, the empty list, the item with every optional field
//  missing, and enough rows to judge scrolling for real.

import SwiftUI

// MARK: - Equipment (AMB.2 specimen sheet, AMB.3 Equipment)

/// A stand-in for `EquipmentItem`, carrying exactly the fields Equipment's real
/// row renders: name, category, condition, serial, status, and the kit colour
/// stripe. Deliberately NOT the production model — the lab stays free of the
/// service layer, and a mockup does not need a Codable.
struct LabEquipmentItem: Identifiable {
    let id: String
    let name: String
    /// Optional on purpose: Equipment's real row wraps this in `if let`, so the
    /// mockup has to show what a row with no category looks like.
    let category: String?
    let serial: String?
    let status: LabEquipmentStatus
    let condition: LabEquipmentCondition
    /// Hex of the kit this belongs to, if any — Equipment draws it as a 4pt
    /// stripe down the leading edge.
    let kitColor: String?
    let assignee: String?

    var hasPhoto: Bool { !name.contains("Reflector") }
}

/// Mirrors the four real cases and their exact hex values from
/// `EquipmentModels.swift`, so the specimen sheet is judged in the app's real
/// status colours rather than approximations.
enum LabEquipmentStatus: String, CaseIterable {
    case available = "Available"
    case checkedOut = "Checked Out"
    case needsRepair = "Needs Repair"
    case retired = "Retired"

    var color: Color {
        switch self {
        case .available: return Color(hex: "#22c55e")
        case .checkedOut: return Color(hex: "#3b82f6")
        case .needsRepair: return Color(hex: "#f97316")
        case .retired: return Color(hex: "#6b7280")
        }
    }

    var symbol: String {
        switch self {
        case .available: return "checkmark.circle.fill"
        case .checkedOut: return "person.fill"
        case .needsRepair: return "wrench.fill"
        case .retired: return "xmark.circle.fill"
        }
    }
}

enum LabEquipmentCondition: String, CaseIterable {
    case excellent = "Excellent"
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"

    var color: Color {
        switch self {
        case .excellent: return Color(hex: "#22c55e")
        case .good: return Color(hex: "#3b82f6")
        case .fair: return Color(hex: "#eab308")
        case .poor: return Color(hex: "#ef4444")
        }
    }
}

enum DesignLabSampleData {

    /// Kit tape colours, so the stripe is exercised on some rows and absent on
    /// others — the row has to read both ways.
    private static let kitBlue = "#3b82f6"
    private static let kitAmber = "#f59e0b"

    /// A realistic equipment list. Long enough to judge scrolling density for
    /// real (D5 is decided on this), and seeded with the cases that break a row:
    /// a name far too long for one line, an item with no serial and no
    /// category, every status, every condition, and both kit and non-kit rows.
    static let equipment: [LabEquipmentItem] = [
        .init(id: "e1", name: "Canon EOS R5", category: "Camera Body", serial: "3421887065",
              status: .checkedOut, condition: .excellent, kitColor: kitBlue, assignee: "Maria Alvarez"),
        .init(id: "e2", name: "Canon RF 24-70mm f/2.8L IS USM", category: "Lens", serial: "9920114774",
              status: .checkedOut, condition: .good, kitColor: kitBlue, assignee: "Maria Alvarez"),
        .init(id: "e3", name: "Profoto B10X Plus Off-Camera Flash Head with Extended Battery Pack",
              category: "Lighting", serial: "PB10X-0042",
              status: .available, condition: .good, kitColor: nil, assignee: nil),
        .init(id: "e4", name: "Westcott 43\" Deep Umbrella", category: "Modifier", serial: nil,
              status: .available, condition: .fair, kitColor: nil, assignee: nil),
        .init(id: "e5", name: "Manfrotto 055 Tripod", category: "Support", serial: "MT055XPRO3",
              status: .needsRepair, condition: .poor, kitColor: kitAmber, assignee: nil),
        // No category and no serial — the sparsest row the list can produce.
        .init(id: "e6", name: "5-in-1 Reflector", category: nil, serial: nil,
              status: .available, condition: .good, kitColor: nil, assignee: nil),
        .init(id: "e7", name: "Canon EOS R6 Mark II", category: "Camera Body", serial: "4410229381",
              status: .available, condition: .excellent, kitColor: kitAmber, assignee: nil),
        .init(id: "e8", name: "Godox AD200 Pro", category: "Lighting", serial: "AD200-77120",
              status: .checkedOut, condition: .good, kitColor: kitAmber, assignee: "Devon Wright"),
        .init(id: "e9", name: "SanDisk Extreme Pro 128GB CFexpress", category: "Media", serial: "SD-CF-0091",
              status: .available, condition: .excellent, kitColor: kitBlue, assignee: nil),
        .init(id: "e10", name: "Backdrop Stand — 10ft", category: "Support", serial: nil,
              status: .retired, condition: .poor, kitColor: nil, assignee: nil),
        .init(id: "e11", name: "Canon RF 70-200mm f/2.8L", category: "Lens", serial: "7712009845",
              status: .checkedOut, condition: .good, kitColor: kitBlue, assignee: "Priya Nair"),
        .init(id: "e12", name: "Impact Light Stand 8ft", category: "Support", serial: "LS8-3312",
              status: .available, condition: .fair, kitColor: nil, assignee: nil),
        .init(id: "e13", name: "Canon Speedlite 600EX II-RT", category: "Lighting", serial: "SP600-4471",
              status: .available, condition: .good, kitColor: kitAmber, assignee: nil),
        .init(id: "e14", name: "Tether Tools USB-C Cable 15ft", category: "Tethering", serial: nil,
              status: .checkedOut, condition: .fair, kitColor: nil, assignee: "Sam Okafor"),
        .init(id: "e15", name: "MacBook Pro 16\" M3", category: "Computer", serial: "C02XW1YZ",
              status: .checkedOut, condition: .excellent, kitColor: nil, assignee: "June Castillo"),
        .init(id: "e16", name: "X-Rite ColorChecker Passport", category: "Calibration", serial: nil,
              status: .available, condition: .excellent, kitColor: kitBlue, assignee: nil),
        .init(id: "e17", name: "Rolling Case — Pelican 1615", category: "Transport", serial: "PEL-1615-08",
              status: .available, condition: .good, kitColor: nil, assignee: nil),
        .init(id: "e18", name: "Savage Seamless Paper — Thunder Gray", category: "Backdrop", serial: nil,
              status: .needsRepair, condition: .poor, kitColor: nil, assignee: nil),
        .init(id: "e19", name: "Canon RF 50mm f/1.2L", category: "Lens", serial: "5012008832",
              status: .available, condition: .excellent, kitColor: kitAmber, assignee: nil),
        .init(id: "e20", name: "Elinchrom Skyport Trigger", category: "Lighting", serial: "SKY-2201",
              status: .checkedOut, condition: .good, kitColor: kitAmber, assignee: "Devon Wright"),
        .init(id: "e21", name: "Posing Stool", category: "Studio", serial: nil,
              status: .available, condition: .fair, kitColor: nil, assignee: nil),
        .init(id: "e22", name: "iPad Pro 12.9\" — Kiosk", category: "Computer", serial: "DMPX2091",
              status: .checkedOut, condition: .good, kitColor: kitBlue, assignee: "Maria Alvarez"),
        .init(id: "e23", name: "Gaffer Tape (case of 12)", category: "Consumable", serial: nil,
              status: .available, condition: .good, kitColor: nil, assignee: nil),
        .init(id: "e24", name: "Canon EOS R3", category: "Camera Body", serial: "3300771294",
              status: .retired, condition: .fair, kitColor: nil, assignee: nil),
    ]

    /// The crew, for avatar specimens. Same names the schedule's lab used, so
    /// the deterministic colours look familiar across the arc.
    static let crew: [AmbientAvatarSubject] = [
        .init(id: "lab-maria", name: "Maria Alvarez"),
        .init(id: "lab-devon", name: "Devon Wright"),
        .init(id: "lab-priya", name: "Priya Nair"),
        .init(id: "lab-sam", name: "Sam Okafor"),
        .init(id: "lab-june", name: "June Castillo"),
        .init(id: "lab-alex", name: "Alex Fontaine"),
    ]

    /// Pills covering a short label, a long one, and enough of them to force the
    /// flow layout to wrap.
    static let pills: [AmbientPill] = [
        .init(text: "Camera Body", systemImage: "camera.fill", tint: .blue),
        .init(text: "Lens", systemImage: "circle.circle", tint: .indigo),
        .init(text: "Needs Calibration Before Next Use", systemImage: "exclamationmark.triangle.fill", tint: .orange),
        .init(text: "Kit A", systemImage: "shippingbox.fill", tint: .teal),
        .init(text: "Retired", systemImage: "xmark.circle.fill", tint: .gray),
    ]
}

// MARK: - Home dashboard (AMB.4)

/// A shift as the dashboard's Upcoming Shifts widget needs it. Deliberately not
/// a real `Session` — the lab stays clear of the schedule's service layer.
struct LabShift: Identifiable {
    let id: String
    let school: String
    let start: Date
    let end: Date
    /// Type name and its colour, exactly as the converted schedule draws them.
    let types: [(name: String, hex: String)]
    let crew: [String]
    /// "Day 2 of 3" for a multi-day job.
    let dayLabel: String?
    /// The colour the SCHEDULER picked. This is the whole point of the widget
    /// mockup: today the dashboard ignores it and paints almost every shift
    /// blue, because it looks the colour up by a field that holds a session
    /// TYPE and almost never matches.
    let sessionHex: String

    var accent: Color { Color(hex: sessionHex) }
}

extension DesignLabSampleData {

    private static func at(_ hour: Int, _ minute: Int, dayOffset: Int = 0) -> Date {
        let calendar = Calendar.current
        let base = calendar.date(byAdding: .day, value: dayOffset,
                                 to: calendar.startOfDay(for: Date())) ?? Date()
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
    }

    /// Three upcoming shifts covering the shapes that decide the layout: a
    /// two-discipline job with a full crew, a solo job, and one day of a
    /// multi-day booking.
    static var upcomingShifts: [LabShift] {
        [
            .init(id: "s1", school: "Lincoln High School",
                  start: at(7, 45), end: at(14, 30),
                  types: [("Fall Portraits", "#2563eb"), ("Class Groups", "#16a34a")],
                  crew: ["Maria Alvarez", "Devon Wright", "Priya Nair", "Sam Okafor"],
                  dayLabel: nil, sessionHex: "#2563eb"),
            .init(id: "s2", school: "Maple Grove Elementary",
                  start: at(15, 30), end: at(17, 0),
                  types: [("Class Groups", "#16a34a")],
                  crew: ["June Castillo"],
                  dayLabel: nil, sessionHex: "#16a34a"),
            .init(id: "s3", school: "Northgate Preparatory",
                  start: at(7, 45, dayOffset: 1), end: at(15, 0, dayOffset: 1),
                  types: [("Fall Portraits", "#ea580c")],
                  crew: ["Maria Alvarez", "Devon Wright"],
                  dayLabel: "Day 2 of 3", sessionHex: "#ea580c"),
        ]
    }

    /// Numbers for the Hours and Mileage widgets, in the shapes those widgets
    /// actually render (hours against a 40h week and an 80h period, mileage
    /// split personal vs company per the CAR arc).
    enum Dashboard {
        static let weekHours: Double = 31.5
        static let weekTarget: Double = 40
        static let periodHours: Double = 62.25
        static let periodTarget: Double = 80
        static let isClockedIn = true
        static let activeHours: Double = 2.4

        static let periodMiles = 182
        static let periodPay = "$49.04"
        static let personalMiles = 87
        static let companyMiles = 94
        static let monthMiles = 182
        static let yearMiles = 7727
        static let yearPay = "$3,444.38"
    }

    /// The dashboard's task strip — the five most urgent assigned to you.
    static let urgentTasks: [LabTask] = [
        .init(id: "t1", title: "Send Lincoln proofs to the office", priority: .urgent,
              status: .inProgress, due: "Today", overdue: false, subtasks: (1, 3)),
        .init(id: "t2", title: "Return the 70-200 to the equipment room", priority: .high,
              status: .todo, due: "Yesterday", overdue: true, subtasks: (0, 0)),
        .init(id: "t3", title: "Confirm Northgate day 3 call time with Ms. Reyes",
              priority: .medium, status: .todo, due: "Tomorrow", overdue: false,
              subtasks: (0, 2)),
    ]
}

struct LabTask: Identifiable {
    enum Priority { case low, medium, high, urgent
        var color: Color {
            switch self {
            case .low: return .gray
            case .medium: return .blue
            case .high: return .orange
            case .urgent: return .red
            }
        }
    }
    enum Status: String { case todo = "To Do", inProgress = "In Progress", completed = "Completed"
        var color: Color {
            switch self {
            case .todo: return .gray
            case .inProgress: return .blue
            case .completed: return .green
            }
        }
    }

    let id: String
    let title: String
    let priority: Priority
    let status: Status
    let due: String
    let overdue: Bool
    /// completed / total
    let subtasks: (Int, Int)
}
