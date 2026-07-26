//  DashboardIPadMockup.swift
//  Iconik Employee — AMB.4's second mockup
//
//  ARC SCAFFOLDING. Deleted with the rest of the lab at AMB.12.
//
//  WHY THIS EXISTS AT ALL
//      Because the iPad home screen is not the iPhone home screen with more
//      room on it. MainEmployeeView picks the widget SET by device:
//
//          iPhone   Hours · Mileage · Upcoming Shifts · Tasks
//          iPad     Sports Rosters · Group Jobs · Photoshoot Notes
//
//      Three different widgets, sharing nothing with the four in
//      DashboardMockup. An iPad user's home has no hours, no mileage, no
//      shifts and no tasks on it. The approved dashboard design covers the
//      iPhone four, so without this file three of the surface's seven widgets
//      would be converted with nobody having seen them (D10), and the iPad
//      smoke D7 requires would be run against an unconverted screen.
//
//      Found by reading the source for AMB.4's parity inventory rather than by
//      looking at a screen — a device-conditional widget list is not something
//      a screenshot can show you.
//
//  THE WASH is the same as the iPhone dashboard's: company blue at 90%, the
//  operator's call. Home is the container, not a feature, so it does not take a
//  feature colour (D11).
//
//  WHAT DOES NOT CHANGE, DELIBERATELY
//      The three widget headers keep the icon colours they have today — orange,
//      purple, blue. The first cut of this file gave them their FEATURE colours
//      instead, which was wrong twice: D11 governs the WASH behind a screen, not
//      icon tints, and home's wash is the company blue either way; and the
//      approved iPhone dashboard keeps ITS four widgets' existing colours, so
//      re-cutting only the iPad's would have made the two halves of one screen
//      follow different rules. A colour change nobody asked for is not what a
//      parity phase is for.

import SwiftUI

struct DashboardIPadMockup: View {
    /// Same default as the iPhone dashboard, and the same reason for keeping the
    /// slider: the number is still arguable on a device.
    @State private var washIntensity: Double = 0.9
    /// The empty states are half of what these three widgets do — an iPad on a
    /// day with no shoots booked is a completely different screen — so they are
    /// switchable rather than left to be discovered after conversion.
    @State private var showEmpty = false
    @State private var selectedNote: LabPhotoshootNote.ID? = DesignLabSampleData.photoshootNotes.first?.id
    @State private var noteText: String = DesignLabSampleData.photoshootNotes.first?.text ?? ""

