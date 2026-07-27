//  AmbientComponents.swift
//  Iconik Employee — the Ambient design language, components
//
//  Promoted out of Schedule/ScheduleStyleKit.swift in AMB.2 (2026-07-25). Each
//  of these arrived as a schedule component taking a `Session`; here they take
//  plain values, so Equipment, Tasks and Chat can use the same badge, the same
//  avatar and the same empty state rather than growing their own. The schedule
//  keeps thin adapters that turn a Session into these values.
//
//  Containers here go through `.ambientCard(...)` — the design system does not
//  get to hand-roll a card either.

import SwiftUI

// MARK: - Badge

/// A state marker: a status, a count, a draft flag, a category.
struct AmbientBadge: View {
    let text: String
    var systemImage: String?
    var tint: Color = .orange

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 9, weight: .bold))
            }
            Text(text)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .textCase(.uppercase)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.16)))
        .foregroundStyle(tint)
    }
}

// MARK: - Pills

/// One labelled pill in a wrapping row.
struct AmbientPill: Identifiable {
    let id: String
    let text: String
    var systemImage: String?
    var tint: Color

    init(id: String? = nil, text: String, systemImage: String? = nil, tint: Color) {
        self.id = id ?? text
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
    }
}

/// A wrapping row of pills.
///
/// Wrapping rather than truncating is deliberate: the things being labelled are
/// user-defined rows in the database, so there is no count at which "and 2 more"
/// is safe to hide behind.
struct AmbientPillRow: View {
    let pills: [AmbientPill]
    /// Compact drops the icons and keeps the words — in a dense list the icons
    /// cost a line of height and add nothing you were not already reading.
    var density: AmbientDensity = .roomy

    var body: some View {
        AmbientFlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(pills) { pill in
                AmbientBadge(text: pill.text,
                             systemImage: density == .compact ? nil : pill.systemImage,
                             tint: pill.tint)
            }
        }
    }
}

// MARK: - Avatars

/// A person (or anything with a name and an optional photo) in an avatar.
struct AmbientAvatarSubject: Identifiable {
    let id: String
    let name: String
    var imageURL: String?

    init(id: String, name: String, imageURL: String? = nil) {
        self.id = id
        self.name = name
        self.imageURL = imageURL
    }
}

/// Initials bubble with an optional remote photo. The colour is derived from the
/// name, so the same person is the same colour on every screen and every device.
struct AmbientAvatar: View {
    let name: String
    var imageURL: String?
    var size: CGFloat = 36
    var ringColor: Color?

    var body: some View {
        ZStack {
            Circle().fill(AmbientStyle.avatarColor(name).gradient)
            if let imageURL, !imageURL.isEmpty {
                AsyncImage(url: URL(string: imageURL)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialsText
                }
                .clipShape(Circle())
            } else {
                initialsText
            }
        }
        .frame(width: size, height: size)
        .overlay {
            if let ringColor { Circle().strokeBorder(ringColor, lineWidth: 2.5) }
        }
    }

    private var initialsText: some View {
        Text(AmbientStyle.initials(name))
            .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
    }
}

/// Overlapping avatars with a "+N" overflow chip.
struct AmbientAvatarStack: View {
    let subjects: [AmbientAvatarSubject]
    var size: CGFloat = 28
    var maxVisible: Int = 4

    var body: some View {
        HStack(spacing: -size * 0.32) {
            ForEach(subjects.prefix(maxVisible)) { subject in
                AmbientAvatar(name: subject.name, imageURL: subject.imageURL, size: size)
                    .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 1.5))
            }
            if subjects.count > maxVisible {
                Text("+\(subjects.count - maxVisible)")
                    .font(.system(size: size * 0.34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
                    .background(Circle().fill(Color(.tertiarySystemFill)))
                    .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 1.5))
            }
        }
    }
}

// MARK: - Text furniture

struct AmbientSectionTitle: View {
    let title: String
    var trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Spacer()
            if let trailing {
                Text(trailing).font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Cards

/// A titled block of prose with a coloured spine — notes, instructions, a
/// description someone typed.
struct AmbientNoteCard: View {
    let title: String
    let text: String
    var accent: Color = .secondary
    var density: AmbientDensity = .roomy

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AmbientSectionTitle(title)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .ambientCard(density: density, fillWidth: true)
        .overlay(alignment: .leading) {
            Capsule()
                .fill(accent)
                .frame(width: 3)
                .padding(.vertical, density.verticalPadding)
                .padding(.leading, 1)
        }
    }
}

/// One number and what it counts.
struct AmbientStatTile: View {
    let value: Int
    let label: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
            Text("\(value)")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .ambientCard(density: .compact, fillWidth: true, contentAlignment: .center)
    }
}

// MARK: - Empty state

struct AmbientEmptyState: View {
    var title: String = "Nothing here"
    var message: String = "There is nothing to show yet."
    var systemImage: String = "tray"

    /// An optional call to action.
    ///
    /// Added in AMB.6 because this component having no action slot is what SILENTLY
    /// DROPPED a feature: Chat's empty state had a "New Conversation" button, the
    /// conversion replaced the hand-rolled state with this, and the button simply
    /// ceased to exist — while the parity inventory recorded it as kept. An empty
    /// state is very often the first screen a new user sees, and the one place a
    /// prompt matters most. Every future surface gets the slot rather than
    /// rediscovering the gap.
    var actionTitle: String?
    var actionIcon: String?
    var action: (() -> Void)?
    var actionTint: Color?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)

            if let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: actionIcon ?? "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        // ambient-allow: a filled call-to-action button is not a
                        // card — it is a control, and it needs a solid tint to
                        // read as tappable against the wash.
                        .background(Capsule().fill(actionTint ?? AmbientStyle.brand))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }
}

// MARK: - Form section

/// One part of a form: a heading, a short state summary on the right, and an
/// OPAQUE panel holding the controls.
///
/// PROMOTED OUT OF `Reports/ReportFormKit.swift` IN AMB.8, where it was called
/// `ReportSection`. It never knew anything about a report — it takes a title, a
/// string and a view builder — and Time Off needed the same thing. The arc's
/// rule when a second surface needs a primitive is to promote it rather than
/// fork it (`AmbientCardFill.surface` and `AmbientEmptyState`'s action slot both
/// arrived that way); a `TimeOffSection` that drew a heading two points
/// differently is exactly the drift the design system exists to stop.
///
/// EVERY section goes through this, which is the point: the moment one gets its
/// own heading treatment the layout starts ranking things again, and the
/// operator's instruction for the report form was "nothing is secondary. it is
/// all important."
struct AmbientFormSection<Content: View>: View {
    let title: String
    /// The short state summary on the right of the heading — "3 selected",
    /// "18.2 mi · Personal", "5 days · 40.0 PTO hours". Together these let the
    /// state of a whole form be read in one scroll.
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

// MARK: - Single choice

/// A capsule radio row — Yes / No / NA, Full Day / Partial Day, and friends.
/// The app's segmented control: `Picker(.segmented)` cannot be tinted per option
/// and reads as system chrome sitting on top of the wash rather than part of it.
///
/// PROMOTED OUT OF `Reports/ReportFormKit.swift` IN AMB.8, where it was called
/// `ReportChoiceRow`. Same reasoning as `AmbientFormSection` above.
///
/// Nothing is pre-selected, and — per the live report form — an answer cannot be
/// cleared once given. A caller that needs a clearable choice needs a different
/// control, not a flag on this one.
struct AmbientChoiceRow: View {
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
