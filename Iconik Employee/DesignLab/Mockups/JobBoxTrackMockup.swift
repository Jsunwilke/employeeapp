//  JobBoxTrackMockup.swift
//  Iconik Employee — AMB.11's job box card, mocked early
//
//  ARC SCAFFOLDING. Deleted when AMB.11 converts the surface, with the rest of
//  the lab going at AMB.12.
//
//  ─────────────────────────────────────────────────────────────────────────
//  ROUND 2. THE FIRST CUT WAS REJECTED AND THE REJECTION WAS RIGHT.
//
//  Round one offered four options and the operator's verdict was that they
//  "look almost identical to what I have that looks wonky". They did. I had
//  fixed the bar's GEOMETRY and its TRUTHFULNESS and then led the screen with an
//  option explicitly captioned "smallest change from today" — so the first thing
//  on screen was the shape being complained about. The other three kept the same
//  four-stage checklist frame.
//
//  This is D12 again, and it is the third time in the arc: I turned a scope rule
//  about CODE (no data, service or schema changes) into a ceiling on the DESIGN.
//  It is the same failure the bottom tab bar went through — "hate it, not really
//  any different" — where a restyle of a shape nobody had questioned was
//  presented as a redesign.
//
//  So the stepper is GONE from every option here. Not corrected — gone. A row of
//  four dots is a warehouse's model of a box, and it is on a screen a
//  photographer opens to ask one question: where is my box and who has it.
//  ─────────────────────────────────────────────────────────────────────────
//
//  WHAT THE DATA SAYS, and it is the reason a stepper is the wrong shape
//
//      `job_boxes` is an APPEND-ONLY SCAN LOG — every scan INSERTs a row
//      (DatabaseManager+NFC.saveJobBoxRecord, and the manager tracker's advance
//      does the same). There is no status-update path. So the rows for a shift
//      ARE the history: stage, who, when.
//
//      Live counts over the 351 boxes that carry a shift (2026-07-29):
//
//          Packed only .................................. 199
//          Packed + Picked Up ............................ 47
//          all four stages ............................... 35
//          Packed + Turned In ............................ 31   <- skips two
//          Packed + Picked Up + Turned In ................ 22   <- skips one
//          ...11 more across six shapes, four never packed at all
//
//      TEN PER CENT of boxes walk all four stages. FIFTY-SEVEN PER CENT never
//      move past Packed. A four-step progress bar is therefore drawing a journey
//      that almost never happens, and the current card compounds it: it reads the
//      LATEST row, converts that one status to a number, and ticks every stage
//      below it — `done = step >= number`. A box scanned Packed then Turned In
//      is drawn with four green ticks, asserting two scans that do not exist.
//
//      Those two facts point the same way. Most boxes have one or two scans, so
//      the interesting content is POSSESSION and TIME, not progression.
//
//  THE FOUR OPTIONS HERE ARE FOUR DIFFERENT OBJECTS, not four skins:
//      1  a SENTENCE   — who has it, in words, with a face
//      2  an OBJECT    — the box drawn as its physical tag
//      3  an ALERT     — silent unless something is actually wrong
//      4  a LOG        — one row per scan, times and names
//
//  WHAT IS NOT BEING PROPOSED (D12 keeps services out of a design phase)
//      No data, service or schema change. Every option draws only what the scan
//      log already contains. The one thing the log CANNOT supply is a "Packed"
//      scanner name — 199 of those rows have a NULL photographer, because packing
//      happens before anyone is assigned — so no option leans on it. Option 3's
//      thresholds are placeholders for the operator, not new business rules.

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

    /// The word that goes on option 2's stamp.
    var stamp: String {
        switch self {
        case .packed: return "READY"
        case .pickedUp: return "OUT"
        case .leftJob: return "RETURNING"
        case .turnedIn: return "BACK"
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

/// Turn a list of scans into what the screen actually needs. The real card does
/// none of this — it reads one row and infers the rest.
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

    // MARK: Where the box IS, in words
    //
    // The four stored stages are warehouse vocabulary. What a person wants is
    // possession: is it here, has someone got it, is it back. These derive that
    // — and they are the reason the new options do not need a stepper at all.

    /// The person holding it, or who last had it. Never a Packed row's
    /// photographer, because that column is NULL on 199 of them.
    var holder: String? {
        guard let furthest, furthest != .packed else { return nil }
        return scan(for: furthest)?.who ?? ordered.last(where: { $0.who?.isEmpty == false })?.who
    }

    /// The headline sentence. This is the whole answer for most boxes.
    var placeSentence: String {
        switch furthest {
        case .packed, .none:
            return "In the warehouse"
        case .pickedUp:
            return holder.map { "\($0) has it" } ?? "Picked up"
        case .leftJob:
            return holder.map { "\($0) is bringing it back" } ?? "Left the job"
        case .turnedIn:
            return "Back in the warehouse"
        }
    }

    /// The supporting line — what happened last and when.
    var placeDetail: String {
        guard let latest else { return "never scanned" }
        let when = Self.since(latest.at)
        switch furthest {
        case .packed, .none: return "Packed \(when)"
        case .pickedUp: return "Picked up \(when)"
        case .leftJob: return "Left the job \(when)"
        case .turnedIn:
            if let who = latest.who, !who.isEmpty { return "\(who) turned it in \(when)" }
            return "Turned in \(when)"
        }
    }

    var isFinished: Bool { furthest == .turnedIn }

    /// How long it has sat in its current state.
    var dwellHours: Double {
        guard let latest else { return 0 }
        return Date().timeIntervalSince(latest.at) / 3600
    }

    /// The exception model. Most boxes are unremarkable — 199 of 351 sit at
    /// Packed forever — so a card that shouts about every box is noise. This is
    /// what lets option 3 stay quiet until something is actually wrong.
    var concern: LabBoxConcern {
        switch furthest {
        case .packed, .none:
            // Packed and not collected. In the real screen this would compare
            // against the shift's start time; the lab has no shift, so it uses
            // dwell.
            return dwellHours > 24 ? .notCollected : .none
        case .pickedUp, .leftJob:
            return dwellHours > 48 ? .outTooLong : .none
        case .turnedIn:
            return .none
        }
    }
}

/// Nothing here is a new business rule — it is a reading of scans the table
/// already has. The thresholds are placeholders for the operator to set.
enum LabBoxConcern {
    case none
    case notCollected
    case outTooLong

    var headline: String {
        switch self {
        case .none: return ""
        case .notCollected: return "Nobody has collected this box"
        case .outTooLong: return "This box has been out a long time"
        }
    }

    var tint: Color {
        switch self {
        case .none: return .clear
        case .notCollected: return Color(hex: "#E8912D")
        case .outTooLong: return Color(hex: "#D9534F")
        }
    }

    var icon: String {
        switch self {
        case .none: return ""
        case .notCollected: return "exclamationmark.triangle.fill"
        case .outTooLong: return "clock.badge.exclamationmark.fill"
        }
    }

    var isRaised: Bool { if case .none = self { return false } else { return true } }
}

// MARK: - OPTION 1 — a SENTENCE

/// No track of any kind. A face, a sentence, and when.
///
/// The argument: for 57% of boxes there is exactly ONE scan, so there is no
/// progression to draw — there is only a fact. Say the fact.
struct LabJobBoxSentence: View {
    let progress: LabBoxProgress
    let boxNumber: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                AmbientSectionTitle("Job box")
                Spacer(minLength: 0)
                Text("#\(boxNumber)")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                avatar

                VStack(alignment: .leading, spacing: 3) {
                    Text(progress.placeSentence)
                        .font(.system(size: 22, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(progress.placeDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .ambientCard(density: .hero, fillWidth: true)
    }

    /// A person when a person has it, the box itself when the warehouse does.
    @ViewBuilder
    private var avatar: some View {
        if let holder = progress.holder {
            ZStack {
                Circle()
                    .fill(AmbientStyle.avatarColor(holder).gradient)
                    .frame(width: 54, height: 54)
                Text(AmbientStyle.initials(holder))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
            }
        } else {
            ZStack {
                Circle()
                    .fill(progress.tint.opacity(0.16))
                    .frame(width: 54, height: 54)
                Image(systemName: progress.isFinished ? "checkmark" : "shippingbox.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(progress.tint)
            }
        }
    }
}

// MARK: - OPTION 2 — an OBJECT

/// The box drawn as the physical thing it is: a tag with a number on it and a
/// stamp saying where it is.
///
/// The argument: photographers talk about "box 3028", not about stage three of
/// four. Make the number the biggest thing on the card and the state a stamp.
struct LabJobBoxTag: View {
    let progress: LabBoxProgress
    let boxNumber: String

    var body: some View {
        HStack(spacing: 0) {
            perforation

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: -4) {
                        Text("BOX")
                            .font(.system(size: 11, weight: .heavy))
                            .kerning(1.6)
                            .foregroundStyle(.secondary)
                        Text(boxNumber)
                            .font(.system(size: 46, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                    }
                    Spacer(minLength: 8)
                    stamp
                }

                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: 1)
                    .padding(.vertical, 10)

                Text(progress.placeSentence)
                    .font(.system(size: 16, weight: .semibold))
                Text(progress.placeDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 12)

            Spacer(minLength: 0)
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    /// The torn edge of a tag. Decoration with a job: it says "this is an object"
    /// before any word is read.
    private var perforation: some View {
        VStack(spacing: 6) {
            ForEach(0..<9, id: \.self) { _ in
                Circle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 4, height: 4)
            }
        }
    }

    private var stamp: some View {
        Text(progress.furthest?.stamp ?? "UNSCANNED")
            .font(.system(size: 13, weight: .heavy))
            .kerning(1.2)
            .foregroundStyle(progress.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            // ambient-allow: a rubber stamp on a tag, not a container.
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(progress.tint.opacity(0.75), lineWidth: 2.5)
            )
            .rotationEffect(.degrees(-8))
            .opacity(0.9)
    }
}

// MARK: - OPTION 3 — an ALERT

/// Nearly invisible when the box is unremarkable; a full card with a sentence
/// and an action when it is not.
///
/// The argument: 199 of 351 boxes sit at Packed forever and nobody needs to be
/// told about them. A card that looks the same whether everything is fine or a
/// box has been missing for four days is not informing anyone. So: one quiet
/// line by default, and the card only earns space when something is wrong.
struct LabJobBoxQuiet: View {
    let progress: LabBoxProgress
    let boxNumber: String

    var body: some View {
        if progress.concern.isRaised {
            raised
        } else {
            quiet
        }
    }

    private var quiet: some View {
        HStack(spacing: 8) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Box #\(boxNumber)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("·")
                .foregroundStyle(.tertiary)
            Text(progress.placeSentence)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }

    private var raised: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: progress.concern.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(progress.concern.tint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(progress.concern.headline)
                        .font(.system(size: 16, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Box #\(boxNumber) · \(progress.placeDetail)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                actionButton("Remind the crew", filled: true)
                actionButton("See history", filled: false)
            }
        }
        .ambientCard(density: .roomy, state: .highlighted,
                     glow: progress.concern.tint, fillWidth: true)
    }

    private func actionButton(_ title: String, filled: Bool) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(filled ? .white : progress.concern.tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            // ambient-allow: a button is a control, not a container.
            .background {
                if filled {
                    Capsule().fill(progress.concern.tint)
                } else {
                    Capsule().strokeBorder(progress.concern.tint.opacity(0.5), lineWidth: 1.5)
                }
            }
    }
}

// MARK: - OPTION 4 — a LOG

/// One row per stage with the time and the person. Cannot claim a scan that did
/// not happen, because it has no row to draw for one.
struct LabJobBoxLog: View {
    let progress: LabBoxProgress
    let boxNumber: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                AmbientSectionTitle("Job box")
                Spacer(minLength: 0)
                Text("#\(boxNumber)")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(progress.tint)
            }

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

                    option("1", "Who has it",
                           "No track at all — a face, a sentence and when. For most boxes there is only ONE scan, so there is no progression to draw; there is a fact.") {
                        LabJobBoxSentence(progress: progress, boxNumber: scenario.boxNumber)
                    }

                    option("2", "The tag",
                           "The box drawn as the physical thing it is. You say “box 3028”, not “stage three of four”, so the number is the biggest thing on the card and the state is a stamp.") {
                        LabJobBoxTag(progress: progress, boxNumber: scenario.boxNumber)
                    }

                    option("3", "Quiet until it matters",
                           "One faint line when the box is unremarkable — which it is for 199 of 351 — and a full card with an action only when something is actually wrong. Switch to “Packed only” to see it wake up.") {
                        LabJobBoxQuiet(progress: progress, boxNumber: scenario.boxNumber)
                    }

                    option("4", "The scan log",
                           "One row per stage with the time and the person. The most information of the four, and the only one that shows you the whole trip at once.") {
                        LabJobBoxLog(progress: progress, boxNumber: scenario.boxNumber)
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
        Text("None of these is a row of dots. Switch the state at the top — especially to “Packed only”, which is 57% of every box you own — and see how differently each one behaves.")
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
