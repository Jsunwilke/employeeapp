//  TrainingMockup.swift
//  Iconik Employee — AMB.12's Training feature, built in batch 4
//
//  ARC SCAFFOLDING. Deleted at AMB.12's close, with the rest of the lab.
//
//  SELF-CONTAINED ON PURPOSE. At the conversion these private types become a
//  `Training/TrainingKit.swift` the lab then imports, the way Class Groups and
//  Yearbook went at AMB.10. Two production types are deliberately NOT redeclared
//  here even in prototype form:
//
//      `ShareSheet` — the activity-sheet wrapper the critique detail's "Share"
//      opens. TRAINING DOES NOT OWN IT: it is declared inside the Yearbook module
//      and consumed from there, and a Yearbook conversion that moves, renames or
//      file-privates that declaration breaks Training at compile time. That
//      coupling is the durable statement; the file and line it currently sits at
//      are not, because they moved WHILE the inventory for this batch was being
//      written. Three near-identical wrappers exist under three names across the
//      app (Yearbook's, one private to the metrics dashboard, one in the image
//      viewer); consolidating them is an obvious AMB.12 cleanup and a
//      cross-feature change, so this mockup references the sheet and declares
//      nothing.
//
//      `StatsCard` — Training's own stat tile. The design system already has
//      `AmbientStatTile`; the app should not carry a third, so this design uses
//      the shared one and Training's is deleted at the conversion.
//
//  WHAT THE DESIGN IS ARGUING, in five claims
//
//      1. ONE CONCEPT, ONE WORD.
//         The same idea is spelled three ways on one screen today: the stat card
//         says "Needs Work", the filter says "Needs Improvement", and the badge on
//         the card says "Needs Improvement". Pick one — and the one to pick is the
//         filter's, because it is the service's own enum and it is what a manager
//         chose when they submitted the photo.
//
//      2. A FAILED FETCH MUST NOT SAY "No Training Photos Yet".
//         The service publishes an `error`, sets it, and NOBODY READS IT — so a
//         dropped connection is reported to a photographer as "your managers
//         haven't sent you anything". That is the same failure-presented-as-empty
//         shape that hid a broken Chat query for a year.
//
//      3. THE GRID FOLLOWS WIDTH, NOT MODEL NAME.
//         This is the ONLY real device-conditional layout in the whole of batch 4
//         — 2 columns on iPhone, 3 on iPad — and it switches on the DEVICE IDIOM,
//         so an iPad in Slide Over at 320pt still draws three columns. It switches
//         on the horizontal size class here, which is what the window is actually
//         doing. Both widths are drawn below by a lab control.
//
//      4. A ROW WITH NO IMAGES IS A REAL ROW.
//         Legacy critiques exist whose image list is empty. The detail screen
//         indexes that list unguarded and force-unwraps the URL, so Save and Share
//         CRASH on those rows today. The design draws the state instead.
//
//      5. A CONFIRMATION MUST DESCRIBE WHAT HAPPENED.
//         "Image saved to Photos" is shown when the DOWNLOAD finished — the save
//         is fired at the photo library with no completion handler, so nothing
//         waits for it or hears it fail. And limited photo access is treated as
//         denied, even though adding a photo is permitted under it.
//
//  WHAT IS NOT BEING PROPOSED
//      No data layer, service, permission or schema changes (D12). Specifically
//      NOT promised: creating, editing, replying to or deleting a critique (this
//      is a read-only screen and the service has no write path), any sort control
//      or date grouping (there are none, and the query is already newest-first),
//      search (there is none), and pagination or an image cache (there is neither
//      — the full published set is re-queried on every appearance and
//      full-resolution URLs are used for 60pt and 100pt tiles).
//      NOT ADDED: a permission gate. Training correctly has none — the query
//      self-scopes to the signed-in photographer — and drawing a gate would
//      imply one exists.
//
//  VOCABULARY COMES FROM PRODUCTION
//      The three filter titles are the service enum's own strings. The badge's
//      binary test is the shipped one: `example_type == "example"` is good and
//      EVERYTHING ELSE renders as a criticism, which is why the sample data
//      carries a row whose type neither client writes.

