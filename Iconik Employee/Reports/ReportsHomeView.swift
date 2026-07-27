//  ReportsHomeView.swift
//  Iconik Employee — "My Daily Job Reports", converted in AMB.7
//
//  Replaces Misc Features/MyJobReportsView.swift AND Misc
//  Features/TemplateReportListView.swift, both deleted in the same commit.
//
//  THE ARGUMENT THIS SCREEN MAKES
//      The list a photographer can actually open had NO search, NO filter, NO
//      grouping and NO EMPTY STATE AT ALL — so "you have never filed a report"
//      and "the query came back with nothing" were the same blank screen. A
//      SECOND list, TemplateReportListView, had every one of those things: 558
//      lines, compiled, shipped, and ORPHANED — its only instantiation anywhere
//      in the repo was its own preview instantiating itself.
//
//      So the capabilities move from the dead screen into the live one and the
//      dead screen goes. Search, a date window, grouping, template badges, a
//      real empty state and an error state with a retry are all here.
//
//  AND THE QUESTION THE SURFACE NEVER ANSWERED
//      "Have I filed today's report yet?" The app already computes exactly this
//      — auto-select walks today's sessions and picks the first one you have NOT
//      reported — but it did it silently, inside a form you had to open first.
//      It leads the screen now.
//
//  WHY IT IS A `List`
//      Swipe-to-delete is a real capability of the screen being replaced, and
//      `.swipeActions` is List-only: on a row inside a LazyVStack it compiles,
//      renders and silently does nothing. So this is a List with its own chrome
//      stripped — hidden scroll background, clear row backgrounds, no
//      separators, insets set by hand — exactly as AMB.6 did for Chat.

import SwiftUI

struct ReportsHomeView: View {

    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""
    @AppStorage("userFirstName") private var storedUserFirstName: String = ""

    @State private var reports: [DailyJobReport] = []
    @State private var isLoading = false
    @State private var errorMessage = ""
    /// Which reload is current. This runs on every appearance now, so a
    /// pop-back and a pull-to-refresh can overlap and resolve in either order —
    /// the slower one's rows would land last and the faster one's `defer` would
    /// clear the spinner while the other was still in flight. The neighbouring
    /// lookup got this guard in the same round; this one needed it too.
    @State private var reloadRun = 0
    @State private var search = ""
    @State private var window: ReportWindow = .all
    @State private var groupByTemplate = false

    @State private var pendingDelete: DailyJobReport?
    @State private var isDeleting = false
    @State private var deleteFailure: String?

    @StateObject private var schedule = ReportSchedule()
    @State private var destination: ReportsDestination?

    /// This feature's colour (D11) and the wash behind the screen.
    private var feature: Color { FeatureTheme.color(for: "myDailyJobReports") }

    /// ONE push target per view, with an enum when a screen needs several — the
    /// rule since AMB.3, because two stacked `NavigationLink(isActive:)` is the
    /// shape of AMB.1's dead tap.
    private enum ReportsDestination: Hashable, Identifiable {
        case newReport
        case templates
        case edit(String)

        var id: String {
            switch self {
            case .newReport: return "new"
            case .templates: return "templates"
            case .edit(let reportID): return "edit-\(reportID)"
            }
        }
    }

    enum ReportWindow: String, CaseIterable, Identifiable {
        case all = "All"
        case week = "This Week"
        case month = "This Month"
        case thirty = "Last 30 Days"

        var id: String { rawValue }

        func contains(_ date: Date) -> Bool {
            guard self != .all else { return true }
            let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0
            switch self {
            case .all: return true
            case .week: return days <= 7
            case .month: return days <= 31
            case .thirty: return days <= 30
            }
        }
    }

    // MARK: - Filtering

    private var filtered: [DailyJobReport] {
        reports.filter { report in
            guard window.contains(report.date) else { return false }
            guard !search.isEmpty else { return true }
            let haystack = [report.school_or_destination ?? "",
                            report.template_name ?? "",
                            report.session_name ?? ""].joined(separator: " ")
            return haystack.localizedCaseInsensitiveContains(search)
        }
    }

