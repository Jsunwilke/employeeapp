//  JobBoxProgressMeter.swift
//  Iconik Employee — the job box progress meter, in ONE place
//
//  THE DESIGN LIVES HERE, AND THE DESIGN LAB IMPORTS IT.
//
//  That inversion is deliberate and is the mechanism AMB.7 built: if the lab owns
//  a mockup and the real screen copies it, the conversion is a matching exercise
//  that prose cannot hold — AMB.1 shipped a static day strip where the lab
//  scrolled, twice. So the mockup draws with THIS type, the shift detail draws
//  with THIS type, and the manager tracker draws with THIS type. There is no
//  copying step to get wrong.
//
//  It also closes a real defect: the shift detail and the manager tracker each
//  had their OWN progress bar with different colour rules, so two screens
//  disagreed about the same box. Both are deleted in the same commit as this file.
//
//  THE SHAPE — a scrubber, chosen by the operator 2026-07-29 from four meters in
//  the lab (a ring, a block bar, a filling crate and this).
//
//      one rail, one puck carrying the current stage's own icon at the exact
//      position, and a notch per stage under the rail showing whether that stage
//      was really scanned
//
//  WHY THE GEOMETRY IS BUILT THE WAY IT IS
//      The bar this replaces positioned its connector with constants
//      (`.padding(.leading, 20).offset(x: 24)`) inside columns that flex to fill
//      the width. On a 402pt iPhone that put the line's start at the dot's CENTRE
//      and its end 6pt short of the next dot — overlap left, gap right — and
//      because the constants were fixed while the columns were not, the error
//      changed with width. Here every position is derived from the measured width
//      inside a GeometryReader, and the puck's travel is inset by its own radius
//      at both ends, so nothing can overhang the card at any size.
//
//  HONESTY IS IN THE RULES, NOT HERE
//      `JobBoxProgressRules.swift` decides what is scanned, skipped or pending,
//      what the current trip is, and where the box is. This file only draws it.
//      Those rules are run by `scripts/test_jobbox_progress_rules.sh` (60 checks,
//      six of them proved to fail without their rule).

import SwiftUI

// MARK: - Stage presentation

extension JobBoxTripStage {

    /// Each stage owns a colour, so a box's position is legible from the hue
    /// before any label is read.
    ///
    /// THIS MAP IS THE SINGLE iOS↔WEB CONTRACT for job-box status colour
    /// (operator ruling, batch-4 sitting 2026-07-30). It replaced a second,
    /// disagreeing map in `NFC/StatusColors.swift`, which was deleted in the same
    /// change — two maps meant two clients could colour the same box differently,
    /// and three of the four statuses did.
    ///
    /// The ruling, in its own terms:
    ///   - NO GREY for any status. The bar this replaces coloured the whole track
    ///     from one status and let `.packed` fall through to grey, so a packed box
    ///     — the single most common state in the table (199 of 351) — was drawn
    ///     inert. An earlier draft of this file kept a deliberate slate for the
    ///     same stage; the ruling bans that too.
    ///   - GREEN IS RESERVED FOR TURNED IN. It is the one stage that means
    ///     "finished", so nothing else may borrow the colour that says so.
    ///   - The other three stages take unique CALMING colours chosen to sit well
    ///     with that green.
    ///
    /// The web app follows this map; a change here is a cross-client change.
    var meterTint: Color {
        switch self {
        case .packed: return Color(hex: "#6B7FD7")
        case .pickedUp: return Color(hex: "#0B8BA8")
        case .leftJob: return Color(hex: "#F09A2B")
        case .turnedIn: return Color(hex: "#31A15D")
        }
    }

    var meterIcon: String {
        switch self {
        case .packed: return "shippingbox.fill"
        case .pickedUp: return "hand.raised.fill"
        case .leftJob: return "figure.walk.departure"
        case .turnedIn: return "checkmark"
        }
    }
}

extension JobBoxProgressReading {

    /// The fallback is the ABSENCE of a status, not a status: a box with no
    /// readable scan on this trip. It is deliberately outside the four-colour
    /// contract above — the no-grey ruling governs the four STAGES, and
    /// "never scanned" must not be dressed as one of them.
    var meterTint: Color { furthest?.meterTint ?? Color(hex: "#7A8794") }