import SwiftUI

// MARK: - Lab state

private enum TrainingLabState: String, CaseIterable, Identifiable {
    case populated = "Photos"
    case loading = "Loading"
    case empty = "Empty"
    case noMatches = "No matches"
    case failed = "Load failed"

    var id: String { rawValue }
}

private enum TrainingLabFilter: String, CaseIterable, Identifiable {
    case all = "All Examples"
    case good = "Good Examples"
    case improvement = "Needs Improvement"

    var id: String { rawValue }
}

private enum TrainingLabWidth: String, CaseIterable, Identifiable {
    case compact = "Phone / Slide Over"
    case regular = "iPad full width"

    var id: String { rawValue }

    var columns: Int { self == .compact ? 2 : 3 }
}

// MARK: - Root

struct TrainingMockup: View {
    /// The registered feature colour, #C43B6D. Training is a SELF-NAV feature —
    /// it builds its own NavigationView, Home button and tab-bar clearance and
    /// gets nothing from the shell — so the lab's container is not the one it
    /// really runs in. Every push here still goes through `.ambientPush`, which
    /// works in both.
    static var featureTint: Color { FeatureTheme.color(for: "training") }

    @State private var state: TrainingLabState = .populated
    @State private var filter: TrainingLabFilter = .all
    @State private var width: TrainingLabWidth = .compact
    @State private var asGrid = true
    @State private var destination: TrainingLabDestination?

