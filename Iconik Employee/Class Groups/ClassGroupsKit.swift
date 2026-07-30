//  ClassGroupsKit.swift
//  Iconik Employee — the Class Groups design, as production code
//
//  PRODUCTION CODE THAT THE LAB MOCKUP IMPORTS. That direction is the whole
//  mechanism, and it is the one AMB.8 (TimeOffKit) and AMB.9 (MileageKit) used:
//  `DesignLab/Mockups/ClassGroupsMockup.swift` draws with the types in this file
//  and so do the real screens, so a conversion is not a matching exercise — it is
//  swapping sample data for a service. Nothing can drift, because there is no
//  second copy to drift from.
//
//  WHAT IS DELIBERATELY NOT HERE: anything that knows about Supabase, and every
//  sentence the screens say about a job. The words are computed in
//  ClassGroupsRules.swift, which is SwiftUI-free and RUN by
//  scripts/test_classgroups_rules.sh; these views take a `ClassGroup`, a
//  `ClassGroupJob` or plain values and draw them.
//
//  THE FOUR CLAIMS THE OPERATOR APPROVED (mockup header, 2026-07-29), and where
//  each one lives:
//    1. A JOB CARD SAYS WHEN — WITH THE YEAR — AND HOW MUCH IS DONE
//                                        — `ClassGroupJobCard`
//    2. THE DETAIL SCREEN SHOWS THE DATE AND THE NOTE BODIES
//                                        — `ClassGroupJobHero`, `ClassGroupRowCard`
//    3. A GROUP ROW'S WHOLE CARD IS TAPPABLE
//                                        — `ClassGroupRowCard`
//    4. THE SLATE STAYS A PLAIN WHITE WHITEBOARD, ON PURPOSE
//                                        — `ClassGroupSlateBoard`

import SwiftUI

// MARK: - Identity

enum ClassGroupsStyle {
    /// D11: the wash takes the FEATURE's colour. Read from `FeatureTheme` rather
    /// than restated, so the tile you tap and the screen you land on cannot
    /// disagree. `#46A758`, the "Groups & delivery" family.
    static var tint: Color { FeatureTheme.color(for: "classGroups") }

    /// A pill's tone, coloured. The tone itself is decided in ClassGroupsRules,
    /// which knows nothing about SwiftUI.
    static func pillTint(_ tone: ClassGroupPillTone) -> Color {
        switch tone {
        case .count:   return .blue
        case .missing: return .orange
        case .images:  return .green
        }
    }

    /// The pills for a job, ready for `AmbientPillRow`.
    static func pills(for job: ClassGroupJob) -> [AmbientPill] {
        ClassGroupsRules.pills(jobType: job.jobType,
                               groupCount: job.classGroupCount,
                               imageCount: job.totalImageCount)
            .map { AmbientPill(id: $0.id, text: $0.text,
                               systemImage: $0.systemImage, tint: pillTint($0.tone)) }
    }
}

// MARK: - 1. The type switcher

/// Replaces the segmented control the jobs list used to carry.
///
/// Three capsule chips — the same control the rest of Ambient uses for a
/// mutually-exclusive choice (`AmbientChoiceRow`). A segmented picker cannot be
/// tinted per option and reads as system chrome sitting on top of the wash rather
/// than part of it. Selecting a type relabels the vocabulary everywhere below: for
/// Clubs the rows are clubs, the fields are Club Name / Advisor Name.
struct ClassGroupTypeSwitcher: View {
    @Binding var jobType: String
    var tint: Color = ClassGroupsStyle.tint

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ClassGroupJobType.all, id: \.self) { option in
                let selected = jobType == option
                Button {
                    withAnimation(AmbientMotion.snappy) { jobType = option }
                    AmbientHaptics.selection()
                } label: {
                    Text(ClassGroupJobType.displayName(option))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selected ? .white : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        // ambient-allow: a selection chip is a control, not a
                        // container — it needs a solid tint to read as chosen.
                        .background(Capsule().fill(selected
                                                   ? AnyShapeStyle(tint)
                                                   : AnyShapeStyle(.ultraThinMaterial)))
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(selected ? 0 : 0.10)))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
    }
}

// MARK: - 2. The job card

