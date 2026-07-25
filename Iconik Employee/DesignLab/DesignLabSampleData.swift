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
    /// The rest of what EquipmentDetailView renders and the row does not. All
    /// optional, all frequently absent — which is the point: the detail has to
    /// read with two of these filled in and four missing.
    var detail: String? = nil
    var notes: String? = nil
    var purchasePrice: Double? = nil
    var purchaseDate: String? = nil
    var kitName: String? = nil
    /// Set on the items checked out to YOU, so the redesigned screen can lead
    /// with what you are holding.
    var mine: Bool = false
    var dueLabel: String? = nil
    var overdue: Bool = false

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
        // Fully catalogued — every optional field the detail can render is set,
        // which is the LONG version of that screen.
        .init(id: "e1", name: "Canon EOS R5", category: "Camera Body", serial: "3421887065",
              status: .checkedOut, condition: .excellent, kitColor: kitBlue, assignee: "Maria Alvarez",
              detail: "Primary body. 45MP full-frame, dual card slots.",
              notes: "Rear dial is stiff in the cold — works fine once it warms up.",
              purchasePrice: 3899, purchaseDate: "Mar 14, 2024",
              kitName: "Portrait Kit A", mine: true, dueLabel: "Permanent"),
        .init(id: "e2", name: "Canon RF 24-70mm f/2.8L IS USM", category: "Lens", serial: "9920114774",
              status: .checkedOut, condition: .good, kitColor: kitBlue, assignee: "Maria Alvarez",
              detail: "Workhorse zoom. Lives on the R5.",
              purchasePrice: 2299, purchaseDate: "Mar 14, 2024",
              kitName: "Portrait Kit A", mine: true, dueLabel: "Permanent"),
        .init(id: "e3", name: "Profoto B10X Plus Off-Camera Flash Head with Extended Battery Pack",
              category: "Lighting", serial: "PB10X-0042",
              status: .available, condition: .good, kitColor: nil, assignee: nil,
              purchasePrice: 2195, purchaseDate: "Aug 2, 2023"),
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

    /// The dashboard's task strip — the most urgent assigned to you.
    ///
    /// Derived from `tasks` rather than typed out again: AMB.5's Tasks mockup
    /// needs the same rows, and a photographer seeing the same three items on
    /// home and in Tasks is what really happens. The first three entries of
    /// `tasks` are the ones the approved dashboard mockup shipped with, so this
    /// renders exactly what the operator already said yes to.
    static var urgentTasks: [LabTask] { Array(tasks.prefix(3)) }
}

// MARK: - Tasks (AMB.5)

struct LabTask: Identifiable {
    enum Priority: String, CaseIterable { case low = "Low", medium = "Medium", high = "High", urgent = "Urgent"
        var color: Color {
            switch self {
            case .low: return .gray
            case .medium: return .blue
            case .high: return .orange
            case .urgent: return .red
            }
        }
    }
    enum Status: String, CaseIterable { case todo = "To Do", inProgress = "In Progress", completed = "Completed"
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
    /// Optional because a real task can carry no due date at all — the row has
    /// to read without the date Label, not with an empty one.
    let due: String?
    let overdue: Bool
    /// completed / total
    let subtasks: (Int, Int)
    /// Everything below is on the MODEL and is NOT rendered by today's row.
    /// Kept here because the mockup has to answer whether any of it earns a
    /// place — the answer for most of it is no, and that is worth showing.
    var comments: Int = 0
    var assignee: String? = nil
    var detail: String? = nil
    var type: String? = nil
    var estimatedHours: Double? = nil
    /// False for a task assigned to someone else — the All filter shows these,
    /// the default My Tasks filter does not.
    var mine: Bool = true
    /// Which "when" band the task falls in. An explicit field rather than a date
    /// the mockup would have to parse back out of a display string — the real
    /// screen computes this from `dueDate`, which it has and the lab does not.
    var when: LabTaskWhen = .later
    /// TaskItem carries `sessionId`, `workflowName` and `workflowStepName`, and
    /// NOTHING in the app renders any of them — a task attached to a job cannot
    /// show you the job. Carried here so the redesign can ask whether it should.
    var sessionLabel: String? = nil
    var workflowLabel: String? = nil

    var isCompleted: Bool { status == .completed }
}

/// The reading order the redesign groups by. Overdue first, because today the
/// only way to find out something is late is to drive the chip bar to Urgent.
enum LabTaskWhen: String, CaseIterable {
    case overdue = "Overdue"
    case today = "Today"
    case thisWeek = "This week"
    case later = "Later"
    case noDate = "No date"

