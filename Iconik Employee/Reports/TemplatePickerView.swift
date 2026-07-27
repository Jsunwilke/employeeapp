//  TemplatePickerView.swift
//  Iconik Employee — "Custom Daily Reports", converted in AMB.7
//
//  Replaces Misc Features/CustomDailyReportsView.swift, deleted in the same
//  commit.
//
//  A ROW, NOT A 160pt CARD IN A TWO-COLUMN GRID
//      The live screen used a fixed-height two-column grid on iPhone AND iPad
//      alike, which forced every title to two lines with a scale factor and left
//      most of each card empty. A template is a list you pick one item from, and
//      a row reads faster and survives a long name.
//
//  THE STATE THAT COULD NEVER BE REACHED, AND NOW CAN
//      `TemplateService.fetchTemplates` THROWS when an organisation has no
//      templates, and the live screen checked its error state before its empty
//      state — so a new organisation saw an orange warning triangle instead of
//      the onboarding copy someone wrote for exactly that moment (finding R35).
//      The same ordering meant a transient network failure HID templates the
//      user already had.
//
//      Both are handled here without touching the service: "no templates" is
//      recognised as its own outcome rather than as a failure, and a real
//      failure with templates already on screen becomes a banner ABOVE the list
//      instead of replacing it.
//
//  A BLANK CATEGORY HEADER IS NOT DRAWN
//      Six `ReportTemplate` properties sit outside `CodingKeys` and are
//      therefore never decoded (finding R13), so `shootType` is always empty and
//      every template falls into ONE category whose header is a blank string
//      with a count pill floating beside it. Recorded, not repaired — but a
//      header with no text in it is not rendered.

import SwiftUI

struct TemplatePickerView: View {

    /// True when PUSHED from the reports list rather than opened as its own
    /// feature. See `PushedTabBarClearance` — the shell's inset does not travel
    /// into what a container pushes, and applying both reserves twice the room.
    var isPushed = false

    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""

    @State private var templates: [ReportTemplate] = []
    @State private var search = ""
    @State private var isLoading = false
    /// Which template fetch is current — this reloads on every appearance.
    @State private var loadRun = 0
    /// A real failure. Separate from "this organisation has no templates", which
    /// is not a failure and must not be drawn as one.
    @State private var failure = ""
    @State private var opening: ReportTemplate?

    private var feature: Color { FeatureTheme.color(for: "customDailyReports") }

    private var filtered: [ReportTemplate] {
        guard !search.isEmpty else { return templates }
        return templates.filter { template in
            template.name.localizedCaseInsensitiveContains(search)
                || (template.description?.localizedCaseInsensitiveContains(search) ?? false)
                || template.shootType.localizedCaseInsensitiveContains(search)
        }
    }

