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


// MARK: - Shared time helper

extension DesignLabSampleData {
    /// A time today (or a day either side of it), so every mockup's sample data sits
    /// around the moment the operator is actually looking at it.
    ///
    /// Lived in AMB.4's dashboard block until that phase's mockups were deleted at
    /// its close, then moved here; AMB.5's Tasks block went the same way, so Chat is
    /// now the only caller. It stays here rather than moving into ChatMockup because
    /// AMB.6 will delete that file too, and the next batch will want this again.
    static func at(_ hour: Int, _ minute: Int, dayOffset: Int = 0) -> Date {
        let calendar = Calendar.current
        let base = calendar.date(byAdding: .day, value: dayOffset,
                                 to: calendar.startOfDay(for: Date())) ?? Date()
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
    }
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

// MARK: - Time off (AMB.8, mocked in batch 2)

/// The five statuses, with the ONE rendering the redesign picks.
///
/// Today the app draws status three incompatible ways: the shared card uses a
/// filled capsule from a `colorName` STRING that is passed to `Color(_:)` — the
/// asset-catalog initialiser, which finds nothing, because AccentColor is the
/// only colorset in the project; TimeOffDetailView uses real SwiftUI colours and
/// prints `rawValue.capitalized`, so underReview reads as "Underreview"; and
/// ScheduleStyleKit makes approved ORANGE when partial and GREY when not.
/// Batch-2 parity finding 6 says a redesign has to pick one knowingly. This is
/// the pick — real colours, and a label a person would actually say.
enum LabTimeOffStatus: String, CaseIterable {
    case pending, underReview, approved, denied, cancelled

    /// Never `rawValue.capitalized` — that is where "Underreview" came from.
    var label: String {
        switch self {
        case .pending: return "Pending"
        case .underReview: return "In Review"
        case .approved: return "Approved"
        case .denied: return "Denied"
        case .cancelled: return "Cancelled"
        }
    }

    var color: Color {
        switch self {
        case .pending: return .orange
        case .underReview: return .blue
        case .approved: return .green
        case .denied: return .red
        case .cancelled: return .gray
        }
    }

    var symbol: String {
        switch self {
        case .pending: return "clock.fill"
        case .underReview: return "magnifyingglass"
        case .approved: return "checkmark.circle.fill"
        case .denied: return "xmark.circle.fill"
        case .cancelled: return "slash.circle.fill"
        }
    }

    /// Drives the Edit and Cancel pills — the app's real condition.
    var isEditable: Bool { self == .pending || self == .underReview }
}

enum LabTimeOffReason: String, CaseIterable {
    case vacation = "Vacation"
    case sick = "Sick"
    case personal = "Personal"
    case family = "Family"
    case bereavement = "Bereavement"
    case other = "Other"

    var symbol: String {
        switch self {
        case .vacation: return "beach.umbrella.fill"
        case .sick: return "cross.case.fill"
        case .personal: return "person.fill"
        case .family: return "figure.2.and.child.holdinghands"
        case .bereavement: return "heart.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .vacation: return .teal
        case .sick: return .red
        case .personal: return .indigo
        case .family: return .purple
        case .bereavement: return .brown
        case .other: return .gray
        }
    }
}

/// One request. Fields taken from what the real card and detail actually render,
/// including the three conditional attribution lines (approved by / in review by
/// / denied by, with its own indented reason line).
struct LabTimeOffRequest: Identifiable {
    let id: String
    let photographer: String
    let status: LabTimeOffStatus
    let reason: LabTimeOffReason
    let startDate: Date
    let endDate: Date
    let isPartialDay: Bool
    var startTime: Date?
    var endTime: Date?
    var notes: String?
    var usesPTO: Bool = true
    var ptoHours: Double?
    /// Present only when BOTH the name and the date exist — the app's real
    /// condition for drawing the attribution line at all.
    var actionedBy: String?
    var actionedAt: Date?
    var denialReason: String?
    /// Drives the employee list's newest-first sort and the manager History tab.
    let createdAt: Date

