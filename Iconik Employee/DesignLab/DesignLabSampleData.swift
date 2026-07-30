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
// MARK: - Time Off (AMB.8)
//
// THE LAB NO LONGER OWNS A STATUS OR REASON VOCABULARY. `LabTimeOffStatus` and
// `LabTimeOffReason` used to live here with their own labels, colours and icons,
// carrying a comment promising they matched the app. They are DELETED: the
// mockup now resolves both through `TimeOffStatusDisplay` / `TimeOffReasonDisplay`
// in `TimeOff/TimeOffKit.swift`, which is the code the real screens draw with and
// which `scripts/test_timeoff_rules.sh` runs.
//
// Same move AMB.7 made when `DesignLabSampleData` stopped keeping its own copy of
// the 22 job descriptions: a private copy in the lab is a second source of truth,
// and a second source of truth is drift waiting for a quiet week.

/// One request. Fields taken from what the real card and detail actually render,
/// including the three conditional attribution lines (approved by / in review by
/// / denied by, with its own indented reason line).
/// One sample request.
///
/// THE STATUS AND REASON ARE RAW STRINGS, exactly as the shared database stores
/// them — and deliberately so. The lab feeds the same values a real row holds and
/// lets the PRODUCTION resolvers render them, which means the mockup exercises the
/// real cross-client parsing rather than a tidied-up copy of it. Two of the rows
/// below carry the strings the WEB app writes, so the operator can see on a device
/// that a web-created request no longer draws a grey ellipsis.
///
/// Every label, duration and date string comes from `TimeOffCardModel`, built the
/// same way `TimeOffRequest.cardModel` builds it — no second implementation.
struct LabTimeOffRequest: Identifiable {
    let id: String
    let photographer: String
    /// The RAW stored value, e.g. "underReview" or the web app's "partially_approved".
    let statusRaw: String
    /// The RAW stored value, e.g. "vacation" (iOS) or "Sick Leave" (web).
    let reasonRaw: String
    let startDate: Date
    let endDate: Date
    let isPartialDay: Bool
    var startTime: TimeOfDay?
    var endTime: TimeOfDay?
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

    /// Built through the SAME rule type the app uses, so the inclusive day count
    /// cannot be one thing in the lab and another in production.
    var span: TimeOffSpan {
        TimeOffSpan(startDay: startDate, endDay: endDate,
                    isPartialDay: isPartialDay, start: startTime, end: endTime)
    }

    /// What the shared card draws. Mirrors `TimeOffRequest.cardModel`.
    var cardModel: TimeOffCardModel {
        let status = TimeOffStatusDisplay.from(raw: statusRaw)
        return TimeOffCardModel(
            id: id,
            photographer: photographer,
            status: status,
            reason: TimeOffReasonDisplay.from(raw: reasonRaw),
            dateLabel: dateLabel,
            timeLabel: timeLabel,
            durationLabel: durationLabel,
            isPartialDay: isPartialDay,
            dayCount: span.dayCount,
            notes: notes,
            usesPTO: usesPTO,
            ptoHours: ptoHours,
            attribution: status.ruleStatus.flatMap {
                TimeOffAttribution(name: actionedBy, date: actionedAt, status: $0)
            },
            denialReason: denialReason,
            createdAt: createdAt)
    }

    var durationLabel: String {
        if isPartialDay {
            guard let hours = span.partialHours else { return "Time not set" }
            if hours == 1 { return "1 hour" }
            if hours.truncatingRemainder(dividingBy: 1) == 0 { return "\(Int(hours)) hours" }
            return String(format: "%.1f hours", hours)
        }
        return span.dayCount == 1 ? "1 day" : "\(span.dayCount) days"
    }

    var dateLabel: String {
        // THROUGH THE PRODUCTION FORMATTER. This built its own `monthDay` string
        // while production moved to `TimeOffDateLabel`, so the lab could no longer
        // draw the out-of-year case that formatter exists for — the exact drift
        // the "design lives in production code the lab imports" rule forbids.
        TimeOffDateLabel.rangeString(from: startDate,
                                     to: endDate,
                                     collapsed: isPartialDay || span.dayCount == 1)
    }

