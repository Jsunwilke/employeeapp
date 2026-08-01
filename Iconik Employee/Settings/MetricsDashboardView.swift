//  MetricsDashboardView.swift
//  Iconik Employee — the sync metrics dashboard, converted to Ambient in AMB.12
//
//  Originally Phase J, the iPad SettingsView surface for §10 observability.
//
//  WHAT IT MEASURES, said on the screen rather than left to be guessed. Everything
//  here is `FocalPointMetrics` — a local in-process instrument for THIS DEVICE'S
//  sync bus: commands sent, acknowledgements, disconnects and HTTP image fetches.
//  Nothing here is about jobs, mileage, schools or payroll, and a support call that
//  assumed otherwise would be reading the wrong screen.
//
//  THREE FIXES:
//
//    · THE REDUCERS ARE HOISTED (G19). All four `summarize*` calls ran INSIDE
//      `body` — four full passes over up to 5,000 entries per re-render, on a view
//      that re-renders on every emission. They run when the data changes now. (The
//      L4 lesson from AMB.1.)
//
//    · THE COUNTER CAPTION IS CORRECTED (G43). It claimed "since the metrics module
//      loaded". The ring buffer holds 5,000 samples and silently drops the oldest,
//      so on a busy day the number is since the buffer ROLLED, not since launch.
//
//    · EXPORT SAYS WHEN THERE IS NOTHING TO EXPORT (G13). `exportURL()` returned
//      today's path whether or not the file existed, so Export on a quiet day handed
//      the share sheet a URL pointing at nothing, with no message.
//
//  NOT PROMISED AND NOT BUILT: a multi-day export picker. `listFiles()` has zero
//  call sites (G14) and only today's file has ever been shareable.
//
//  KEPT: the p50/p95/p99/max labels, the `count: N` line, the sorted-by-name
//  ordering, the `key=value` label pills, the empty-section sentences, and
//  "Export Today's Metrics".

import SwiftUI

struct MetricsDashboardView: View {
    @ObservedObject private var metrics = FocalPointMetrics.shared
    @State private var showingShareSheet = false

    // The reduced views of the ring buffer, computed on CHANGE rather than per
    // body pass. Sorted here too, for the same reason.
    @State private var counters: [(name: String, labels: [String: String]?, total: Double)] = []
    @State private var gauges: [(name: String, labels: [String: String]?, value: Double, ts: String)] = []
    @State private var histograms: [(name: String, labels: [String: String]?, count: Int, p50: Double, p95: Double, p99: Double, min: Double, max: Double)] = []
    @State private var timestamps: [(name: String, labels: [String: String]?, value: Double, ts: String)] = []

    private var exportURL: URL? { metrics.exportURL() }