    /// Categories in ascending alphabetical order. Defaults lead inside a group,
    /// as they did before.
    private var categories: [(String, [ReportTemplate])] {
        Dictionary(grouping: filtered) { $0.shootType.capitalized }
            .sorted { $0.key < $1.key }
            // `{ $0.isDefault && !$1.isDefault }` is NOT a strict weak ordering
            // — it is false in both directions for two equal elements, which
            // leaves `sort` free to do anything. Carried in verbatim from the
            // screen this replaces and fixed here rather than inherited again.
            .map { ($0.key, $0.value.sorted { ($0.isDefault ? 0 : 1) < ($1.isDefault ? 0 : 1) }) }
    }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: feature, intensity: 0.75)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !failure.isEmpty { failureBanner }
                    searchField
                    summaryRow
                    content
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            // AMB.8: NO .ambientNoBounceWhenShort() with .refreshable. It is
            // scrollBounceBehavior(.basedOnSize), which removes the very bounce the
            // pull gesture needs, so refresh was dead whenever the content fit.
            // This file's own comment blamed ScrollView-vs-List; the real cause was
            // two lines above it.
        }
        .modifier(PushedTabBarClearance(active: isPushed))
        .navigationTitle("Custom Daily Reports")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await loadTemplates() }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                // A ScrollView does not wire up `.refreshable` the way a List
                // does, so pull-to-refresh here is not something to rely on.
                // This button always works.
                Button { Task { await loadTemplates() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .onAppear {
            // Every appearance, so a template edited in the web app is picked up
            // when the photographer comes back to this screen. The spinner only
            // replaces the content when there is nothing to show yet, so a
            // refresh over an existing list is invisible.
            Task { await loadTemplates() }
        }
        .ambientPush(item: $opening) { template in
            TemplateReportView(template: template)
        }
    }

    // MARK: - States, in the order they can actually happen

    @ViewBuilder
    private var content: some View {
        if isLoading && templates.isEmpty {
            VStack(spacing: 8) {
                ProgressView()
                Text("Loading templates…").font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 44)
        } else if templates.isEmpty {
            AmbientEmptyState(
                title: "No Templates Available",
                message: "Contact your administrator to set up daily report templates for your organization.",
                systemImage: "doc.text")
        } else if filtered.isEmpty {
            AmbientEmptyState(
                title: "No matching templates",
                message: "Nothing matches “\(search)”.",
                systemImage: "magnifyingglass")
        } else {
            list
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(categories, id: \.0) { name, group in
                VStack(alignment: .leading, spacing: 8) {
                    // Every template's shoot type is empty today, so this header
                    // would be a gap with a count pill beside it. Nothing is
                    // better than nothing-with-a-badge.
                    if !name.trimmingCharacters(in: .whitespaces).isEmpty {
                        AmbientSectionTitle(name, trailing: "\(group.count)")
                    }
                    VStack(spacing: AmbientDensity.compact.stackSpacing) {
                        ForEach(group) { template in
                            Button { opening = template } label: { row(template) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            TextField("Search templates", text: $search)
                .font(.subheadline).textFieldStyle(.plain)
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

    /// "N templates available · N categories", both counting the FILTERED set.
    /// A KEEP from the inventory that the first cut of this screen dropped.
    @ViewBuilder
    private var summaryRow: some View {
        if !templates.isEmpty {
            HStack {
                Text("\(filtered.count) template\(filtered.count == 1 ? "" : "s") available")
                Spacer()
                let named = categories.filter { !$0.0.trimmingCharacters(in: .whitespaces).isEmpty }.count
                if named > 0 {
                    Text("\(named) categor\(named == 1 ? "y" : "ies")")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func row(_ template: ReportTemplate) -> some View {
        let smartFields = template.fields.filter { $0.smartConfig != nil }.count
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "doc.text.below.ecg")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(feature)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(template.name).font(AmbientDensity.compact.titleFont)
                    if template.isDefault { AmbientBadge(text: "Default", tint: .green) }
                }
                if let detail = template.description, !detail.isEmpty {
                    Text(detail)
                        .font(AmbientDensity.compact.subtitleFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text("No description available")
                        .font(AmbientDensity.compact.subtitleFont)
                        .foregroundStyle(.tertiary)
                        .italic()
                }
                HStack(spacing: 8) {
                    Text("\(template.fields.count) field\(template.fields.count == 1 ? "" : "s")")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                    if smartFields > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "sparkles").font(.system(size: 9, weight: .semibold))
                            Text("\(smartFields) auto")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                        }
                        .foregroundStyle(feature)
                    }
                    Spacer(minLength: 0)
                    Text("v\(template.version)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
        }
        .ambientCard(density: .compact,
                     border: template.isDefault ? .hairline(Color.green.opacity(0.4)) : .none,
                     fillWidth: true)
    }

    private var failureBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Unable to Load Templates").font(.subheadline.weight(.semibold))
                Text(failure)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                Task { await loadTemplates() }
            } label: {
                Text("Try Again").font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(feature)
        }
        .ambientCard(density: .compact,
                     border: .hairline(Color.orange.opacity(0.45)),
                     fillWidth: true)
    }

    // MARK: - Data

    private func loadTemplates() async {
        guard !storedUserOrganizationID.isEmpty else {
            failure = "No organization found."
            return
        }
        // No `guard !isLoading` — that dropped the NEWER request and kept the
        // older one's answer, and it also made the generation guard below
        // unreachable. Both may run; the newest one wins.
        isLoading = true
        loadRun += 1
        let run = loadRun
        defer { if run == loadRun { isLoading = false } }
        do {
            let fetched = try await TemplateService.shared.fetchTemplates(for: storedUserOrganizationID)
            guard run == loadRun else { return }
            templates = fetched
            failure = ""
        } catch TemplateError.noTemplatesFound {
            // NOT a failure. This is the empty state, and it is the first thing
            // a new organisation sees.
            guard run == loadRun else { return }
            templates = []
            failure = ""
        } catch {
            guard run == loadRun else { return }
            // A real failure does NOT clear what is already on screen.
            failure = error.localizedDescription
        }
    }
}