    var timeLabel: String {
        guard isPartialDay, let startTime, let endTime else { return "Full day" }
        return "\(startTime.displayString) – \(endTime.displayString)"
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
        .init(id: "t1", photographer: "You", statusRaw: "pending", reasonRaw: "vacation",
              startDate: day(24), endDate: day(28), isPartialDay: false,
              notes: "Family trip — booked the flights already.",
              ptoHours: 40, createdAt: day(-1)),
        // Partial day, and the one that does NOT have the PTO to cover it.
        .init(id: "t2", photographer: "You", statusRaw: "pending", reasonRaw: "personal",
              startDate: day(9), endDate: day(9), isPartialDay: true,
              startTime: TimeOfDay(hour: 13, minute: 0), endTime: TimeOfDay(hour: 17, minute: 0),
              notes: nil, ptoHours: 4, createdAt: day(-2)),
        // WEB VOCABULARY. "Family Emergency" is what the web app writes; iOS
        // writes "emergency". Before AMB.8 this row drew a grey ellipsis and read
        // "Other". It must now show the emergency icon and label.
        .init(id: "t3", photographer: "You", statusRaw: "underReview", reasonRaw: "Family Emergency",
              startDate: day(16), endDate: day(17), isPartialDay: false,
              notes: "Parent-teacher conferences both mornings.",
              ptoHours: 16, actionedBy: "Alex Fontaine", actionedAt: day(-3),
              createdAt: day(-5)),
        .init(id: "t4", photographer: "You", statusRaw: "approved", reasonRaw: "sick",
              startDate: day(-8), endDate: day(-8), isPartialDay: false,
              notes: nil, ptoHours: 8,
              actionedBy: "Alex Fontaine", actionedAt: day(-9), createdAt: day(-10)),
        // Approved but the approver name never came back — the attribution line is
        // conditional on BOTH the name and the date, so this row must draw WITHOUT
        // it rather than showing a bare "Approved by".
        .init(id: "t5", photographer: "You", statusRaw: "approved", reasonRaw: "vacation",
              startDate: day(-30), endDate: day(-26), isPartialDay: false,
              notes: "Spring break.", ptoHours: 40, createdAt: day(-45)),
        // A WEB DENIAL: the web app stamps the APPROVAL columns and leaves the
        // denial ones NULL, so there is a denial reason and NO denier. The reason
        // must still draw — before AMB.8 it was nested inside the attribution
        // block and vanished with it.
        .init(id: "t6", photographer: "You", statusRaw: "denied", reasonRaw: "Personal Day",
              startDate: day(-14), endDate: day(-14), isPartialDay: false,
              notes: nil, usesPTO: false,
              denialReason: "Three photographers already off that day and it is a fall original day.",
              createdAt: day(-20)),
        .init(id: "t7", photographer: "You", statusRaw: "cancelled", reasonRaw: "other",
              startDate: day(-40), endDate: day(-39), isPartialDay: false,
              notes: "Changed my mind.", usesPTO: false, createdAt: day(-50)),
        // A STATUS NEITHER CLIENT'S ENUM KNOWS. The web app really does write
        // this. Before AMB.8 it rendered as an orange "Pending" badge with live
        // Edit and Cancel buttons on a request somebody had already decided.
        .init(id: "t8", photographer: "You", statusRaw: "partially_approved", reasonRaw: "Medical Appointment",
              startDate: day(-3), endDate: day(-2), isPartialDay: false,
              notes: "Follow-up appointment.", ptoHours: 16,
              createdAt: day(-8)),
    ]