    /// INCLUSIVE of both endpoints — days + 1. A domain rule, not a formatting
    /// choice, so it lives on the model where a mockup cannot quietly drop it.
    var dayCount: Int {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: startDate),
                                                   to: Calendar.current.startOfDay(for: endDate)).day ?? 0
        return days + 1
    }

    var durationLabel: String {
        if isPartialDay, let start = startTime, let end = endTime {
            let hours = end.timeIntervalSince(start) / 3600
            return String(format: "%.1f hours", hours)
        }
        return dayCount == 1 ? "1 day" : "\(dayCount) days"
    }

    var dateLabel: String {
        if isPartialDay || dayCount == 1 {
            return Formatters.monthDay.string(from: startDate)
        }
        return "\(Formatters.monthDay.string(from: startDate)) – \(Formatters.monthDay.string(from: endDate))"
    }

    var timeLabel: String {
        guard isPartialDay, let start = startTime, let end = endTime else { return "Full day" }
        return "\(Formatters.shortTime.string(from: start)) – \(Formatters.shortTime.string(from: end))"
    }
}

/// The balance, with every conditional the real screen carries: banking is
/// omitted when absent, pending is omitted when zero, and the accrual policy card
/// disappears entirely unless the org has enabled accrual — which DEFAULTS TO
/// FALSE, so most orgs never see it.
struct LabPTOBalance {
    let totalBalance: Double
    let pendingHours: Double
    let bankingBalance: Double?
    let usedThisYear: Double
    let totalAccrued: Double
    let accrualEnabled: Bool
    let accrualRate: String
    let accrualCap: String
    let rolloverPolicy: String

    var available: Double { totalBalance - pendingHours }
}

extension DesignLabSampleData {

    /// A day at a fixed hour, N days from today. Time off is drawn against real
    /// dates so the "past request outside the picker's range" case is real.
    static func day(_ offset: Int, hour: Int = 9) -> Date {
        at(hour, 0, dayOffset: offset)
    }

    /// Your own requests, NEWEST FIRST — which is the employee list's real order
    /// and the deliberate opposite of the manager queue below.
    ///
    /// Seeded to contain every case that decides the design: all five statuses,
    /// a partial day, a multi-day span, a single day, a request with no notes, a
    /// denial WITH a reason and the indented line it needs, an approval whose
    /// approver name is missing (so the attribution line must NOT draw), and a
    /// PTO request that does not have the balance to cover it.
    static let myTimeOff: [LabTimeOffRequest] = [
        .init(id: "t1", photographer: "You", status: .pending, reason: .vacation,
              startDate: day(24), endDate: day(28), isPartialDay: false,
              notes: "Family trip — booked the flights already.",
              ptoHours: 40, createdAt: day(-1)),
        // Partial day, and the one that does NOT have the PTO to cover it.
        .init(id: "t2", photographer: "You", status: .pending, reason: .personal,
              startDate: day(9), endDate: day(9), isPartialDay: true,
              startTime: at(13, 0, dayOffset: 9), endTime: at(17, 0, dayOffset: 9),
              notes: nil, ptoHours: 4, createdAt: day(-2)),
        .init(id: "t3", photographer: "You", status: .underReview, reason: .family,
              startDate: day(16), endDate: day(17), isPartialDay: false,
              notes: "Parent-teacher conferences both mornings.",
              ptoHours: 16, actionedBy: "Alex Fontaine", actionedAt: day(-3),
              createdAt: day(-5)),
        .init(id: "t4", photographer: "You", status: .approved, reason: .sick,
              startDate: day(-8), endDate: day(-8), isPartialDay: false,
              notes: nil, ptoHours: 8,
              actionedBy: "Alex Fontaine", actionedAt: day(-9), createdAt: day(-10)),
        // Approved but the approver name never came back — the attribution line
        // is conditional on BOTH the name and the date, so this row must draw
        // WITHOUT it rather than showing "Approved by".
        .init(id: "t5", photographer: "You", status: .approved, reason: .vacation,
              startDate: day(-30), endDate: day(-26), isPartialDay: false,
              notes: "Spring break.", ptoHours: 40, createdAt: day(-45)),
        .init(id: "t6", photographer: "You", status: .denied, reason: .personal,
              startDate: day(-14), endDate: day(-14), isPartialDay: false,
              notes: nil, usesPTO: false,
              actionedBy: "Alex Fontaine", actionedAt: day(-16),
              denialReason: "Three photographers already off that day and it is a fall original day.",
              createdAt: day(-20)),
        .init(id: "t7", photographer: "You", status: .cancelled, reason: .other,
              startDate: day(-40), endDate: day(-39), isPartialDay: false,
              notes: "Changed my mind.", usesPTO: false, createdAt: day(-50)),
    ]

