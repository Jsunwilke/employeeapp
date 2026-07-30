//  MileageKit.swift
//  Iconik Employee — the Mileage design, as production code
//
//  PRODUCTION CODE THAT THE LAB MOCKUP IMPORTS. That direction is the whole
//  mechanism, and it is the same one AMB.8 used for Time Off: the mockup
//  (`DesignLab/Mockups/MileageMockup.swift`) draws with the types in this file and
//  so do the real screens, so a conversion is not a matching exercise — it is
//  swapping sample data for a service. Nothing can drift, because there is no
//  second copy to drift from.
//
//  WHAT IS DELIBERATELY NOT HERE: anything that knows about Supabase, and any
//  arithmetic. These views take plain values — a `MileageFigures`, a date, a
//  string — so the lab feeds them sample data and production feeds them a service,
//  and neither owns the other. The numbers they show are computed in
//  MileageRules.swift, which is SwiftUI-free and RUN by
//  scripts/test_mileage_rules.sh.
//
//  THE FOUR CLAIMS THE OPERATOR APPROVED, and where each one lives:
//    1. THE MONEY LEADS               — `MileageHeroCard`
//    2. THE SPLIT IS ALWAYS VISIBLE   — `MileageFigures.splitLine`, drawn
//                                       unconditionally by that card
//    3. A CARD IS TITLED BY WHAT IT SHOWS — `MileagePeriod.headerLabel`, passed in
//                                       rather than typed above the values
//    4. THE MISSING STATES ARE DRAWN  — `MileageFailureCard`,
//                                       `MileageStaleFiguresBanner`,
//                                       `MileageEmptyTripsState`

import SwiftUI

// MARK: - Identity

enum MileageStyle {
    /// D11: the wash takes the FEATURE's colour. Read from `FeatureTheme` rather
    /// than restated, so the tile you tap and the screen you land on cannot
    /// disagree. `#E8830C`, the "On the road" family it shares with the Route
    /// Planner.
    static var tint: Color { FeatureTheme.color(for: "mileageReports") }
}

// MARK: - 1. The money card