    /// The manager queue. THE ORDER IS THE POINT: pending and in-review sort
    /// OLDEST FIRST because a manager works a queue, which is the deliberate
    /// reverse of the employee list. History sorts by when it was ACTIONED.
    static let approvalQueue: [LabTimeOffRequest] = [
        .init(id: "a1", photographer: "Sam Okafor", statusRaw: "pending", reasonRaw: "sick",
              startDate: day(1), endDate: day(1), isPartialDay: false,
              notes: "Woke up with it — sorry for the short notice.",
              ptoHours: 8, createdAt: day(-6)),
        .init(id: "a2", photographer: "Priya Nair", statusRaw: "pending", reasonRaw: "Vacation",
              startDate: day(33), endDate: day(40), isPartialDay: false,
              notes: "Wedding, out of state. Booked a year ago.",
              ptoHours: 48, createdAt: day(-4)),
        .init(id: "a3", photographer: "Devon Wright", statusRaw: "pending", reasonRaw: "personal",
              startDate: day(5), endDate: day(5), isPartialDay: true,
              startTime: TimeOfDay(hour: 8, minute: 0), endTime: TimeOfDay(hour: 10, minute: 30),
              notes: nil, ptoHours: 2.5, createdAt: day(-1)),
        .init(id: "a4", photographer: "Maria Alvarez", statusRaw: "underReview", reasonRaw: "emergency",
              startDate: day(12), endDate: day(13), isPartialDay: false,
              notes: "Can move it if the Lincoln retakes land that week.",
              ptoHours: 16, actionedBy: "You", actionedAt: day(-2), createdAt: day(-7)),
        .init(id: "a5", photographer: "June Castillo", statusRaw: "approved", reasonRaw: "vacation",
              startDate: day(-3), endDate: day(-2), isPartialDay: false,
              notes: nil, ptoHours: 16,
              actionedBy: "You", actionedAt: day(-5), createdAt: day(-12)),
        .init(id: "a6", photographer: "Alex Fontaine", statusRaw: "denied", reasonRaw: "other",
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

// MARK: - Reports family (AMB.7) — DELETED
//
// AMB.7's sample data went with its two mockups at that phase's close, once the
// operator confirmed BOTH device smokes on the converted screens. A validation
// reference outlives the port it validates, not the phase that built it — so it
// is kept while a port is still being checked and deleted the moment it is not.
//
// The one thing that did NOT live here is the part that mattered: the 22 job
// descriptions and 12 extra items are in Reports/ReportOptions.swift, which the
// APP builds and this file used to forward to. That is the whole mechanism —
// the design lives in production code the lab imports, so deleting the lab
// takes nothing real with it.

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

// MARK: - Job box / NFC (AMB.11, batch 4)

/// One job box and its WHOLE scan log.
///
/// `job_boxes` is an append-only scan log (`JobBox/JobBoxProgressRules.swift`), so a
/// box IS its rows. The lab therefore stores rows, not a status — a sample set that
/// carried one status per box could not exercise the shipped meter at all, because
/// the meter's two load-bearing rules (position is not completeness; progress means
/// the CURRENT trip) are both statements about a LOG.
///
/// The scan points are `JobBoxScanPoint`, the production type, so the reading below
/// is built by the same code the shift detail and the manager tracker use.
struct LabJobBox: Identifiable {
    let id: String
    let boxNumber: String
    let school: String
    /// Nil is real and common — 336 of 1,059 live rows have a NULL or empty
    /// photographer, and a Packed row usually has none because packing happens
    /// before anyone is assigned.
    let photographer: String?
    /// Every row for this box, across all time — including a previous trip where
    /// the sample has one.
    let scans: [JobBoxScanPoint]
    /// Nil where a box was never linked to a session — the case the pickup guard
    /// exists for.
    var shiftUid: String?

    /// Through the PRODUCTION rules: this cuts the log at the last Packed scan.
    var reading: JobBoxProgressReading { JobBoxProgressReading(log: scans) }

    /// The whole-log latest, which is what the tracker's "Updated …" line reports.
    var latest: JobBoxScanPoint? { scans.max { $0.at < $1.at } }

    var stage: JobBoxTripStage? { reading.furthest }
}

/// An SD card scan row. Shaped like `records`, which the live schema proves has
/// exactly ten columns and **no `photographer`** — so this struct deliberately has
/// no photographer either. A lab type carrying a field the table cannot hold is how
/// a mockup comes to promise a dead capability.
struct LabSDRecord: Identifiable {
    let id: String
    let cardNumber: String
    let school: String
    /// The stored value, from ScanView's hardcoded list.
    let status: String
    let at: Date
    /// "Jason's house" / "Andy's house" — the two hardcoded personal names in
    /// shipped UI, written only when the status is `uploaded`.
    var uploadedFrom: String?
}

extension DesignLabSampleData {

    /// Boxes across the REAL live distribution, which is the only reason this set
    /// can judge the meter. Live over the 351 boxes carrying a shift (2026-07-29):
    /// 199 Packed only, 47 Packed + Picked Up, 35 walking all four, 31 Packed
    /// straight to Turned In, 22 skipping Left Job, four never packed at all.
    ///
    /// Seeded to contain: a box that walked ALL FOUR stages, a box that SKIPPED two,
    /// a box that skipped one, a packed-only box with no photographer, a box that
    /// was NEVER packed, a box stalled in Left Job past the 12-hour threshold, a box
    /// on its SECOND trip (so `currentTrip` has a seam to cut), and a box with no
    /// session link at all.
    static let jobBoxes: [LabJobBox] = [
        // ALL FOUR STAGES. The 10%-of-boxes case, and the only one where every
        // notch on the scrubber is filled.
        LabJobBox(id: "jb-3028", boxNumber: "3028", school: "Riverside Elementary",
                  photographer: "Maria Alvarez",
                  scans: [
                    JobBoxScanPoint(stage: .packed, who: nil, at: at(6, 40, dayOffset: -2)),
                    JobBoxScanPoint(stage: .pickedUp, who: "Maria Alvarez", at: at(7, 15, dayOffset: -2)),
                    JobBoxScanPoint(stage: .leftJob, who: "Maria Alvarez", at: at(15, 2, dayOffset: -2)),
                    JobBoxScanPoint(stage: .turnedIn, who: "Maria Alvarez", at: at(17, 30, dayOffset: -2))
                  ],
                  shiftUid: "s-riverside"),
        // SKIPS TWO — Packed straight to Turned In. The old bars drew this with
        // four ticks, two of them fiction.
        LabJobBox(id: "jb-3031", boxNumber: "3031", school: "Northgate Middle School",
                  photographer: "Devon Wright",
                  scans: [
                    JobBoxScanPoint(stage: .packed, who: nil, at: at(6, 30, dayOffset: -4)),
                    JobBoxScanPoint(stage: .turnedIn, who: "Devon Wright", at: at(18, 5, dayOffset: -4))
                  ],
                  shiftUid: "s-northgate"),
        // SKIPS ONE — no Left Job scan.
        LabJobBox(id: "jb-3044", boxNumber: "3044", school: "Westbrook High School",
                  photographer: "Priya Nair",
                  scans: [
                    JobBoxScanPoint(stage: .packed, who: nil, at: at(6, 45, dayOffset: -1)),
                    JobBoxScanPoint(stage: .pickedUp, who: "Priya Nair", at: at(7, 40, dayOffset: -1)),
                    JobBoxScanPoint(stage: .turnedIn, who: "Priya Nair", at: at(16, 55, dayOffset: -1))
                  ],
                  shiftUid: "s-westbrook"),
        // PACKED ONLY, no photographer — the single most common live shape, and the
        // one an old bar drew inert because `.packed` fell through to a grey default.
        LabJobBox(id: "jb-3050", boxNumber: "3050", school: "Riverside Elementary",
                  photographer: nil,
                  scans: [
                    JobBoxScanPoint(stage: .packed, who: nil, at: at(16, 10, dayOffset: -1))
                  ],
                  shiftUid: "s-riverside-2"),
        // STALLED IN LEFT JOB, 26 hours — past the 12-hour alert threshold, so the
        // Scan screen's Job Box Alert banner has something real to fire on.
        LabJobBox(id: "jb-3055", boxNumber: "3055", school: "Lincoln High School",
                  photographer: "Sam Okafor",
                  scans: [
                    JobBoxScanPoint(stage: .packed, who: nil, at: at(6, 20, dayOffset: -2)),
                    JobBoxScanPoint(stage: .pickedUp, who: "Sam Okafor", at: at(7, 5, dayOffset: -2)),
                    JobBoxScanPoint(stage: .leftJob, who: "Sam Okafor", at: at(14, 30, dayOffset: -2))
                  ],
                  shiftUid: "s-lincoln"),
        // NEVER PACKED — four live boxes look like this, and there is then no seam
        // for `currentTrip` to cut on, so the whole log is one trip.
        LabJobBox(id: "jb-3061", boxNumber: "3061", school: "Northgate Middle School",
                  photographer: "June Castillo",
                  scans: [
                    JobBoxScanPoint(stage: .pickedUp, who: "June Castillo", at: at(8, 12, dayOffset: -6))
                  ],
                  shiftUid: nil),
        // SECOND TRIP. Two complete trips in one log: the reading must show only
        // the second, and the tracker groups by box number across ALL TIME, which
        // is exactly why the seam matters.
        LabJobBox(id: "jb-3072", boxNumber: "3072", school: "Westbrook High School",
                  photographer: "Alex Fontaine",
                  scans: [
                    JobBoxScanPoint(stage: .packed, who: nil, at: at(6, 30, dayOffset: -48)),
                    JobBoxScanPoint(stage: .pickedUp, who: "Devon Wright", at: at(7, 30, dayOffset: -48)),
                    JobBoxScanPoint(stage: .leftJob, who: "Devon Wright", at: at(15, 0, dayOffset: -48)),
                    JobBoxScanPoint(stage: .turnedIn, who: "Devon Wright", at: at(17, 0, dayOffset: -48)),
                    JobBoxScanPoint(stage: .packed, who: nil, at: at(6, 30, dayOffset: -1)),
                    JobBoxScanPoint(stage: .pickedUp, who: "Alex Fontaine", at: at(7, 20, dayOffset: -1))
                  ],
                  shiftUid: "s-westbrook-2"),
        // NO SESSION LINK on a live pickup — the `.noJobLink` pickup warning's case.
        LabJobBox(id: "jb-3080", boxNumber: "3080", school: "Lincoln High School",
                  photographer: "Maria Alvarez",
                  scans: [
                    JobBoxScanPoint(stage: .packed, who: nil, at: at(6, 15, dayOffset: -3)),
                    JobBoxScanPoint(stage: .pickedUp, who: "Maria Alvarez", at: at(7, 50, dayOffset: -3))
                  ],
                  shiftUid: nil),
    ]

    /// The four job-box statuses and their LIVE counts (1,059 rows, zero outside
    /// the four) — so the Statistics distribution is judged against real weights
    /// rather than a tidy quarter each.
    static let jobBoxStatusCounts: [(status: JobBoxTripStage, count: Int)] = [
        (.packed, 674), (.pickedUp, 160), (.turnedIn, 159), (.leftJob, 66)
    ]

    /// SD statuses and their live counts. **`Personal` is offered in every picker
    /// and has ZERO rows** — kept in the list precisely so the design has to decide
    /// what to do with an option nobody has ever used.
    static let sdStatusCounts: [(status: String, count: Int)] = [
        ("Job Box", 1791), ("Cleared", 944), ("Uploaded", 921),
        ("Camera", 272), ("Envelope", 232), ("Camera Bag", 8), ("Personal", 0)
    ]

    /// SD rows for the search list and the history bubbles: one of each interesting
    /// shape, including both house flags and a card whose number has a leading zero
    /// (search is an exact string `.eq`, so "0301" and "301" are different cards).
    static let sdRecords: [LabSDRecord] = [
        LabSDRecord(id: "sd1", cardNumber: "1042", school: "Riverside Elementary",
                    status: "Uploaded", at: at(19, 20, dayOffset: -1),
                    uploadedFrom: "Andy's house"),
        LabSDRecord(id: "sd2", cardNumber: "1042", school: "Riverside Elementary",
                    status: "Envelope", at: at(17, 5, dayOffset: -1)),
        LabSDRecord(id: "sd3", cardNumber: "1103", school: "Westbrook High School",
                    status: "Job Box", at: at(6, 55, dayOffset: -1)),
        LabSDRecord(id: "sd4", cardNumber: "1188", school: "Iconik",
                    status: "Cleared", at: at(9, 30, dayOffset: -2)),
        LabSDRecord(id: "sd5", cardNumber: "1207", school: "Northgate Middle School",
                    status: "Camera", at: at(8, 2, dayOffset: -3)),
        LabSDRecord(id: "sd6", cardNumber: "0301", school: "Lincoln High School",
                    status: "Camera Bag", at: at(11, 45, dayOffset: -9)),
        LabSDRecord(id: "sd7", cardNumber: "1990", school: "Riverside Elementary",
                    status: "Uploaded", at: at(21, 10, dayOffset: -5),
                    uploadedFrom: "Jason's house"),
    ]
}

// MARK: - Manager features (AMB.12, batch 4)

/// A row from `getTeamMembers`, which — unlike `getPhotographers` — returns
/// INACTIVE users too, and carries only the first name into the flag picker.
struct LabTeamMember: Identifiable {
    let id: String
    let firstName: String
    let fullName: String
    let isActive: Bool
}

/// A flagged user as the unflag list renders them: first name, the note, and who
/// flagged them. The list SORTS by full name and DISPLAYS the first name, which is
/// why two people sharing a first name look randomly ordered.
struct LabFlaggedUser: Identifiable {
    let id: String
    let firstName: String
    let fullName: String
    let note: String
    let flaggedBy: String
    let flaggedAt: Date
}

/// One day of a photographer's mileage, for the manager's employee detail — a
/// 14-day window, date-descending, with the company/personal split that is hidden
/// when company mileage is zero.
struct LabManagerMileageDay: Identifiable {
    let id: String
    let date: Date
    let school: String
    let miles: Double
    let isCompany: Bool
    let photoCount: Int
}

extension DesignLabSampleData {

    /// The flag picker's source. Seeded with the two shapes that break it: an
    /// INACTIVE user (who is offered anyway, because this screen calls
    /// `getTeamMembers`), and TWO people called Chris (who are indistinguishable,
    /// because only `firstName` is carried into the model).
    static let teamMembers: [LabTeamMember] = [
        LabTeamMember(id: "u1", firstName: "Maria", fullName: "Maria Alvarez", isActive: true),
        LabTeamMember(id: "u2", firstName: "Devon", fullName: "Devon Wright", isActive: true),
        LabTeamMember(id: "u3", firstName: "Chris", fullName: "Chris Bhatt", isActive: true),
        LabTeamMember(id: "u4", firstName: "Chris", fullName: "Chris Okonkwo", isActive: true),
        LabTeamMember(id: "u5", firstName: "Priya", fullName: "Priya Nair", isActive: true),
        LabTeamMember(id: "u6", firstName: "Sam", fullName: "Sam Okafor", isActive: false),
        LabTeamMember(id: "u7", firstName: "June", fullName: "June Castillo", isActive: true),
    ]

    /// Flagged users: a long note that must wrap, a one-word note, and the two
    /// Chrises again — this list sorts by full name and shows first names.
    static let flaggedUsers: [LabFlaggedUser] = [
        LabFlaggedUser(id: "f1", firstName: "Chris", fullName: "Chris Bhatt",
                       note: "Three Lincoln retake cards came back with no job box scan at all — please scan the box in and out on every job this week so the tracker matches the cards.",
                       flaggedBy: "Alex Fontaine", flaggedAt: at(16, 20, dayOffset: -2)),
        LabFlaggedUser(id: "f2", firstName: "Chris", fullName: "Chris Okonkwo",
                       note: "Mileage report missing for 7/22.",
                       flaggedBy: "Alex Fontaine", flaggedAt: at(9, 5, dayOffset: -5)),
        LabFlaggedUser(id: "f3", firstName: "Devon", fullName: "Devon Wright",
                       note: "Call the office.",
                       flaggedBy: "June Castillo", flaggedAt: at(11, 45, dayOffset: -1)),
    ]

    /// One photographer's 14-day mileage, for the manager employee detail: a
    /// company day, a day with more than five photos (the `+N` overflow), and a
    /// zero-photo day.
    static let managerMileageDays: [LabManagerMileageDay] = [
        LabManagerMileageDay(id: "m1", date: day(-1), school: "Riverside Elementary",
                             miles: 24.6, isCompany: false, photoCount: 7),
        LabManagerMileageDay(id: "m2", date: day(-2), school: "Northgate Middle School",
                             miles: 41.2, isCompany: true, photoCount: 3),
        LabManagerMileageDay(id: "m3", date: day(-4), school: "Westbrook High School",
                             miles: 18.0, isCompany: false, photoCount: 0),
        LabManagerMileageDay(id: "m4", date: day(-7), school: "Lincoln High School",
                             miles: 33.9, isCompany: false, photoCount: 2),
        LabManagerMileageDay(id: "m5", date: day(-11), school: "Riverside Elementary",
                             miles: 24.6, isCompany: false, photoCount: 5),
    ]
}

// MARK: - Training (AMB.12, batch 4)

/// A published critique, shaped like `Critique` in `Models.swift` — including the
/// three different fields the app uses for one asset (`thumbnailUrl` singular on the
/// cards, `thumbnailUrls` and `imageUrls` plural in the detail) and the `imageCount`
/// that defaults to 0 when the column is NULL.
struct LabCritique: Identifiable {
    let id: String
    /// The RAW stored value. `"example"` means good; **anything else renders as a
    /// criticism**, including a value neither client wrote.
    let exampleType: String
    let notes: String?
    let submitter: String
    /// Decoded by the model and displayed nowhere today.
    let submitterEmail: String
    let createdAt: Date
    /// What the row's `image_count` column holds. 0 is the NULL default, and it
    /// suppresses both the "n of m" counter and the whole thumbnail strip.
    let imageCount: Int
    /// How many images the row REALLY has — the number `imageUrls` would return.
    let realImageCount: Int
    let forRole: String

    var isGoodExample: Bool { exampleType == "example" }
}

extension DesignLabSampleData {

    /// Seeded with every case that decides the Training design: a good example, a
    /// needs-improvement example, a multi-image row whose `image_count` is 0 (so
    /// production hides the strip on a row that HAS a strip), a row with an
    /// `example_type` neither client writes (which silently renders as a
    /// criticism), a row with NO notes, and a LEGACY row with zero images — the row
    /// on which Save and Share crash today.
    static let critiques: [LabCritique] = [
        LabCritique(id: "cr1", exampleType: "example",
                    notes: "Exactly the separation we want on a class group — front row knees turned in, back row shoulders square.",
                    submitter: "Alex Fontaine", submitterEmail: "alex@iconikphoto.com",
                    createdAt: at(15, 10, dayOffset: -1),
                    imageCount: 3, realImageCount: 3, forRole: "Class Groups"),
        LabCritique(id: "cr2", exampleType: "improvement",
                    notes: "Backdrop crease is in every frame from this set. Steam it or move the stand a foot forward.",
                    submitter: "June Castillo", submitterEmail: "june@iconikphoto.com",
                    createdAt: at(9, 30, dayOffset: -3),
                    imageCount: 2, realImageCount: 2, forRole: "Underclass"),
        // image_count NULL -> 0, but the row really has four images. Today the
        // counter and the entire thumbnail strip vanish on this row.
        LabCritique(id: "cr3", exampleType: "example",
                    notes: "Good recovery on the gym window — this is the angle to use after ten.",
                    submitter: "Alex Fontaine", submitterEmail: "alex@iconikphoto.com",
                    createdAt: at(17, 45, dayOffset: -6),
                    imageCount: 0, realImageCount: 4, forRole: "Sports"),
        // An example_type neither client writes. `type == "example"` is the whole
        // test, so this draws as "Needs Improvement" with no way to tell.
        LabCritique(id: "cr4", exampleType: "good_example",
                    notes: "Nice work on the senior set.",
                    submitter: "June Castillo", submitterEmail: "june@iconikphoto.com",
                    createdAt: at(12, 0, dayOffset: -9),
                    imageCount: 1, realImageCount: 1, forRole: "Seniors"),
        // No notes at all.
        LabCritique(id: "cr5", exampleType: "improvement", notes: nil,
                    submitter: "Alex Fontaine", submitterEmail: "alex@iconikphoto.com",
                    createdAt: at(8, 15, dayOffset: -14),
                    imageCount: 1, realImageCount: 1, forRole: "Retakes"),
        // THE LEGACY ROW: zero images. `imageUrls` defaults to [] and the detail
        // indexes it unguarded, so Save and Share crash here today.
        LabCritique(id: "cr6", exampleType: "example",
                    notes: "Older critique — the image was attached before the app stored a list.",
                    submitter: "Alex Fontaine", submitterEmail: "alex@iconikphoto.com",
                    createdAt: at(10, 0, dayOffset: -40),
                    imageCount: 0, realImageCount: 0, forRole: "Class Groups"),
    ]
}

// MARK: - Settings (AMB.12, batch 4)

/// A school as School Info renders it, plus what School Detail adds. Mileage is
/// OPTIONAL because the live row shows `--` for both a genuine zero AND a failed
/// per-school query — the two are indistinguishable today.
struct LabSchoolInfo: Identifiable {
    let id: String
    let name: String
    let address: String
    /// Nil where the school was never geocoded — the coordinates row and the map
    /// are conditional on this, and coordinates can never be edited.
    let coordinates: String?
    /// Nil means the mileage lookup returned nothing — NOT zero miles.
    let seasonMiles: Double?
    let reportCount: Int
    /// Location photo labels. The delete button beside each has no confirmation
    /// and never removes the storage object.
    let photoLabels: [String]
}

extension DesignLabSampleData {

    /// Seeded with the shapes that decide the Settings design: a school with no
    /// coordinates (no map, unfixable), a school with NO mileage figure at all (the
    /// `--` that means either zero or a failure), a school with a long name that has
    /// to truncate, and a school with several location photos.
    static let schoolsInfo: [LabSchoolInfo] = [
        LabSchoolInfo(id: "sc1", name: "Riverside Elementary",
                      address: "1200 Riverside Dr, Springfield",
                      coordinates: "39.781721, -89.650148",
                      seasonMiles: 246.4, reportCount: 11,
                      photoLabels: ["Gym entrance", "Load-in door", "Parking"]),
        LabSchoolInfo(id: "sc2", name: "Northgate Middle School",
                      address: "88 Northgate Ave, Springfield",
                      coordinates: "39.812004, -89.611930",
                      seasonMiles: 0, reportCount: 3, photoLabels: []),
        // No mileage figure — the row that renders "Mileage: --" today, which means
        // either a real zero or a failed query and never says which.
        LabSchoolInfo(id: "sc3", name: "Westbrook High School",
                      address: "4400 Westbrook Pkwy, Springfield",
                      coordinates: nil, seasonMiles: nil, reportCount: 0,
                      photoLabels: ["Front office"]),
        LabSchoolInfo(id: "sc4", name: "Lincoln High School — Performing Arts Annex",
                      address: "9 Lincoln Sq, Springfield",
                      coordinates: "39.799512, -89.644001",
                      seasonMiles: 118.7, reportCount: 6, photoLabels: []),
    ]
}
