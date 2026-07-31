//  JobBoxBubbleView.swift
//  Iconik Employee — one job-box scan, as a row (AMB.11)
//
//  Built from the approved mockup's `JobBoxLabBoxBubble`: status dot, the status
//  as a status-coloured headline, "Box #n · school", who and when, and the
//  left-at-a-job warning.
//
//  DELETED HERE:
//    - the hand-rolled `systemGray6` + radius 12 container (now `.ambientCard`);
//    - the per-body `DateFormatter` (finding N42);
//    - `formatTimeDifference` (findings N42/N51) — a SECOND, different elapsed
//      implementation whose `hours > 24` boundary rendered exactly 24h as
//      "24 hours" rather than "1 day". `JobBoxFormat.elapsed` is the one
//      formatter, hoisted and shared;
//    - the hardcoded `43200` (finding N27, the third copy of it). The threshold
//      is `NFCRoutingRules.leftJobAlertThreshold`, which the routing-rules test
//      script compiles and runs;
//    - `"School: "` rendered with nothing after it when `school` is NULL
//      (§1.11) — the school segment is drawn only when there is one.

import SwiftUI

struct JobBoxBubbleView: View {
    let record: JobBox

    private var statusColor: Color {
        // The one job-box colour contract (operator ruling 2026-07-30). The
        // fallback is the never-scanned colour for a status this app cannot read.
        JobBoxTripStage(stored: record.status)?.meterTint ?? Color(hex: "#7A8794")
    }

    private var identityLine: String {
        let school = (record.school ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return school.isEmpty ? "Box #\(record.boxNumber)" : "Box #\(record.boxNumber) · \(school)"
    }

    /// Who and when — the name omitted when the row has none rather than
    /// invented. 336 of 1,059 live rows have no photographer.
    private var detailLine: String {
        let stamp = Formatters.mediumDateTime.string(from: record.timestampDate)
        let who = record.scannedBy.trimmingCharacters(in: .whitespacesAndNewlines)
        return who.isEmpty ? stamp : "\(who) · \(stamp)"
    }

    private var isOverdueAtJob: Bool {
        guard record.jobBoxStatus == .leftJob else { return false }
        return Date().timeIntervalSince(record.timestampDate) > NFCRoutingRules.leftJobAlertThreshold
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                Text(record.status)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(statusColor)

                Text(identityLine).font(.caption)

                Text(detailLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // A FLAG IS FOR EVERYONE (operator ruling 2026-07-31), so Search
                // shows it too. ROW-LEVEL is the honest read HERE and only here:
                // each bubble IS one scan row, not a box, so it reports whether
                // THIS row is flagged. The box-level (current-trip) reading is the
                // manager tracker's and the scan sheet's.
                if record.flagged {
                    JobBoxFlagBadge(note: record.flag_note, flaggedAt: record.flagged_at)
                }

                if isOverdueAtJob {
                    // "Left 5mo ago", not "Left for 5mo ago": `JobBoxFormat.elapsed`
                    // returns a relative phrase that already ends in "ago", and
                    // "for … ago" is not a sentence.
                    Label("Left \(JobBoxFormat.elapsed(since: record.timestampDate))",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            Spacer(minLength: 0)
        }
        .ambientCard(density: .compact, fillWidth: true)
    }
}