    /// The supporting line: who and when, with the name omitted when the log has
    /// none rather than inventing one.
    func detailLine(relativeTo now: Date = Date()) -> String {
        guard let latest else { return "no scans on this box" }
        let when = Self.meterRelative.localizedString(for: latest.at, relativeTo: now)
        if let who = latest.who, !who.isEmpty { return "\(who) · \(when)" }
        return when
    }

    static let meterRelative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}

// MARK: - Building a reading from database rows

extension JobBoxProgressReading {

    /// Turn the `job_boxes` rows for one box into a reading of its current trip.
    ///
    /// A row whose status does not map to a stage is DROPPED rather than guessed
    /// at — the column is plain text shared with the web app, and inventing a
    /// stage for an unrecognised value is how a screen starts lying.
    init(rows: [JobBox]) {
        self.init(log: rows.compactMap { row in
            guard let stage = JobBoxTripStage(stored: row.status) else { return nil }
            guard let at = row.timestamp else { return nil }
            let who = row.photographer.isEmpty ? nil : row.photographer
            return JobBoxScanPoint(stage: stage, who: who, at: at)
        })
    }
}

// MARK: - The meter

/// The scrubber. Rail, puck, and a notch per stage.
struct JobBoxProgressMeter: View {
    let reading: JobBoxProgressReading

    /// The compact form drops the puck's shadow and shrinks everything, for a
    /// list row where the meter is one of several columns.
    var compact: Bool = false

    private var railHeight: CGFloat { compact ? 6 : 8 }
    private var puck: CGFloat { compact ? 24 : 34 }

    var body: some View {
        GeometryReader { geo in
            // The puck must stay inside its container at both ends, so the travel
            // available to it is the width less its own diameter.
            let travel = max(0, geo.size.width - puck)
            let position = puck / 2 + travel * CGFloat(reading.positionFraction)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.tertiarySystemFill))
                    .frame(height: railHeight)

                Capsule()
                    .fill(reading.meterTint.gradient)
                    .frame(width: position, height: railHeight)

                ForEach(JobBoxTripStage.allCases, id: \.rawValue) { stage in
                    notch(stage)
                        .position(x: puck / 2 + travel * CGFloat(stage.rawValue) / 4,
                                  y: railHeight / 2)
                }

                ZStack {
                    Circle()
                        .fill(reading.meterTint)
                        .frame(width: puck, height: puck)
                        .shadow(color: reading.meterTint.opacity(compact ? 0 : 0.45),
                                radius: compact ? 0 : 6, y: compact ? 0 : 2)
                    Image(systemName: reading.furthest?.meterIcon ?? "shippingbox")
                        .font(.system(size: compact ? 10 : 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                .position(x: position, y: railHeight / 2)
            }
        }
        .frame(height: puck)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    /// One notch per stage: filled when a scan exists, hollow when the box got
    /// past it without one.
    @ViewBuilder
    private func notch(_ stage: JobBoxTripStage) -> some View {
        let size: CGFloat = compact ? 4 : 5
        switch reading.state(stage) {
        case .scanned:
            Circle()
                .fill(.white)
                .frame(width: size, height: size)
        case .skipped:
            Circle()
                .strokeBorder(Color.secondary.opacity(0.7), lineWidth: 1.5)
                .frame(width: size + 2, height: size + 2)
        case .pending:
            Circle()
                .fill(Color(.quaternaryLabel))
                .frame(width: size, height: size)
        }
    }

    private var accessibilityDescription: String {
        var parts = [reading.headline, "\(reading.scannedCount) of 4 stages scanned"]
        if let note = reading.skipNote { parts.append(note) }
        return parts.joined(separator: ", ")
    }
}

// MARK: - The whole card

/// The meter with its headline, for a screen that gives the box a section of its
/// own. Both the shift detail and the design lab use exactly this.
struct JobBoxProgressCard: View {
    let reading: JobBoxProgressReading
    let boxNumber: String
    /// A second box on the same job is rare (2 of 349 shifts) but real, and the
    /// old card silently showed one and hid the other.
    var otherBoxCount: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                AmbientSectionTitle("Job box")
                Spacer(minLength: 0)
                if !boxNumber.isEmpty {
                    Text("#\(boxNumber)")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(reading.meterTint)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(reading.headline)
                    .font(.system(size: 22, weight: .semibold))
                Text(reading.detailLine())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            JobBoxProgressMeter(reading: reading)

            if let note = reading.skipNote {
                Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if otherBoxCount > 0 {
                Text(otherBoxCount == 1
                     ? "1 other box was scanned for this job"
                     : "\(otherBoxCount) other boxes were scanned for this job")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }
}
