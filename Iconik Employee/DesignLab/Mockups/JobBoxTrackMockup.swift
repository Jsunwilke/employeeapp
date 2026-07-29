//  JobBoxTrackMockup.swift
//  Iconik Employee — the job box meter, kept as a validation reference
//
//  ARC SCAFFOLDING. Deleted once the operator confirms the converted screens on
//  a device; the rest of the lab goes at AMB.12.
//
//  THIS FILE NO LONGER CONTAINS A DESIGN.
//
//  It draws `JobBoxProgressCard` and `JobBoxProgressMeter` from
//  `JobBox/JobBoxProgressMeter.swift` — the SAME types the shift detail and the
//  manager tracker draw — and reads them through `JobBoxProgressRules`, the same
//  rules. That inversion is the point (AMB.7's mechanism): a mockup the real
//  screen COPIES is a matching exercise prose cannot hold, and this arc has
//  already shipped a static day strip where the lab scrolled. There is no copying
//  step left to get wrong; what changes here changes in production, and vice
//  versa.
//
//  WHAT IT IS STILL FOR
//      Sample data. The real screens can only show the boxes that exist on the
//      job you happen to be looking at, and the state that matters most —
//      Packed-then-Turned-In, 31 live boxes — is the one you cannot conjure on
//      demand. This screen puts all four real shapes behind a picker, and keeps a
//      faithful copy of the OLD drawing beside them so the change is checkable
//      rather than remembered.
//
//  THE THREE ROUNDS THIS WENT THROUGH, because the record is the useful part
//      1. Four options around the existing four-dot stepper. Rejected: "almost
//         identical to what i have that looks wonky". I had fixed the bar's
//         geometry and its truthfulness and then LED with an option captioned
//         "smallest change from today".
//      2. The stepper deleted entirely — a sentence, a luggage tag, an alert, a
//         log. Rejected: "not really liking any of those. I do want some sort of
//         progress meter though."
//      3. Four real meters: a ring, a block bar, a filling crate, and a scrubber.
//         THE SCRUBBER WAS CHOSEN (operator, 2026-07-29) and is now production.
//
//      The lesson is round 1's: I turned a scope rule about CODE (no data,
//      service or schema changes) into a ceiling on the DESIGN, which is the same
//      D12 failure the bottom tab bar went through in AMB.4.

import SwiftUI

// MARK: - Sample data

/// Each case is a real shape from the live `job_boxes` table, in the proportion
/// it occurs there (counts taken 2026-07-29 over the 351 boxes carrying a shift).
enum LabBoxScenario: String, CaseIterable, Identifiable {
    case packedOnly
    case inFlight
    case skippedTwo
    case fullWalk
    case reusedBox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .packedOnly: return "Packed only"
        case .inFlight: return "Out"
        case .skippedTwo: return "2 skipped"
        case .fullWalk: return "All four"
        case .reusedBox: return "Reused"
        }
    }

    var incidence: String {
        switch self {
        case .packedOnly: return "199 of 351 boxes — the most common state by far"
        case .inFlight: return "47 boxes sit here; 6 more reach Left job"
        case .skippedTwo: return "31 boxes go Packed straight to Turned in — the case the old bar drew as four ticks"
        case .fullWalk: return "35 boxes — only 10% walk every stage"
        case .reusedBox: return "A box on its SECOND trip. The meter must show this trip, not the season."
        }
    }

    var boxNumber: String {
        switch self {
        case .packedOnly: return "3041"
        case .inFlight: return "3028"
        case .skippedTwo: return "3017"
        case .fullWalk: return "3005"
        case .reusedBox: return "3028"
        }
    }

    /// Built as scan POINTS rather than database rows, because that is the seam
    /// the rules are written against — the row-to-point adapter is production's
    /// and is exercised by the real screens.
    var log: [JobBoxScanPoint] {
        let now = Date()
        func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }
        func scan(_ s: JobBoxTripStage, _ who: String?, _ h: Double) -> JobBoxScanPoint {
            JobBoxScanPoint(stage: s, who: who, at: ago(h))
        }

        switch self {
        case .packedOnly:
            return [scan(.packed, nil, 30)]
        case .inFlight:
            return [scan(.packed, nil, 26), scan(.pickedUp, "Isaac", 9), scan(.leftJob, "Isaac", 2.5)]
        case .skippedTwo:
            return [scan(.packed, nil, 52), scan(.turnedIn, "Rylee", 4)]
        case .fullWalk:
            return [scan(.packed, nil, 78), scan(.pickedUp, "Isaac", 54),
                    scan(.leftJob, "Isaac", 28), scan(.turnedIn, "Isaac", 26)]
        case .reusedBox:
            // June's completed trip, then a repack. Only the second trip counts.
            return [scan(.packed, nil, 900), scan(.pickedUp, "Isaac", 890),
                    scan(.leftJob, "Isaac", 870), scan(.turnedIn, "Isaac", 868),
                    scan(.packed, nil, 20), scan(.pickedUp, "Zada", 6)]
        }
    }

    var reading: JobBoxProgressReading { JobBoxProgressReading(log: log) }
}

