//  JobBoxTrackMockup.swift
//  Iconik Employee — AMB.11's job box progression, mocked early
//
//  ARC SCAFFOLDING. Deleted when AMB.11 converts the surface, with the rest of
//  the lab going at AMB.12.
//
//  WHY THIS EXISTS
//      The operator looked at the shift detail's job box bar and said it read
//      "funky". It does, and the drawing defect is real (see below) — but
//      inventorying the LIVE table first turned a cosmetic fix into a design
//      question, which is why this is four options rather than one patch.
//
//  THE DRAWING DEFECT, measured not guessed (ShiftDetailView.jobBoxCard)
//      The connector is an .overlay on each step column, positioned with
//      constants (.padding(.leading, 20).offset(x: 24)) while the columns
//      themselves flex to fill the width. On a 402pt iPhone that puts the line's
//      start at exactly the dot's CENTRE — so it is drawn over the dot's right
//      half — and its end 6pt short of the next dot. Every segment therefore
//      overlaps on the left and leaves a gap on the right. Confirmed against the
//      running app's pixels: the segment ends at x=410 in a 1206px screenshot,
//      which is the constant-derived position to the pixel. Because the numbers
//      are constants and the columns are not, the error CHANGES with width — on
//      a wider card the line detaches from the dot entirely.
//
//      Every option here draws the rail as a flexible segment between two fixed
//      28pt dots, so it meets the dot's edge at ANY width by construction. That
//      is the part that is not up for a vote.
//
//  THE FINDING THAT ACTUALLY DRIVES THE DESIGN
//      `job_boxes` is an APPEND-ONLY SCAN LOG — every scan INSERTs a row
//      (DatabaseManager+NFC.saveJobBoxRecord, and the manager tracker's advance
//      does the same). There is no status-update path. So the rows for a shift
//      ARE the history: stage, who scanned it, when.
//
//      The current card throws all of that away. It sorts to the LATEST row,
//      converts that one status to a number, and then draws every lower stage as
//      complete — `done = step >= number`. It is inferring history it has not
//      read.
//
//      Live counts over the 351 boxes that carry a shift (2026-07-29):
//
//          Packed only .................................. 199
//          Packed + Picked Up ............................ 47
//          all four stages ............................... 35
//          Packed + Turned In ............................ 31   <- skips two
//          Packed + Picked Up + Turned In ................ 22   <- skips one
//          Left Job + Packed + Picked Up .................. 6
//          Left Job + Packed .............................. 3
//          Left Job + Turned In ........................... 2   <- never packed
//          Left Job + Picked Up + Turned In ............... 2   <- never packed
//          Left Job + Packed + Turned In .................. 2
//          Picked Up only ................................. 2   <- never packed
//
//      TEN PER CENT of boxes walk all four stages. Skipping is the norm, not the
//      exception, and 57% never move past Packed at all. So today a box scanned
//      Packed then Turned In is drawn with four green ticks — the screen states
//      that "Picked up" and "Left job" happened when NO SUCH SCAN EXISTS.
//
//      That is the real defect. It is not cosmetic, and no amount of fixing the
//      line geometry addresses it. Three of the four options below stop claiming
//      unscanned stages; option A keeps the familiar shape and marks them.
//
//  WHAT IS NOT BEING PROPOSED (D12 keeps services out of a design phase)
//      No data, service or schema change. Every option draws only what the scan
//      log already contains. The one thing the log CANNOT supply is a "Packed"
//      scanner name — 199 of those rows have a NULL photographer, because packing
//      happens before anyone is assigned — so no option leans on it.

import SwiftUI

// MARK: - The stage vocabulary

enum LabBoxStage: Int, CaseIterable, Identifiable {
    case packed = 1, pickedUp = 2, leftJob = 3, turnedIn = 4

    var id: Int { rawValue }

