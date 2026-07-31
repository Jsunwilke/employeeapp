//  YearbookKit.swift
//  Iconik Employee — the Yearbook design, as production code
//
//  PRODUCTION CODE THAT THE LAB MOCKUP IMPORTS. That direction is the whole
//  mechanism (AMB.7's rule, MileageKit's and TimeOffKit's shape): the mockup
//  `DesignLab/Mockups/YearbookMockup.swift` draws with the types in THIS file and
//  so do the real screens, so the design cannot drift — there is no second copy
//  to drift from.
//
//  WHAT IS DELIBERATELY NOT HERE: anything that knows about Supabase, and any
//  decision. These views take plain values and a `YearbookItem` / a
//  `YearbookShootList`; every judgement they render — what the progress fraction
//  is, whether a note badge is earned, what a category's real count is — is made
//  in `YearbookRules.swift`, which is SwiftUI-free and RUN by
//  `scripts/test_yearbook_rules.sh`.
//
//  THE FOUR CLAIMS THE OPERATOR APPROVED (2026-07-29), and where each one lives:
//    1. PROGRESS MUST NOT READ AS AN ERROR AT 0%   — `YearbookProgressRow`
//    2. FILTERS MUST COMPOSE WITH SEARCH           — `YearbookFilterChip` +
//                                                    `YearbookSearchField`, which
//                                                    set ONE thing each
//    3. WHEN EVERYTHING IS "REQUIRED", NOTHING IS  — `YearbookItemRow`'s Optional
//                                                    badge (the inversion)
//    4. A FAILED LOAD MUST SAY SO                  — `YearbookFailureCard` and
//                                                    `YearbookInlineFailure`

import SwiftUI

// MARK: - Identity

enum YearbookStyle {
    /// This feature's ACCENT (D11), read from `FeatureTheme` rather than restated
    /// — `#2E9B4F`, the deeper green of the "Groups & delivery" family, which
    /// before AMB.10 never reached these screens at all. It no longer reaches the
    /// background: D14 gives every screen the one app wash.
    static var tint: Color { FeatureTheme.color(for: "yearbookChecklists") }

    /// ONE formatter, created once.
    ///
    /// The old root row wrote `Text("Updated \(date, formatter: RelativeDateTimeFormatter())")`
    /// — a fresh formatter per row PER BODY EVALUATION. `Formatters` is the app's
    /// shared cache and has no relative formatter in it; this is the only surface
    /// that wants one, so it lives here rather than being promoted for one caller.
    static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    static func updatedLine(_ date: Date) -> String {
        "Updated \(relative.localizedString(for: date, relativeTo: Date()))"
    }
}

// MARK: - 1. The search field

/// Hand-rolled, IN THE CONTENT.
///
/// The old root screen used `.searchable`, which the arc does not use: it puts a
/// system field in the nav bar, outside the wash, and on a pushed screen it
/// competes with the title. On the checklist screen it matters more than style —
/// claim 2 is that the filters compose, and a field you cannot see to be
/// populated cannot be seen to be composing.
struct YearbookSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .font(.subheadline)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .ambientCard(density: .compact, fillWidth: true)
    }
}

// MARK: - 2. The filter chip

/// A control, not a container — see the `ambient-allow` marker.
///
/// Its action sets ONE thing. The live filter bar's three quick chips all routed
/// through the view model's `clearFilters()`, which is the defect claim 2 names.
struct YearbookFilterChip: View {
    let label: String
    let isSelected: Bool
    var tint: Color = YearbookStyle.tint
    let action: () -> Void