/// ROOMY, not compact. There are a handful of these a season, not three hundred —
/// the old `InsetGroupedListStyle` row was denser than the content deserves, and
/// the two things a photographer needs off this card (which day, how far along)
/// both want a line of their own.
struct ClassGroupJobCard: View {
    let job: ClassGroupJob

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            // THE FIX: THE YEAR. The old row formatted "EEEE, MMM d" with a
            // privately allocated DateFormatter, so last August's job and this
            // August's job were two rows both reading "Tuesday, Aug 4" — on a list
            // sorted date-DESCENDING with no year anywhere on it.
            // `Formatters.longDate` is the app's shared full-date formatter.
            Text(Formatters.longDate.string(from: job.sessionDate))
                .font(AmbientDensity.roomy.titleFont)
                .fixedSize(horizontal: false, vertical: true)

            Text(job.schoolName)
                .font(AmbientDensity.roomy.subtitleFont)
                .foregroundStyle(.secondary)

            AmbientPillRow(pills: ClassGroupsStyle.pills(for: job), density: .compact)

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }
}

// MARK: - 3. The detail hero

/// The three facts that identify a job: where, what kind, and WHEN.
///
/// THE FIX: THE SESSION DATE. The old detail screen showed the school name in
/// `.largeTitle` and the type below it and never showed the date anywhere — you
/// could stand in a school looking at a job and not be told which day it was for.
/// It also blanked the nav title to do that, which NAV.1 spent a session undoing
/// elsewhere; the title goes back in the bar and the hero carries the facts.
struct ClassGroupJobHero: View {
    let schoolName: String
    let jobType: String
    let sessionDate: Date
    let totalsLine: String
    var tint: Color = ClassGroupsStyle.tint

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(schoolName)
                    .font(.system(size: 22, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                AmbientBadge(text: ClassGroupJobType.badgeLabel(jobType),
                             systemImage: ClassGroupsRules.countIcon(jobType: jobType),
                             tint: tint)
            }

            Text(Formatters.longDate.string(from: sessionDate))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(totalsLine)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .ambientCard(density: .hero, state: .highlighted, glow: tint, fillWidth: true)
    }
}

// MARK: - 4. The group row

/// One photographed group. COMPACT — this is the list you scan between frames, and
/// the old row's hard 22pt title was bigger than anything else in the app.
///
/// THE WHOLE CARD IS THE EDIT TARGET. The old row carried `.contentShape(Rectangle())`
/// with NO tap gesture, so it read tappable and was not; the only edit target was
/// an invisible 36pt pencil. The slate keeps its own button because it is a
/// full-screen, brightness-changing destination you must not reach by fumbling a row.
struct ClassGroupRowCard: View {
    let group: ClassGroup
    let onEdit: () -> Void
    let onSlate: () -> Void
    var tint: Color = ClassGroupsStyle.tint

    private var notes: String {
        group.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(ClassGroupsRules.rowTitle(grade: group.grade, teacher: group.teacher))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    imagesLine

                    // THE FIX: the note BODY, not a hint that one exists. The old
                    // row drew an orange "Has notes" and made you open the Edit
                    // sheet to read it — a note a photographer typed for themselves
                    // is the whole reason the field exists.
                    if !notes.isEmpty {
                        HStack(alignment: .top, spacing: 5) {
                            Image(systemName: "note.text")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.orange)
                                .padding(.top, 2)
                            Text(notes)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // WITHOUT THIS the button is only tappable ON THE GLYPHS: the
                // card fill is applied to the enclosing HStack, outside this
                // Button, so a short title leaves most of the row dead (AMB.10
                // review — the same on-device finding YearbookKit's row fixed).
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edit this row")

            Button(action: onSlate) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    // ambient-allow: a round icon control, not a container — the
                    // slate is a separate destination from editing the row.
                    .background(Circle().fill(tint))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show whiteboard")
        }
        .ambientCard(density: .compact, fillWidth: true)
    }

