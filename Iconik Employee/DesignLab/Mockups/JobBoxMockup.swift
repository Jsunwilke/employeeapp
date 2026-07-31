//  JobBoxMockup.swift
//  Iconik Employee — AMB.11's remaining surface: job box / NFC, built in batch 4
//
//  ARC SCAFFOLDING. Deleted at AMB.11's close, with the rest of the lab going at
//  AMB.12.
//
//  SELF-CONTAINED ON PURPOSE, WITH ONE EXCEPTION. Nothing in this file is a
//  production component yet — at the conversion these private types become an
//  `NFC/JobBoxKit.swift` the lab then imports, exactly as Class Groups and
//  Yearbook did at AMB.10. The exception is the PROGRESS METER, which already
//  shipped: `JobBoxProgressMeter`, `JobBoxProgressCard` and the whole
//  `JobBoxProgressRules` vocabulary are drawn here THROUGH THE PRODUCTION TYPES.
//  This mockup embeds the shipped scrubber; it does not propose a new one.
//
//  WHAT THE DESIGN IS ARGUING, in six claims
//
//      1. ONE FEATURE, ONE CHROME.
//         `NFCContainerView` is a five-tab sub-shell inside a feature the app
//         shell already wrapped, and THREE of its five tabs add a second
//         `NavigationView` of their own — so "Write NFC" draws its title in an
//         inner bar below the Home button while "Scan" draws its title in the
//         shell bar. Two chrome layouts in one feature. The nested containers go;
//         the five tabs become a segmented row INSIDE the content, under one bar.
//         The 60pt vertical rail goes with them: it is 60pt on a 4.7" SE and 60pt
//         on a 12.9" iPad, and at its 50pt label width "Manual Entry" and "Write
//         NFC" are the only two labels that wrap to two lines.
//
//      2. THE SCREEN IS THE COLOUR THE APP ALREADY SAYS IT IS.
//         `FeatureTheme` registers `scan` as #2AA7D8 and it reaches exactly one
//         pixel: the bottom tab bar's centre button. Every NFC surface is
//         hand-rolled ORANGE, so the bar and the screen it opens are different
//         colours today, and zero `ambientCard`/`FeatureTheme`/`AmbientStyle`
//         tokens exist anywhere in `NFC/`. This design uses the REGISTERED colour.
//
//      3. A FAILURE MUST NOT BE PRESENTABLE AS AN EMPTY SCREEN.
//         Search has NO empty state — an empty result is a blank `List` plus a
//         modal alert titled "Info". Statistics has NO loading state at all
//         (`isLoading` is written three times and never read), so first paint is a
//         screen of zeroes that looks like an answer. The tracker cannot tell
//         "no boxes" from "no boxes in the last 30 days" from "no organization id".
//
//      4. THE TRACKER SAYS WHAT IT IS SHOWING.
//         Both of its queries are silently windowed to 30 days — live, that is 17
//         of 1,059 rows — and nothing on screen says so. It opens on the "Active"
//         filter, already hiding every turned-in box, with the "All" pill visibly
//         unselected. And ONE text field drives two different list semantics: a
//         number shows every scan row for that box, a word shows one row per box.
//
//      5. THE STATUS VOCABULARY IS ONE VOCABULARY.
//         Three colour maps describe four statuses and they disagree on three of
//         them: the shipped meter (slate/teal/amber/green), the tracker's row
//         background (blue/purple/orange/green) and `NFC/StatusColors`
//         (blue/green/orange/grey), which `STATUS_COLORS_DOCUMENTATION.md`
//         presents as the iOS↔web contract. The two never meet on one screen
//         today, which is why nobody has noticed. Drawn here side by side so the
//         operator can settle it — see the PROPOSED caption on the tracker.
//
//      6. A CONTROL THAT CANNOT WORK IS NOT DRAWN.
//         Four affordances in this surface are attached to columns that do not
//         exist or to state nothing reads. They are ABSENT here, each with a
//         caption saying what was removed and why, rather than restyled.
//
//  WHAT IS NOT BEING PROPOSED
//      No data layer, service, schema, RLS or business-rule changes (D12).
//      Specifically NOT promised: job-box FLAGGING (the three columns do not
//      exist — PROVED by live query: `job_boxes` has exactly ten columns), DATE
//      FILTERING on the tracker (`selectedDate` is read by nothing), any CARD
//      NUMBER concept on the tracker (`cardNumber` is hardcoded ""), SD-CARD
//      PHOTOGRAPHER anywhere (the `records` table has no such column — PROVED),
//      a job-box OFFLINE CACHE (SD cards fall back to a cache; job boxes throw),
//      NFC tag READ-BACK, duplicate-number checking or overwrite confirmation in
//      the writer, and any change to the tag format or the 3001 routing rule.
//      The shipped progress meter is FROZEN — it is embedded, not redesigned.
//
//  VOCABULARY COMES FROM PRODUCTION
//      Stage names, colours, icons, the headline and the skip note all resolve
//      through `JobBox/JobBoxProgressRules.swift` and `JobBoxProgressMeter.swift`
//      — the SwiftUI-free rules file with a 60-check harness. The lab keeps no
//      second table of the four stages' nouns. `StatusColors` is shown where the
//      design has to ask about it, read from the production file rather than
//      restated.
//
//  WHAT CANNOT BE DEMONSTRATED HERE, ON ANY SIMULATOR
//      NFC is hardware. `NFCNDEFReaderSession.readingAvailable` is false in every
//      simulator, so the scan sheet, the writer's tag branches and the reader's
//      parse errors cannot be exercised — they are DRAWN here and captioned. The
//      highest-value device check is not a design question at all: the
//      entitlement declares `TAG` only, not `NDEF`, while the reader uses
//      `NFCNDEFReaderSession`. Flagged, not claimed.

import SwiftUI

// MARK: - Lab state

/// Which surface of the feature is on screen. A lab control, not a design element
/// — in the app these are the container's five tabs plus two manager screens.
private enum JobBoxLabSurface: String, CaseIterable, Identifiable {
    case scan = "Scan"
    case search = "Search"
    case stats = "Stats"
    case write = "Write"
    case manual = "Manual"
    case tracker = "Tracker"

    var id: String { rawValue }
}

/// Which state the Scan screen is showing. A lab control, not a design element.
private enum JobBoxLabScanState: String, CaseIterable, Identifiable {
    case ready = "Ready"
    case alert = "Alert"
    case offline = "Offline"
    case error = "Error"
    case noNFC = "No NFC"

    var id: String { rawValue }
}

/// Which state a list is showing. A lab control, not a design element.
private enum JobBoxLabListState: String, CaseIterable, Identifiable {
    case results = "Results"
    case loading = "Loading"
    case empty = "Empty"
    case failed = "Failed"

