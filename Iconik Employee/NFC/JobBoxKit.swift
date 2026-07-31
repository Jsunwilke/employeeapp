//  JobBoxKit.swift
//  Iconik Employee — the AMB.11 job box / NFC component kit
//
//  THE DESIGN LIVES HERE, AND THE DESIGN LAB IMPORTS IT.
//
//  That inversion is the mechanism AMB.7 built and `JobBoxProgressMeter.swift`
//  already ships under: if the lab owns a component and the real screen copies
//  it, the conversion is a matching exercise that prose cannot hold — AMB.1
//  shipped a static day strip where the lab scrolled, twice. So these components
//  are the operator-approved `JobBoxMockup` ones, moved into production and taking
//  plain values instead of lab sample data. The mockup keeps its private copies
//  only until the conversion slices land, at which point it draws THESE.
//
//  Spacing, fonts, materials and the `ambient-allow` reasons are carried over
//  verbatim from the approved mockup. A component here that renders differently
//  from the design the operator approved is a defect, not a refinement.
//
//  WHAT IS NOT HERE: the tracker row, the box bubble and the card bubble. Those
//  are built by the slices that own their screens, from production models, out of
//  these primitives — they are compositions, not vocabulary.

import SwiftUI

// MARK: - Controls

/// A filter chip. From `JobBoxLabChip`.
struct JobBoxChip: View {
    let text: String
    let on: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(on ? .white : .primary)
                .padding(.horizontal, 12).padding(.vertical, 8)
                // ambient-allow: a filter chip, not a container.
                .background(Capsule().fill(on ? AnyShapeStyle(tint) : AnyShapeStyle(.ultraThinMaterial)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(on ? 0 : 0.12)))
        }
        .buttonStyle(.plain)
    }
}

/// One tab in the NFC sub-shell's tab row. From `JobBoxLabTabRow`'s cells —
/// hoisted out of the row so the container slice can lay the pills out in an
/// `AmbientFlowLayout` itself.
///
/// The five tabs used to be one hardcoded colour each
/// (`.orange`/`.blue`/`.green`/`.purple`/`.teal`), bypassing `FeatureTheme`
/// entirely; one feature is one colour, and the caller passes it.
struct JobBoxTabPill: View {
    let title: String
    let systemImage: String
    let on: Bool
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button {
            withAnimation(AmbientMotion.snappy) { action() }
            AmbientHaptics.selection()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(on ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                // ambient-allow: a tab control, not a container.
                .background(Capsule().fill(on
                                           ? AnyShapeStyle(tint)
                                           : AnyShapeStyle(.ultraThinMaterial)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(on ? 0 : 0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// The search field. From `JobBoxLabSearchField`.
///
/// `keyboard` is the one addition the lab component did not need: Search's box /
/// card number field is `.numberPad` today and must stay that way, and a
/// `.keyboardType` applied by the CALLER to this whole view is not a contract
/// SwiftUI guarantees to forward to the `TextField` inside it. Defaulted, so
/// every other call site reads exactly as the mockup does.
struct JobBoxSearchField: View {
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .font(.subheadline)
                .keyboardType(keyboard)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .ambientCard(density: .compact, fill: .surface,
                     border: .hairline(Color.primary.opacity(0.10)), fillWidth: true)
    }
}

// MARK: - Readouts

/// One status's share of a total, as a labelled bar. From
/// `JobBoxLabDistributionRow`.
struct JobBoxDistributionRow: View {
    let label: String
    let count: Int
    let total: Int
    let tint: Color

    private var fraction: Double {
        total == 0 ? 0 : Double(count) / Double(total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.footnote.weight(.semibold))
                Spacer(minLength: 8)
                Text("\(count) · \(String(format: "%.1f%%", fraction * 100))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill)).frame(height: 8)
                    Capsule().fill(tint.gradient)
                        .frame(width: max(0, geo.size.width * fraction), height: 8)
                }
            }
            .frame(height: 8)
        }
    }
}

/// A label and its value on one line. From `JobBoxLabStatLine`.
struct JobBoxStatLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.footnote).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).font(.footnote.weight(.semibold)).multilineTextAlignment(.trailing)
        }
    }
}

/// The flagged treatment for a box row.
///
/// NEW IN AMB.11 — the mockup drew "Flag for Attention" as ABSENT, because the
/// three columns it wrote did not exist and nothing read them. The operator's
/// 2026-07-30 ruling was to BUILD it: the columns are real now
/// (`supabase/drafts/20260730_amb11_jobbox_flag_columns.sql`) and this is how a
/// flagged box reads.
///
/// RED IS CORRECT HERE. D14 reserves the app-wide WASH — one blue for every
/// screen — but momentary and status colours keep their meaning, and the
/// operator's words were that red means flagged.
struct JobBoxFlagBadge: View {
    let note: String?
    let flaggedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                AmbientBadge(text: "Flagged", systemImage: "flag.fill", tint: .red)
                if let flaggedAt {
                    Text(JobBoxFormat.elapsed(since: flaggedAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if let note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(note)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Reading a box's current trip off its rows

/// The CURRENT-TRIP CUT, applied to DATABASE ROWS rather than scan points.
///
/// `JobBoxProgressRules` owns the cut itself and this does not re-implement it:
/// it builds the reading, takes the boundary the reading already decided, and
/// maps it back onto the `JobBox` rows — which is what the FLAG columns live on
/// (`JobBoxScanPoint` deliberately does not carry them, so the rules file can
/// compile with nothing but Foundation).
///
/// It lives here rather than in `JobBoxFlagRules.swift` because that file is
/// compiled STANDALONE by `scripts/test_jobbox_flag_rules.sh`, and `JobBox`
/// imports Supabase.
///
/// Two screens need this: the manager tracker (`JobBoxWithEvent.currentTripRows`)
/// and the photographer's scan sheet (`JobBoxFormView`). One implementation, so
/// the flag a manager sees and the flag a photographer sees are the same reading.
enum JobBoxCurrentTrip {
    /// The rows of the box's current trip — everything from the last Packed scan
    /// onward. A log with no readable scan at all has no seam to cut on, so every
    /// row stays in.
    static func rows(from rows: [JobBox]) -> [JobBox] {
        guard let start = JobBoxProgressReading(rows: rows).scans.first?.at else { return rows }
        return rows.filter { $0.timestampDate >= start }
    }
}

// MARK: - States

/// The loading state. From `JobBoxLabLoading`.
struct JobBoxLoadingCard: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(message).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .ambientCard(density: .roomy, fillWidth: true, contentAlignment: .center)
    }
}

/// The failure state, with a real retry. From `JobBoxLabFailure` MINUS the lab's
/// caption — that text explained the mockup to the operator and is not part of
/// the production screen.
struct JobBoxFailureCard: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: retry) {
                Label("Retry", systemImage: "arrow.clockwise")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    // ambient-allow: a retry control, not a container.
                    .background(Capsule().fill(Color.orange))
            }
            .buttonStyle(.plain)
        }
        .ambientCard(density: .compact, fillWidth: true)
    }
}

// MARK: - Formatting

/// From `JobBoxLabFormat`.
enum JobBoxFormat {
    /// One relative formatter, hoisted — the tracker allocates a
    /// `RelativeDateTimeFormatter` per access and calls it twice per row.
    static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    static func elapsed(since date: Date?) -> String {
        guard let date else { return "never scanned" }
        return relative.localizedString(for: date, relativeTo: Date())
    }

    static func stamp(_ date: Date?) -> String {
        guard let date else { return "—" }
        return Formatters.mediumDateTime.string(from: date)
    }
}