    /// ONE LINE, TRUNCATED, with the count beside it. The old row set
    /// `lineLimit(nil)` on the raw comma list, so a group with forty frames pushed
    /// every other row off the screen.
    @ViewBuilder
    private var imagesLine: some View {
        if group.hasImages {
            HStack(spacing: 6) {
                Text("Images: \(group.image_numbers)")
                    .font(.caption)
                    .foregroundStyle(.blue)
                    .lineLimit(1)
                    .truncationMode(.tail)
                AmbientBadge(text: "\(group.imageCount)", tint: .blue)
            }
        } else {
            Text("No images")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - 5. The create route

/// The screen's primary action, floating bottom-trailing.
///
/// It replaces the toolbar "+", which on a large phone sits in the one corner a
/// photographer holding a camera in the other hand cannot reach. There is now ONE
/// route to the create sheet from the jobs list, not two.
struct ClassGroupAddButton: View {
    var tint: Color = ClassGroupsStyle.tint
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                // ambient-allow: a floating action button is a control, not a
                // container — it needs a solid tint and a lift to read as the
                // screen's primary action.
                .background(Circle().fill(tint))
                .shadow(color: tint.opacity(0.35), radius: 12, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Create job")
    }
}

// MARK: - 6. The create screen's session card

/// One session that has no job of this type yet. Single-select; the highlighted
/// fill and the hairline and the checkmark all say the same thing, so the state
/// survives dark mode and colour-blindness rather than leaning on a tint alone.
struct ClassGroupSessionCard: View {
    let dateLabel: String
    let schoolName: String
    let sessionTypes: [String]
    let isSelected: Bool
    var tint: Color = ClassGroupsStyle.tint

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(dateLabel)
                    .font(AmbientDensity.compact.titleFont)
                    .fixedSize(horizontal: false, vertical: true)
                Text(schoolName)
                    .font(AmbientDensity.compact.subtitleFont)
                    .foregroundStyle(.secondary)
                if !sessionTypes.isEmpty {
                    Text(sessionTypes.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
            }
            Spacer(minLength: 0)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(tint)
            }
        }
        .ambientCard(density: .compact,
                     state: isSelected ? .highlighted : .normal,
                     border: isSelected ? .hairline(tint.opacity(0.55)) : .none,
                     fillWidth: true)
    }

    /// The live format, "EEE, MMM d 'at' h:mm a", assembled from the SHARED
    /// formatter cache rather than from a `DateFormatter` allocated per row.
    static func dateLabel(for date: Date?) -> String {
        guard let date else { return "Date not available" }
        return "\(Formatters.weekdayShort.string(from: date)), "
             + "\(Formatters.monthDay.string(from: date)) at "
             + "\(Formatters.shortTime.string(from: date))"
    }
}

// MARK: - 7. The form

/// Which field the keyboard is on. Owned here so the form and the lab agree, and
/// so the two duplicate forms that used to disagree about everything else cannot
/// grow two focus chains.
enum ClassGroupFormField: Hashable {
    case primary, secondary, images, notes
}

/// A labelled text field in the form's information panel.
struct ClassGroupTextField: View {
    let label: String
    @Binding var text: String
    let focus: FocusState<ClassGroupFormField?>.Binding
    let field: ClassGroupFormField
    var keyboardType: UIKeyboardType = .default
    var submitLabel: SubmitLabel = .next
    var onSubmit: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(label, text: $text)
                .font(.subheadline)
                .keyboardType(keyboardType)
                .submitLabel(submitLabel)
                .focused(focus, equals: field)
                .onSubmit(onSubmit)
        }
    }
}

