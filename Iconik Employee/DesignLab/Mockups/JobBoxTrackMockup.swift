//  JobBoxTrackMockup.swift
//  Iconik Employee — AMB.11's job box card, mocked early
//
//  ARC SCAFFOLDING. Deleted when AMB.11 converts the surface, with the rest of
//  the lab going at AMB.12.
//
//  ─────────────────────────────────────────────────────────────────────────
//  ROUND 3. TWO REJECTIONS, AND THEY POINTED IN OPPOSITE DIRECTIONS.
//
//  Round 1 — four options, all built around the existing four-dot stepper. I had
//  fixed the rail's GEOMETRY and its TRUTHFULNESS and then led the screen with an
//  option captioned "smallest change from today". Verdict: "why are you showing
//  me ui that looks almost identical to what i have that looks wonky". Fair — the
//  first thing on screen was the shape being complained about.
//
//  Round 2 — I deleted the meter entirely and offered a sentence, a luggage tag,
//  an alert and a log. Verdict: "not really liking any of those. I do want some
//  sort of progress meter though."
//
//  So the concept was never wrong. A progress meter IS the right thing on this
//  card; my first attempt just reproduced the wonky one, and my second threw out
//  the baby. Round 3 is four PROPERLY DESIGNED METERS — a ring, a block bar, a
//  crate that fills, and a scrubber. Every one reads as a meter at a glance and
//  none of them is a row of four identical dots with four labels underneath.
//  ─────────────────────────────────────────────────────────────────────────
//
//  WHAT THE ORIGINAL DEFECT WAS (both halves still fixed here)
//
//  1. GEOMETRY. `ShiftDetailView.jobBoxCard` positions the connector with
//     constants (`.padding(.leading, 20).offset(x: 24)`) inside columns that flex
//     to fill the width. On a 402pt iPhone that starts the line at the dot's
//     CENTRE — over the dot — and ends it 6pt short of the next. Overlap left,
//     gap right, and the error CHANGES with width. Measured against the running
//     app's pixels, not eyeballed.
//
//  2. TRUTHFULNESS. `job_boxes` is an APPEND-ONLY SCAN LOG — every scan INSERTs a
//     row (DatabaseManager+NFC.saveJobBoxRecord, and the manager tracker's
//     advance does the same; there is no status-update path). The rows for a
//     shift ARE the history. The card ignores that: it reads the LATEST row,
//     converts that one status to a number, and ticks every stage below it via
//     `done = step >= number`.
//
//     Live counts over the 351 boxes carrying a shift (2026-07-29):
//
//         Packed only .................................. 199
//         Packed + Picked Up ............................ 47
//         all four stages ............................... 35
//         Packed + Turned In ............................ 31   <- skips two
//         Packed + Picked Up + Turned In ................ 22   <- skips one
//         ...11 more across six shapes, four never packed at all
//
//     So a box scanned Packed then Turned In is drawn today with four green
//     ticks, asserting two scans that never happened. Every meter below shows a
//     jumped stage as hollow instead of filled.
//
//  HOW A METER STAYS HONEST ABOUT A SKIP
//      POSITION and COMPLETENESS are different questions, and conflating them is
//      what made round 1's bar fill 100% solid for a box that was only scanned
//      twice. The meters here fill to where the box actually IS (its furthest
//      stage — that part is true) while drawing each stage's own segment filled
//      or hollow according to whether a scan exists. So a Packed-then-Turned-In
//      box reads as "back at the warehouse, but two stages were never scanned",
//      which is exactly what the table says.
//
//  WHAT IS NOT BEING PROPOSED (D12 keeps services out of a design phase)
//      No data, service or schema change. Every meter draws only what the scan
//      log already contains. The log CANNOT supply a "Packed" scanner name — 199
//      of those rows have a NULL photographer, because packing happens before
//      anyone is assigned — so nothing leans on it.

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

    /// The short form, for a meter that labels its segments at all.
    var short: String {
        switch self {
        case .packed: return "Packed"
        case .pickedUp: return "Out"
        case .leftJob: return "Returning"
        case .turnedIn: return "Back"
        }
    }

    var icon: String {
        switch self {
        case .packed: return "shippingbox.fill"
        case .pickedUp: return "hand.raised.fill"
        case .leftJob: return "figure.walk.departure"
        case .turnedIn: return "checkmark"
        }
    }

    /// Each stage owns a colour, so a box's position is legible from the hue
    /// before any label is read. The current card colours the WHOLE track from
    /// the latest status, and its `.packed` case falls through to grey — so a
    /// packed box, the single most common state in the table, is drawn inert.
    var tint: Color {
        switch self {
        case .packed: return Color(hex: "#7A8794")
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
        case .skippedTwo: return "Two skipped"
        case .fullWalk: return "All four"
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

/// Turn a list of scans into what a meter needs. The real card does none of this
/// — it reads one row and infers the rest.
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

    var tint: Color { furthest?.tint ?? Color(hex: "#7A8794") }

    /// How far along the trip the box actually IS, 0–1. Truthful on its own
    /// terms: a box that has been turned in is at the end, however few stages
    /// were scanned on the way. Completeness is drawn separately, per segment.
    var positionFraction: CGFloat {
        guard let furthest else { return 0 }
        return CGFloat(furthest.rawValue) / CGFloat(LabBoxStage.allCases.count)
    }

    var headline: String { furthest?.label ?? "Not scanned" }

    /// The supporting line — what happened last, when, and by whom if known.
    var detail: String {
        guard let latest else { return "no scans on this box" }
        let when = Self.since(latest.at)
        if let who = latest.who, !who.isEmpty { return "\(who) · \(when)" }
        return when
    }

    /// Named only when there is something to say, so a normal box gets no
    /// apology line.
    var skipNote: String? {
        guard !skipped.isEmpty else { return nil }
        let names = skipped.map(\.label)
        let list = names.count == 1
            ? names[0]
            : names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
        return "\(list) never scanned"
    }

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

// MARK: - Shared card head

private struct LabMeterHead: View {
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

// MARK: - METER 1 — the ring

/// A radial gauge: four arcs around a circle, the stage named in the middle.
///
/// Reads as an instrument rather than a checklist. The four arcs still carry
/// per-stage truth — a jumped stage is a hollow arc — but you take the state in
/// from the ring's colour and how much of it is closed, before reading a word.
struct LabJobBoxRing: View {
    let progress: LabBoxProgress
    let boxNumber: String

    private let diameter: CGFloat = 116
    private let lineWidth: CGFloat = 13
    /// Half the angular gap between arcs, as a fraction of the circle.
    private let gap: CGFloat = 0.016

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabMeterHead(boxNumber: boxNumber, progress: progress)

            HStack(spacing: 18) {
                ring

                VStack(alignment: .leading, spacing: 4) {
                    Text(progress.headline)
                        .font(.system(size: 20, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(progress.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let note = progress.skipNote {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    private var ring: some View {
        ZStack {
            ForEach(LabBoxStage.allCases) { stage in
                arc(stage)
            }

            VStack(spacing: 0) {
                Text("\(progress.scannedCount)")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                Text("of 4 scanned")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: diameter, height: diameter)
    }

    @ViewBuilder
    private func arc(_ stage: LabBoxStage) -> some View {
        let index = CGFloat(stage.rawValue - 1)
        let from = index / 4 + gap
        let to = (index + 1) / 4 - gap

        switch progress.state(stage) {
        case .scanned:
            Circle()
                .trim(from: from, to: to)
                .stroke(stage.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        case .skipped:
            // Hollow: the box got past this point without a scan here.
            Circle()
                .trim(from: from, to: to)
                .stroke(stage.tint.opacity(0.32),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [2, 5]))
                .rotationEffect(.degrees(-90))
        case .pending:
            Circle()
                .trim(from: from, to: to)
                .stroke(Color(.tertiarySystemFill),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - METER 2 — the block bar

/// Four heavy blocks, the stage named above them in full size.
///
/// The closest thing here to a conventional progress bar, and deliberately so —
/// but the four labels are gone, the dots are gone, and the blocks are thick
/// enough to read from arm's length. It looks like a battery, not a checklist.
struct LabJobBoxBlocks: View {
    let progress: LabBoxProgress
    let boxNumber: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabMeterHead(boxNumber: boxNumber, progress: progress)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(progress.headline)
                    .font(.system(size: 22, weight: .semibold))
                Spacer(minLength: 0)
                Text(progress.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 5) {
                ForEach(LabBoxStage.allCases) { stage in
                    block(stage)
                }
            }
            .frame(height: 16)

            if let note = progress.skipNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    @ViewBuilder
    private func block(_ stage: LabBoxStage) -> some View {
        switch progress.state(stage) {
        case .scanned:
            Capsule().fill(stage.tint.gradient)
        case .skipped:
            Capsule()
                .strokeBorder(stage.tint.opacity(0.45),
                              style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
        case .pending:
            Capsule().fill(Color(.tertiarySystemFill))
        }
    }
}

// MARK: - METER 3 — the crate that fills

/// The meter IS a box, and it fills up as the box completes its trip.
///
/// A gauge nobody has to learn: an empty crate is a box that has not gone
/// anywhere, a full one is a box that is back. Four notches on the side keep the
/// per-stage truth available without turning it into a checklist.
struct LabJobBoxCrate: View {
    let progress: LabBoxProgress
    let boxNumber: String

    private let crateWidth: CGFloat = 76
    private let crateHeight: CGFloat = 66

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabMeterHead(boxNumber: boxNumber, progress: progress)

            HStack(spacing: 16) {
                crate

                VStack(alignment: .leading, spacing: 4) {
                    Text(progress.headline)
                        .font(.system(size: 20, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(progress.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let note = progress.skipNote {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    private var crate: some View {
        HStack(spacing: 6) {
            // ambient-allow: this is the meter's graphic, not a content container.
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.05))

                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Rectangle()
                        .fill(progress.tint.gradient)
                        .frame(height: crateHeight * progress.positionFraction)
                }
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                // The lid seam, so it reads as a crate rather than a bar chart.
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.18))
                        .frame(height: 1.5)
                        .padding(.top, 13)
                    Spacer(minLength: 0)
                }

                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.22), lineWidth: 2)
            }
            .frame(width: crateWidth, height: crateHeight)

            // Four notches, bottom stage first, so the crate keeps per-stage
            // truth without four labels.
            VStack(spacing: 3) {
                ForEach(LabBoxStage.allCases.reversed()) { stage in
                    notch(stage)
                }
            }
            .frame(height: crateHeight)
        }
    }

    @ViewBuilder
    private func notch(_ stage: LabBoxStage) -> some View {
        let width: CGFloat = 9
        switch progress.state(stage) {
        case .scanned:
            Capsule().fill(stage.tint).frame(width: width, height: 3)
        case .skipped:
            Capsule().fill(stage.tint.opacity(0.3)).frame(width: width * 0.55, height: 3)
        case .pending:
            Capsule().fill(Color(.tertiarySystemFill)).frame(width: width * 0.55, height: 3)
        }
    }
}

// MARK: - METER 4 — the scrubber

/// One continuous rail with a raised puck showing exactly where the box is.
///
/// The rail answers "how far" in one shape rather than four, and the puck carries
/// the stage's own icon — so the meter names the state without a label row. Stage
/// notches sit under the rail, hollow where a scan is missing.
struct LabJobBoxScrubber: View {
    let progress: LabBoxProgress
    let boxNumber: String

    private let railHeight: CGFloat = 8
    private let puck: CGFloat = 34

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            LabMeterHead(boxNumber: boxNumber, progress: progress)

            VStack(alignment: .leading, spacing: 3) {
                Text(progress.headline)
                    .font(.system(size: 22, weight: .semibold))
                Text(progress.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                // The puck must stay inside the card, so the travel available to
                // it is the width less its own diameter.
                let travel = max(0, geo.size.width - puck)
                let x = puck / 2 + travel * progress.positionFraction

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.tertiarySystemFill))
                        .frame(height: railHeight)

                    Capsule()
                        .fill(progress.tint.gradient)
                        .frame(width: x, height: railHeight)

                    // Notches under the rail: which stages were actually scanned.
                    ForEach(LabBoxStage.allCases) { stage in
                        notch(stage)
                            .position(x: puck / 2 + travel * CGFloat(stage.rawValue) / 4,
                                      y: railHeight / 2)
                    }

                    ZStack {
                        Circle()
                            .fill(progress.tint)
                            .frame(width: puck, height: puck)
                            .shadow(color: progress.tint.opacity(0.45), radius: 6, y: 2)
                        Image(systemName: progress.furthest?.icon ?? "shippingbox")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .position(x: x, y: railHeight / 2)
                }
            }
            .frame(height: puck)

            if let note = progress.skipNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    @ViewBuilder
    private func notch(_ stage: LabBoxStage) -> some View {
        switch progress.state(stage) {
        case .scanned:
            Circle()
                .fill(.white)
                .frame(width: 5, height: 5)
        case .skipped:
            Circle()
                .strokeBorder(Color.secondary.opacity(0.7), lineWidth: 1.5)
                .frame(width: 7, height: 7)
        case .pending:
            Circle()
                .fill(Color(.quaternaryLabel))
                .frame(width: 5, height: 5)
        }
    }
}

// MARK: - The mockup screen

struct JobBoxTrackMockup: View {
    static let featureTint = Color(hex: "#0B8BA8")

    @State private var scenario: LabBoxScenario = .inFlight

    private var progress: LabBoxProgress { LabBoxProgress(scans: scenario.scans) }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: Self.featureTint, intensity: 0.8)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    premise

                    statePicker

                    option("1", "The ring",
                           "A gauge rather than a checklist. Four arcs, the count in the middle — you read the state from how much of the ring is closed before you read a word.") {
                        LabJobBoxRing(progress: progress, boxNumber: scenario.boxNumber)
                    }

                    option("2", "The block bar",
                           "The most familiar of the four, but the dots and the four labels are gone and the stage is named in full size above. Reads like a battery.") {
                        LabJobBoxBlocks(progress: progress, boxNumber: scenario.boxNumber)
                    }

                    option("3", "The crate",
                           "The meter is a box and it fills as the trip completes. Nothing to learn: empty means it has not gone anywhere, full means it is back.") {
                        LabJobBoxCrate(progress: progress, boxNumber: scenario.boxNumber)
                    }

                    option("4", "The scrubber",
                           "One rail, one puck carrying the stage's own icon. The single clearest read of “how far along is it” — position is a place on a line, not four boxes.") {
                        LabJobBoxScrubber(progress: progress, boxNumber: scenario.boxNumber)
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
        Text("Four progress meters. Switch the state at the top — “Two skipped” is the one that catches a meter lying, and “Packed only” is 57% of every box you own.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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
    private func option<Content: View>(_ number: String, _ title: String, _ premise: String,
                                       @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(number)
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
            Text("The current drawing, reproduced exactly: the rail starts at the dot's centre and stops short of the next one, and every stage below the latest scan is ticked whether or not it was ever scanned.")
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