    var body: some View {
        ZStack {
            AmbientBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    AmbientNoteCard(
                        title: "What this measures",
                        text: "Sync activity on THIS device only — commands, acknowledgements, disconnects and image fetches. Nothing here is about jobs, mileage or payroll.",
                        accent: SettingsStyle.tint,
                        density: .compact)

                    counterSection
                    gaugeSection
                    histogramSection
                    timestampSection
                    exportSection
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .ambientNoBounceWhenShort()
        }
        .tabBarClearance()
        .navigationTitle("Metrics")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: recompute)
        .onReceive(metrics.$recent) { _ in recompute() }
    }

    // MARK: - Sections

    private var counterSection: some View {
        AmbientFormSection(title: "Counters", status: "in memory", statusTint: nil) {
            VStack(alignment: .leading, spacing: 8) {
                if counters.isEmpty {
                    Text("No counter samples yet")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(counters, id: \.name) { counter in
                        VStack(alignment: .leading, spacing: 2) {
                            AmbientStatLine(label: counter.name, value: "\(Int(counter.total))")
                            labelPills(counter.labels)
                        }
                    }
                }

                // CORRECTED: it is not "since the module loaded".
                Text("Total emissions per (name, labels) bucket over the samples still in memory. The buffer keeps the most recent 5,000 emissions and drops the oldest, so on a busy day this counts from when the buffer rolled rather than from launch.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var gaugeSection: some View {
        AmbientFormSection(title: "Gauges", status: "latest value", statusTint: nil) {
            VStack(alignment: .leading, spacing: 8) {
                if gauges.isEmpty {
                    Text("No gauge samples yet")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(gauges, id: \.name) { gauge in
                        VStack(alignment: .leading, spacing: 2) {
                            AmbientStatLine(label: gauge.name, value: formatNumber(gauge.value))
                            labelPills(gauge.labels)
                        }
                    }
                }

                Text("Most-recent value per bucket. Reflects the live state at the last emission.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var histogramSection: some View {
        AmbientFormSection(title: "Histograms", status: "p50 / p95 / p99 / max", statusTint: nil) {
            VStack(alignment: .leading, spacing: 10) {
                if histograms.isEmpty {
                    Text("No histogram samples yet")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(histograms, id: \.name) { histogram in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(histogram.name).font(.footnote).foregroundStyle(.secondary)
                                Spacer(minLength: 8)
                                Text("count: \(histogram.count)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            labelPills(histogram.labels)
                            HStack(spacing: 12) {
                                quantileLabel("p50", histogram.p50)
                                quantileLabel("p95", histogram.p95)
                                quantileLabel("p99", histogram.p99)
                                quantileLabel("max", histogram.max)
                            }
                        }
                    }
                }

                Text("p50/p95/p99/max computed from in-memory samples. Samples roll over as the buffer fills.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var timestampSection: some View {
        AmbientFormSection(title: "Timestamps", status: "", statusTint: nil) {
            VStack(alignment: .leading, spacing: 8) {
                if timestamps.isEmpty {
                    Text("No timestamp samples yet")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(timestamps, id: \.name) { stamp in
                        VStack(alignment: .leading, spacing: 2) {
                            AmbientStatLine(label: stamp.name, value: formatTimestamp(stamp.value))
                            labelPills(stamp.labels)
                        }
                    }
                }
            }
        }
    }

    private var exportSection: some View {
        AmbientFormSection(title: "Export",
                           status: exportURL == nil ? "nothing today" : "today",
                           statusTint: exportURL == nil ? nil : .green) {
            VStack(alignment: .leading, spacing: 8) {
                AmbientActionButton(title: "Export Today's Metrics",
                                    systemImage: "square.and.arrow.up",
                                    role: .primary,
                                    tint: SettingsStyle.tint,
                                    isEnabled: exportURL != nil) {
                    showingShareSheet = true
                }

                if exportURL == nil {
                    // G13 — the share sheet used to be handed a path to a file that
                    // did not exist, and said nothing at all.
                    Text("Nothing to export yet — this device has recorded no sync activity today.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Shares today's metrics jsonl file. Send via email to support, AirDrop to a Mac, or save locally.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let exportURL {
                ActivityShareSheet(items: [exportURL])
            }
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private func labelPills(_ labels: [String: String]?) -> some View {
        if let labels, !labels.isEmpty {
            Text(labels.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " "))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func quantileLabel(_ label: String, _ value: Double) -> some View {
        VStack(spacing: 0) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(formatNumber(value)).font(.caption.monospacedDigit())
        }
    }

    private func formatNumber(_ v: Double) -> String {
        if v.truncatingRemainder(dividingBy: 1) == 0 && abs(v) < 1e9 {
            return "\(Int(v))"
        }
        return String(format: "%.1f", v)
    }

    private func formatTimestamp(_ ms: Double) -> String {
        Self.timeOfDay.string(from: Date(timeIntervalSince1970: ms / 1000.0))
    }

    /// Time of day WITH SECONDS — this is a diagnostic screen and the second is the
    /// point. `Formatters` has no medium-time formatter and this is the only caller,
    /// so it stays here rather than widening the shared cache; it is allocated once
    /// rather than once per row, which is what the old code did.
    private static let timeOfDay: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .medium
        return f
    }()

    // MARK: - Data

    /// Runs on appearance and on each emission — NOT once per section per body pass,
    /// which is what it used to do (G19).
    private func recompute() {
        counters = metrics.summarizeCounters().sorted { $0.name < $1.name }
        gauges = metrics.summarizeGauges().sorted { $0.name < $1.name }
        histograms = metrics.summarizeHistograms().sorted { $0.name < $1.name }
        timestamps = metrics.summarizeTimestamps().sorted { $0.name < $1.name }
    }
}