    /// What a person says out loud. The DATABASE stores "Packed" / "Picked Up" /
    /// "Left Job" / "Turned In" (JobBoxStatus's raw values) — the difference is
    /// only capitalisation, so the conversion can map on rawValue and does not
    /// need a translation table.
    var label: String {
        switch self {
        case .packed: return "Packed"
        case .pickedUp: return "Picked up"
        case .leftJob: return "Left job"
        case .turnedIn: return "Turned in"
        }
    }

    var icon: String {
        switch self {
        case .packed: return "shippingbox.fill"
        case .pickedUp: return "hand.raised.fill"
        case .leftJob: return "figure.walk.departure"
        case .turnedIn: return "checkmark.circle.fill"
        }
    }

    /// Each stage owns a colour, so a box's position is legible from the hue
    /// before any label is read. The current card colours the WHOLE track from
    /// the latest status, and its `.packed` case falls through to grey — so a
    /// packed box, the single most common state in the table, is drawn inert.
    var tint: Color {
        switch self {
        case .packed: return Color(hex: "#8E8E93")
        case .pickedUp: return Color(hex: "#0B8BA8")
        case .leftJob: return Color(hex: "#F09A2B")
        case .turnedIn: return Color(hex: "#31A15D")
        }
    }
}

/// One row of the scan log.
struct LabBoxScan: Identifiable {
    let id = UUID()
    let stage: LabBoxStage
    /// Nil is REAL: a Packed row usually has no photographer.
    let who: String?
    let at: Date
}

/// How a stage should be drawn once the log has been read.
enum LabStageState {
    /// A scan exists for it.
    case scanned
    /// No scan — but a LATER stage was scanned, so this one was jumped.
    case skipped
    /// Not reached yet.
    case pending
}

// MARK: - The scenarios

/// Each case is a real shape from the live table, in the proportion it occurs.
enum LabBoxScenario: String, CaseIterable, Identifiable {
    case packedOnly
    case inFlight
    case skippedTwo
    case fullWalk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .packedOnly: return "Packed only"
        case .inFlight: return "Out on a job"
        case .skippedTwo: return "Two stages skipped"
        case .fullWalk: return "All four scanned"
        }
    }

    /// Shown under the picker so it is obvious this is not invented sample data.
    var incidence: String {
        switch self {
        case .packedOnly: return "199 of 351 boxes — the most common state by far"
        case .inFlight: return "47 boxes sit here; 6 more reach Left job"
        case .skippedTwo: return "31 boxes go Packed straight to Turned in"
        case .fullWalk: return "35 boxes — only 10% walk every stage"
        }
    }

    var boxNumber: String {
        switch self {
        case .packedOnly: return "3041"
        case .inFlight: return "3028"
        case .skippedTwo: return "3017"
        case .fullWalk: return "3005"
        }
    }

    var scans: [LabBoxScan] {
        // A fixed reference so the relative times read sensibly without the
        // screenshot changing meaning between two runs of the lab.
        let now = Date()
        func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }

        switch self {
        case .packedOnly:
            return [LabBoxScan(stage: .packed, who: nil, at: ago(30))]
        case .inFlight:
            return [
                LabBoxScan(stage: .packed, who: nil, at: ago(26)),
                LabBoxScan(stage: .pickedUp, who: "Isaac", at: ago(9)),
                LabBoxScan(stage: .leftJob, who: "Isaac", at: ago(2.5))
            ]
        case .skippedTwo:
            return [
                LabBoxScan(stage: .packed, who: nil, at: ago(52)),
                LabBoxScan(stage: .turnedIn, who: "Rylee", at: ago(4))
            ]
        case .fullWalk:
            return [
                LabBoxScan(stage: .packed, who: nil, at: ago(78)),
                LabBoxScan(stage: .pickedUp, who: "Isaac", at: ago(54)),
                LabBoxScan(stage: .leftJob, who: "Isaac", at: ago(28)),
                LabBoxScan(stage: .turnedIn, who: "Isaac", at: ago(26))
            ]
        }
    }
}

