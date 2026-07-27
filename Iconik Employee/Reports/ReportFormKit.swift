//  ReportFormKit.swift
//  Iconik Employee — the daily job report's form components
//
//  PRODUCTION CODE, used by the lab mockup. That direction matters: the mockup
//  imports these, so when AMB.7 converts the real screen it imports the SAME
//  ones. There is no copying step, and therefore no drift.
//
//  WHY THIS EXISTS
//      The operator asked how the conversion would build the design EXACTLY
//      rather than treating it as inspiration. The honest answer was that the
//      mechanism we had — step 3b of the phase kickoff, "account for EVERY
//      difference" — has already failed: it was in place when AMB.1 shipped a
//      static day strip where the lab scrolled, and then shipped it scrolling at
//      the wrong capsule width. A stronger instruction was not the answer.
//
//      So the answer is that there is nothing to match. A converted screen
//      cannot have different padding, a different checkbox, a different heading
//      weight or a different confirm layout, because it is not drawing them —
//      these are. Same reasoning as AmbientCard and its drift gate: a design
//      nobody is forced to use is decoration.
//
//  WHAT IS DELIBERATELY NOT HERE
//      Anything that knows about a report. These take plain values and bindings,
//      so the lab can feed them sample data and production can feed them the
//      real thing without either one owning the other.

import SwiftUI

// MARK: - Section

/// One part of the report.
///
/// EVERY section goes through this, which is the point: the moment one gets its
/// own heading treatment the layout starts ranking things again, and the
/// operator's instruction was "nothing is secondary. it is all important."
struct ReportSection<Content: View>: View {
    let title: String
    /// The short state summary on the right of the heading — "3 selected",
    /// "18.2 mi · Personal", "2 of 3 answered". Together these let the state of
    /// the whole report be read in one scroll.
    let status: String
    /// Nil leaves the status tertiary, which is how "nothing here yet" reads.
    var statusTint: Color?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline)
                Spacer(minLength: 8)
                Text(status)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusTint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.tertiary))
                    .contentTransition(.numericText())
                    .multilineTextAlignment(.trailing)
            }
            content()
                // An OPAQUE panel plus a lit edge. A glass card over a tinted
                // wash sits at nearly the same value as the page, and eight of
                // them read as one mass — the operator's words were that they
                // "practically blend in with the background". `.surface` was
                // added to AmbientCard for this rather than hand-rolling a
                // background or abusing `state: .highlighted` for a heavier
                // material it does not mean.
                .ambientCard(density: .compact,
                             fill: .surface,
                             border: .hairline(Color.primary.opacity(0.10)),
                             fillWidth: true)
        }
    }
}

// MARK: - Multi-select