    var id: String { rawValue }
}

private enum JobBoxLabSheet: Identifiable {
    case sdForm
    case boxForm
    case editStatus(String)
    case settings

    var id: String {
        switch self {
        case .sdForm: return "sd-form"
        case .boxForm: return "box-form"
        case .editStatus(let boxId): return "edit-\(boxId)"
        case .settings: return "settings"
        }
    }
}

// MARK: - Root

struct JobBoxMockup: View {
    /// The REGISTERED feature colour, #2AA7D8 — not the hand-rolled orange every
    /// NFC screen draws today (claim 2).
    static var featureTint: Color { FeatureTheme.color(for: "scan") }
    /// The tracker is its own registered feature, #0B8BA8.
    static var trackerTint: Color { FeatureTheme.color(for: "jobBoxTracker") }

    @State private var surface: JobBoxLabSurface = .scan
    @State private var sheet: JobBoxLabSheet?

    private var tint: Color {
        surface == .tracker ? Self.trackerTint : Self.featureTint
    }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: tint, intensity: 0.8)

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
        .sheet(item: $sheet) { which in
            switch which {
            case .sdForm: JobBoxLabSDForm()
            case .boxForm: JobBoxLabBoxForm()
            case .editStatus(let boxId): JobBoxLabEditSheet(boxId: boxId)
            case .settings: JobBoxLabSettingsSheet()
            }
        }
    }

    private var labControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            AmbientSectionTitle("Lab · surface", trailing: "not a design element")
            Picker("Surface", selection: $surface) {
                ForEach(JobBoxLabSurface.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var content: some View {
        // 1 — THE TAB ROW, in the content, under ONE bar. This is what replaces the
        // 60pt rail and the three nested NavigationViews.
        if surface != .tracker {
            JobBoxLabTabRow(surface: $surface, tint: Self.featureTint)
            Text("The five tabs move off a fixed 60pt right-hand rail and into the content, under the shell's one nav bar. Three of them wrapped themselves in a SECOND NavigationView today, which is why \"Write NFC\" drew its title in an inner bar and \"Scan\" drew its in the shell's. On iPad the bar is the only route into this feature at all — the Scan tab is deliberately removed from the bottom bar because iPads have no NFC, but All Features does not filter it, so the whole feature is one tap away on a device that cannot scan. See the caption on Scan.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }

        switch surface {
        case .scan: JobBoxLabScanSurface(sheet: $sheet)
        case .search: JobBoxLabSearchSurface()
        case .stats: JobBoxLabStatsSurface()
        case .write: JobBoxLabWriteSurface()
        case .manual: JobBoxLabManualSurface(sheet: $sheet)
        case .tracker: JobBoxLabTrackerSurface(sheet: $sheet)
        }
    }
}

// MARK: - The tab row

/// Five equal cells, wrapping to two rows on a narrow phone rather than shrinking
/// the labels. The rail it replaces gave every label a 50pt frame, which is what
/// made two of the five wrap while the other three did not.
private struct JobBoxLabTabRow: View {
    @Binding var surface: JobBoxLabSurface
    let tint: Color

    /// The five container tabs, in their shipped order. The tracker is not one of
    /// them — it is a separate registered feature.
    private var tabs: [JobBoxLabSurface] { [.scan, .search, .stats, .write, .manual] }

    private func symbol(_ tab: JobBoxLabSurface) -> String {
        switch tab {
        case .scan: return "wave.3.right.circle.fill"
        case .search: return "magnifyingglass"
        case .stats: return "chart.bar.fill"
        case .write: return "pencil.circle.fill"
        case .manual: return "square.and.pencil"
        case .tracker: return "shippingbox.fill"
        }
    }

    var body: some View {
        AmbientFlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(tabs) { tab in
                let on = surface == tab
                Button {
                    withAnimation(AmbientMotion.snappy) { surface = tab }
                    AmbientHaptics.selection()
                } label: {
                    Label(tab.rawValue, systemImage: symbol(tab))
                        .font(.caption.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(on ? .white : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        // ambient-allow: a tab control, not a container. The five
                        // tabs used to be one hardcoded colour each
                        // (.orange/.blue/.green/.purple/.teal), bypassing
                        // FeatureTheme entirely; one feature is one colour.
                        .background(Capsule().fill(on
                                                   ? AnyShapeStyle(tint)
                                                   : AnyShapeStyle(.ultraThinMaterial)))
                        .overlay(Capsule().strokeBorder(Color.primary.opacity(on ? 0 : 0.12)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.rawValue)
            }
        }
    }
}

// MARK: - Scan

private struct JobBoxLabScanSurface: View {
    @Binding var sheet: JobBoxLabSheet?
    @State private var state: JobBoxLabScanState = .ready

    /// The boxes this photographer left at a job more than 12 hours ago — the
    /// filter `checkForLeftJobBoxes()` runs, matched on FIRST NAME rather than
    /// user id (two photographers sharing a first name see each other's alerts).
    private var stalled: [LabJobBox] {
        DesignLabSampleData.jobBoxes.filter { $0.stage == .leftJob }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                AmbientSectionTitle("Lab · state", trailing: "not a design element")
                Picker("State", selection: $state) {
                    ForEach(JobBoxLabScanState.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            if state == .offline { offlineBanner }
            if state == .alert { alertBanner }

            scanDisc

            if state == .error { errorCard }

            lastScanned
            captions
        }
    }

    // MARK: the disc

    @ViewBuilder
    private var scanDisc: some View {
        if state == .noNFC {
            // 3 — PROPOSED. Today there is no pre-emptive check anywhere: the disc
            // is always live, you tap it, and CoreNFC answers "NFC scanning is not
            // supported on this device." into a red box. The reader has the app's
            // ONE availability check; the WRITER has none at all. Drawing this
            // state needs `NFCNDEFReaderSession.readingAvailable` consulted before
            // the button renders — a code change, so it is captioned PROPOSED.
            VStack(spacing: 10) {
                Image(systemName: "wave.3.right.circle")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("This device can't scan tags")
                    .font(.headline)
                Text("iPads have no NFC hardware. Search, Stats and Manual Entry all work here — use Manual Entry to record a box or a card by number.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)
            .ambientCard(density: .roomy, fillWidth: true, contentAlignment: .center)

            Text("PROPOSED — the disc is disabled BEFORE it is tapped. Today it is always live and the device answers with an error string after the fact; on iPad three of the five tabs are genuinely useful and nothing tells you which. Approving this design is not approving the code change: it needs the availability check consulted at render time, and the WRITER has no availability guard at all.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: 12) {
                Button {
                    AmbientHaptics.impact(.medium)
                    sheet = .boxForm
                } label: {
                    ZStack {
                        // ambient-allow: the scan target — a control, and
                        // deliberately the biggest one on the screen. 200pt, as
                        // shipped, but in the REGISTERED feature colour rather
                        // than a hand-rolled orange gradient.
                        Circle()
                            .fill(JobBoxMockup.featureTint.gradient)
                            .frame(width: 200, height: 200)
                            .shadow(color: JobBoxMockup.featureTint.opacity(0.35), radius: 18, y: 8)
                        VStack(spacing: 10) {
                            Image(systemName: "wave.3.right.circle.fill")
                                .font(.system(size: 72, weight: .light))
                            Text("Scan Tag").font(.title2.bold())
                        }
                        .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Scan Tag")
                .accessibilityHint("Tap to scan an NFC tag")

                Text("Hold your iPhone near the NFC tag.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: banners

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text("Offline Mode").font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
            Text("• Sync Pending").font(.caption.weight(.semibold)).foregroundStyle(.yellow)
        }
        .foregroundStyle(.white)
        .ambientCard(density: .compact, fill: .tint(.red), fillWidth: true)
    }

    /// The "Job Box Alert" banner. Kept — and given the tap target it has never
    /// had. Today it reports a problem and offers no route to fix it: no button,
    /// no tap gesture, not dismissible.
    private var alertBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                AmbientHaptics.impact(.light)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Job Box Alert").font(.subheadline.weight(.bold))
                        ForEach(stalled.prefix(3)) { box in
                            Text("Box #\(box.boxNumber) · \(JobBoxLabFormat.elapsed(since: box.latest?.at))" +
                                 (box.school.isEmpty ? "" : " · \(box.school)"))
                                .font(.caption)
                        }
                        if stalled.count > 3 {
                            Text("…and \(stalled.count - 3) more").font(.caption)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.caption.weight(.bold))
                }
                .foregroundStyle(.white)
                .ambientCard(density: .compact, fill: .tint(.orange), fillWidth: true)
            }
            .buttonStyle(.plain)

            Text("PROPOSED — the banner becomes a tap target that opens Search filtered to Left Job. Today it is a `JobBoxNotification` with no button, no tap gesture and no dismissal: it tells you a box has been sitting at a job for over 12 hours and gives you nowhere to go. Also fixed here: the plural copy hardcodes \"over 12 hours\" while the threshold is a variable (5 minutes in debug), and 43200 seconds is written out in three separate files.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var errorCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientNoteCard(title: "Couldn't read that tag",
                            text: "Unexpected tag format. Please scan a valid tag.",
                            accent: .red, density: .compact)
            Text("ONE error surface. Today the same NFC error is drawn TWICE at once — an inline red box and a red toast from the same source — and the toast's copy for a degraded fetch (\"Could not fetch job box history. Starting fresh.\") is success-shaped text delivered on the red/xmark treatment.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: what happens after a read

    private var lastScanned: some View {
        VStack(alignment: .leading, spacing: 10) {
            AmbientSectionTitle("After a read", trailing: "the two sheets")

            JobBoxLabRow(title: "Tag #3044 → Job Box",
                         detail: "3001 and above is a job box; anything else is an SD card.",
                         symbol: "shippingbox.fill",
                         tint: JobBoxTripStage.packed.meterTint) { sheet = .boxForm }

            JobBoxLabRow(title: "Tag #1042 → SD Card",
                         detail: "The read path enforces nothing — a tag written outside the app, or any non-numeric text, falls to the SD path.",
                         symbol: "sdcard.fill",
                         tint: JobBoxMockup.featureTint) { sheet = .sdForm }
        }
    }

    private var captions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOT DEMONSTRABLE IN A SIMULATOR: everything past the tap. `NFCNDEFReaderSession.readingAvailable` is false on every simulator, so the system scan sheet, the reader's five parse errors and every writer branch (read-only tag, non-NDEF tag, capacity, multi-tag collision, mid-write disconnect) need a physical device and a physical tag. Separately flagged, not claimed: the entitlement declares `TAG` only, not `NDEF`, while the reader uses `NFCNDEFReaderSession` — the single highest-value device check in this phase.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text("KEPT, unchanged: the 3001 routing rule, the status auto-advance rings (SD advances Job Box → Camera → Envelope → Uploaded → Cleared and never auto-advances to Camera Bag or Personal; job box advances round the four), the school pre-fill including \"Iconik\" after a cleared card, and shiftUid inheritance. All of it is business logic — out of scope for a design phase (D12).")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Search

private struct JobBoxLabSearchSurface: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case boxes = "Job Boxes"
        case cards = "SD Cards"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .boxes
    @State private var state: JobBoxLabListState = .results
    @State private var field = "Box #"
    @State private var query = ""

    private var fields: [String] {
        mode == .boxes
            ? ["Box #", "Photographer", "School", "Status"]
            : ["Card #", "School", "Status"]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                AmbientSectionTitle("Lab · state", trailing: "not a design element")
                Picker("State", selection: $state) {
                    ForEach(JobBoxLabListState.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Picker("Search type", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _ in field = fields[0] }

            AmbientFlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(fields, id: \.self) { name in
                    let on = field == name
                    Button {
                        withAnimation(AmbientMotion.snappy) { field = name }
                    } label: {
                        Text(name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(on ? .white : .primary)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            // ambient-allow: a filter chip, not a container.
                            .background(Capsule().fill(on
                                                       ? AnyShapeStyle(JobBoxMockup.featureTint)
                                                       : AnyShapeStyle(.ultraThinMaterial)))
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(on ? 0 : 0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }

            JobBoxLabSearchField(placeholder: "Search \(field.lowercased())", text: $query)

            content

            Text("DROPPED, deliberately: the SD-card \"Photographer\" search field. It issues `.eq(\"photographer\", …)` against a column the `records` table does not have — PROVED by live query, the table's ten columns are id, organization_id, card_number, school, status, user_id, timestamp, uploaded_from_andys_house, uploaded_from_jasons_house, created_at. PostgREST errors, the catch falls back to cached rows whose photographer is empty, and the search can never return a row. It looks like a working control today. Removing it is an OPERATOR decision, not a design one: the alternative is growing the column.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text("UNCHANGED and worth knowing: a number search is an EXACT string match, so \"0301\" and \"301\" are different cards and there is no partial or prefix match; a STATUS search is done client-side over every row in the org (4,166 of them) and answers \"currently at status X\", not \"was ever at X\". Both are data-layer behaviour — named here, not changed.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            JobBoxLabLoading(message: "Searching…")
        case .empty:
            // 3 — the state that does not exist today. An empty result is a blank
            // List plus a modal alert titled "Info" — errors and successes share
            // that one non-error title on three screens.
            VStack(spacing: 10) {
                AmbientEmptyState(
                    title: "No boxes match",
                    message: "Nothing in this organization matches \"\(query.isEmpty ? "3099" : query)\". Box numbers match exactly — a leading zero counts.",
                    systemImage: "magnifyingglass")
                Text("PROPOSED — Search has NO empty state today. An empty result draws a blank list and raises a modal alert titled \"Info\" saying \"No records found.\", which you have to dismiss before you can edit the query.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .failed:
            JobBoxLabFailure(message: "Couldn't reach the server. Your last results are still shown below.",
                             detail: "PROPOSED — a failed search is an alert titled \"Info\" today, with no retry and nothing distinguishing it from a search that legitimately found nothing.")
        case .results:
            VStack(alignment: .leading, spacing: 10) {
                AmbientSectionTitle(mode == .boxes ? "Job boxes" : "SD cards",
                                    trailing: mode == .boxes
                                        ? "\(DesignLabSampleData.jobBoxes.count)"
                                        : "\(DesignLabSampleData.sdRecords.count)")
                if mode == .boxes {
                    ForEach(DesignLabSampleData.jobBoxes) { box in
                        JobBoxLabBoxBubble(box: box)
                    }
                } else {
                    ForEach(DesignLabSampleData.sdRecords) { record in
                        JobBoxLabCardBubble(record: record)
                    }
                }
                Text("Swipe a row to delete it — unchanged, and it keeps its confirmation. Not drawable on these cards: swipe actions are List-only, so the converted screen stays a List. The scrim behind that confirmation has an `.onTapGesture { }` with a fully commented-out body today — a scrim that visibly accepts a tap and does nothing. It becomes a real dismiss.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Statistics

private struct JobBoxLabStatsSurface: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case boxes = "Job Boxes"
        case cards = "SD Cards"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .boxes
    @State private var state: JobBoxLabListState = .results
    @State private var timeFrame = "All Time"

    private let timeFrames = ["Today", "This Week", "This Month", "All Time"]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                AmbientSectionTitle("Lab · state", trailing: "not a design element")
                Picker("State", selection: $state) {
                    ForEach(JobBoxLabListState.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            Picker("View mode", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            AmbientFlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(timeFrames, id: \.self) { frame in
                    let on = timeFrame == frame
                    Button {
                        withAnimation(AmbientMotion.snappy) { timeFrame = frame }
                    } label: {
                        Text(frame)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(on ? .white : .primary)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            // ambient-allow: a time-frame chip, not a container.
                            .background(Capsule().fill(on
                                                       ? AnyShapeStyle(JobBoxMockup.featureTint)
                                                       : AnyShapeStyle(.ultraThinMaterial)))
                            .overlay(Capsule().strokeBorder(Color.primary.opacity(on ? 0 : 0.12)))
                    }
                    .buttonStyle(.plain)
                }
            }

            content
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            VStack(alignment: .leading, spacing: 8) {
                JobBoxLabLoading(message: "Loading statistics…")
                Text("PROPOSED — Statistics has NO loading state. `isLoading` is set in three places and never read in `body`, so the first paint of the screen is a full set of ZEROES that reads as an answer, and both tables are re-pulled whole on every appearance.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .failed:
            JobBoxLabFailure(message: "Couldn't load job box statistics.",
                             detail: "Kept from today: an SD failure aborts everything while a job-box failure still computes the SD half. What is added is a retry — and a job-box failure while OFFLINE says so, because there is no job-box cache at all (SD cards fall back to one; job boxes throw \"Job box data not available offline\").")
        case .empty:
            AmbientEmptyState(title: "No data available",
                              message: "No scans in this time frame.",
                              systemImage: "chart.bar")
        case .results:
            VStack(alignment: .leading, spacing: 14) {
                distribution
                averages
                lifecycle
                photographerActivity
                captions
            }
        }
    }

    /// The distribution. The pie is REPLACED: it is hand-drawn (a `PieSlice: Shape`
    /// with two `addArc`s — `import Charts` is present and unused for it), its slice
    /// labels are white text positioned by trig over the fill, which is
    /// near-invisible over `envelope #FFCC00`, and its percentage is `Int(...)`
    /// truncated while the legend beside it prints `%.1f%%` — two roundings of one
    /// number sitting side by side.
    private var distribution: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle(mode == .boxes ? "Job box status distribution" : "Card status distribution",
                                trailing: mode == .boxes ? "1,059 boxes" : "4,168 cards")

            VStack(spacing: 8) {
                if mode == .boxes {
                    ForEach(DesignLabSampleData.jobBoxStatusCounts, id: \.status.rawValue) { entry in
                        JobBoxLabDistributionRow(
                            label: entry.status.label,
                            count: entry.count,
                            total: DesignLabSampleData.jobBoxStatusCounts.reduce(0) { $0 + $1.count },
                            tint: entry.status.meterTint)
                    }
                } else {
                    ForEach(DesignLabSampleData.sdStatusCounts, id: \.status) { entry in
                        JobBoxLabDistributionRow(
                            label: entry.status,
                            count: entry.count,
                            total: DesignLabSampleData.sdStatusCounts.reduce(0) { $0 + $1.count },
                            tint: StatusColors.color(forSDStatus: entry.status))
                    }
                }
            }
            .ambientCard(density: .compact, fill: .surface,
                         border: .hairline(Color.primary.opacity(0.10)), fillWidth: true)

            Text("Each row is still a tap through to Search filtered to that status — the only cross-screen navigation this view has, and it is kept. The SD colours here come from `NFC/StatusColors`, which `STATUS_COLORS_DOCUMENTATION.md` calls the iOS↔web standard; the job-box colours come from the SHIPPED meter. Those two maps disagree about three of the four job-box statuses. See the tracker.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var averages: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Average time in status")
            VStack(spacing: 8) {
                JobBoxLabStatLine(label: "Packed", value: "1.4 days")
                JobBoxLabStatLine(label: "Picked up", value: "6.2 hours")
                JobBoxLabStatLine(label: "Left job", value: "14.8 hours")
                JobBoxLabStatLine(label: "Turned in", value: "3.1 days")
            }
            .ambientCard(density: .compact, fill: .surface,
                         border: .hairline(Color.primary.opacity(0.10)), fillWidth: true)
            Text("The arithmetic is unchanged and is worth stating: the mean divides by the number of INTERVAL SAMPLES, not by the number of boxes, and an open dwell (now − last scan) is folded in only when it is under 30 days — so an idle box contributes nothing and an open one inflates the figure.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var lifecycle: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle(mode == .boxes ? "Job box processing timeline" : "Card lifecycle")
            VStack(spacing: 8) {
                if mode == .boxes {
                    JobBoxLabStatLine(label: "Assignment · Packed → Picked Up", value: "9.4 hours")
                    JobBoxLabStatLine(label: "Completion · Picked Up → Turned In", value: "11.2 hours")
                } else {
                    JobBoxLabStatLine(label: "Average", value: "6.8 days")
                    JobBoxLabStatLine(label: "Shortest", value: "1.2 days")
                    JobBoxLabStatLine(label: "Longest", value: "31.0 days")
                    JobBoxLabStatLine(label: "Total completed cycles", value: "412")
                }
            }
            .ambientCard(density: .compact, fill: .surface,
                         border: .hairline(Color.primary.opacity(0.10)), fillWidth: true)
            Text("Kept exactly: only ADJACENT pairs count, so a Left Job scan between pickup and turn-in destroys the completion pair; job-box intervals are accepted only between 0 and 168 hours and card cycles only between 0 and 90 days. Named, not fixed: one \"cleared\" row can close several \"job box\" starts for the same card, so overlapping cycles are double counted.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var photographerActivity: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Photographer activity")
            if mode == .cards {
                AmbientEmptyState(
                    title: "Not available for SD cards",
                    message: "SD card scans do not record who scanned them, so there is nothing to group by.",
                    systemImage: "person.crop.circle.badge.questionmark")
                Text("PROPOSED — today this chart is drawn in SD mode as a TITLED, PERMANENTLY EMPTY chart with no empty-state text at all. It groups by photographer and drops empty names, and every SD row's photographer is the empty string because the column does not exist. Either it says this, or it is not drawn in SD mode; drawn here as the honest version.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 8) {
                    JobBoxLabStatLine(label: "Maria Alvarez", value: "38 boxes")
                    JobBoxLabStatLine(label: "Devon Wright", value: "31 boxes")
                    JobBoxLabStatLine(label: "Priya Nair", value: "22 boxes")
                }
                .ambientCard(density: .compact, fill: .surface,
                             border: .hairline(Color.primary.opacity(0.10)), fillWidth: true)
                Text("The metric is DISTINCT box numbers, not scan count, top five — unchanged. The \"Left Job duration by photographer\" block below it is kept too, with one thing said out loud that today's headline hides: its \"Average Time\" mixes closed spans (counted only at an hour or more) with spans that are still open, so it is not a like-for-like average.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var captions: some View {
        Text("DROPPED: roughly 150 lines of `#available(iOS 16.0, *)` else-branches, including a \"Chart requires iOS 16+\" string no user can ever see — the deployment target is 16.6 (D4). Also dropped: 88 lines of donut hit-testing with zero call sites whose own comment describes a donut this screen does not draw, and about twenty `print(\"DEBUG:\")` calls inside the per-photographer loop.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Write NFC

private struct JobBoxLabWriteSurface: View {
    private enum Kind: String, CaseIterable, Identifiable {
        case box = "Job Box"
        case card = "SD Card"
        var id: String { rawValue }
    }

    @State private var kind: Kind = .box
    @State private var number = ""
    @State private var writing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AmbientFormSection(title: "Write to a tag",
                               status: number.isEmpty ? "required" : number,
                               statusTint: number.isEmpty ? .orange : nil) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Item type", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    TextField(kind == .box ? "Enter Job Box Number (3001+)" : "Enter SD Card Number (1001-2000)",
                              text: $number)
                        .font(.subheadline)
                        .keyboardType(.numberPad)

                    Text(kind == .box ? "Suggested Job Box Number: 3081" : "Suggested SD Card Number: 1208")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                withAnimation(AmbientMotion.snappy) { writing.toggle() }
            } label: {
                HStack(spacing: 8) {
                    if writing { ProgressView().tint(.white) }
                    Text(writing ? "Hold your iPhone near the tag…" : "Write NFC")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                // ambient-allow: the primary action — a control, not a container.
                .background(Capsule().fill(JobBoxMockup.featureTint))
            }
            .buttonStyle(.plain)

            Text("The button STAYS while it writes. Today it is replaced by a bare `ProgressView()`, so the control vanishes rather than dimming, and the alert that follows decides whether to dismiss the screen by testing `alertMessage.contains(\"successfully\")` — string-matched control flow.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text("NOT PROMISED, and each is a code change rather than a layout one: reading a tag back to confirm what was written, checking whether the number is already in use, and confirming before overwriting a tag that already holds one. None exists today. Also unchanged: the SD suggestion is clamped with `max(1001, min(2000, …))`, so once the org reaches card 2000 it pins there forever and pre-fills a duplicate.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text("PROPOSED — an OFFLINE state on this screen. It has none: writing a tag offline succeeds on the hardware, the record silently takes the offline queue path, and the alert still says \"saved successfully\". Suspected and unverified without a device: a second write in one visit may save no record at all, because `isWritingSuccessful` is never reset to false.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Manual entry

private struct JobBoxLabManualSurface: View {
    @Binding var sheet: JobBoxLabSheet?

    private enum Kind: String, CaseIterable, Identifiable {
        case box = "Job Box"
        case card = "SD Card"
        var id: String { rawValue }
    }

    @State private var kind: Kind = .box
    @State private var number = "3044"
    @State private var sessionsLoading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            AmbientFormSection(title: kind == .box ? "Job box information" : "Card information",
                               status: number.count == 4 ? number : "4 digits",
                               statusTint: number.count == 4 ? nil : .orange) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Entry type", selection: $kind) {
                        ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    TextField(kind == .box ? "Enter 4-digit Box Number (3001+)" : "Enter 4-digit Card Number",
                              text: $number)
                        .font(.subheadline)
                        .keyboardType(.numberPad)

                    Text("The last record for this number is fetched the moment the fourth digit lands — unchanged.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            AmbientFormSection(title: "Session assignment",
                               status: sessionsLoading ? "loading" : "1 selected",
                               statusTint: sessionsLoading ? .orange : .blue) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Lab · sessions still loading", isOn: $sessionsLoading)
                        .font(.caption)
                        .tint(JobBoxMockup.featureTint)

                    if sessionsLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Loading today's sessions…").font(.subheadline).foregroundStyle(.secondary)
                        }
                    } else {
                        JobBoxLabRow(title: "Riverside Elementary",
                                     detail: "Tomorrow · 7:30 AM – 2:00 PM · Underclass",
                                     symbol: "calendar",
                                     tint: JobBoxMockup.featureTint) {}
                    }

                    Text("PROPOSED — a LOADING state on the session control. Today the session picker is not rendered AT ALL while sessions are in flight or when there are none, so you cannot tell \"still loading\" from \"no sessions\" on the one control that links a box to a job; a load FAILURE is swallowed to a `print` and shows the same nothing. The session list itself is unchanged: published, scheduled sessions from today to today+14.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            AmbientFormSection(title: "Additional information", status: "Packed", statusTint: nil) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("School · Riverside Elementary").font(.subheadline)
                    Text("A searchable school picker on BOTH paths. The two sheets the Scan screen presents use a plain `Picker` over every school in the org while Manual Entry uses a searchable sheet — one control, the searchable one.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider()
                    Text("Status · Packed").font(.subheadline)
                    Text("The two \"Uploaded from …'s house\" toggles are kept, and they stay gated to the one organization whose id is hardcoded in two files. They are two people's names in shipped UI; renaming them is an operator call, not a design one.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Text("Cancel")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    // ambient-allow: a form button, not a container.
                    .background(Capsule().fill(.ultraThinMaterial))
                Button { sheet = .boxForm } label: {
                    Text("Submit")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        // ambient-allow: the primary action — a control.
                        .background(Capsule().fill(JobBoxMockup.featureTint))
                }
                .buttonStyle(.plain)
            }

            pickupWarning

            Text("PROPOSED — the form CLEARS after a successful save. Today it does not, so a second Submit re-inserts the same values; and Submit has no in-flight state at all, it only greys.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The pickup guard's copy, drawn as text so the words can be judged here — an
    /// `.alert` cannot be evaluated in a gallery, and these words are the whole
    /// safety mechanism. Owned by `JobBox/JobBoxPickupRules.swift`, which already
    /// has its own test harness.
    private var pickupWarning: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientNoteCard(
                title: "Check This Pickup",
                text: "This is box 3044, but box 3050 was packed for Riverside Elementary. Make sure you have the right box.",
                accent: .orange, density: .compact)
            Text("KEPT WORD FOR WORD, and the guard behind it is untouched — including that it deliberately FAILS OPEN when the device is offline or the lookup errors. Confirm reads \"Pick Up Anyway\", or \"Save Without a Session\" when the box is not linked to a job. NAMED, NOT FIXED: the Scan screen never calls this guard — it is only on Manual Entry and the job box sheet, and Scan is safe today only because it delegates to that sheet. A redesign that inlines the form into the scan screen loses the guard silently.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - The manager tracker

private struct JobBoxLabTrackerSurface: View {
    @Binding var sheet: JobBoxLabSheet?

    @State private var state: JobBoxLabListState = .results
    @State private var filter = "Active"
    @State private var statusFilter = "All statuses"
    @State private var advanced = false
    @State private var query = ""

    private let filters = ["All", "Active", "Stalled", "Today", "Completed"]
    private let statuses = ["All statuses", "Packed", "Picked Up", "Left Job", "Turned In"]

    private var boxes: [LabJobBox] {
        let all = DesignLabSampleData.jobBoxes
        switch filter {
        case "Completed": return all.filter { $0.stage == .turnedIn }
        case "Active": return all.filter { $0.stage != .turnedIn }
        case "Stalled": return all.filter { $0.stage == .leftJob }
        default: return all
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                AmbientSectionTitle("Lab · state", trailing: "not a design element")
                Picker("State", selection: $state) {
                    ForEach(JobBoxLabListState.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            header
            JobBoxLabSearchField(placeholder: "Search schools, photographers or box #", text: $query)
            filterRow
            if advanced { statusRow }
            windowNote
            content
            flagAbsence
            colourQuestion
        }
    }

    /// ONE title. The shell supplies a nav bar, the view sets `.navigationTitle`,
    /// AND the body's first element is a `largeTitle` Text of the same words — so
    /// the title renders twice today.
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                AmbientSectionTitle("Job boxes", trailing: "\(boxes.count) shown")
                Spacer(minLength: 8)
                Button { sheet = .settings } label: {
                    Image(systemName: "gearshape")
                        .font(.footnote.weight(.semibold))
                        .frame(width: 30, height: 30)
                        // ambient-allow: an icon control, not a container.
                        .background(Circle().fill(.ultraThinMaterial))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stalled time settings")

                Button {} label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.footnote.weight(.semibold))
                        .frame(width: 30, height: 30)
                        // ambient-allow: an icon control, not a container.
                        .background(Circle().fill(.ultraThinMaterial))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh")
            }
            Text("Both icon controls get accessibility labels here. Neither has one today — nor does the search field's clear button — while the shipped meter beside them does.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var filterRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientFlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(filters, id: \.self) { name in
                    JobBoxLabChip(text: name, on: filter == name,
                                  tint: JobBoxMockup.trackerTint) {
                        withAnimation(AmbientMotion.snappy) { filter = name }
                    }
                }
                JobBoxLabChip(text: advanced ? "Status ▾" : "Status ▸", on: advanced,
                              tint: JobBoxMockup.trackerTint) {
                    withAnimation(AmbientMotion.snappy) { advanced.toggle() }
                }
            }
            Text("ONE selection colour. Today the primary pills select BLUE and the status pills directly under them select GREEN — two selection colours for two adjacent rows on one screen. DROPPED: the \"Date Filter\" toggle and its DatePicker. `selectedDate` is written by that picker and read by NOTHING — no query, no filter, no sort. It is a control that does nothing at all.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var statusRow: some View {
        AmbientFlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(statuses, id: \.self) { name in
                JobBoxLabChip(text: name, on: statusFilter == name,
                              tint: JobBoxMockup.trackerTint) {
                    withAnimation(AmbientMotion.snappy) { statusFilter = name }
                }
            }
        }
    }

    /// 4 — the sentence that does not exist today.
    private var windowNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientNoteCard(
                title: "Showing the last 30 days",
                text: "Boxes last scanned more than 30 days ago are not fetched. A box you cannot find here may still exist — search its number to see every scan on it.",
                accent: JobBoxMockup.trackerTint, density: .compact)
            Text("PROPOSED — both tracker queries are hardcoded to a 30-day window and nothing says so. Live, that is 17 rows of 1,059: a manager looking for a box last scanned five weeks ago is told \"No job boxes found\". The screen also opens on the Active filter, already hiding every turned-in box, with the \"All\" pill visibly unselected — kept, but the count line now says what is being counted. And ONE field still drives two list semantics: typing a NUMBER lists every scan row for that box, typing a WORD lists one row per box.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            JobBoxLabLoading(message: "Loading job boxes…")
        case .empty:
            AmbientEmptyState(
                title: "No job boxes in the last 30 days",
                message: "Nothing matches this filter inside the window. Search a box number to look further back.",
                systemImage: "shippingbox",
                actionTitle: "Show all statuses",
                actionIcon: "line.3.horizontal.decrease.circle",
                action: { filter = "All"; statusFilter = "All statuses" },
                actionTint: JobBoxMockup.trackerTint)
        case .failed:
            JobBoxLabFailure(
                message: "Couldn't load job boxes.",
                detail: "PROPOSED — a retry. Today the error is a bare red `Text` above the list with no retry affordance; it clears only when the next load happens to start. Offline is not detected at all here, so it surfaces as a raw URLError string, and a missing organization id returns silently and draws \"No job boxes found\" instead.")
        case .results:
            VStack(alignment: .leading, spacing: 10) {
                ForEach(boxes) { box in
                    Button { sheet = .editStatus(box.id) } label: {
                        JobBoxLabTrackerRow(box: box)
                    }
                    .buttonStyle(.plain)
                    .ambientScrollFade()
                }
                Text("The meter on each row is the SHIPPED scrubber (`JobBoxProgressMeter`, compact), reading the same rules the shift detail uses — embedded, not redesigned. What changed around it: the row background no longer carries a fifth colour map, and the stage colour comes from the meter so one box is one colour everywhere.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 6 — the affordance drawn as ABSENT.
    private var flagAbsence: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientNoteCard(
                title: "\"Flag for Attention\" is not drawn",
                text: "The swipe action, the context-menu item and the whole flag sheet are gone from this design. They write `flagged`, `flag_note` and `flagged_at` — and PROVED by live query, `job_boxes` has exactly ten columns and none of those three. PostgREST rejects the statement as a unit, so the only possible outcome of using it today is a red error string. Nothing anywhere reads a job-box flag.",
                accent: .red, density: .compact)
            Text("PROPOSED, PENDING AN OPERATOR RULING — this is a decision, not a design. Either the schema grows three columns and something reads them (a feature, with its own phase), or the three affordances come out. Drawn here as absent because a mockup must not promise dead API surface; approving this design is NOT approving the removal, and it is NOT approving a schema change.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var colourQuestion: some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Three colour maps, one vocabulary")
            VStack(spacing: 6) {
                ForEach(JobBoxTripStage.allCases, id: \.rawValue) { stage in
                    HStack(spacing: 10) {
                        Text(stage.label).font(.footnote.weight(.semibold))
                        Spacer(minLength: 8)
                        JobBoxLabSwatch(tint: stage.meterTint, caption: "meter")
                        // SETTLED 2026-07-30: the second swatch used to draw the
                        // `StatusColors` job-box map so the disagreement could be
                        // seen. That map is deleted and this one is the contract,
                        // so both swatches are now the same colour by
                        // construction — which is the point.
                        JobBoxLabSwatch(tint: stage.meterTint, caption: "contract")
                    }
                }
            }
            .ambientCard(density: .compact, fill: .surface,
                         border: .hairline(Color.primary.opacity(0.10)), fillWidth: true)
            Text("PROPOSED, PENDING AN OPERATOR RULING — the two swatches disagree on three of four statuses, and a third map (the tracker's own row background: packed blue, picked-up purple, left-job orange) has already been deleted by the meter slice. `STATUS_COLORS_DOCUMENTATION.md` declares the `StatusColors` map a cross-platform iOS↔web standard, so re-tokenising it is a contract change and not a style choice. This design draws the SHIPPED METER's colours everywhere a job box appears; the decision needed is whether `StatusColors` is retired or becomes authoritative.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Sheets

/// The SD sheet the Scan screen presents. It sets a `navigationTitle` today with no
/// enclosing container to render it, and its alert is titled `Text("")` on both
/// branches — a message with no heading.
private struct JobBoxLabSDForm: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop(tint: JobBoxMockup.featureTint, intensity: 0.6)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        AmbientFormSection(title: "Card information", status: "#1042", statusTint: .blue) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Last seen · Envelope · Riverside Elementary · yesterday 5:05 PM")
                                    .font(.subheadline)
                                Text("Status pre-selects the NEXT step in the ring — unchanged. A card sitting in Camera Bag or Personal falls back to \"Job Box\" rather than to a successor, deliberately.")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        AmbientFormSection(title: "Details", status: "Uploaded", statusTint: nil) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("School · Riverside Elementary").font(.subheadline)
                                Text("Status · Uploaded").font(.subheadline)
                                Text("DROPPED: the Photographer picker. Its value is discarded server-side on every online save — the column does not exist. Keeping it preserves a broken feature; removing it takes away a control that looks like it works. Operator decision.")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Text("This sheet gets a real title bar. Today it declares \"Enter Info\" with no NavigationView around it, so the title never renders; the job box sheet has the same shape.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("SD Card 1042")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Submit") { dismiss() } }
            }
        }
    }
}

private struct JobBoxLabBoxForm: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sessionsLoading = false

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop(tint: JobBoxMockup.featureTint, intensity: 0.6)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        AmbientFormSection(title: "Job box information", status: "#3044", statusTint: .blue) {
                            JobBoxProgressCard(reading: DesignLabSampleData.jobBoxes[2].reading,
                                               boxNumber: "3044")
                        }
                        AmbientFormSection(title: "Session",
                                           status: sessionsLoading ? "loading" : "Westbrook High School",
                                           statusTint: sessionsLoading ? .orange : nil) {
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle("Lab · sessions still loading", isOn: $sessionsLoading)
                                    .font(.caption)
                                    .tint(JobBoxMockup.featureTint)
                                if sessionsLoading {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                        Text("Loading sessions…").font(.subheadline).foregroundStyle(.secondary)
                                    }
                                } else {
                                    Text("Westbrook High School · 7:40 AM – 3:00 PM").font(.subheadline)
                                }
                                Text("ONE session-choosing UI. Today this sheet uses an inline Picker with a \"None\" tag while Manual Entry opens a searchable sheet over the same data — two designs for one choice. And while sessions are loading, this control is NOT RENDERED AT ALL, so \"still loading\" and \"no sessions\" look identical on the control that links a box to a job.")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Text("A brand-new box deliberately arrives with NO school and NO status so the session picker supplies them — unchanged.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Job Box 3044")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Submit") { dismiss() } }
            }
        }
    }
}

/// The tracker's edit sheet: five detail rows and the four transition buttons.
private struct JobBoxLabEditSheet: View {
    let boxId: String
    @Environment(\.dismiss) private var dismiss

    private var box: LabJobBox {
        DesignLabSampleData.jobBoxes.first { $0.id == boxId } ?? DesignLabSampleData.jobBoxes[0]
    }

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop(tint: JobBoxMockup.trackerTint, intensity: 0.6)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        JobBoxProgressCard(reading: box.reading, boxNumber: box.boxNumber)

                        AmbientFormSection(title: "Details", status: box.school, statusTint: nil) {
                            VStack(alignment: .leading, spacing: 6) {
                                JobBoxLabStatLine(label: "Photographer",
                                                  value: box.photographer ?? "Not recorded")
                                JobBoxLabStatLine(label: "Last scan",
                                                  value: JobBoxLabFormat.stamp(box.latest?.at))
                                JobBoxLabStatLine(label: "Session",
                                                  value: box.shiftUid == nil ? "Not linked" : "Linked")
                            }
                        }

                        AmbientFormSection(title: "Record a scan", status: "inserts a row", statusTint: .orange) {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(JobBoxTripStage.allCases, id: \.rawValue) { stage in
                                    HStack(spacing: 10) {
                                        Image(systemName: stage.meterIcon)
                                            .foregroundStyle(stage.meterTint)
                                            .frame(width: 22)
                                        Text(stage.label).font(.subheadline)
                                        Spacer(minLength: 0)
                                        if box.reading.state(stage) == .scanned {
                                            Image(systemName: "checkmark").foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                Text("These INSERT a new scan row rather than updating one — deliberately, and it stays that way: an update falsified the scan moment and skipped the crew push trigger. NAMED, NOT FIXED: there is no transition validation at all, so Turned In → Packed is one tap with no confirmation and no undo.")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        Text("PROPOSED — a success confirmation. Today the sheet just dismisses: no toast, no haptic, nothing that says the scan was recorded, on a screen whose whole purpose is recording one.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("DROPPED: the two \"Card #\" rows. `cardNumber` is hardcoded to the empty string on every row the tracker builds, so those rows, the row's card pill and both card-number branches of the grouping key are structurally unreachable.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Box \(box.boxNumber)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

/// Job Box Settings — reachable only from the tracker's gear, with no feature id
/// and no theme of its own.
private struct JobBoxLabSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var packedDays: Double = 2
    @State private var pickedUpDays: Double = 4
    @State private var leftJobHours: Double = 12

    var body: some View {
        NavigationView {
            ZStack {
                AmbientBackdrop(tint: JobBoxMockup.trackerTint, intensity: 0.6)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        AmbientNoteCard(
                            title: "These settings live on this device",
                            text: "They are stored on this iPad only and are not shared. Two managers on two devices can see different boxes called stalled from identical data.",
                            accent: .orange, density: .compact)

                        AmbientFormSection(title: "Stalled thresholds", status: "3 rules", statusTint: nil) {
                            VStack(alignment: .leading, spacing: 14) {
                                JobBoxLabSlider(title: "Packed",
                                                value: $packedDays, range: 1...10, step: 1,
                                                readout: "\(Int(packedDays)) days",
                                                tint: JobBoxTripStage.packed.meterTint)
                                JobBoxLabSlider(title: "Picked up",
                                                value: $pickedUpDays, range: 1...10, step: 1,
                                                readout: "\(Int(pickedUpDays)) days",
                                                tint: JobBoxTripStage.pickedUp.meterTint)
                                JobBoxLabSlider(title: "Left job",
                                                value: $leftJobHours, range: 0.5...48, step: 0.5,
                                                readout: String(format: "%.1f hrs", leftJobHours),
                                                tint: JobBoxTripStage.leftJob.meterTint)
                            }
                        }

                        Text("PROPOSED — the \"Left Job\" default. Its shipped default is 192 hours, which is OUTSIDE its own slider's 0.5…48 range: on first open the slider renders clamped, and the first touch silently rewrites a 192-hour threshold to 48 or less, changing which boxes the tracker calls stalled with no confirmation. Drawn here at 12 hours, matching the Job Box Alert's own threshold. Approving this design is not approving the constant change.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Every drag tick still commits — there is no Save and no Cancel, and Reset is the only undo. That is kept: it is how the screen behaves and changing it is behaviour, not layout. The \"Unknown\" status keeps its 3-hour threshold with no control, because no live row has ever had that status.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("Reset to default values")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            // ambient-allow: a destructive control, not a container.
                            .background(Capsule().fill(Color.red.opacity(0.12)))
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Job Box Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

// MARK: - Components

private struct JobBoxLabTrackerRow: View {
    let box: LabJobBox

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(box.school).font(AmbientDensity.compact.titleFont)
                Spacer(minLength: 8)
                AmbientBadge(text: "Box \(box.boxNumber)", tint: box.reading.meterTint)
            }

            HStack(spacing: 8) {
                Text(box.reading.headline)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(box.reading.meterTint)
                Text(box.reading.detailLine())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            JobBoxProgressMeter(reading: box.reading, compact: true)

            if let note = box.reading.skipNote {
                Text(note).font(.caption2).foregroundStyle(.secondary)
            }
            if box.shiftUid == nil {
                Text("Not linked to a session — this box will not appear on a job's tracker.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .ambientCard(density: .compact, fillWidth: true)
    }
}

private struct JobBoxLabBoxBubble: View {
    let box: LabJobBox

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(box.reading.meterTint).frame(width: 10, height: 10).padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(box.reading.headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(box.reading.meterTint)
                Text("Box #\(box.boxNumber) · \(box.school)").font(.caption)
                Text(box.reading.detailLine()).font(.caption).foregroundStyle(.secondary)
                if box.stage == .leftJob {
                    Label("Left for \(JobBoxLabFormat.elapsed(since: box.latest?.at))",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
        }
        .ambientCard(density: .compact, fillWidth: true)
    }
}

private struct JobBoxLabCardBubble: View {
    let record: LabSDRecord

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(StatusColors.color(forSDStatus: record.status))
                .frame(width: 10, height: 10)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(record.status)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(StatusColors.color(forSDStatus: record.status))
                Text("Card #\(record.cardNumber) · \(record.school)").font(.caption)
                Text(Formatters.mediumDateTime.string(from: record.at))
                    .font(.caption).foregroundStyle(.secondary)
                if let from = record.uploadedFrom {
                    Text("Uploaded from \(from)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .ambientCard(density: .compact, fillWidth: true)
    }
}

private struct JobBoxLabRow: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol).foregroundStyle(tint).frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(AmbientDensity.compact.titleFont)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
            .ambientCard(density: .compact, fillWidth: true)
        }
        .buttonStyle(.plain)
    }
}

private struct JobBoxLabChip: View {
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

private struct JobBoxLabSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(placeholder, text: $text).font(.subheadline)
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

private struct JobBoxLabDistributionRow: View {
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

private struct JobBoxLabStatLine: View {
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

private struct JobBoxLabSwatch: View {
    let tint: Color
    let caption: String

    var body: some View {
        VStack(spacing: 3) {
            // ambient-allow: a colour swatch, not a container — it is the thing
            // being compared.
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(tint)
                .frame(width: 34, height: 16)
            Text(caption).font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
        }
    }
}

private struct JobBoxLabSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let readout: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.footnote.weight(.semibold))
                Spacer(minLength: 8)
                Text(readout).font(.footnote.weight(.semibold)).foregroundStyle(tint)
            }
            Slider(value: $value, in: range, step: step).tint(tint)
        }
    }
}

private struct JobBoxLabLoading: View {
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

private struct JobBoxLabFailure: View {
    let message: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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

            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Formatting

private enum JobBoxLabFormat {
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