    var symbol: String {
        switch self {
        case .overdue: return "exclamationmark.triangle.fill"
        case .today: return "sun.max.fill"
        case .thisWeek: return "calendar"
        case .later: return "clock"
        case .noDate: return "tray"
        }
    }

    var tint: Color {
        switch self {
        case .overdue: return .red
        case .today: return .orange
        case .thisWeek: return .blue
        case .later: return .secondary
        case .noDate: return .secondary
        }
    }
}

extension DesignLabSampleData {

    /// Fourteen tasks, seeded with the shapes that decide the row: every
    /// priority, every status, an overdue one, one with NO due date, a title
    /// long enough to wrap to two lines, completed ones that have to read as
    /// finished without disappearing, and one assigned to somebody else.
    static let tasks: [LabTask] = [
        .init(id: "t1", title: "Send Lincoln proofs to the office", priority: .urgent,
              status: .inProgress, due: "Today", overdue: false, subtasks: (1, 3),
              comments: 2, assignee: "You",
              detail: "Full set from the gym plus the twelve retakes. The office wants them before the Friday cutoff so the proofs go out with the Monday mailing.",
              type: "Delivery", estimatedHours: 1.5, when: .today,
              sessionLabel: "Lincoln High — Fall Portraits"),
        .init(id: "t2", title: "Return the 70-200 to the equipment room", priority: .high,
              status: .todo, due: "Yesterday", overdue: true, subtasks: (0, 0),
              comments: 0, assignee: "You", type: "Equipment", when: .overdue),
        .init(id: "t3", title: "Confirm Northgate day 3 call time with Ms. Reyes",
              priority: .medium, status: .todo, due: "Tomorrow", overdue: false,
              subtasks: (0, 2), comments: 1, assignee: "You", type: "Scheduling",
              when: .thisWeek, sessionLabel: "Northgate Preparatory — Day 3"),
        // The two-line title. Nothing truncates it in the real row either — it
        // is allowed two lines and then cuts.
        .init(id: "t4", title: "Re-shoot the eleven Maple Grove kindergarten portraits flagged for eyes-closed, and pick up the class composite while you are there",
              priority: .urgent, status: .todo, due: "Friday", overdue: false,
              subtasks: (0, 4), comments: 5, assignee: "You", type: "Reshoot",
              estimatedHours: 3, when: .thisWeek,
              sessionLabel: "Maple Grove Elementary", workflowLabel: "Reshoots · Step 2 of 4"),
        .init(id: "t5", title: "Chase Ms. Alvarado for the missing photo release forms",
              priority: .high, status: .inProgress, due: "Today", overdue: false,
              subtasks: (2, 5), comments: 8, assignee: "You", type: "Paperwork",
              when: .today),
        // No due date at all.
        .init(id: "t6", title: "Order more gaffer tape", priority: .low,
              status: .todo, due: nil, overdue: false, subtasks: (0, 0),
              assignee: "You", type: "Supplies", when: .noDate),
        // Overdue but only MEDIUM priority — the case that proves grouping by
        // when beats sorting by priority: today this sits below four urgent
        // items that are not actually late.
        .init(id: "t7", title: "Fix the tripod head that sticks when cold", priority: .medium,
              status: .todo, due: "Jul 21", overdue: true, subtasks: (1, 2),
              comments: 1, assignee: "You", type: "Equipment", when: .overdue),
        .init(id: "t8", title: "Pack the sports kit for Friday", priority: .urgent,
              status: .todo, due: "Thursday", overdue: false, subtasks: (3, 7),
              assignee: "You", type: "Equipment", estimatedHours: 0.5, when: .thisWeek),
        .init(id: "t9", title: "Swap the backdrop rolls in the studio", priority: .medium,
              status: .todo, due: "Aug 4", overdue: false, subtasks: (0, 0),
              assignee: "You", type: "Studio", when: .later),
        // Someone else's — visible under All, hidden under the default My Tasks.
        .init(id: "t10", title: "Review the new photographer's first day report",
              priority: .medium, status: .inProgress, due: "Today", overdue: false,
              subtasks: (0, 3), comments: 2, assignee: "Devon Wright",
              type: "Review", mine: false, when: .today),
        .init(id: "t11", title: "Send the invoice for Northgate", priority: .low,
              status: .todo, due: nil, overdue: false, subtasks: (0, 0),
              assignee: "June Castillo", type: "Billing", mine: false, when: .noDate),
        .init(id: "t12", title: "Upload Riverside proofs", priority: .medium,
              status: .completed, due: "Monday", overdue: false, subtasks: (4, 4),
              comments: 3, assignee: "You", type: "Delivery", when: .thisWeek),
        .init(id: "t13", title: "Clean the sensor on the R5 body", priority: .low,
              status: .completed, due: "Last week", overdue: false, subtasks: (0, 0),
              assignee: "You", type: "Equipment", when: .later),
        .init(id: "t14", title: "Archive last season's job boxes", priority: .low,
              status: .completed, due: "Jun 30", overdue: false, subtasks: (0, 0),
              assignee: "You", type: "Admin", when: .later),
    ]

