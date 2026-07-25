//  DashboardMockup.swift
//  Iconik Employee — AMB.4's mockup
//
//  ARC SCAFFOLDING. Deleted with the rest of the lab at AMB.12.
//
//  The home dashboard is the most-opened screen in the app and the one whose
//  Upcoming Shifts widget currently disagrees with the schedule the arc has
//  already converted. This is the proposal.
//
//  THE WASH  (operator decision, 2026-07-25)
//      D11 gives every screen its feature's colour, but home is not a feature —
//      it is the container, and it already carries a stack of coloured cards.
//      Full strength would fight all of them; none at all leaves the cards the
//      same colour as the page behind them, which is why today's dashboard reads
//      flat. So: the company blue from the logo, turned right down.
//
//  WHAT THIS FIXES, BESIDES THE STYLING
//      The live widget paints its colour rail by looking up `session.position`
//      in a table of job titles — but that field holds a session TYPE, so the
//      lookup almost always misses and falls through to blue. Nearly every shift
//      on the dashboard is blue today regardless of what the scheduler chose.
//      This mockup uses the scheduler's colour, the same as the schedule does.

import SwiftUI

struct DashboardMockup: View {
    /// So the operator can see the decision, not just the result.
    @State private var washIntensity: Double = 0.28

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: AmbientStyle.brand, intensity: washIntensity)

            ScrollView {
                VStack(spacing: 16) {
                    washControl
                    hoursWidget
                    mileageWidget
                    upcomingShiftsWidget
                    tasksWidget
                    allFeaturesButton
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - The one control

    private var washControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(AmbientStyle.brand).frame(width: 12, height: 12)
                Text("Company blue, turned down")
                    .font(.footnote.weight(.semibold))
                Spacer()
                Text(washIntensity == 0 ? "off" : "\(Int(washIntensity * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $washIntensity, in: 0...1)
                .tint(AmbientStyle.brand)
            Text("Drag to nothing and back. The schedule runs at 100% because its colour means something; home is carrying its own colours already, so it wants far less.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .ambientCard(density: .compact, fillWidth: true)
    }

    // MARK: - Hours

    private var hoursWidget: some View {
        let d = DesignLabSampleData.Dashboard.self
        return VStack(alignment: .leading, spacing: 14) {
            widgetHeader("Hours Tracking", systemImage: "clock.fill", tint: .yellow) {
                HStack(spacing: 5) {
                    Image(systemName: "stop.circle.fill")
                    Text("2h 24m")
                        .font(.caption.weight(.semibold)).monospacedDigit()
                }
                .foregroundStyle(.red)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Capsule().fill(Color.red.opacity(0.12)))
            }

            meter(label: "This week", value: d.weekHours, target: d.weekTarget,
                  live: d.activeHours, tint: .blue)
            meter(label: "Pay period", value: d.periodHours, target: d.periodTarget,
                  live: d.activeHours, tint: .indigo)
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    private func meter(label: String, value: Double, target: Double,
                       live: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label).font(.subheadline.weight(.medium))
                Spacer()
                Text("\(hours(value)) / \(Int(target))h")
                    .font(.caption.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(tint.gradient)
                        .frame(width: geo.size.width * min(value / target, 1))
                    Capsule()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: geo.size.width * min(live / target, 1))
                        .offset(x: geo.size.width * min((value - live) / target, 1))
                }
            }
            .frame(height: 10)
        }
    }

    private func hours(_ value: Double) -> String {
        let total = Int((value * 60).rounded())
        return "\(total / 60)h \(String(format: "%02d", total % 60))m"
    }

    // MARK: - Mileage

    private var mileageWidget: some View {
        let d = DesignLabSampleData.Dashboard.self
        return VStack(alignment: .leading, spacing: 12) {
            widgetHeader("Mileage", systemImage: "car.fill", tint: .orange) {
                Text("View all").font(.caption.weight(.semibold))
                    .foregroundStyle(AmbientStyle.brand)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(d.periodMiles)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("mi").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(d.periodPay)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.green)
            }
            AmbientPillRow(pills: [
                .init(text: "Personal \(d.personalMiles)", systemImage: "person.fill", tint: .orange),
                .init(text: "Company \(d.companyMiles)", systemImage: "building.2.fill", tint: .teal),
            ], density: .compact)

            Divider().opacity(0.4)

            HStack {
                labelled("This month", "\(d.monthMiles) mi")
                Spacer()
                labelled("This year", "\(d.yearMiles) mi", trailing: true)
            }
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    private func labelled(_ caption: String, _ value: String, trailing: Bool = false) -> some View {
        VStack(alignment: trailing ? .trailing : .leading, spacing: 2) {
            Text(caption).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }

    // MARK: - Upcoming shifts  (the one that disagrees with the schedule today)

    private var upcomingShiftsWidget: some View {
        VStack(alignment: .leading, spacing: 12) {
            widgetHeader("Upcoming Shifts", systemImage: "calendar", tint: .red) {
                Text("3").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(DesignLabSampleData.upcomingShifts) { shift in
                    shiftRow(shift)
                }
            }
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    /// The schedule's row vocabulary, at dashboard scale: the stacked time
    /// column, the type pills, the crew stack, the scheduler's colour.
    private func shiftRow(_ shift: LabShift) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 1) {
                Text(Formatters.shortTime.string(from: shift.start))
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Rectangle().fill(shift.accent.opacity(0.35))
                    .frame(width: 2).frame(maxHeight: .infinity)
                Text(Formatters.shortTime.string(from: shift.end))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            .frame(width: 52)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(shift.school)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    if let dayLabel = shift.dayLabel {
                        AmbientBadge(text: dayLabel, systemImage: "square.stack.3d.up.fill",
                                     tint: shift.accent)
                    }
                }
                AmbientPillRow(pills: shift.types.map {
                    .init(text: $0.name, tint: Color(hex: $0.hex))
                }, density: .compact)
                AmbientAvatarStack(
                    subjects: shift.crew.map { .init(id: $0, name: $0) },
                    size: 20, maxVisible: 4)
            }
            Spacer(minLength: 0)
        }
        .ambientCard(density: .compact,
                     border: .hairline(shift.accent.opacity(0.35)))
    }

    // MARK: - Tasks

    private var tasksWidget: some View {
        VStack(alignment: .leading, spacing: 12) {
            widgetHeader("Tasks", systemImage: "checklist", tint: .green) {
                Text("View all").font(.caption.weight(.semibold))
                    .foregroundStyle(AmbientStyle.brand)
            }
            VStack(spacing: 8) {
                ForEach(DesignLabSampleData.urgentTasks) { task in
                    taskRow(task)
                }
            }
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    private func taskRow(_ task: LabTask) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "circle")
                .font(.system(size: 17))
                .foregroundStyle(.secondary)
            Capsule().fill(task.priority.color).frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    AmbientBadge(text: task.status.rawValue, tint: task.status.color)
                    Label(task.due, systemImage: task.overdue ? "exclamationmark.triangle.fill" : "calendar")
                        .font(.caption2)
                        .foregroundStyle(task.overdue ? .red : .secondary)
                    if task.subtasks.1 > 0 {
                        Label("\(task.subtasks.0)/\(task.subtasks.1)", systemImage: "checklist")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .ambientCard(density: .compact, border: .hairline(Color.primary.opacity(0.07)))
    }

    // MARK: - Furniture

    private func widgetHeader<Trailing: View>(
        _ title: String, systemImage: String, tint: Color,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(Circle().fill(tint.opacity(0.16)))
            Text(title).font(.headline)
            Spacer(minLength: 0)
            trailing()
        }
    }

    private var allFeaturesButton: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AmbientStyle.brand)
            Text("All Features").font(.headline)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .ambientCard(density: .roomy, fillWidth: true,
                     contentAlignment: .leading)
    }
}