    private var critiques: [LabCritique] {
        switch filter {
        case .all: return DesignLabSampleData.critiques
        case .good: return DesignLabSampleData.critiques.filter(\.isGoodExample)
        case .improvement: return DesignLabSampleData.critiques.filter { !$0.isGoodExample }
        }
    }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: Self.featureTint, intensity: 0.8)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    labControl
                    content
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .ambientNoBounceWhenShort()
        }
        .ambientPush(item: $destination) { destination in
            switch destination {
            case .detail(let id):
                TrainingLabDetail(critique: DesignLabSampleData.critiques.first { $0.id == id }
                                  ?? DesignLabSampleData.critiques[0])
            }
        }
    }

    private var labControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            AmbientSectionTitle("Lab · state and width", trailing: "not a design element")
            Picker("State", selection: $state) {
                ForEach(TrainingLabState.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("Width", selection: $width) {
                ForEach(TrainingLabWidth.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            TrainingLabLoading(message: "Loading training photos…")
        case .empty:
            AmbientEmptyState(
                title: "No Training Photos Yet",
                message: "Your training examples will appear here when managers submit them.",
                systemImage: "camera.on.rectangle")
        case .failed:
            // 2 — the state that does not exist today.
            VStack(alignment: .leading, spacing: 8) {
                TrainingLabFailure(message: "Couldn't load your training photos.")
                Text("PROPOSED — a failed load says so. The service publishes an `error`, sets it on failure, and NOTHING reads it, so today a dropped connection draws \"No Training Photos Yet\" — the app telling a photographer their managers have never sent them anything. Offline is not detected here either.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .noMatches:
            VStack(alignment: .leading, spacing: 12) {
                stats
                filters
                AmbientEmptyState(
                    title: "No Results",
                    message: "No training photos match the selected filter.",
                    systemImage: "magnifyingglass",
                    actionTitle: "Show All",
                    actionIcon: "square.grid.2x2",
                    action: { filter = .all },
                    actionTint: Self.featureTint)
                Text("KEPT: the no-results state and its \"Show All\" button are distinct from the never-had-any state above, and that distinction is worth keeping — it is one of the few places this feature already gets right.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .populated:
            VStack(alignment: .leading, spacing: 14) {
                stats
                filters
                if asGrid { grid } else { list }
                captions
            }
        }
    }

    // MARK: 1 — the stats, in one vocabulary

    private var stats: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                AmbientStatTile(value: DesignLabSampleData.critiques.count,
                                label: "Total", systemImage: "photo.stack",
                                tint: Self.featureTint)
                AmbientStatTile(value: DesignLabSampleData.critiques.filter(\.isGoodExample).count,
                                label: "Good Examples", systemImage: "checkmark.circle",
                                tint: .green)
                AmbientStatTile(value: DesignLabSampleData.critiques.filter { !$0.isGoodExample }.count,
                                label: "Needs Improvement", systemImage: "exclamationmark.triangle",
                                tint: .orange)
            }
            Text("The third tile said \"Needs Work\" while the filter beside it and the badge on every card said \"Needs Improvement\" — three words for one concept on one screen. These are the shared stat tiles, not Training's own: the app had two stat-tile components and should not have a third.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AmbientFlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(TrainingLabFilter.allCases) { option in
                        let on = filter == option
                        Button {
                            withAnimation(AmbientMotion.snappy) { filter = option }
                            AmbientHaptics.selection()
                        } label: {
                            Text(option.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(on ? .white : .primary)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                // ambient-allow: a filter chip, not a container.
                                .background(Capsule().fill(on
                                                           ? AnyShapeStyle(Self.featureTint)
                                                           : AnyShapeStyle(.ultraThinMaterial)))
                                .overlay(Capsule().strokeBorder(Color.primary.opacity(on ? 0 : 0.12)))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    withAnimation(AmbientMotion.snappy) { asGrid.toggle() }
                } label: {
                    Image(systemName: asGrid ? "list.bullet" : "square.grid.2x2")
                        .font(.footnote.weight(.semibold))
                        .frame(width: 32, height: 32)
                        // ambient-allow: an icon control, not a container.
                        .background(Circle().fill(.ultraThinMaterial))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(asGrid ? "Show as a list" : "Show as a grid")
            }

            Text("The layout toggle's icon shows what you will GET, and it has an accessibility label. Today the icon shows the CURRENT mode with no label at all, and the toggle's state resets to grid on every appearance while the FILTER persists across screen exits — because the filter is bound straight into a shared singleton and the layout is local.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 3 — the two widths

    private var grid: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                     count: width.columns),
                      spacing: 10) {
                ForEach(critiques) { critique in
                    Button { destination = .detail(critique.id) } label: {
                        TrainingLabGridCard(critique: critique)
                    }
                    .buttonStyle(.plain)
                    .ambientScrollFade()
                }
            }

            Text("The column count comes from the horizontal SIZE CLASS — \(width.columns) here. Today it comes from the device idiom, so an iPad in Slide Over at 320 points still draws three columns and each card is about 100 points wide. This is the only real device-conditional layout in the whole of batch 4; every other screen in this batch is device-agnostic with hard constant sizes, which is why the lab switch above exists at all.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
                ForEach(critiques) { critique in
                    Button { destination = .detail(critique.id) } label: {
                        TrainingLabListRow(critique: critique)
                    }
                    .buttonStyle(.plain)
                    .ambientScrollFade()
                }
            }
            Text("The list row's failed-thumbnail treatment now matches the grid card's — icon AND the words \"Image unavailable\". Today the grid card says it and the list row draws a bare icon, so the same broken image means two different things depending on which layout you are in.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var captions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HIDDEN QUERY FILTERS, unchanged and worth stating: this list is only YOUR critiques, only in your organization, only ones a manager has PUBLISHED, newest first. None of that is exposed as a control and none of it is added here — but a photographer who was told a photo was sent and cannot see it is looking at the \"published\" filter, so the empty state says who sends these.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text("KEPT: pull to refresh, and the push deep link that opens a specific critique when a photographer taps its notification. NAMED, NOT FIXED: the service is a singleton whose published list is never cleared when it stops listening, so critiques survive a sign-out until the process dies.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Destination

/// One enum, one `.ambientPush` — the AMB.3 rule.
private enum TrainingLabDestination: Identifiable {
    case detail(String)

    var id: String {
        switch self {
        case .detail(let critiqueId): return "detail-\(critiqueId)"
        }
    }
}

// MARK: - Cards

private struct TrainingLabGridCard: View {
    let critique: LabCritique

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TrainingLabThumbnail(critique: critique, height: 120)

            TrainingLabBadge(isGood: critique.isGoodExample)

            Text(critique.notes ?? "No notes")
                .font(.caption)
                .foregroundStyle(critique.notes == nil ? .tertiary : .secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(critique.submitter) · \(Formatters.shortDate.string(from: critique.createdAt))")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .ambientCard(density: .compact, fillWidth: true)
    }
}

private struct TrainingLabListRow: View {
    let critique: LabCritique

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            TrainingLabThumbnail(critique: critique, height: 74, width: 74)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    TrainingLabBadge(isGood: critique.isGoodExample)
                    Spacer(minLength: 0)
                    Text(Formatters.shortDate.string(from: critique.createdAt))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Text(critique.notes ?? "No notes")
                    .font(.caption)
                    .foregroundStyle(critique.notes == nil ? .tertiary : .secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(critique.submitter) · for \(critique.forRole)")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .ambientCard(density: .compact, fillWidth: true)
    }
}

/// A stand-in for the remote image. The lab does not load anything from the
/// network, so this draws the two states the real `AsyncImage` produces and the
/// count pill that sits on top of it.
private struct TrainingLabThumbnail: View {
    let critique: LabCritique
    var height: CGFloat
    var width: CGFloat?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // ambient-allow: a photo well — the image itself, not a card.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.tertiarySystemFill))
                .frame(width: width, height: height)
                .overlay {
                    if critique.realImageCount == 0 {
                        VStack(spacing: 4) {
                            Image(systemName: "photo").font(.title3).foregroundStyle(.tertiary)
                            Text("Image unavailable").font(.system(size: 9)).foregroundStyle(.tertiary)
                        }
                    } else {
                        Image(systemName: "photo.fill")
                            .font(.title2)
                            .foregroundStyle(TrainingMockup.featureTint.opacity(0.5))
                    }
                }

            if critique.realImageCount > 1 {
                Label("\(critique.realImageCount)", systemImage: "square.stack")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    // ambient-allow: a count pill over a photo, not a container.
                    .background(Capsule().fill(.ultraThinMaterial))
                    .padding(5)
            }
        }
    }
}

/// The badge, on the shipped binary test. `example_type == "example"` is good and
/// everything else is a criticism — including a value neither client writes.
private struct TrainingLabBadge: View {
    let isGood: Bool

    var body: some View {
        AmbientBadge(text: isGood ? "Good Example" : "Needs Improvement",
                     systemImage: isGood ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                     tint: isGood ? .green : .orange)
    }
}

// MARK: - Detail

private struct TrainingLabDetail: View {
    let critique: LabCritique

    @State private var page = 0
    @State private var saving = false

    /// What the pager can actually show. The COUNT the row stores and the number of
    /// images it really has are two different numbers today — the card and the
    /// counter read `image_count`, the pager reads the list — and this is the field
    /// the design has to choose between.
    private var pageCount: Int { max(critique.realImageCount, 0) }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: TrainingMockup.featureTint, intensity: 0.7)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if pageCount == 0 { noImages } else { pager }
                    meta
                    if let notes = critique.notes {
                        AmbientNoteCard(title: "Training Notes", text: notes,
                                        accent: .orange, density: .roomy)
                    }
                    actions
                    captions
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .ambientNoBounceWhenShort()
        }
        .navigationTitle("Training Photo")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: 4 — the row with no images

    private var noImages: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientEmptyState(
                title: "This photo is no longer attached",
                message: "The critique's note is below. The image was stored before the app kept a list of them and cannot be shown.",
                systemImage: "exclamationmark.triangle")
            Text("PROPOSED — this state, and Save and Share disabled with it. Today a critique whose image list is empty indexes that list unguarded and force-unwraps the URL, so BOTH Save and Share CRASH on those rows; the older singular image field the model still carries is never consulted. Approving the state is not approving the guard — that is a code change.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var pager: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ambient-allow: the photo well — the subject of the screen.
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.tertiarySystemFill))
                .frame(height: 280)
                .overlay {
                    Image(systemName: "photo.fill")
                        .font(.system(size: 42))
                        .foregroundStyle(TrainingMockup.featureTint.opacity(0.5))
                }

            if pageCount > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<pageCount, id: \.self) { index in
                        // ambient-allow: a thumbnail strip cell, not a container.
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color(.tertiarySystemFill))
                            .frame(width: 46, height: 46)
                            .overlay {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(index == page ? TrainingMockup.featureTint : .clear,
                                                  lineWidth: 2)
                            }
                            .onTapGesture { page = index }
                    }
                    Spacer(minLength: 0)
                    Text("\(page + 1) of \(pageCount)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Text("The counter and the strip come from the number of images the row REALLY has. Today both come from an `image_count` column that defaults to 0 when it is NULL, so a genuinely multi-image critique is drawn as a single photo with no strip and no counter. The strip's own failure branch is also missing today — a broken thumbnail spins forever, because that image has a placeholder and no failure case.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text("KEPT: pinch to zoom clamped between 1× and 3×, and double-tap toggling 1× and 2×. The pager's height is a fraction of the SCREEN today rather than of its container, so on iPad it can overflow the sheet it is in; here it is a fixed well inside the layout.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var meta: some View {
        VStack(alignment: .leading, spacing: 6) {
            TrainingLabBadge(isGood: critique.isGoodExample)
            TrainingLabStatLine(label: "Submitted by", value: critique.submitter)
            TrainingLabStatLine(label: "Email", value: critique.submitterEmail)
            TrainingLabStatLine(label: "Date",
                                value: Formatters.mediumDate.string(from: critique.createdAt))
            TrainingLabStatLine(label: "For", value: critique.forRole)
            Text("The submitter's email is ADDED — it is already decoded from the row and displayed nowhere, and \"who do I ask about this\" is the obvious next question after reading a critique. No new query: the data is already on screen's worth of model.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    // MARK: 5 — the two actions

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(AmbientMotion.snappy) { saving.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        if saving { ProgressView().tint(.white) }
                        Label(saving ? "Saving…" : "Save to Photos",
                              systemImage: "square.and.arrow.down")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    // ambient-allow: a control, not a container.
                    .background(Capsule().fill(pageCount == 0
                                               ? AnyShapeStyle(Color.secondary.opacity(0.4))
                                               : AnyShapeStyle(TrainingMockup.featureTint)))
                }
                .buttonStyle(.plain)
                .disabled(pageCount == 0)

                Label("Share", systemImage: "square.and.arrow.up")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    // ambient-allow: a control, not a container.
                    .background(Capsule().fill(.ultraThinMaterial))
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
            }

            Text("Both actions come OUT of the ellipsis menu. They are the only two things this screen does; a menu hiding two items is a tap spent on discovery. Share still opens the app's activity sheet — the one declared in the Yearbook module that Training does not own, referenced here and not redeclared, because a rename or a file-private over there breaks this screen at compile time.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text("PROPOSED — a save-in-progress state, and a confirmation that describes the SAVE. Today \"Image saved to Photos\" is shown when the DOWNLOAD finished: the image is handed to the photo library with no completion target, so nothing waits for the write or hears it fail. There is no in-progress state at all, and Save and Share each perform a second, independent full download of the same URL.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text("PROPOSED — LIMITED photo access is treated as permission granted. Today it is treated as DENIED and the user is told \"Please allow access to Photos in Settings\", even though adding a photo is permitted under limited access; the authorization call used is also the deprecated one.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var captions: some View {
        Text("KEPT: \"Close\", the inline title \"Training Photo\", and this screen staying a sheet with its own navigation container. NOT ADDED: any way to reply to a critique or mark it read — neither exists in the service and both would be features.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Components

private struct TrainingLabStatLine: View {
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

private struct TrainingLabLoading: View {
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

private struct TrainingLabFailure: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
            Button {} label: {
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