    /// "Standard reports" for everything with no template — the orphaned screen
    /// called that group "Legacy Reports", which is a word for the developer
    /// rather than for the photographer.
    private var groups: [(String, [DailyJobReport])] {
        Dictionary(grouping: filtered) { $0.template_name ?? "Standard reports" }
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: feature, intensity: 0.75)
            content
        }
        .navigationTitle("My Daily Job Reports")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .onDisappear { schedule.stop() }
        .refreshable { await reload() }
        .alert("Delete Report", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingDelete = nil }
            Button("Delete", role: .destructive) {
                if let report = pendingDelete { delete(report) }
            }
        } message: {
            if let report = pendingDelete {
                Text("Are you sure you want to delete the report from \(Formatters.mediumDate.string(from: report.date))?")
            }
        }
        .ambientPush(item: $destination) { destination in
            switch destination {
            case .newReport:
                DailyReportView(isPushed: true)
            case .templates:
                TemplatePickerView(isPushed: true)
            case .edit(let reportID):
                ReportEditorView(reportID: reportID)
            }
        }
        .disabled(isDeleting)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && reports.isEmpty {
            VStack(spacing: 8) {
                ProgressView()
                Text("Loading reports…").font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            list
        }
    }

    private var list: some View {
        List {
            todayLead.modifier(ReportListRow())

            if !errorMessage.isEmpty {
                failureBanner(errorMessage).modifier(ReportListRow())
            }
            if let deleteFailure {
                failureBanner(deleteFailure).modifier(ReportListRow())
            }

            searchField.modifier(ReportListRow())
            filterRow.modifier(ReportListRow())

            if !errorMessage.isEmpty && reports.isEmpty {
                // The banner above is the whole story: a query that failed must
                // not also be told as "you have no reports". Nothing is drawn
                // here, deliberately.
                EmptyView()
            } else if reports.isEmpty {
                // The state MyJobReportsView did not have at all: an empty list
                // and a failed query used to be the same blank screen.
                AmbientEmptyState(
                    title: "No Reports Yet",
                    message: "Reports you file will be listed here. Start with today's session.",
                    systemImage: "doc.text",
                    actionTitle: "File Today's Report",
                    actionIcon: "plus.circle.fill",
                    action: { destination = .newReport },
                    actionTint: feature)
                    .modifier(ReportListRow())
            } else if filtered.isEmpty {
                // A search or a window that matches nothing is a DIFFERENT
                // state, and the orphaned screen got this wrong too — it
                // branched on the raw fetch rather than the filtered set, so a
                // non-matching search rendered a blank scroll view.
                AmbientEmptyState(
                    title: "No matching reports",
                    message: search.isEmpty
                        ? "Nothing was filed in this window."
                        : "Nothing matches “\(search)” in this window.",
                    systemImage: "magnifyingglass")
                    .modifier(ReportListRow())
            } else if groupByTemplate {
                // Headings are ORDINARY ROWS, not `Section` headers. A plain
                // List's header sticks and draws its own opaque background,
                // which would put a grey bar across the ambient wash — and the
                // approved design has the title sitting on the wash. The rows
                // stay real List rows either way, which is what keeps
                // `.swipeActions` alive.
                ForEach(groups, id: \.0) { name, rows in
                    AmbientSectionTitle(name, trailing: "\(rows.count)")
                        .padding(.top, 6)
                        .modifier(ReportListRow())
                    ForEach(rows) { report in row(report) }
                }
            } else {
                AmbientSectionTitle("Filed reports", trailing: "\(filtered.count)")
                    .padding(.top, 6)
                    .modifier(ReportListRow())
                ForEach(filtered) { report in row(report) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
    }

    private func row(_ report: DailyJobReport) -> some View {
        ReportRow(report: report)
            .contentShape(Rectangle())
            .onTapGesture { destination = .edit(report.id) }
            .modifier(ReportListRow())
            // Swipe-to-delete does NOT delete — it raises a confirmation, which
            // is the shipped behaviour and is kept exactly.
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    pendingDelete = report
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    // MARK: - Today

    /// Not "file a report" — file THIS report.
    private var todayLead: some View {
        let outstanding = schedule.outstandingSessions
        let filed = schedule.reportedSessionIDs.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "doc.badge.clock")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(feature)
                Text("Today").font(.headline)
                Spacer(minLength: 0)
                Text(Formatters.monthDay.string(from: Date()))
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }

            if schedule.isLoadingSessions {
                Text("Checking your schedule…").font(.subheadline).foregroundStyle(.secondary)
            } else if schedule.reportedLookupFailed {
                // NOT "0 reports filed". A failed lookup that renders as a zero
                // is the shape that hid a dead feature for a year here, and this
                // one would actively steer a photographer into filing a report
                // they have already filed.
                Text("\(schedule.sessions.count) session\(schedule.sessions.count == 1 ? "" : "s") scheduled · couldn't check what you have filed")
                    .font(.subheadline).foregroundStyle(.orange)
            } else {
                Text("\(schedule.sessions.count) session\(schedule.sessions.count == 1 ? "" : "s") scheduled · \(filed) report\(filed == 1 ? "" : "s") filed")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            Button { destination = .newReport } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(outstanding.first?.reportDisplayLabel ?? "File a daily job report")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(subtitleForLead(outstanding: outstanding))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                // ambient-allow: a filled primary action is a control, not a card.
                .background(Capsule().fill(feature))
            }
            .buttonStyle(.plain)

            Button { destination = .templates } label: {
                Label("Use a template instead", systemImage: "doc.text.below.ecg")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(feature)
            }
            .buttonStyle(.plain)
        }
        .ambientCard(density: .hero, state: .highlighted, glow: feature, fillWidth: true)
    }

    private func subtitleForLead(outstanding: [Session]) -> String {
        if schedule.reportedLookupFailed { return "Check the list below before filing again" }
        if !outstanding.isEmpty { return "Not yet reported" }
        return schedule.sessions.isEmpty
            ? "Nothing scheduled — an off-schedule day still files"
            : "Everything scheduled is already reported"
    }

    // MARK: - Controls

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            TextField("Search reports", text: $search)
                .font(.subheadline)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.footnote).foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .ambientCard(density: .compact, fillWidth: true)
    }

    private var filterRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ReportWindow.allCases) { option in
                        Button {
                            withAnimation(AmbientMotion.snappy) { window = option }
                            AmbientHaptics.selection()
                        } label: {
                            Text(option.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(window == option ? .white : .primary)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                // ambient-allow: a selection chip is a control.
                                .background(Capsule().fill(window == option
                                                           ? AnyShapeStyle(feature)
                                                           : AnyShapeStyle(.ultraThinMaterial)))
                                .overlay(Capsule().strokeBorder(Color.primary.opacity(window == option ? 0 : 0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Toggle(isOn: $groupByTemplate) {
                Text("Group by template").font(.caption)
            }
            .toggleStyle(.switch)
            .tint(feature)
        }
    }

    private func failureBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Something went wrong").font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                errorMessage = ""
                deleteFailure = nil
                Task { await reload() }
            } label: {
                Text("Retry").font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(feature)
        }
        .ambientCard(density: .compact,
                     border: .hairline(Color.orange.opacity(0.45)),
                     fillWidth: true)
    }

    // MARK: - Data

    private func load() {
        schedule.start(for: Date()) { }
        // Reload on EVERY appearance, which includes popping back from the
        // editor — otherwise a report you just edited or deleted keeps showing
        // its old values. `content` only draws the full-screen loading state
        // when there is nothing to show yet, so a refresh over an existing list
        // is invisible rather than a blank flash.
        Task { await reload() }
    }

    private func reload() async {
        guard let userID = UserManager.shared.getCurrentUserIDUnified() else {
            errorMessage = "Unable to load reports: not signed in"
            return
        }
        guard !storedUserOrganizationID.isEmpty else {
            errorMessage = "Unable to load reports: no organization found"
            return
        }

        reloadRun += 1
        let run = reloadRun
        isLoading = true
        defer { if run == reloadRun { isLoading = false } }
        do {
            // Newest first, from the query's own ordering.
            let fetched = try await DailyJobReportService.shared.getReports(
                userId: userID, organizationID: storedUserOrganizationID)
            guard run == reloadRun else { return }
            reports = fetched
            errorMessage = ""
        } catch {
            guard run == reloadRun else { return }
            errorMessage = "Failed to load reports: \(error.localizedDescription)"
        }

        await schedule.refreshReported(photographerFirstName: storedUserFirstName,
                                       organizationID: storedUserOrganizationID)
    }

    private func delete(_ report: DailyJobReport) {
        pendingDelete = nil
        isDeleting = true
        Task {
            do {
                try await DailyJobReportService.shared.deleteReport(reportId: report.id)
                await MainActor.run {
                    reports.removeAll { $0.id == report.id }
                    deleteFailure = nil
                    isDeleting = false
                }
            } catch {
                await MainActor.run {
                    // A failed delete used to be invisible — the row simply
                    // stayed and nothing said why.
                    deleteFailure = "That report could not be deleted: \(error.localizedDescription)"
                    isDeleting = false
                }
            }
        }
    }
}

// MARK: - Row

/// The live row was: date, school (drawn even when the column is null),
/// "Mileage: N", and a photo pill. It could not tell a template report from a
/// standard one — that distinction existed only in the orphaned list.
///
/// File-private: the lab's mockup carries a row of the same name until it is
/// deleted at this phase's close, and two internal types cannot share it.
private struct ReportRow: View {
    let report: DailyJobReport
    private var density: AmbientDensity { .compact }

    private var school: String { report.school_or_destination ?? "" }
    private var isTemplate: Bool { (report.report_type ?? "standard") == "template" }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Text(Formatters.dayNumber.string(from: report.date))
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text(Formatters.weekdayShort.string(from: report.date).uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                // The sparse case is real: a report can carry no school at all,
                // and the row still has to read.
                Text(school.isEmpty ? "No school recorded" : school)
                    .font(density.titleFont)
                    .foregroundStyle(school.isEmpty ? .secondary : .primary)
                    .lineLimit(1)

                if let session = report.session_name {
                    Text(session).font(density.subtitleFont).foregroundStyle(.secondary).lineLimit(1)
                } else {
                    // Off-schedule is a real and common case, and saying so is
                    // more useful than leaving the line blank.
                    Text("Off-schedule").font(density.subtitleFont).foregroundStyle(.tertiary)
                }

                HStack(spacing: 6) {
                    if report.total_mileage > 0 {
                        metric(String(format: "%.1f mi", report.total_mileage), "car.fill")
                    }
                    if !report.photoURLs.isEmpty {
                        metric("\(report.photoURLs.count)", "photo.fill")
                    }
                    if report.vehicle_type == "company" {
                        AmbientBadge(text: "Company", tint: .teal)
                    }
                }
                .padding(.top, 1)
            }

            Spacer(minLength: 0)

            if isTemplate {
                VStack(alignment: .trailing, spacing: 3) {
                    AmbientBadge(text: "Template", systemImage: "doc.text.below.ecg",
                                 tint: FeatureTheme.color(for: "customDailyReports"))
                    if !report.smartFieldsUsed.isEmpty {
                        Text("\(report.smartFieldsUsed.count) auto")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .ambientCard(density: density, fillWidth: true)
    }

    private func metric(_ text: String, _ icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold))
            Text(text).font(.system(size: 11, weight: .medium, design: .rounded))
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - List chrome

/// Strips a List row back to nothing so the ambient wash shows through and the
/// cards supply all the spacing — while keeping the row a real List row, which
/// is what keeps `.swipeActions` alive. Same modifier AMB.6 wrote for Chat.
private struct ReportListRow: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: AmbientDensity.compact.stackSpacing / 2,
                                      leading: 16,
                                      bottom: AmbientDensity.compact.stackSpacing / 2,
                                      trailing: 16))
    }
}