    /// The manager queue. THE ORDER IS THE POINT: pending and in-review sort
    /// OLDEST FIRST because a manager works a queue, which is the deliberate
    /// reverse of the employee list. History sorts by when it was ACTIONED.
    static let approvalQueue: [LabTimeOffRequest] = [
        .init(id: "a1", photographer: "Sam Okafor", status: .pending, reason: .sick,
              startDate: day(1), endDate: day(1), isPartialDay: false,
              notes: "Woke up with it — sorry for the short notice.",
              ptoHours: 8, createdAt: day(-6)),
        .init(id: "a2", photographer: "Priya Nair", status: .pending, reason: .vacation,
              startDate: day(33), endDate: day(40), isPartialDay: false,
              notes: "Wedding, out of state. Booked a year ago.",
              ptoHours: 48, createdAt: day(-4)),
        .init(id: "a3", photographer: "Devon Wright", status: .pending, reason: .personal,
              startDate: day(5), endDate: day(5), isPartialDay: true,
              startTime: at(8, 0, dayOffset: 5), endTime: at(10, 30, dayOffset: 5),
              notes: nil, ptoHours: 2.5, createdAt: day(-1)),
        .init(id: "a4", photographer: "Maria Alvarez", status: .underReview, reason: .family,
              startDate: day(12), endDate: day(13), isPartialDay: false,
              notes: "Can move it if the Lincoln retakes land that week.",
              ptoHours: 16, actionedBy: "You", actionedAt: day(-2), createdAt: day(-7)),
        .init(id: "a5", photographer: "June Castillo", status: .approved, reason: .vacation,
              startDate: day(-3), endDate: day(-2), isPartialDay: false,
              notes: nil, ptoHours: 16,
              actionedBy: "You", actionedAt: day(-5), createdAt: day(-12)),
        .init(id: "a6", photographer: "Alex Fontaine", status: .denied, reason: .other,
              startDate: day(-6), endDate: day(-6), isPartialDay: false,
              notes: nil, usesPTO: false,
              actionedBy: "You", actionedAt: day(-8),
              denialReason: "Homecoming — everyone is on that shoot.",
              createdAt: day(-15)),
    ]

    /// Sufficient to cover most things and NOT sufficient to cover request t2 —
    /// so the shortfall state has something real to fire against.
    static let ptoBalance = LabPTOBalance(
        totalBalance: 62.5,
        pendingHours: 46.5,
        bankingBalance: 12,
        usedThisYear: 48,
        totalAccrued: 110.5,
        accrualEnabled: true,
        accrualRate: "1 hour per 40 hours worked",
        accrualCap: "240 hours (30 days)",
        rolloverPolicy: "Up to 40 hours"
    )
}

// MARK: - Reports family (AMB.7, mocked in batch 2)