    var body: some View {
        Button {
            withAnimation(AmbientMotion.snappy) { action() }
            AmbientHaptics.selection()
        } label: {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                // ambient-allow: a filter chip is a control, not a container.
                .background(Capsule().fill(isSelected
                                           ? AnyShapeStyle(tint)
                                           : AnyShapeStyle(.ultraThinMaterial)))
                .overlay(Capsule().strokeBorder(Color.primary.opacity(isSelected ? 0 : 0.08)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 3. The root list card

/// ONE fill colour on a NEUTRAL track, with the number beside it doing the
/// talking.
///
/// The old row coloured the bar on a ladder — 100% green, ≥75 orange, ≥50 yellow,
/// ELSE RED — so a brand-new list, correctly at 0%, rendered RED. Red in this app
/// means something is wrong, and nothing is wrong: the season has not started.
struct YearbookProgressRow: View {
    let completed: Int
    let total: Int
    var tint: Color = YearbookStyle.tint

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                ProgressView(value: YearbookRules.progressFraction(completed: completed, total: total))
                    .progressViewStyle(.linear)
                    .tint(tint)
                Text("\(completed)/\(total)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            // A list can exist with no items in it — the row is written by the web
            // app before anyone fills it — and "0/0" alone reads as a broken screen.
            if total == 0 {
                Text("No items yet — the list exists but nothing has been added to it in the web app.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// ROOMY. A school has a handful of years, not hundreds, and the two numbers that
/// matter (how far along, how many items) both want room.
struct YearbookListCard: View {
    let list: YearbookShootList
    var tint: Color = YearbookStyle.tint

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(YearbookRules.shortSchoolYear(list.schoolYear))
                    .font(AmbientDensity.roomy.titleFont)
                if list.isActive {
                    AmbientBadge(text: "Current", systemImage: "star.fill", tint: tint)
                }
                Spacer(minLength: 0)
                if list.isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(tint)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }

            YearbookProgressRow(completed: list.completedCount, total: list.totalCount, tint: tint)

            if let summary = YearbookRules.categorySummary(list.items) {
                Text(summary)
                    .font(AmbientDensity.roomy.subtitleFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(YearbookStyle.updatedLine(list.updatedAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }
}

// MARK: - 4. The checklist hero

/// The percentage as a gauge. 64pt, 8pt stroke, animated.
struct YearbookProgressRing: View {
    let completed: Int
    let total: Int
    var tint: Color = YearbookStyle.tint

    var body: some View {
        let fraction = YearbookRules.progressFraction(completed: completed, total: total)
        return ZStack {
            // ambient-allow: a progress ring is a gauge, not a container.
            Circle()
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 8)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(AmbientMotion.gentle, value: fraction)
            Text("\(YearbookRules.progressPercent(completed: completed, total: total))%")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
        }
        .frame(width: 64, height: 64)
    }
}

/// The ring leads, and the per-category counts wrap beneath it.
///
/// The old header showed ONE overall number, so "which part of the book is
/// behind" was a question you answered by tapping through every category chip in
/// turn. The counts here are of the WHOLE category (`YearbookRules`), never of
/// whatever the filter left.
struct YearbookHeroCard: View {
    let schoolName: String
    let schoolYear: String
    let items: [YearbookItem]
    let completedCount: Int
    let totalCount: Int
    var tint: Color = YearbookStyle.tint

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                YearbookProgressRing(completed: completedCount, total: totalCount, tint: tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(completedCount) of \(totalCount) completed")
                        .font(.system(size: 19, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(YearbookRules.listTitle(schoolName: schoolName, schoolYear: schoolYear))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            AmbientFlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(YearbookRules.categories(in: items), id: \.self) { name in
                    AmbientBadge(text: "\(name) \(YearbookRules.categoryCountLabel(items, category: name))",
                                 tint: YearbookRules.categoryIsComplete(items, category: name) ? tint : .secondary)
                }
            }
        }
        .ambientCard(density: .hero, state: .highlighted, glow: tint, fillWidth: true)
    }
}

// MARK: - 5. The item row

/// One line of the checklist: tick it, or open it.
///
/// The checkbox and the body are SEPARATE buttons — the old row put a whole-row
/// tap gesture over a checkbox button, which is two targets fighting for the same
/// pixels.
struct YearbookItemRow: View {
    let item: YearbookItem
    var tint: Color = YearbookStyle.tint
    let onToggle: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(item.completed
                                     ? AnyShapeStyle(tint)
                                     : AnyShapeStyle(Color.secondary))
                    // A 22pt glyph is under the 44pt touch minimum, and this is the
                    // control a photographer taps most on the screen.
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.completed ? "Mark \(item.name) incomplete" : "Mark \(item.name) complete")

            Button(action: onTap) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(item.name)
                            .font(AmbientDensity.compact.titleFont)
                            .strikethrough(item.completed)
                            .foregroundStyle(item.completed
                                             ? AnyShapeStyle(Color.secondary)
                                             : AnyShapeStyle(Color.primary))
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)

                        // THE INVERSION (claim 3): `required` is the default and
                        // therefore silent; the few optional items are marked.
                        if YearbookRules.showsOptionalBadge(item) {
                            AmbientBadge(text: "Optional", tint: .secondary)
                        }

                        Spacer(minLength: 0)

                        if YearbookRules.hasNote(item.notes) {
                            Image(systemName: "note.text")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.orange)
                        }
                    }

                    if let description = item.description, !description.isEmpty {
                        Text(description)
                            .font(AmbientDensity.compact.subtitleFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if item.completed,
                       let attribution = YearbookRules.attribution(
                        photographerName: item.photographerName,
                        completedDate: item.completedDate,
                        monthDay: { Formatters.monthDay.string(from: $0) }) {
                        Text(attribution)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if let images = YearbookRules.imageCountLabel(item.imageNumbers) {
                        Text(images)
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // FOUND ON DEVICE: without this the button is only tappable ON THE
                // GLYPHS. A `Button`'s hit region is its label's content shape, and
                // a VStack of Text stretched with `.frame(maxWidth: .infinity)` has
                // no fill — so the right-hand two thirds of every row was dead
                // space that looked exactly like the part that worked.
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .ambientCard(density: .compact,
                     state: item.completed ? .receded : .normal,
                     fillWidth: true)
    }
}

// MARK: - 6. The year picker row

/// One school year in the session-entry picker.
struct YearbookYearRow: View {
    let year: String
    let isCurrent: Bool
    var tint: Color = YearbookStyle.tint
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(year)
                    .font(AmbientDensity.compact.titleFont)
                if isCurrent {
                    AmbientBadge(text: "Current", systemImage: "star.fill", tint: tint)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .ambientCard(density: .compact, fillWidth: true)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 7. The states the screens did not have

/// A failed load, said out loud, with the retry the copy names.
///
/// Before AMB.10 a dropped connection on the session entry rendered "No Yearbook
/// List Found — no yearbook checklist exists for X", which is a factual claim
/// about the SCHOOL made on the strength of a network error. A photographer who
/// reads it stops looking.
struct YearbookFailureCard: View {
    var systemImage: String = "exclamationmark.triangle.fill"
    let title: String
    let message: String
    var retryTitle: String = "Try Again"
    var tint: Color = YearbookStyle.tint
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 30))
                .foregroundStyle(.orange)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: retry) {
                Label(retryTitle, systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    // ambient-allow: a control, not a card.
                    .background(Capsule().fill(tint))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    /// The sentence a failed load gets when the error itself is not worth showing.
    static let genericMessage =
        "The server didn't answer. Your lists are safe — this screen just can't show them right now."
}

/// A failure that happened to ONE action while the screen around it is fine — a
/// toggle that did not save, a note that did not write.
///
/// `viewModel.error` was set in three places and read by nothing on the checklist
/// and detail screens, so a failed check-off was completely silent. It is
/// dismissible because the screen is still usable: this is a report, not a state.
struct YearbookInlineFailure: View {
    let message: String
    var systemImage: String = "xmark.octagon.fill"
    var tint: Color = .red
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: systemImage).font(.caption.weight(.semibold))
            Text(message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.caption2.weight(.bold))
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(tint)
        .ambientCard(density: .compact,
                     border: .hairline(tint.opacity(0.4)),
                     fillWidth: true)
    }
}

/// The list while it is on its way. Drawn in place of the content rather than over
/// the whole screen.
struct YearbookLoadingRow: View {
    var message: String = "Loading…"

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text(message).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