    private var notes: [LabPhotoshootNote] { DesignLabSampleData.photoshootNotes }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: AmbientStyle.brand, intensity: washIntensity)

            ScrollView {
                VStack(spacing: 16) {
                    controls
                    sportsRostersWidget
                    groupJobsWidget
                    photoshootNotesWidget
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
    }

    // MARK: - Lab controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle().fill(AmbientStyle.brand).frame(width: 12, height: 12)
                Text("Company blue")
                    .font(.footnote.weight(.semibold))
                Spacer()
                Text(washIntensity == 0 ? "off" : "\(Int(washIntensity * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $washIntensity, in: 0...1)
                .tint(AmbientStyle.brand)

            Toggle(isOn: $showEmpty) {
                Text("Show a day with nothing booked")
                    .font(.footnote.weight(.semibold))
            }
            .tint(AmbientStyle.brand)

            Text("These three widgets are the iPad's ENTIRE home screen — the hours, mileage, shifts and tasks you approved are iPhone-only. Worth checking on a quiet day as well as a busy one, because an iPad often sits on an empty dashboard between jobs.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .ambientCard(density: .compact, fillWidth: true)
    }

    // MARK: - Sports rosters

    private var sportsRostersWidget: some View {
        let tint = Color.orange   // the colour this widget has today
        let shoots = showEmpty ? [] : DesignLabSampleData.sportsShoots
        return VStack(alignment: .leading, spacing: 12) {
            widgetHeader("Sports Rosters", systemImage: "sportscourt", tint: tint) {
                Text("View all").font(.caption.weight(.semibold))
                    .foregroundStyle(AmbientStyle.brand)
            }

            if shoots.isEmpty {
                emptyRow(systemImage: "sportscourt",
                         title: "No sports rosters today",
                         message: "Rosters appear here on the day of the shoot.")
            } else {
                VStack(spacing: 8) {
                    ForEach(shoots.prefix(3)) { shoot in
                        shootRow(shoot, tint: tint)
                    }
                }
                if shoots.count > 3 {
                    moreLine("\(shoots.count - 3) more roster\(shoots.count - 3 == 1 ? "" : "s") today")
                }
            }
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    private func shootRow(_ shoot: LabSportsShoot, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: sportSymbol(shoot.sport))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(Circle().fill(tint.opacity(0.16)))

            VStack(alignment: .leading, spacing: 4) {
                Text(shoot.school)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(shoot.sport)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("·").foregroundStyle(.tertiary)
                    Text(Formatters.shortTime.string(from: shoot.time))
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)

            // The route, said out loud. Two rows that look the same open two
            // different tools, and the only thing that decides it is whether
            // the shoot is linked to Production.
            AmbientBadge(text: shoot.linkedToProduction ? "FP Sports" : "Captura",
                         systemImage: shoot.linkedToProduction ? "bolt.fill" : "sportscourt.fill",
                         tint: shoot.linkedToProduction ? .green : .blue)

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
        }
        .ambientCard(density: .compact, border: .hairline(tint.opacity(0.25)))
    }

    /// The same keyword derivation the live widget uses, kept verbatim so the
    /// mockup cannot promise a glyph the conversion will not produce.
    private func sportSymbol(_ sport: String) -> String {
        let name = sport.lowercased()
        if name.contains("basketball") { return "basketball" }
        if name.contains("football") { return "football" }
        if name.contains("soccer") { return "soccerball" }
        if name.contains("baseball") || name.contains("softball") { return "baseball" }
        if name.contains("tennis") { return "tennis.racket" }
        if name.contains("golf") { return "flag" }
        if name.contains("swim") { return "drop" }
        if name.contains("track") || name.contains("cross country") { return "figure.run" }
        if name.contains("volleyball") { return "volleyball" }
        return "sportscourt"
    }

    // MARK: - Group jobs

    private var groupJobsWidget: some View {
        let tint = Color.purple   // the colour this widget has today
        let jobs = showEmpty ? [] : DesignLabSampleData.groupJobs
        return VStack(alignment: .leading, spacing: 12) {
            widgetHeader("Group Jobs", systemImage: "person.3.fill", tint: tint) {
                Label("Add jobs", systemImage: "plus")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    // ambient-allow: a filled action button, not a card. The
                    // live widget's Add Jobs control is a filled purple capsule
                    // and it is the widget's only write action — demoting it to
                    // a plain label to satisfy a card rule would lose the one
                    // thing on this widget you can DO.
                    .background(Capsule().fill(tint))
            }

            if jobs.isEmpty {
                VStack(spacing: 10) {
                    emptyRow(systemImage: "person.3.fill",
                             title: "No group jobs today",
                             message: "Add the classes, clubs or candids you are shooting.")
                    Label("Add group jobs", systemImage: "plus.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        // ambient-allow: selection/action chip, not a card.
                        .background(Capsule().fill(tint.opacity(0.12)))
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 8) {
                    ForEach(jobs.prefix(3)) { job in
                        groupJobRow(job, tint: tint)
                    }
                }
                if jobs.count > 3 {
                    moreLine("View all (\(jobs.count) jobs)")
                }
            }
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    private func groupJobRow(_ job: LabGroupJob, tint: Color) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(job.school)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(Formatters.shortTime.string(from: job.time))
                        .font(.caption).monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                AmbientPillRow(pills: pills(for: job, tint: tint), density: .compact)
            }
        }
        .ambientCard(density: .compact, border: .hairline(tint.opacity(0.25)))
    }

    /// Zero groups is the case worth reading first, so it takes the warning
    /// colour rather than being a quiet "0".
    private func pills(for job: LabGroupJob, tint: Color) -> [AmbientPill] {
        var pills: [AmbientPill] = []
        if job.count > 0 {
            let noun = job.count == 1 ? job.noun.singular : job.noun.plural
            pills.append(.init(text: "\(job.count) \(noun)", systemImage: "person.3.fill", tint: .blue))
        } else {
            pills.append(.init(text: "No \(job.noun.plural) added",
                               systemImage: "exclamationmark.triangle.fill", tint: .orange))
        }
        if job.images > 0 {
            pills.append(.init(text: "\(job.images)", systemImage: "photo", tint: .green))
        }
        pills.append(.init(text: job.badge, tint: tint))
        return pills
    }

    // MARK: - Photoshoot notes

    private var photoshootNotesWidget: some View {
        let tint = Color.blue     // the colour this widget has today
        let list = showEmpty ? [] : notes
        return VStack(alignment: .leading, spacing: 12) {
            widgetHeader("Photoshoot Notes", systemImage: "note.text", tint: tint) {
                HStack(spacing: 14) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 19))
                        .foregroundStyle(tint)
                    Image(systemName: "arrow.up.forward.circle")
                        .font(.system(size: 19))
                        .foregroundStyle(.secondary)
                }
            }

            if list.isEmpty {
                VStack(spacing: 10) {
                    emptyRow(systemImage: "note.text",
                             title: "No notes yet",
                             message: "Notes you write on a job are kept here until they sync.")
                    Label("Add note", systemImage: "plus.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        // ambient-allow: action chip, not a card.
                        .background(Capsule().fill(tint.opacity(0.12)))
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(list) { note in
                            noteChip(note, tint: tint)
                                .onTapGesture {
                                    withAnimation(AmbientMotion.snappy) {
                                        selectedNote = note.id
                                        noteText = note.text
                                    }
                                    AmbientHaptics.selection()
                                }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .ambientNoBounceWhenShort()

                if let note = list.first(where: { $0.id == selectedNote }) {
                    noteEditor(note, tint: tint)
                }
            }
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    private func noteChip(_ note: LabPhotoshootNote, tint: Color) -> some View {
        let isSelected = note.id == selectedNote
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(Formatters.shortTime.string(from: note.time))
                    .font(.caption2.weight(.semibold)).monospacedDigit()
                if note.photos > 0 {
                    Image(systemName: "photo").font(.system(size: 9))
                    Text("\(note.photos)").font(.caption2)
                }
                Spacer(minLength: 0)
                Circle().fill(note.sync.color).frame(width: 6, height: 6)
            }
            .foregroundStyle(.secondary)

            Text(note.school.isEmpty ? "No school" : note.school)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(note.text.isEmpty ? "(No content)" : note.text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .frame(width: 132, height: 76, alignment: .topLeading)
        .ambientCard(density: .compact,
                     state: isSelected ? .highlighted : .normal,
                     border: isSelected ? .strong(tint) : .hairline(Color.primary.opacity(0.07)))
    }

    private func noteEditor(_ note: LabPhotoshootNote, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "building.columns.fill")
                    .font(.caption).foregroundStyle(.secondary)
                Text(note.school.isEmpty ? "Choose a school" : note.school)
                    .font(.subheadline.weight(.medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 0)
                AmbientBadge(text: note.sync.label, tint: note.sync.color)
            }

            // The real widget binds a TextEditor straight to the note and saves
            // on every keystroke. Kept as a real editor here rather than a
            // rendered block, because how it feels to type into is the only
            // thing worth judging about it.
            TextEditor(text: $noteText)
                .font(.subheadline)
                .frame(height: 96)
                .scrollContentBackgroundHiddenIfAvailable()
                .padding(8)
                // ambient-allow: a text input field, not a card. An input needs
                // an opaque fill to read as writable; a material would let the
                // ambient wash through the thing you are typing into.
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(tint.opacity(0.3), lineWidth: 1))

            HStack(spacing: 12) {
                Text("\(noteText.count) characters")
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                if note.photos > 0 {
                    Label("\(note.photos) photo\(note.photos == 1 ? "" : "s")", systemImage: "photo")
                        .font(.caption2).foregroundStyle(tint)
                }
                Spacer()
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.top, 2)
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

    private func emptyRow(systemImage: String, title: String, message: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(.subheadline.weight(.semibold))
            Text(message)
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private func moreLine(_ text: String) -> some View {
        HStack {
            Spacer()
            Text(text).font(.caption.weight(.semibold))
                .foregroundStyle(AmbientStyle.brand)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(AmbientStyle.brand)
            Spacer()
        }
        .padding(.top, 2)
    }
}

private extension View {
    /// `scrollContentBackground` is iOS 16.0+, which the 16.6 floor clears —
    /// but TextEditor only honours it from 16.0 and the app supports nothing
    /// below, so this is a plain availability wrapper kept local to the lab.
    @ViewBuilder
    func scrollContentBackgroundHiddenIfAvailable() -> some View {
        if #available(iOS 16.0, *) { self.scrollContentBackground(.hidden) } else { self }
    }
}