// MARK: - Reading the log

/// The one piece of logic every option shares: turn a list of scans into a
/// per-stage state. This is what the real card does not do today.
struct LabBoxProgress {
    let scans: [LabBoxScan]

    var ordered: [LabBoxScan] { scans.sorted { $0.at < $1.at } }

    var latest: LabBoxScan? { ordered.last }

    /// The furthest stage any scan reached — NOT the latest scan's stage. They
    /// differ whenever a box is scanned out of order, which the live table does
    /// contain.
    var furthest: LabBoxStage? {
        scans.map(\.stage).max(by: { $0.rawValue < $1.rawValue })
    }

    func scan(for stage: LabBoxStage) -> LabBoxScan? {
        ordered.first { $0.stage == stage }
    }

    func state(_ stage: LabBoxStage) -> LabStageState {
        if scan(for: stage) != nil { return .scanned }
        guard let furthest, stage.rawValue < furthest.rawValue else { return .pending }
        return .skipped
    }

    var scannedCount: Int { LabBoxStage.allCases.filter { state($0) == .scanned }.count }

    var skipped: [LabBoxStage] { LabBoxStage.allCases.filter { state($0) == .skipped } }

    /// The colour the card leans on — the furthest stage's, so a packed box is
    /// grey, a box out on a job is orange, a finished one green.
    var tint: Color { furthest?.tint ?? Color(hex: "#8E8E93") }

    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static let clock: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d, h:mm a"; return f
    }()

    static func since(_ date: Date) -> String {
        relative.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - The shared rail

/// The geometry every option that draws a track uses.
///
/// A fixed-width dot with a FLEXIBLE rail either side of it, all inside one
/// column. The rail's width is therefore (column - dot) / 2 at any width, so it
/// meets the dot's edge exactly — on an iPhone, on an iPad, and at every Dynamic
/// Type size. The current card's constants cannot do that, which is the whole
/// reason it looks wrong.
private struct LabStageColumn<Dot: View, Caption: View>: View {
    var leadingRail: Color?
    var trailingRail: Color?
    var leadingDashed: Bool = false
    var trailingDashed: Bool = false
    var dotSize: CGFloat = 28
    @ViewBuilder var dot: () -> Dot
    @ViewBuilder var caption: () -> Caption

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                HStack(spacing: 0) {
                    rail(leadingRail, dashed: leadingDashed)
                    Color.clear.frame(width: dotSize)
                    rail(trailingRail, dashed: trailingDashed)
                }
                .frame(height: dotSize)

                dot()
            }
            caption()
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func rail(_ color: Color?, dashed: Bool) -> some View {
        if let color {
            if dashed {
                // A jumped stage gets a broken rail: the box did not travel
                // that way, and a solid line would say it did.
                Line()
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [3, 4]))
                    .frame(height: 3)
            } else {
                Capsule().fill(color).frame(height: 3)
            }
        } else {
            Color.clear.frame(height: 3)
        }
    }
}

/// A plain horizontal line, so the dashed rail can be stroked.
private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

// MARK: - OPTION A — the familiar track, told the truth

/// Keeps the shape everyone already recognises and fixes the two things wrong
/// with it: the rail geometry, and the claim that every earlier stage happened.
struct LabJobBoxOptionA: View {
    let progress: LabBoxProgress
    let boxNumber: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabBoxCardHeader(boxNumber: boxNumber, progress: progress)