/// The grade suggestions, on the surface.
///
/// The old form hid fourteen grades behind a `Menu` you had to know to open. Chips
/// put them where they can be seen and tapped, and the tap target IS the thing you
/// are choosing. Not drawn for Clubs — a club name is not on a list.
struct ClassGroupGradeChips: View {
    @Binding var grade: String
    var tint: Color = ClassGroupsStyle.tint

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ClassGroup.commonGrades, id: \.self) { option in
                    let selected = grade == option
                    Button {
                        withAnimation(AmbientMotion.snappy) { grade = option }
                        AmbientHaptics.selection()
                    } label: {
                        Text(option)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(selected ? .white : .primary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            // ambient-allow: a suggestion chip is a control, not a
                            // container.
                            .background(Capsule().fill(selected
                                                       ? AnyShapeStyle(tint)
                                                       : AnyShapeStyle(.ultraThinMaterial)))
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(selected ? 0 : 0.10)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
    }
}

/// The notes editor, with the placeholder the old one did not have — an empty grey
/// box under a heading told you nothing about what to put in it. Drawn as an
/// overlay because `TextEditor` has no placeholder API on iOS 16.
struct ClassGroupNotesEditor: View {
    @Binding var notes: String
    let focus: FocusState<ClassGroupFormField?>.Binding

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $notes)
                .font(.subheadline)
                .frame(minHeight: 90)
                .scrollContentBackground(.hidden)
                .focused(focus, equals: ClassGroupFormField.notes)
            if notes.isEmpty {
                Text("Retakes, a missing student, anything the next person needs to know.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// Disabled until the grade exists — the old rule, kept. A slate with no grade on
/// it is a blank whiteboard.
struct ClassGroupWhiteboardButton: View {
    let primaryFieldLabel: String
    let isEnabled: Bool
    var tint: Color = ClassGroupsStyle.tint
    let action: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Button(action: action) {
                Label("Show Whiteboard", systemImage: "camera.viewfinder")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    // ambient-allow: a filled primary control, not a card.
                    .background(Capsule().fill(isEnabled ? tint : Color.gray))
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)

            if !isEnabled {
                Text("Enter a \(primaryFieldLabel.lowercased()) first.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - 8. The state the feature did not have

/// A failed LOAD, said out loud.
///
/// THE ARC'S LAW, learned in AMB.6 at the cost of a year of dormant chat: a
/// failure that is presentable as an empty state will hide forever. This feature
/// had exactly that shape — `ClassGroupJobService` publishes an `error` that NO
/// VIEW READ, and a missing organization id was a `print` — so a failed load
/// rendered "No Class Group Jobs / Create a job…", which is indistinguishable from
/// a photographer who genuinely has none.
///
/// A banner rather than an alert: an alert fires on CHANGE, so two identical
/// consecutive failures raise it once, and a failure arriving while it is
/// dismissed is lost entirely. This describes a state that persists.
struct ClassGroupsFailureBanner: View {
    let message: String
    var tint: Color = ClassGroupsStyle.tint
    var retry: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't load jobs")
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let retry {
                Button(action: retry) {
                    Text("Retry").font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(tint)
            }
        }
        .ambientCard(density: .compact,
                     border: .hairline(Color.orange.opacity(0.45)),
                     fillWidth: true)
    }
}

// MARK: - 9. The slate

/// EXACTLY a whiteboard, and deliberately outside the design language: hard white,
/// huge black text, no wash, no card, no dark-mode adaptation. It is held up in
/// front of a class so the frame is labelled, and every Ambient instinct — glass,
/// tint, restraint — makes it worse.
///
/// ONLY THE X DISMISSES IT. The old slate dismissed on a tap ANYWHERE: a
/// photographer holding a phone in one hand and a camera in the other lost the
/// slate mid-shoot to a stray thumb, and there is no undo — they found out when the
/// frame came back unlabelled.
struct ClassGroupSlateBoard: View {
    let grade: String
    let teacher: String
    let schoolName: String?
    let onClose: () -> Void

    private var trimmedTeacher: String {
        teacher.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // ambient-allow: the slate is a physical whiteboard, not a
                // container — it must stay hard white in both appearances.
                Color.white
                    .edgesIgnoringSafeArea(.all)

                VStack(spacing: dynamicSpacing(for: geometry.size)) {
                    Text(grade)
                        .font(.system(size: dynamicFontSize(for: geometry.size, multiplier: 1.0),
                                      weight: .bold))
                        .foregroundColor(.black)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)

                    // Blank teacher draws NOTHING rather than an empty line that
                    // pushes the grade off centre — the same optionality the row
                    // title respects.
                    if !trimmedTeacher.isEmpty {
                        Text(trimmedTeacher)
                            .font(.system(size: dynamicFontSize(for: geometry.size, multiplier: 0.9),
                                          weight: .bold))
                            .foregroundColor(.black)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                    }

                    if let schoolName, !schoolName.isEmpty {
                        Text(schoolName)
                            .font(.system(size: dynamicFontSize(for: geometry.size, multiplier: 0.5),
                                          weight: .medium))
                            .foregroundColor(.gray)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                            .padding(.top, 10)
                    }
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack {
                    HStack {
                        Spacer()
                        Button(action: onClose) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(Color.gray.opacity(0.6))
                                // ambient-allow: the exit control's own backing
                                // disc, so the glyph stays visible over the board.
                                .background(Circle().fill(Color.white.opacity(0.9)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close whiteboard")
                        .padding(20)
                    }
                    Spacer()
                }
            }
        }
    }

    /// ~15% of the smaller dimension, so the board fills whichever way the phone is
    /// held. Unchanged from the screen this replaces.
    private func dynamicFontSize(for size: CGSize, multiplier: CGFloat) -> CGFloat {
        min(size.width, size.height) * 0.15 * multiplier
    }

    private func dynamicSpacing(for size: CGSize) -> CGFloat {
        min(size.width, size.height) * 0.05
    }
}