// MARK: - The screen

struct JobBoxTrackMockup: View {
    static let featureTint = Color(hex: "#0B8BA8")

    @State private var scenario: LabBoxScenario = .skippedTwo

    private var reading: JobBoxProgressReading { scenario.reading }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: Self.featureTint, intensity: 0.8)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    premise
                    statePicker

                    section("Shipped — the shift detail's card",
                            "The production type, not a copy of it. This is exactly what a photographer sees on a job.") {
                        JobBoxProgressCard(reading: reading, boxNumber: scenario.boxNumber)
                    }

                    section("Shipped — the manager tracker's row",
                            "The same meter, compact form. The tracker used to hand-roll its own four pills with a different colour map, so the two screens disagreed about the same box.") {
                        managerRow
                    }

                    section("A job with two boxes",
                            "Rare — 2 of 349 shifts — and the old card silently showed one and hid the other.") {
                        JobBoxProgressCard(reading: reading, boxNumber: scenario.boxNumber,
                                           otherBoxCount: 1)
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
        Text("The scrubber, shipped. Everything below is drawn by the production types — change one and this screen changes with it. Switch the state to check the awkward shapes.")
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
                .fixedSize(horizontal: false, vertical: true)

            Text("\(reading.scannedCount) of 4 scanned · position \(Int(reading.positionFraction * 100))%")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    /// The manager list row's shape, so the compact meter is judged at the size it
    /// actually runs at rather than blown up.
    private var managerRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Mt Vernon High").font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Text("#\(scenario.boxNumber)").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                JobBoxProgressMeter(reading: reading, compact: true)
                    .frame(maxWidth: 116)
                Text(reading.headline)
                    .font(.caption).fontWeight(.medium)
                    .foregroundColor(reading.meterTint)
                if !reading.skipped.isEmpty {
                    Text("\(reading.scannedCount)/4")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .ambientCard(density: .compact, fillWidth: true)
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, _ note: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            content()
        }
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("What it replaced")
            Text("The old drawing, reproduced exactly. Two defects: the rail started at the dot's centre and stopped short of the next one, and every stage below the latest scan was ticked whether or not it was ever scanned. Set the state to “2 skipped” to see it claim two scans that never happened.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LabJobBoxToday(reading: reading, boxNumber: scenario.boxNumber)
        }
    }
}

// MARK: - The old drawing, reproduced

/// A faithful copy of the `jobBoxCard` track this replaced — same constants, same
/// `step >= number` rule — so the comparison is against what actually shipped
/// rather than against a description of it.
///
/// This is the ONE thing in the file that is deliberately not production code: it
/// is a record of a deleted defect, and it dies with the mockup.
private struct LabJobBoxToday: View {
    let reading: JobBoxProgressReading
    let boxNumber: String

    private var step: Int { reading.latest?.stage.rawValue ?? 0 }

    private var highlight: Color {
        switch reading.latest?.stage {
        case .pickedUp: return .blue
        case .leftJob: return .orange
        case .turnedIn: return .green
        default: return .gray          // <- .packed landed here, the commonest state
        }
    }

    private let steps = ["Packed", "Picked up", "Left job", "Turned in"]

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
                ForEach(Array(steps.enumerated()), id: \.offset) { index, title in
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
                        Text(title)
                            .font(.system(size: 10, weight: done ? .semibold : .regular))
                            .foregroundStyle(done ? .primary : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .top) {
                        if index < steps.count - 1 {
                            Rectangle()
                                .fill(step > number ? highlight : Color(.tertiarySystemFill))
                                .frame(height: 2)
                                .padding(.leading, 20)
                                .offset(x: 24, y: 13)
                        }
                    }
                }
            }
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }
}
