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

// MARK: - The kit edge

/// The coloured band down the left of a row that says which kit a thing is in.
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

// EVERYTHING BELOW THIS POINT WAS DELETED AT AMB.12'S CLOSE (2026-08-01).
//
// It was the sample data for six mockups that no longer exist — Chat, Time Off,
// Class Groups, Yearbook, Manager Tools, Training and Settings — each deleted at
// its own phase's close once the operator had smoked the converted screens. Data
// that only ever fed a deleted screen is not scaffolding, it is a fossil: it
// still compiles, so nothing complains, and the next person to open the lab has
// to work out which of it is live.
//
// What remains above is what the two surviving FOUNDATION mockups actually draw:
// Equipment's real row content, the crew avatars, and the pill vocabulary. The
// specimen sheet and the palette are not a phase's proposal, so they stay for as
// long as there is a phase left to design — AMB.13, the time clock, which will
// add its own sample data and take it away again at its close.