            HStack(spacing: 0) {
                ForEach(LabBoxStage.allCases) { stage in
                    LabStageColumn(
                        leadingRail: railColor(before: stage),
                        trailingRail: railColor(after: stage),
                        leadingDashed: railDashed(before: stage),
                        trailingDashed: railDashed(after: stage)
                    ) {
                        dot(stage)
                    } caption: {
                        Text(stage.label)
                            .font(.system(size: 10, weight: progress.state(stage) == .scanned ? .semibold : .regular))
                            .foregroundStyle(captionColor(stage))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                }
            }

            LabBoxFooter(progress: progress)
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    @ViewBuilder
    private func dot(_ stage: LabBoxStage) -> some View {
        switch progress.state(stage) {
        case .scanned:
            ZStack {
                Circle().fill(stage.tint).frame(width: 28, height: 28)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
        case .skipped:
            // Hollow and dashed, with NO tick. The box got past this stage
            // without ever being scanned at it, and the card says so.
            ZStack {
                Circle()
                    .strokeBorder(Color.secondary.opacity(0.55),
                                  style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                    .frame(width: 28, height: 28)
                Image(systemName: "minus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        case .pending:
            ZStack {
                Circle().fill(Color(.tertiarySystemFill)).frame(width: 28, height: 28)
                Text("\(stage.rawValue)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func captionColor(_ stage: LabBoxStage) -> Color {
        switch progress.state(stage) {
        case .scanned: return .primary
        case .skipped, .pending: return .secondary
        }
    }

    /// A rail is only solid where the box actually travelled between two
    /// scanned stages.
    private func railColor(after stage: LabBoxStage) -> Color? {
        guard stage != .turnedIn else { return nil }
        return segment(from: stage.rawValue)
    }

    private func railColor(before stage: LabBoxStage) -> Color? {
        guard stage != .packed else { return nil }
        return segment(from: stage.rawValue - 1)
    }

    private func railDashed(after stage: LabBoxStage) -> Bool {
        guard stage != .turnedIn else { return false }
        return segmentDashed(from: stage.rawValue)
    }

    private func railDashed(before stage: LabBoxStage) -> Bool {
        guard stage != .packed else { return false }
        return segmentDashed(from: stage.rawValue - 1)
    }

    /// The segment between stage `index` and `index + 1`.
    private func segment(from index: Int) -> Color {
        guard let furthest = progress.furthest, furthest.rawValue > index else {
            return Color(.tertiarySystemFill)
        }
        guard let lower = LabBoxStage(rawValue: index),
              let upper = LabBoxStage(rawValue: index + 1) else {
            return Color(.tertiarySystemFill)
        }
        // Travelled. Solid in the upper stage's colour when both ends were
        // scanned, faint when one end was jumped.
        let bothScanned = progress.state(lower) == .scanned && progress.state(upper) == .scanned
        return bothScanned ? upper.tint : upper.tint.opacity(0.45)
    }

    private func segmentDashed(from index: Int) -> Bool {
        guard let furthest = progress.furthest, furthest.rawValue > index else { return false }
        guard let lower = LabBoxStage(rawValue: index),
              let upper = LabBoxStage(rawValue: index + 1) else { return false }
        return progress.state(lower) == .skipped || progress.state(upper) == .skipped
    }
}

// MARK: - OPTION B — one bar, and where the box is now

/// Argues that the four stage names are reference material and the question a
/// person actually opens this card to answer is "where is my box".
struct LabJobBoxOptionB: View {
    let progress: LabBoxProgress
    let boxNumber: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabBoxCardHeader(boxNumber: boxNumber, progress: progress)

            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle().fill(progress.tint.opacity(0.16)).frame(width: 44, height: 44)
                    Image(systemName: progress.furthest?.icon ?? "shippingbox")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(progress.tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(progress.furthest?.label ?? "Not scanned")
                        .font(.system(size: 19, weight: .semibold))
                    if let latest = progress.latest {
                        Text(LabBoxProgress.since(latest.at))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }

            // The track: FOUR SEGMENTS, one per stage, not one continuous fill.
            //
            // A continuous fill was the first cut and it was wrong for the
            // commonest broken case — a box scanned Packed then Turned In has
            // "reached" stage 4, so the bar ran 100% solid and said exactly the
            // thing this redesign exists to stop saying. Segment it, and a
            // jumped stage is a visible hole in the bar.
            HStack(spacing: 3) {
                ForEach(LabBoxStage.allCases) { stage in
                    segment(stage)
                }
            }
            .frame(height: 8)

            HStack(spacing: 4) {
                Text("\(progress.scannedCount) of 4 scanned")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if !progress.skipped.isEmpty {
                    Text("· \(skippedSentence) never scanned")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            LabBoxFooter(progress: progress)
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    @ViewBuilder
    private func segment(_ stage: LabBoxStage) -> some View {
        switch progress.state(stage) {
        case .scanned:
            Capsule().fill(stage.tint)
        case .skipped:
            // Outlined, not filled: the box passed this point without ever
            // being scanned here, and a filled segment would claim it was.
            Capsule()
                .strokeBorder(Color.secondary.opacity(0.5),
                              style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
        case .pending:
            Capsule().fill(Color(.tertiarySystemFill))
        }
    }

    private var skippedSentence: String {
        let names = progress.skipped.map(\.label)
        if names.count == 1 { return names[0] }
        return names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
    }
}

// MARK: - OPTION C — the scan log, drawn as a log

/// Draws ONE ROW PER ACTUAL SCAN and nothing else. It cannot state a stage that
/// did not happen, because it has no row to draw for one. This is the option
/// that uses the whole of what the table already stores.
struct LabJobBoxOptionC: View {
    let progress: LabBoxProgress
    let boxNumber: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabBoxCardHeader(boxNumber: boxNumber, progress: progress)

            VStack(spacing: 0) {
                ForEach(Array(LabBoxStage.allCases.enumerated()), id: \.element.id) { index, stage in
                    row(stage, isLast: index == LabBoxStage.allCases.count - 1)
                }
            }
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    @ViewBuilder
    private func row(_ stage: LabBoxStage, isLast: Bool) -> some View {
        let state = progress.state(stage)
        let scan = progress.scan(for: stage)

        HStack(alignment: .top, spacing: 10) {
            // The vertical rail, drawn per row so it always meets the dot.
            VStack(spacing: 0) {
                dot(stage, state: state)
                if !isLast {
                    railBelow(stage)
                        .frame(width: 3)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(stage.label)
                        .font(.system(size: 15, weight: state == .scanned ? .semibold : .regular))
                        .foregroundStyle(state == .scanned ? .primary : .secondary)
                    if state == .skipped {
                        Text("never scanned")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            // ambient-allow: a status tag on a row, not a container.
                            .background(Capsule().fill(Color.secondary.opacity(0.14)))
                    }
                }

                if let scan {
                    HStack(spacing: 4) {
                        Text(LabBoxProgress.clock.string(from: scan.at))
                        if let who = scan.who, !who.isEmpty {
                            Text("· \(who)").fontWeight(.semibold)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if state == .pending {
                    Text("not yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.bottom, isLast ? 0 : 12)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func dot(_ stage: LabBoxStage, state: LabStageState) -> some View {
        switch state {
        case .scanned:
            ZStack {
                Circle().fill(stage.tint).frame(width: 24, height: 24)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
        case .skipped:
            Circle()
                .strokeBorder(Color.secondary.opacity(0.55),
                              style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                .frame(width: 24, height: 24)
        case .pending:
            Circle()
                .fill(Color(.tertiarySystemFill))
                .frame(width: 24, height: 24)
        }
    }

    @ViewBuilder
    private func railBelow(_ stage: LabBoxStage) -> some View {
        let travelled = (progress.furthest?.rawValue ?? 0) > stage.rawValue
        if travelled {
            Capsule().fill(progress.tint.opacity(0.5))
        } else {
            Capsule().fill(Color(.tertiarySystemFill))
        }
    }
}

// MARK: - OPTION D — one line, history on tap

/// The smallest thing that is still honest. The shift screen is long and the box
/// is one of nine sections on it; this argues the card should cost four lines
/// until you ask it for more.
struct LabJobBoxOptionD: View {
    let progress: LabBoxProgress
    let boxNumber: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: expanded ? 12 : 0) {
            Button {
                withAnimation(AmbientMotion.snappy) { expanded.toggle() }
                AmbientHaptics.impact(.light)
            } label: {
                HStack(spacing: 10) {
                    Circle().fill(progress.tint).frame(width: 10, height: 10)

                    Text("Job box")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .kerning(0.4)

                    Spacer(minLength: 0)

                    Text("#\(boxNumber)")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(progress.tint)

                    Text(progress.furthest?.label ?? "Not scanned")
                        .font(.system(size: 15, weight: .semibold))

                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !expanded {
                HStack(spacing: 4) {
                    Text("\(progress.scannedCount) of 4 scanned")
                    if let latest = progress.latest {
                        Text("· \(LabBoxProgress.since(latest.at))")
                    }
                    if !progress.skipped.isEmpty {
                        // Inside `if !progress.skipped.isEmpty`, so this is
                        // always the attention colour.
                        Text("· \(progress.skipped.count) skipped")
                            .foregroundStyle(Color.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }

            if expanded {
                Divider()
                ForEach(LabBoxStage.allCases) { stage in
                    HStack(spacing: 8) {
                        Image(systemName: iconName(stage))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(iconTint(stage))
                            .frame(width: 18)
                        Text(stage.label)
                            .font(.system(size: 14, weight: progress.state(stage) == .scanned ? .semibold : .regular))
                            .foregroundStyle(progress.state(stage) == .scanned ? .primary : .secondary)
                        Spacer(minLength: 0)
                        if let scan = progress.scan(for: stage) {
                            Text(LabBoxProgress.clock.string(from: scan.at))
                                .font(.caption).foregroundStyle(.secondary)
                            if let who = scan.who, !who.isEmpty {
                                Text(who).font(.caption.weight(.semibold))
                            }
                        } else {
                            Text(progress.state(stage) == .skipped ? "never scanned" : "not yet")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    private func iconName(_ stage: LabBoxStage) -> String {
        switch progress.state(stage) {
        case .scanned: return "checkmark.circle.fill"
        case .skipped: return "minus.circle"
        case .pending: return "circle"
        }
    }

    private func iconTint(_ stage: LabBoxStage) -> Color {
        switch progress.state(stage) {
        case .scanned: return stage.tint
        case .skipped: return .secondary
        case .pending: return Color(.quaternaryLabel)
        }
    }
}

// MARK: - Shared card furniture

private struct LabBoxCardHeader: View {
    let boxNumber: String
    let progress: LabBoxProgress

    var body: some View {
        HStack {
            AmbientSectionTitle("Job box")
            Spacer(minLength: 0)
            Text("#\(boxNumber)")
                .font(.footnote.weight(.bold))
                .foregroundStyle(progress.tint)
        }
    }
}

private struct LabBoxFooter: View {
    let progress: LabBoxProgress

    var body: some View {
        if let latest = progress.latest {
            HStack(spacing: 4) {
                Text("Last scanned")
                    .font(.caption).foregroundStyle(.secondary)
                if let who = latest.who, !who.isEmpty {
                    Text("by").font(.caption).foregroundStyle(.secondary)
                    Text(who).font(.caption.weight(.semibold))
                }
                Text("· \(LabBoxProgress.clock.string(from: latest.at))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - The mockup screen

struct JobBoxTrackMockup: View {
    static let featureTint = Color(hex: "#0B8BA8")

    @State private var scenario: LabBoxScenario = .skippedTwo

    private var progress: LabBoxProgress { LabBoxProgress(scans: scenario.scans) }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: Self.featureTint, intensity: 0.8)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    premise

                    statePicker

                    option("A", "Corrected step track",
                           "The shape you already know, with the rail geometry fixed and a jumped stage drawn as jumped instead of ticked. Smallest change from today.") {
                        LabJobBoxOptionA(progress: progress, boxNumber: scenario.boxNumber)
                    }

                    option("B", "Where is it now",
                           "Leads with the box's current state in words, with one bar underneath for context. Readable at arm's length; the stage names stop competing with the answer.") {
                        LabJobBoxOptionB(progress: progress, boxNumber: scenario.boxNumber)
                    }

                    option("C", "The scan log",
                           "One row per stage with the time and the person. Uses everything the table already stores, and can never claim a scan that did not happen. Tallest of the four.") {
                        LabJobBoxOptionC(progress: progress, boxNumber: scenario.boxNumber)
                    }

                    option("D", "Compact, history on tap",
                           "Four lines closed, the full log open. The shift screen is long and the box is one section of nine.") {
                        LabJobBoxOptionD(progress: progress, boxNumber: scenario.boxNumber)
                    }

                    todayCard

                    Color.clear.frame(height: 90)
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
    }

    private var premise: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Switch the state at the top and watch each option answer the same question differently. The state that matters most is “Two stages skipped” — today the real screen draws four green ticks for it, claiming two scans that never happened.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .ambientCard(density: .compact, fillWidth: true)
    }

    private var statePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Box state")

            // ambient-allow: a segmented selection control, not a container.
            Picker("Box state", selection: $scenario) {
                ForEach(LabBoxScenario.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)

            Text(scenario.incidence)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    @ViewBuilder
    private func option<Content: View>(_ letter: String, _ title: String, _ premise: String,
                                       @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(letter)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    // ambient-allow: an index marker on a heading, not a container.
                    .background(Circle().fill(Self.featureTint))
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
            }
            Text(premise)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            content()
        }
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("For comparison — today")
            Text("This is the current drawing, reproduced exactly: the rail starts at the dot's centre and stops short of the next one, and every stage below the latest scan is ticked whether or not it was ever scanned.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LabJobBoxToday(progress: progress, boxNumber: scenario.boxNumber)
        }
    }
}

// MARK: - Today's drawing, reproduced

/// A faithful copy of `ShiftDetailView.jobBoxCard`'s track — same constants,
/// same `step >= number` rule — so the comparison is against what actually ships
/// rather than against a description of it.
private struct LabJobBoxToday: View {
    let progress: LabBoxProgress
    let boxNumber: String

    private var step: Int { progress.latest?.stage.rawValue ?? 0 }

    private var highlight: Color {
        switch progress.latest?.stage {
        case .pickedUp: return .blue
        case .leftJob: return .orange
        case .turnedIn: return .green
        default: return .gray          // <- .packed lands here, the commonest state
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                AmbientSectionTitle("Job box")
                Spacer(minLength: 0)
                Text("#\(boxNumber)")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(highlight)
            }

            HStack(spacing: 0) {
                ForEach(Array(LabBoxStage.allCases.enumerated()), id: \.element.id) { index, stage in
                    let number = index + 1
                    let done = step >= number
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(done ? highlight : Color(.tertiarySystemFill))
                                .frame(width: 28, height: 28)
                            if done {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                            } else {
                                Text("\(number)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(stage.label)
                            .font(.system(size: 10, weight: done ? .semibold : .regular))
                            .foregroundStyle(done ? .primary : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .top) {
                        if index < LabBoxStage.allCases.count - 1 {
                            Rectangle()
                                .fill(step > number ? highlight : Color(.tertiarySystemFill))
                                .frame(height: 2)
                                .padding(.leading, 20)
                                .offset(x: 24, y: 13)
                        }
                    }
                }
            }

            if let latest = progress.latest, let who = latest.who, !who.isEmpty {
                HStack(spacing: 4) {
                    Text("Last scanned by").font(.caption).foregroundStyle(.secondary)
                    Text(who).font(.caption.weight(.semibold))
                    Text("· \(LabBoxProgress.clock.string(from: latest.at))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }
}