/// A filed report as the list renders it, plus the fields only the ORPHANED
/// TemplateReportListView can currently show — template name and version, the
/// smart-field count, the completed-field count. Those capabilities exist in the
/// codebase and are unreachable; the redesign either builds them or drops them
/// knowingly, so the sample data has to carry them either way.
struct LabJobReport: Identifiable {
    let id: String
    let date: Date
    /// Can be empty. The real row renders this line ALWAYS, even when the column
    /// is null — so the sparse case has to be drawn, not avoided.
    let school: String
    let mileage: Double
    let photoCount: Int
    let vehicle: String
    /// nil for a standard report; a name for a template-backed one.
    var templateName: String?
    var templateVersion: Int?
    var smartFieldCount: Int = 0
    var completedFieldCount: Int = 0
    /// nil = filed off-schedule, which is a real and common case.
    var sessionName: String?

    var isTemplate: Bool { templateName != nil }
}

struct LabReportTemplate: Identifiable {
    let id: String
    let name: String
    /// Never decoded from the database today (batch-2 finding R13), so every
    /// card in the live app shows the italic placeholder. Kept optional here so
    /// the mockup can show BOTH what it looks like now and what it looks like
    /// once the field is decoded.
    let detail: String?
    let shootType: String
    let fieldCount: Int
    let smartFieldCount: Int
    let isDefault: Bool
    let version: Int
}

/// A school you can pick on a report.
///
/// Carries a distance from home so the mockup's mileage can actually RESPOND to
/// what you select — add a stop and the number moves. The live form computes
/// this with real driving directions; the arithmetic here is fake, but it has to
/// be live, because "does the mileage update when I add a school" is one of the
/// things this screen is being judged on.
struct LabSchool: Identifiable, Hashable {
    let id: String
    let name: String
    let address: String
    /// One-way miles from the photographer's home address.
    let milesFromHome: Double
}

/// A photoshoot note. Local-first, one school NAME (not an id), no categories
/// and no session binding — which is the real model, and thinner than the screen
/// makes it look.
/// Mutable throughout, because the mockup lets you actually write a note —
/// type in it, set its school, add photos and submit it.
struct LabPhotoshootNote: Identifiable {
    let id: String
    let timestamp: Date
    /// Empty when the schedule could not fill it — the state that opens the
    /// "which school?" dialog.
    var school: String
    var text: String
    var photoCount: Int
    var submitted: Bool = false
    var syncedToServer: Bool = false
    var submittedAt: Date?
}

extension DesignLabSampleData {

    /// The org's schools. Long enough that the picker needs its search, and
    /// seeded with a name long enough to break a row that assumes one line.
    static let schools: [LabSchool] = [
        .init(id: "s1", name: "Lincoln High School",
              address: "2400 W Lincoln Ave", milesFromHome: 21.3),
        .init(id: "s2", name: "Riverside Middle School",
              address: "870 Riverside Dr", milesFromHome: 9.1),
        .init(id: "s3", name: "Oakmont Elementary",
              address: "115 Oakmont Rd", milesFromHome: 33.7),
        .init(id: "s4", name: "Pine Ridge Elementary",
              address: "4402 Pine Ridge Pkwy", milesFromHome: 16.5),
        .init(id: "s5", name: "District Office",
              address: "1 Education Plaza", milesFromHome: 4.9),
        .init(id: "s6", name: "St. Catherine of Siena Preparatory Academy",
              address: "9915 Cathedral Way", milesFromHome: 27.2),
        .init(id: "s7", name: "Westbrook Junior High",
              address: "600 Westbrook Ln", milesFromHome: 12.8),
        .init(id: "s8", name: "Harbor View Christian School",
              address: "77 Harbor View Ter", milesFromHome: 41.4),
        .init(id: "s9", name: "Maple Grove Elementary",
              address: "3300 Maple Grove Ave", milesFromHome: 7.6),
        .init(id: "s10", name: "Northgate Academy",
              address: "1250 Northgate Blvd", milesFromHome: 18.9),
    ]