    /// Subtasks and comments for the one task whose detail sheet is mocked.
    static let sampleSubtasks: [(title: String, done: Bool)] = [
        ("Export the gym set at full resolution", true),
        ("Cull the twelve retakes", false),
        ("Upload to the office share", false),
    ]

    /// Comments carry ATTACHMENTS in the app — file name, formatted size and an
    /// image-or-document glyph. Easy to drop in a redesign and it would be
    /// feature loss, so one of these has one.
    static let sampleComments: [LabComment] = [
        .init(author: "Devon Wright",
              text: "Two of the retakes are the same kid — I think Row 3 got shot twice.",
              when: "Yesterday",
              attachment: .init(fileName: "row3-compare.jpg", size: "2.4 MB", isImage: true)),
        .init(author: "You",
              text: "Good catch, I'll drop the second one before it goes over.",
              when: "Yesterday", attachment: nil),
    ]
}

struct LabComment: Identifiable {
    struct Attachment {
        let fileName: String
        let size: String
        let isImage: Bool
    }

    var id: String { author + when + text.prefix(12) }
    let author: String
    let text: String
    let when: String
    var attachment: Attachment? = nil
}

// MARK: - Equipment kits (AMB.3, the DEFAULT tab)

/// A kit as My Kits renders it. Fields taken from `KitCard` and `KitDetailView`:
/// display name, an optional description, the tape colour, an item count, and
/// exactly one of overdue / permanent / a return date.
struct LabKit: Identifiable {
    let id: String
    let name: String
    let detail: String?
    /// A hex string, OR the literal "rainbow" — the real model accepts both
    /// (`KitTemplate.isRainbow`), and rainbow tape is a real kit colour in the
    /// field, so every place that draws a kit colour has to survive it.
    let colorHex: String?
    let due: LabKitDue
    /// Ids into `DesignLabSampleData.equipment`.
    let itemIDs: [String]

    var itemCount: Int { itemIDs.count }
    var isRainbow: Bool { colorHex?.lowercased() == "rainbow" }

    var items: [LabEquipmentItem] {
        itemIDs.compactMap { id in
            DesignLabSampleData.equipment.first { $0.id == id }
        }
    }
}

enum LabKitDue {
    case permanent
    case on(String)
    case overdue(days: Int)
}

extension DesignLabSampleData {

    /// Three kits, because three is enough to carry the cases: a permanent kit,
    /// one with a return date, and one that is overdue AND uses rainbow tape —
    /// the shape most likely to break a stripe drawn as a flat colour.
    static let myKits: [LabKit] = [
        .init(id: "k1", name: "Portrait Kit A",
              detail: "Two bodies, three lenses, tethering",
              colorHex: "#3b82f6", due: .permanent,
              itemIDs: ["e1", "e2", "e9", "e16", "e22", "e11"]),
        .init(id: "k2", name: "Sports Kit B",
              detail: "Long glass and the field lighting",
              colorHex: "#f59e0b", due: .on("Aug 2"),
              itemIDs: ["e5", "e7", "e8", "e13", "e19", "e20"]),
        // No description, rainbow tape, and late.
        .init(id: "k3", name: "Loaner Kit", detail: nil,
              colorHex: "rainbow", due: .overdue(days: 3),
              itemIDs: ["e12", "e17", "e21"]),
    ]

    /// Items checked out to you that belong to no kit — My Kits' second section.
    static var otherAssignedEquipment: [LabEquipmentItem] {
        equipment
            .filter { ["e15", "e14"].contains($0.id) }
            .map { item in
                var copy = item
                copy.mine = true
                copy.dueLabel = item.id == "e14" ? "Jul 22" : "Aug 9"
                copy.overdue = item.id == "e14"
                return copy
            }
    }