/// The screen's opening statement: what you are owed for the selected period.
///
/// Nobody opens a mileage screen to learn how far they drove. Before AMB.9 this
/// screen opened with a carousel and then three cards of EQUAL weight, each with
/// miles in the big number and the money in a caption underneath. Here the
/// reimbursement is the big number, the miles sit under it, and NOTHING IS
/// DELETED — both figures survive on every card, because a past phase of this arc
/// lost a money figure by dropping a label.
struct MileageHeroCard: View {
    /// Derived from the selection — `MileagePeriod.headerLabel`. Never a constant:
    /// the old card was titled "Current Period" while showing a past period.
    let header: String
    let figures: MileageFigures
    var tint: Color = MileageStyle.tint
    /// True while the selected period's figures are being fetched.
    ///
    /// THE HEADER CHANGES ON THE TAP AND THE MONEY ARRIVES LATER. For that gap the
    /// figures belong to the period you just left, so they are redacted and the
    /// header carries a spinner — a card that shows one period's money under
    /// another period's title, silently, is the defect this screen was converted to
    /// remove.
    var isRefreshing: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text(header)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if isRefreshing {
                    ProgressView().scaleEffect(0.6)
                }
                Spacer(minLength: 0)
            }

            figureLines
                .redacted(reason: isRefreshing ? .placeholder : [])
        }
        .ambientCard(density: .hero, state: .highlighted, glow: tint, fillWidth: true)
    }

    private var figureLines: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Formatters.currency(figures.reimbursement))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("reimbursement")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            Text(figures.milesLine)
                .font(.system(size: 17, weight: .semibold, design: .rounded))

            // Claim 2: ALWAYS drawn, including at zero company miles. The two
            // halves are paid at different rates; the split is payroll, not trim.
            HStack(spacing: 6) {
                Image(systemName: "car.fill").font(.caption2.weight(.semibold))
                Text(figures.splitLine)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - 2. The period chip

/// One pay period in the carousel. A control, not a container — see the
/// `ambient-allow` marker.
struct MileagePeriodChip: View {
    let label: String
    let isCurrent: Bool
    let isSelected: Bool
    var tint: Color = MileageStyle.tint
    let action: () -> Void

    var body: some View {
        Button {
            withAnimation(AmbientMotion.snappy) { action() }
            AmbientHaptics.selection()
        } label: {
            HStack(spacing: 5) {
                if isCurrent {
                    Circle()
                        .fill(isSelected ? Color.white : tint)
                        .frame(width: 5, height: 5)
                }
                Text(label).font(.caption.weight(.semibold))
                if isCurrent {
                    Text("Now")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(isSelected ? .white : .secondary)
                }
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            // ambient-allow: a selection chip is a control, not a container.
            .background(Capsule().fill(isSelected
                                       ? AnyShapeStyle(tint)
                                       : AnyShapeStyle(.ultraThinMaterial)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(isSelected ? 0 : 0.08)))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 3. The month and year tiles

/// One period's miles AND its money, stepped down from the hero.
///
/// The old month card carried a CLOCK icon over a count of miles, which read as
/// elapsed time; the caller passes a calendar glyph now. Both figures are drawn:
/// the miles bold, the money beside them, and the calendar span underneath, so a
/// tile can never be read as a figure for some other span.
struct MileageFigureTile: View {
    let title: String
    let caption: String
    let miles: Double
    let reimbursement: Double
    let systemImage: String
    var tint: Color = MileageStyle.tint
    /// False when the figure behind this tile has NEVER BEEN FETCHED — the year query
    /// failed while the period query succeeded, so the screen is `.loaded` and these
    /// two numbers are still their init values.
    ///
    /// A NUMBER IS A CLAIM. `0.0 miles · $0.00` is indistinguishable from a real empty
    /// year, and the caveat used to live in an inline notice the next chip tap cleared
    /// — leaving two tiles quietly stating zero. Unloaded draws no figure at all.
    var isLoaded: Bool = true
    /// Offered in the unloaded state, because that state is the only place on the
    /// screen naming a fetch the user cannot otherwise re-run.
    var retry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            if isLoaded {
                Text(MileageFigures.oneDecimal(miles))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("miles · \(Formatters.currency(reimbursement))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("—")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                unloadedLine
            }
            Text(caption).font(.caption2).foregroundStyle(.tertiary)
        }
        .ambientCard(density: .compact, fillWidth: true)
    }

    private var unloadedLine: some View {
        HStack(spacing: 4) {
            Text("not loaded yet").font(.caption).foregroundStyle(.secondary)
            if let retry {
                Text("·").font(.caption).foregroundStyle(.tertiary)
                Button("retry", action: retry)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(tint)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - 4. The trip row

/// One filed daily job report, seen from the money side.
struct MileageTripRow: View {
    let date: Date
    let school: String
    let miles: Double
    let amount: Double
    let isCompany: Bool
    var tint: Color = MileageStyle.tint

    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 0) {
                Text(Formatters.weekdayShort.string(from: date).uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Text(Formatters.dayNumber.string(from: date))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
            }
            .frame(width: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(school.isEmpty ? "No school recorded" : school)
                    .font(AmbientDensity.compact.titleFont)
                    .foregroundStyle(school.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                if isCompany {
                    AmbientBadge(text: "Company", systemImage: "car.2.fill", tint: tint)
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(MileageFigures.oneDecimal(miles)) mi")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text(Formatters.currency(amount))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
        }
        .ambientCard(density: .compact, fillWidth: true)
    }
}

/// The only place either screen says where mileage comes from. Without it a
/// read-only list of trips looks broken rather than derived.
struct MileageSourceNote: View {
    var body: some View {
        Text("Mileage is one of 28 columns of a daily job report. These rows are those reports, seen from the money side.")
            .font(.caption2).foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 5. The states the screen did not have

/// NO ACTION BUTTON, deliberately. Mileage arrives with a filed daily job report
/// and there is no add flow anywhere in the app, so the empty state explains the
/// route instead of offering one that does not exist.
struct MileageEmptyTripsState: View {
    var body: some View {
        AmbientEmptyState(
            title: "No trips this period",
            message: "Mileage comes from your daily job reports — file one with mileage and it lands here.",
            systemImage: "car")
    }
}

/// A failed load, said out loud.
///
/// Before AMB.9 both fetch paths swallowed their failure to a `print`, so a failed
/// load rendered "0.0 miles / $0.00" — indistinguishable from a genuinely empty
/// period. Money that silently reads zero is the worst failure mode on this screen.
struct MileageFailureCard: View {
    let message: String
    var tint: Color = MileageStyle.tint
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundStyle(.orange)
            Text("Couldn't load mileage").font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: retry) {
                Label("Retry", systemImage: "arrow.clockwise")
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
        .padding(.vertical, 36)
    }

    /// The sentence a failed fetch gets when the error itself is not worth
    /// showing. It states what is and is not true, which is the distinction the
    /// old silent zero destroyed.
    static let genericMessage =
        "The server didn't answer. Your trips and your reimbursement are safe — this screen just can't show them right now."
}

/// A failure with figures behind it. NOT an error: the numbers are real, they are
/// just older than now.
///
/// The three headline totals are persisted on every successful load, the same way
/// the home dashboard's mileage widget already caches to UserDefaults, so a
/// failure has something honest to fall back to instead of zeroes.
struct MileageStaleFiguresBanner: View {
    /// THE RETRY THE COPY NAMES. The sentence below tells you to pull the figures
    /// again with Retry, and in this state there was no Retry drawn anywhere on the
    /// screen: the failure card owns one, but the failure card is what `.stale`
    /// replaces. Copy that names a control the screen does not have is worse than
    /// no copy.
    var retry: (() -> Void)?
    var tint: Color = MileageStyle.tint

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash").font(.footnote.weight(.semibold))
                Text("Showing the last figures that synced")
                    .font(.footnote.weight(.semibold))
                Spacer(minLength: 0)
                if let retry {
                    Button(action: retry) {
                        Label("Retry", systemImage: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            // ambient-allow: a control, not a card.
                            .background(Capsule().fill(tint))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("These totals are from the last time this screen reached the server. Pull them again with Retry once you have a connection.")
                .font(.caption2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.orange)
        .ambientCard(density: .compact, border: .dashed(Color.orange.opacity(0.5)), fillWidth: true)
    }
}

/// The trips list while it is on its way. Drawn in place of the list rather than
/// over the whole screen, so the figures above it stay readable.
struct MileageTripsLoading: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Loading trips…").font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - The detail

/// One trip's hero: where, when, how far, and what it pays.
struct MileageDetailHero: View {
    let school: String
    let date: Date
    let miles: Double
    let vehicle: MileageVehicle
    let rate: Double
    var tint: Color = MileageStyle.tint

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(school.isEmpty ? "No school recorded" : school)
                    .font(.headline)
                    .foregroundStyle(school.isEmpty ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                // Personal is BADGED TOO — absence is no longer the signal.
                AmbientBadge(text: vehicle.badgeLabel,
                             systemImage: vehicle == .company ? "car.2.fill" : "car.fill",
                             tint: vehicle == .company ? tint : .secondary)
            }
            Text(Formatters.longDate.string(from: date))
                .font(.subheadline).foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(MileageFigures.oneDecimal(miles))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("miles").font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Text(Formatters.currency(miles * rate))
                    .font(.system(size: 19, weight: .bold, design: .rounded))
            }
            Text("at \(Formatters.currency(rate)) per mile")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .ambientCard(density: .hero, state: .highlighted, glow: tint, fillWidth: true)
    }
}

/// One labelled line in the detail's read mode.
struct MileageDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value).font(.subheadline).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 8)
    }
}

/// Read mode: the three columns of the report this screen can touch.
struct MileageDetailReadRows: View {
    let school: String
    let vehicle: MileageVehicle
    let miles: Double

    var body: some View {
        VStack(spacing: 0) {
            MileageDetailRow(label: "School", value: school.isEmpty ? "—" : school)
            Divider()
            MileageDetailRow(label: "Vehicle", value: vehicle.readLabel)
            Divider()
            MileageDetailRow(label: "Miles", value: MileageFigures.oneDecimal(miles))
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }
}

/// An inline validation or failure line. Replaces the two stacked `.alert`
/// modifiers the old screen carried, one of which could swallow the other.
struct MileageInlineNotice: View {
    let message: String
    var systemImage: String = "exclamationmark.circle.fill"
    var tint: Color = .orange

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: systemImage).font(.caption.weight(.semibold))
            Text(message).font(.caption).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
    }
}

/// The edit form, whole — school, vehicle, miles — so the lab and the real screen
/// cannot lay it out differently.
///
/// The school control is the app's own `SearchableMileageSchoolPicker`
/// (`Components/SearchableSchoolPicker.swift`), which owns its search sheet. That
/// is reuse rather than a second picker: the lab passes sample schools into the
/// same component the real screen passes the org's schools into.
struct MileageEditForm: View {
    @Binding var schoolName: String
    @Binding var vehicleChoice: String?
    @Binding var milesText: String
    let schools: [MileageSchoolItem]
    let schoolsState: MileageSchoolsState
    /// Nil when nothing is wrong. Drawn under the panel, not in an alert.
    let validationMessage: String?
    /// Offered when the school list could not be loaded at all.
    var retrySchools: (() -> Void)?
    var tint: Color = MileageStyle.tint

    private var vehicle: MileageVehicle {
        MileageVehicle.from(choiceLabel: vehicleChoice ?? "") ?? .personal
    }

    private var statusLine: String {
        let miles = Double(milesText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        return "\(MileageFigures.oneDecimal(miles)) mi · \(vehicle.choiceLabel)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientFormSection(title: "Trip",
                               status: statusLine,
                               statusTint: tint,
                               density: .roomy) {
                VStack(alignment: .leading, spacing: 12) {
                    schoolField
                    Divider()
                    AmbientChoiceRow(title: "Vehicle",
                                     options: MileageVehicle.choiceLabels,
                                     selection: $vehicleChoice,
                                     tint: tint)
                    Divider()
                    milesField
                }
            }

            if let validationMessage {
                MileageInlineNotice(message: validationMessage)
            }
        }
    }

    private var schoolField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("School").font(.caption.weight(.semibold)).foregroundStyle(.secondary)

            if schoolsState.allowsPicking {
                SearchableMileageSchoolPicker(selectedSchoolName: $schoolName,
                                              schools: schools,
                                              title: "Select School")
            } else {
                // Loading, "this org has no schools" and "the load failed" are
                // three different situations and each says which it is. The old
                // screen drew a spinner caption for all three, forever.
                HStack(spacing: 8) {
                    if schoolsState == .loading { ProgressView().scaleEffect(0.8) }
                    Text(schoolsState.message ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if case .failed = schoolsState, let retrySchools {
                        Button("Retry", action: retrySchools)
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.plain)
                            .foregroundStyle(tint)
                    }
                }
            }
        }
    }

    private var milesField: some View {
        VStack(spacing: 4) {
            Text("Miles driven").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            TextField("0.0", text: $milesText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.center)
                .font(.system(size: 38, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity)
    }
}

/// What the edit does, said once. "Open full report" is deliberately NOT offered:
/// there is no route from a mileage row to its report in the data layer.
struct MileageEditFootnote: View {
    var body: some View {
        Text("Edits change the mileage on the filed report.")
            .font(.caption2).foregroundStyle(.tertiary)
    }
}