    /// Home to the first stop, between each pair, then back home. The constant
    /// on the cross-town legs stops two nearby schools reading as a zero-mile
    /// hop, which is the shape that makes fake numbers look fake.
    static func routeMiles(_ stops: [LabSchool]) -> Double {
        guard let first = stops.first, let last = stops.last else { return 0 }
        var total = first.milesFromHome + last.milesFromHome
        for (a, b) in zip(stops, stops.dropFirst()) {
            total += abs(a.milesFromHome - b.milesFromHome) + 4.2
        }
        return (total * 10).rounded() / 10
    }

    /// What the app can work out about YOUR habits from reports you already
    /// filed. This is the raw material for reviewing a report BY EXCEPTION —
    /// "you drove 68 miles and you usually drive 18 here" — which the research
    /// says is the only kind of review a daily user still reads on day 200.
    ///
    /// Deliberately derived from `jobReports` rather than typed out, because the
    /// point being demonstrated is that the app already HAS this.
    enum History {
        /// Median-ish miles previously claimed for a school.
        static func usualMiles(_ school: String) -> Double? {
            let past = DesignLabSampleData.jobReports
                .filter { $0.school == school && $0.mileage > 0 }
                .map(\.mileage)
            guard !past.isEmpty else { return nil }
            return (past.reduce(0, +) / Double(past.count) * 10).rounded() / 10
        }

        /// The vehicle you almost always use. Confirming it EVERY time is what
        /// wears the safeguard out; confirming it when it CHANGES is what keeps
        /// it meaningful.
        static var usualVehicle: String {
            let counts = Dictionary(grouping: DesignLabSampleData.jobReports, by: \.vehicle)
                .mapValues(\.count)
            return counts.max { $0.value < $1.value }?.key ?? "personal"
        }
    }

    /// Filed reports, NEWEST FIRST — the real order of every list query.
    ///
    /// Deliberately MIXED standard and template reports, because that mix is
    /// exactly what the one reachable list cannot currently tell apart, and it
    /// is the case the redesign has to answer.
    static let jobReports: [LabJobReport] = [
        .init(id: "r1", date: day(-1), school: "Lincoln High School", mileage: 42.6,
              photoCount: 3, vehicle: "personal",
              sessionName: "Lincoln High School — 7:45 AM (Fall Original)"),
        .init(id: "r2", date: day(-2), school: "Riverside Middle School", mileage: 18.2,
              photoCount: 0, vehicle: "company",
              templateName: "Sports Day", templateVersion: 1,
              smartFieldCount: 4, completedFieldCount: 11,
              sessionName: "Riverside Middle — 3:30 PM (Fall Sports)"),
        // No school on the record at all — the row still draws the line.
        .init(id: "r3", date: day(-3), school: "", mileage: 0,
              photoCount: 0, vehicle: "personal"),
        .init(id: "r4", date: day(-4), school: "Oakmont Elementary, Pine Ridge Elementary",
              mileage: 71.4, photoCount: 12, vehicle: "personal",
              sessionName: "Oakmont Elementary — 8:00 AM (Classroom Groups)"),
        .init(id: "r5", date: day(-7), school: "Lincoln High School", mileage: 42.6,
              photoCount: 1, vehicle: "personal",
              templateName: "Yearbook Candids", templateVersion: 1,
              smartFieldCount: 2, completedFieldCount: 7),
        .init(id: "r6", date: day(-8), school: "District Office", mileage: 9.8,
              photoCount: 0, vehicle: "company"),
        .init(id: "r7", date: day(-14), school: "Riverside Middle School", mileage: 18.2,
              photoCount: 5, vehicle: "personal",
              templateName: "Sports Day", templateVersion: 1,
              smartFieldCount: 4, completedFieldCount: 12),
        .init(id: "r8", date: day(-21), school: "Pine Ridge Elementary", mileage: 33.1,
              photoCount: 2, vehicle: "personal"),
    ]