    /// The org's real category list, for All Equipment's category filter chips —
    /// derived rather than typed out, because in the app these come from the
    /// database and a hardcoded list would drift the moment anyone added one.
    static var equipmentCategories: [String] {
        Array(Set(equipment.compactMap(\.category))).sorted()
    }

    /// What the redesigned screen leads with: how much you are holding, how much
    /// is due back soon, and how much is late. None of this is a single glance
    /// today — you find out by reading every kit card.
    enum MyGear {
        static var itemCount: Int {
            DesignLabSampleData.myKits.reduce(0) { $0 + $1.itemCount }
                + DesignLabSampleData.otherAssignedEquipment.count
        }

        static var overdueCount: Int {
            let kits = DesignLabSampleData.myKits.filter {
                if case .overdue = $0.due { return true }
                return false
            }.reduce(0) { $0 + $1.itemCount }
            return kits + DesignLabSampleData.otherAssignedEquipment.filter(\.overdue).count
        }

        static var dueSoonCount: Int {
            DesignLabSampleData.myKits.filter {
                if case .on = $0.due { return true }
                return false
            }.reduce(0) { $0 + $1.itemCount }
        }
    }
}

// MARK: - Chat (AMB.6, the hardest test of compact)

enum LabMessageKind {
    case text, gif, image, link, file
    /// "X added Y to the group", "X removed Y", "X left the group". Rendered
    /// centred in a capsule, never in a bubble, and never with a sender name.
    /// Absent from the first cut of this mockup entirely — which would have
    /// been feature loss, not a style choice.
    case system

    /// The emoji-typed preview the conversation list shows instead of a body.
    /// The app derives these by sniffing the URL of the last message.
    var previewLabel: String? {
        switch self {
        case .text, .system: return nil
        case .gif: return "🎬 GIF"
        case .image: return "📷 Photo"
        case .link: return "🔗 Link"
        case .file: return "📎 File"
        }
    }
}

struct LabConversation: Identifiable {
    let id: String
    let name: String
    let isGroup: Bool
    let participants: [String]
    let preview: String
    let previewKind: LabMessageKind
    /// Drives the "You: " prefix.
    let fromYou: Bool
    let time: String
    let unread: Int
    let pinned: Bool
    /// False for a conversation that has never had a message — the app draws
    /// "No messages yet" in italic rather than an empty preview line.
    var hasMessages: Bool = true

    var previewText: String {
        let body = previewKind.previewLabel ?? preview
        return fromYou ? "You: \(body)" : body
    }
}

struct LabMessage: Identifiable {
    let id: String
    let sender: String
    let mine: Bool
    let text: String?
    let kind: LabMessageKind
    let sentAt: Date
}

extension DesignLabSampleData {

    /// Eight conversations: two pinned, a group whose preview is somebody
    /// else's line, a "You:" preview, every media preview type, an unread
    /// count that needs two digits' worth of pill, and one preview long enough
    /// to prove the two-line cut.
    static let conversations: [LabConversation] = [
        .init(id: "c1", name: "Maria Alvarez", isGroup: false, participants: ["Maria Alvarez"],
              preview: "On my way — traffic on the 5", previewKind: .text,
              fromYou: false, time: "9:41 AM", unread: 2, pinned: true),
        .init(id: "c2", name: "Lincoln High — Fall Portraits", isGroup: true,
              participants: ["Maria Alvarez", "Devon Wright", "Priya Nair", "Sam Okafor", "June Castillo"],
              preview: "Sam: We're set up in the gym", previewKind: .text,
              fromYou: false, time: "9:12 AM", unread: 12, pinned: true),
        .init(id: "c3", name: "Devon Wright", isGroup: false, participants: ["Devon Wright"],
              preview: "", previewKind: .gif,
              fromYou: false, time: "Yesterday", unread: 0, pinned: false),
        .init(id: "c4", name: "Office", isGroup: true,
              participants: ["June Castillo", "Alex Fontaine"],
              preview: "Sending the count now", previewKind: .text,
              fromYou: true, time: "Yesterday", unread: 0, pinned: false),
        .init(id: "c5", name: "June Castillo", isGroup: false, participants: ["June Castillo"],
              preview: "", previewKind: .image,
              fromYou: false, time: "Tuesday", unread: 1, pinned: false),
        // Long enough to need the two-line cut.
        .init(id: "c6", name: "Priya Nair", isGroup: false, participants: ["Priya Nair"],
              preview: "I moved the composite to the stage end because the window light was blowing out the whole left side of the gym by about ten",
              previewKind: .text, fromYou: false, time: "Monday", unread: 0, pinned: false),
        .init(id: "c7", name: "Equipment Room", isGroup: true,
              participants: ["Sam Okafor", "Alex Fontaine", "Devon Wright"],
              preview: "", previewKind: .link,
              fromYou: true, time: "Jul 18", unread: 0, pinned: false),
        .init(id: "c8", name: "Alex Fontaine", isGroup: false, participants: ["Alex Fontaine"],
              preview: "Thanks!", previewKind: .text,
              fromYou: false, time: "Jul 14", unread: 0, pinned: false),
        // A conversation with NO messages. The app draws "No messages yet" in
        // italic here rather than an empty line, and the first cut of this
        // mockup had no such row to draw it with.
        .init(id: "c9", name: "Riverside Middle — Retakes", isGroup: true,
              participants: ["Priya Nair", "Sam Okafor"],
              preview: "", previewKind: .text,
              fromYou: false, time: "Jul 12", unread: 0, pinned: false,
              hasMessages: false),
    ]