/// A long fixed option list — the 22 job descriptions, the 12 extra items.
///
/// Everything visible, nothing behind a disclosure control. Grouped under
/// families, TWO COLUMNS, checkbox leading, whole cell tappable.
///
/// THE ORDER NEVER CHANGES. Not by recency, not by frequency. A controlled study
/// (Findlater & McGrenere, CHI 2004) measured adaptive menus as SLOWER than
/// static ones, because frequent users learn where things are — and a
/// photographer files this ~200 times a year.
struct ReportMultiSelect: View {
    /// Families, in a fixed order, each with its options in a fixed order.
    /// Grouping is presentation only: every option must appear exactly once.
    let groups: [(String, [String])]
    @Binding var selection: Set<String>
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.element.0) { index, group in
                header(group.0, first: index == 0)
                // TWO COLUMNS. One per line turned 22 + 12 options into 34
                // scrolled rows; paired up it is 12 + 7. The family heading
                // still spans the full width, so the grouping survives.
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10, alignment: .leading),
                                    GridItem(.flexible(), spacing: 10, alignment: .leading)],
                          alignment: .leading, spacing: 0) {
                    ForEach(group.1, id: \.self) { option in
                        cell(option)
                    }
                }
            }

            // "NONE" is an ordinary option with no exclusivity, so it can be
            // ticked alongside others and the report is stored saying both.
            // That is a data rule and out of this arc's scope — the screen just
            // stops being silent about it.
            if selection.contains("NONE") && selection.count > 1 {
                Label("\"NONE\" is selected alongside \(selection.count - 1) other item\(selection.count == 2 ? "" : "s").",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
        }
    }

    /// Readable, not decorative. The label that organises a list should not be
    /// the smallest text in it — which is what it was when the operator said the
    /// screen was "not grouped and separated well".
    private func header(_ title: String, first: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !first { Divider().padding(.vertical, 7) }
            Text(title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 2)
        }
    }

    private func cell(_ option: String) -> some View {
        let on = selection.contains(option)
        return Button {
            withAnimation(AmbientMotion.snappy) {
                if on { selection.remove(option) } else { selection.insert(option) }
            }
            AmbientHaptics.selection()
        } label: {
            HStack(alignment: .top, spacing: 9) {
                // The box LEADS, so both columns have a hard left edge to run
                // down. A trailing control leaves the eye chasing a ragged
                // gutter, which is what a chip cloud did wrong here.
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(on ? Color.clear : Color.secondary.opacity(0.45), lineWidth: 1.5)
                        .frame(width: 21, height: 21)
                    if on {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(tint).frame(width: 21, height: 21)
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                }
                Text(option)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            // The WHOLE cell is the target, not the 21pt box.
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Single choice

/// Yes / No / NA and friends. Nothing is pre-selected and, per the live form,
/// an answer cannot be cleared once given.
struct ReportChoiceRow: View {
    let title: String
    let options: [String]
    @Binding var selection: String?
    var tint: Color = .teal

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ForEach(options, id: \.self) { option in
                    let on = selection == option
                    Button {
                        withAnimation(AmbientMotion.snappy) { selection = option }
                        AmbientHaptics.selection()
                    } label: {
                        Text(option)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(on ? .white : .primary)
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            // ambient-allow: a radio control, not a container.
                            .background(Capsule().fill(on
                                                       ? AnyShapeStyle(tint)
                                                       : AnyShapeStyle(.ultraThinMaterial)))
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(on ? 0 : 0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Vehicle

/// The vehicle control and its two-step, drawn together.
///
/// The confirmation appears INLINE, directly under the buttons that raised it.
/// The operator's reason is the whole design: the vehicle sits somewhere in a
/// long scroll, and finishing at the top of the screen something you started at
/// the bottom means changing your grip.
///
/// Behaviour is `VehicleSelection`'s, which is tested — no default, both options
/// take a second tap, the first tap never commits.
struct ReportVehiclePicker: View {
    @Binding var selection: VehicleSelection
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                button(.personal)
                button(.company)
            }

            if let pending = selection.pending {
                confirm(pending)
            } else if selection.needsChoice {
                Label("Required — pick a vehicle, then confirm it.",
                      systemImage: "exclamationmark.circle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func button(_ vehicle: VehicleSelection.Vehicle) -> some View {
        let on = selection.confirmed == vehicle
        let armed = selection.pending == vehicle
        return Button {
            withAnimation(AmbientMotion.snappy) { selection.tap(vehicle) }
            AmbientHaptics.impact(.light)
        } label: {
            Text(vehicle.rawValue.capitalized)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(on ? .white : (armed ? .orange : .primary))
                .frame(maxWidth: .infinity).padding(.vertical, 11)
                // ambient-allow: a segmented control, not a container.
                .background(Capsule().fill(on ? AnyShapeStyle(tint) : AnyShapeStyle(.ultraThinMaterial)))
                // Armed but NOT committed — a dashed edge says "this is the one
                // the confirm below is about" without pretending it is chosen.
                .overlay(
                    Capsule().strokeBorder(
                        armed ? Color.orange : Color.primary.opacity(on ? 0 : 0.12),
                        style: StrokeStyle(lineWidth: armed ? 2 : 1, dash: armed ? [5, 3] : []))
                )
        }
        .buttonStyle(.plain)
    }

    private func confirm(_ vehicle: VehicleSelection.Vehicle) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill").font(.caption.weight(.bold))
                // The live form's wording, kept.
                Text("Confirm \(vehicle.rawValue.capitalized) — this sets your mileage reimbursement and can't be changed by an accidental tap.")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.orange)

            HStack(spacing: 8) {
                Button {
                    withAnimation(AmbientMotion.snappy) { selection.cancel() }
                } label: {
                    Text("Cancel")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        // ambient-allow: a control, not a container.
                        .background(Capsule().fill(.ultraThinMaterial))
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(AmbientMotion.snappy) { selection.confirm() }
                    AmbientHaptics.impact(.medium)
                } label: {
                    Text("Yes, \(vehicle.rawValue)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        // ambient-allow: a control, not a container.
                        .background(Capsule().fill(Color.orange))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 2)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