    /// Templates. Note every one carries a real shoot type and description here —
    /// which is what the screen was DESIGNED for and what it has never shown,
    /// because six model properties are outside CodingKeys (finding R13).
    static let reportTemplates: [LabReportTemplate] = [
        .init(id: "tp1", name: "Sports Day", detail: "Fall and winter sports, team and individual.",
              shootType: "sports", fieldCount: 14, smartFieldCount: 4, isDefault: true, version: 3),
        .init(id: "tp2", name: "Sports League", detail: "Weekend league work, multiple teams per session.",
              shootType: "sports", fieldCount: 11, smartFieldCount: 3, isDefault: false, version: 2),
        .init(id: "tp3", name: "Yearbook Candids", detail: nil,
              shootType: "yearbook", fieldCount: 9, smartFieldCount: 2, isDefault: false, version: 1),
        .init(id: "tp4", name: "Yearbook Groups and Clubs", detail: "One entry per group, with the advisor's name.",
              shootType: "yearbook", fieldCount: 12, smartFieldCount: 2, isDefault: true, version: 4),
        .init(id: "tp5", name: "Classroom Groups", detail: "Class composites and teacher portraits.",
              shootType: "portraits", fieldCount: 16, smartFieldCount: 5, isDefault: false, version: 2),
        .init(id: "tp6", name: "Dr. Office Head Shots", detail: "Commercial work — invoice reference required.",
              shootType: "commercial", fieldCount: 8, smartFieldCount: 1, isDefault: false, version: 1),
    ]

    /// Notes in CREATION order — oldest first, which is what the full screen
    /// does and the opposite of what the iPad widget does. Both are real.
    static let photoshootNotes: [LabPhotoshootNote] = [
        .init(id: "n1", timestamp: at(7, 52), school: "Lincoln High School",
              text: "Gym window blows out the left side after ten. Shot the stage end instead — flag it for next year.",
              photoCount: 2, syncedToServer: true),
        .init(id: "n2", timestamp: at(11, 20), school: "Lincoln High School",
              text: "Two students missed the session, office has the list. Retakes are the 14th.",
              photoCount: 0),
        // No school yet — this is the note that opens the "which school?" dialog.
        .init(id: "n3", timestamp: at(14, 5), school: "",
              text: "", photoCount: 0),
        .init(id: "n4", timestamp: at(9, 15, dayOffset: -1), school: "Riverside Middle School",
              text: "Backdrop stand from Kit A is bent. Used the loaner.",
              photoCount: 1, submitted: true, syncedToServer: true,
              submittedAt: at(16, 40, dayOffset: -1)),
    ]

    /// The eight sections of the standard daily job report, with the ONE that is
    /// actually required marked as such.
    ///
    /// The live form draws a progress bar over EIGHT sections with a denominator
    /// of SEVEN, ticks sections by rules that gate nothing, and then blocks
    /// submission on exactly one field: the vehicle. The mockup has to be able to
    /// draw both the honest version and the current one.
    static let reportSections: [(title: String, symbol: String, tint: Color, required: Bool, done: Bool)] = [
        ("Basic Information", "info.circle", .blue, false, true),
        ("Photoshoot Note", "note.text", .purple, false, true),
        ("Schools & Mileage", "building.2", .green, true, false),
        ("Job Description", "list.bullet", .orange, false, true),
        ("Extra Items", "plus.circle", .pink, false, false),
        ("Scan Status", "barcode.viewfinder", .teal, false, false),
        ("Notes", "text.bubble", .indigo, false, true),
        ("Photos", "photo", .red, false, true),
    ]

    /// The 22 job descriptions, verbatim and in the shipped order. A redesign
    /// that reorders or prunes this list is changing a business vocabulary, not
    /// a layout, so it is here in full where a mockup can be checked against it.
    static let jobDescriptionOptions = [
        "Fall Original Day", "Fall Makeup Day", "Classroom Groups", "Fall Sports",
        "Winter Sports", "Spring Sports", "Spring Photos", "Homecoming", "Prom",
        "Graduation", "Yearbook Candid's", "Yearbook Groups and Clubs",
        "Sports League", "District Office Photos", "Banner Photos",
        "In Studio Photos", "School Board Photos", "Dr. Office Head Shots",
        "Dr. Office Cards", "Dr. Office Candid's", "Deliveries", "NONE",
    ]