    /// The thread for the group conversation, which is the hard one: several
    /// senders, consecutive runs from the same person, a GIF, an image, and a
    /// day boundary. This is the scrollback the density question is decided on.
    static var thread: [LabMessage] {
        [
            .init(id: "m1", sender: "Maria Alvarez", mine: false,
                  text: "Are we still on for 7:45 tomorrow?", kind: .text,
                  sentAt: at(16, 2, dayOffset: -1)),
            .init(id: "m2", sender: "You", mine: true,
                  text: "Yes — gym doors at 7:30", kind: .text,
                  sentAt: at(16, 3, dayOffset: -1)),
            .init(id: "m3", sender: "You", mine: true,
                  text: "Bring the second backdrop stand, the one in Kit A is bent", kind: .text,
                  sentAt: at(16, 3, dayOffset: -1)),
            .init(id: "m4", sender: "Sam Okafor", mine: false,
                  text: "I can grab it on the way", kind: .text,
                  sentAt: at(16, 31, dayOffset: -1)),
            // A system message. The app renders three of these — participants
            // added, participant removed, participant left — centred in a grey
            // capsule with their own timestamp underneath.
            .init(id: "m4b", sender: "System", mine: false,
                  text: "Maria Alvarez added June Castillo to the group",
                  kind: .system, sentAt: at(17, 5, dayOffset: -1)),
            // ── day boundary ──
            .init(id: "m5", sender: "Sam Okafor", mine: false,
                  text: "Loading now", kind: .text, sentAt: at(7, 12)),
            .init(id: "m6", sender: "Sam Okafor", mine: false,
                  text: nil, kind: .gif, sentAt: at(7, 12)),
            .init(id: "m7", sender: "Maria Alvarez", mine: false,
                  text: "On my way — traffic on the 5", kind: .text, sentAt: at(7, 41)),
            .init(id: "m8", sender: "You", mine: true,
                  text: "No rush, the first class isn't until 8:20", kind: .text,
                  sentAt: at(7, 58)),
            .init(id: "m9", sender: "Devon Wright", mine: false,
                  text: nil, kind: .image, sentAt: at(8, 2)),
            .init(id: "m10", sender: "Devon Wright", mine: false,
                  text: "Gym looks like this — that window is going to be a problem by ten, the whole left side is already two stops hot",
                  kind: .text, sentAt: at(8, 3)),
            .init(id: "m11", sender: "You", mine: true,
                  text: "Flag it and shoot the other end", kind: .text, sentAt: at(8, 5)),
            .init(id: "m12", sender: "You", mine: true,
                  text: "I'll bring the scrim", kind: .text, sentAt: at(8, 5)),
            .init(id: "m13", sender: "Priya Nair", mine: false,
                  text: "Where do you want the class composites?", kind: .text,
                  sentAt: at(9, 10)),
            .init(id: "m14", sender: "You", mine: true,
                  text: "Stage end, same as last year", kind: .text, sentAt: at(9, 11)),
            .init(id: "m15", sender: "Sam Okafor", mine: false,
                  text: "We're set up in the gym", kind: .text, sentAt: at(9, 12)),
        ]
    }
}
