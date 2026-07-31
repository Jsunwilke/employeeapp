//  RecordBubbleView.swift
//  Iconik Employee — one SD-card scan, as a row (AMB.11)
//
//  Built from the approved mockup's `JobBoxLabCardBubble`: status dot, the
//  status itself as a status-coloured headline, "Card #n · school", the stamp,
//  and the upload-location line.
//
//  DELETED HERE:
//    - the hand-rolled `systemGray6` + radius 12 container (now `.ambientCard`);
//    - the per-body `DateFormatter` (finding N42) — `Formatters.mediumDateTime`
//      is one shared, already-configured `.medium`/`.short` formatter;
//    - the `"Photographer: …"` line. The `records` table has NO photographer
//      column (§0.26), so that line has always rendered `"Photographer: "` with
//      nothing after it on every online-fetched row. The mockup's card bubble
//      does not carry it.
//
//  KEPT VERBATIM: the two hardcoded house literals and their `else if`
//  precedence — a record flagged for both still shows only Jason. They are live
//  data (586 Andy rows, 27 Jason rows) and changing what they say is not a
//  design decision.

import SwiftUI

struct RecordBubbleView: View {
    let record: NFCRecord

    private var statusColor: Color {
        StatusColors.color(forSDStatus: record.status)
    }

    /// `"Card #1042 · Lincoln High"`, and just `"Card #1042"` when the row has no
    /// school — rather than a trailing separator pointing at nothing.
    private var identityLine: String {
        let school = record.school.trimmingCharacters(in: .whitespacesAndNewlines)
        return school.isEmpty ? "Card #\(record.cardNumber)" : "Card #\(record.cardNumber) · \(school)"
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

                Text(Formatters.mediumDateTime.string(from: record.timestamp))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if record.status.lowercased() == "uploaded" {
                    if let jasonHouse = record.uploadedFromJasonsHouse, !jasonHouse.isEmpty {
                        Text("📍 Uploaded from Jason's house")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if let andyHouse = record.uploadedFromAndysHouse, !andyHouse.isEmpty {
                        Text("📍 Uploaded from Andy's house")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .ambientCard(density: .compact, fillWidth: true)
    }
}