    /// The 12 extra items, verbatim and in the shipped order.
    static let extraItemOptions = [
        "Underclass Makeup", "Staff Makeup", "ID card Images", "Sports Makeup",
        "Class Groups", "Yearbook Groups and Clubs", "Class Candids",
        "Students from other schools", "Siblings", "Office Staff Photos",
        "Deliveries", "NONE",
    ]

    /// Every field type the template form can render, with a real label — so the
    /// dynamic form can be judged against the whole vocabulary rather than the
    /// three types a nice-looking sample would have contained.
    static let templateFieldTypes: [(type: String, label: String, required: Bool, readOnly: Bool)] = [
        ("user_name", "Photographer", false, true),
        ("date_auto", "Date", false, true),
        ("time_auto", "Start time", false, true),
        ("text", "Team or group name", true, false),
        ("email", "Coach email", false, false),
        ("phone", "Coach phone", false, false),
        ("number", "Athletes photographed", true, false),
        ("currency", "Cash collected", false, false),
        ("select", "Sport", true, false),
        ("multiselect", "Packages sold", false, false),
        ("radio", "Cards turned in", true, false),
        ("toggle", "Background used", false, false),
        ("date", "Retake date", false, false),
        ("time", "Wrap time", false, false),
        ("textarea", "Notes for the lab", false, false),
        ("school_name", "School", false, true),
        ("mileage", "Mileage", false, true),
        ("photo_count", "Photos attached", false, true),
        ("weather_conditions", "Weather", false, true),
        ("file", "Reference photos", false, false),
    ]
}

// MARK: - Shared lab helper, kept when its mockup went

/// Binds a card with a kit's tape colour.
///
/// This lived in EquipmentMockup.swift and moved here when AMB.6 closed batch 1
/// and deleted that mockup — the specimen sheet still uses it, so it is
/// HARNESS-level rather than a phase's scaffolding. Same call AMB.5 made when it
/// kept the shared time helper.
///
/// A helper hiding inside a phase's mockup is worth noticing: deleting the
/// mockup broke the build, which is the cheap version of that lesson.
///
/// Rainbow is a real tape colour (`KitTemplate.isRainbow`, special-cased in three
/// production views), so a band drawn as a flat `Color(hex:)` renders garbage.
struct LabKitEdge: ViewModifier {
    /// A hex string, or the literal "rainbow", or nil for an item in no kit.
    let hex: String?
    let density: AmbientDensity

    private var isRainbow: Bool { hex?.lowercased() == "rainbow" }

    /// Branches on a value fixed at the call site — a row's kit does not change
    /// under it — so the `_ConditionalContent` identity switch cannot fire
    /// mid-animation. Same reasoning as `AmbientGlow`.
    func body(content: Content) -> some View {
        if let hex {
            content
                .overlay(alignment: .leading) {
                    Group {
                        if isRainbow {
                            Rectangle().fill(LabKitEdge.rainbow)
                        } else {
                            Rectangle().fill(Color(hex: hex))
                        }
                    }
                    .frame(width: 4)
                }
                // Clipping the CARD, not the band: this is what makes the band
                // follow the corner curve instead of overhanging it.
                .clipShape(RoundedRectangle(cornerRadius: density.cornerRadius,
                                            style: .continuous))
        } else {
            content
        }
    }

    static let rainbow = LinearGradient(
        colors: [.red, .orange, .yellow, .green, .blue, .purple],
        startPoint: .top, endPoint: .bottom)
}

extension View {
    /// No-op when the thing is in no kit.
    func labKitEdge(_ hex: String?, density: AmbientDensity) -> some View {
        modifier(LabKitEdge(hex: hex, density: density))
    }
}
