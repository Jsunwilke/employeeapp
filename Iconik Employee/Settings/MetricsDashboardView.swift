// Phase J — Metrics dashboard view (iPad SettingsView surface for §10
// observability). Subscribes to FocalPointMetrics.shared's @Published
// recent buffer and re-renders live as emissions arrive.

import SwiftUI

struct MetricsDashboardView: View {
    @ObservedObject private var metrics = FocalPointMetrics.shared
    @State private var showingShareSheet = false

    var body: some View {
        List {
            counterSection
            gaugeSection
            histogramSection
            timestampSection
            exportSection
        }
        .navigationTitle("Metrics")
        .listStyle(InsetGroupedListStyle())
    }

    private var counterSection: some View {
        Section {
            let counters = metrics.summarizeCounters()
            if counters.isEmpty {
                Text("No counter samples yet").foregroundColor(.secondary)
            } else {
                ForEach(counters.sorted { $0.name < $1.name }, id: \.name) { c in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name).font(.body)
                            if let labels = c.labels {
                                Text(labels.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " "))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Text("\(Int(c.total))").font(.body.monospacedDigit())
                    }
                    .frame(minHeight: 44)
                }
            }
        } header: {
            Text("Counters")
        } footer: {
            Text("Total emissions per (name, labels) bucket since the metrics module loaded.")
        }
    }

    private var gaugeSection: some View {
        Section {
            let gauges = metrics.summarizeGauges()
            if gauges.isEmpty {
                Text("No gauge samples yet").foregroundColor(.secondary)
            } else {
                ForEach(gauges.sorted { $0.name < $1.name }, id: \.name) { g in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(g.name).font(.body)
                            if let labels = g.labels {
                                Text(labels.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " "))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Text(formatNumber(g.value)).font(.body.monospacedDigit())
                    }
                    .frame(minHeight: 44)
                }
            }
        } header: {
            Text("Gauges")
        } footer: {
            Text("Most-recent value per bucket. Reflects the live state at the last emission.")
        }
    }

    private var histogramSection: some View {
        Section {
            let histograms = metrics.summarizeHistograms()
            if histograms.isEmpty {
                Text("No histogram samples yet").foregroundColor(.secondary)
            } else {
                ForEach(histograms.sorted { $0.name < $1.name }, id: \.name) { h in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(h.name).font(.body)
                            Spacer()
                            Text("count: \(h.count)").font(.caption.monospacedDigit()).foregroundColor(.secondary)
                        }
                        if let labels = h.labels {
                            Text(labels.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " "))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        HStack(spacing: 12) {
                            quantileLabel("p50", h.p50)
                            quantileLabel("p95", h.p95)
                            quantileLabel("p99", h.p99)
                            quantileLabel("max", h.max)
                        }
                    }
                    .frame(minHeight: 44)
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("Histograms")
        } footer: {
            Text("p50/p95/p99/max computed from in-memory samples. Samples roll over as the buffer fills.")
        }
    }

    private var timestampSection: some View {
        Section {
            let timestamps = metrics.summarizeTimestamps()
            if timestamps.isEmpty {
                Text("No timestamp samples yet").foregroundColor(.secondary)
            } else {
                ForEach(timestamps.sorted { $0.name < $1.name }, id: \.name) { t in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.name).font(.body)
                            if let labels = t.labels {
                                Text(labels.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " "))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Text(formatTimestamp(t.value)).font(.caption.monospacedDigit())
                    }
                    .frame(minHeight: 44)
                }
            }
        } header: {
            Text("Timestamps")
        }
    }

    private var exportSection: some View {
        Section {
            Button {
                showingShareSheet = true
            } label: {
                HStack {
                    Label("Export Today's Metrics", systemImage: "square.and.arrow.up")
                    Spacer()
                }
                .frame(minHeight: 44)
            }
        } header: {
            Text("Export")
        } footer: {
            Text("Shares today's metrics jsonl file. Send via email to support, AirDrop to a Mac, or save locally.")
        }
        .sheet(isPresented: $showingShareSheet) {
            MetricsShareSheet(activityItems: [metrics.exportURL()])
        }
    }

    private func quantileLabel(_ label: String, _ value: Double) -> some View {
        VStack(spacing: 0) {
            Text(label).font(.caption2).foregroundColor(.secondary)
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
        let date = Date(timeIntervalSince1970: ms / 1000.0)
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .medium
        return f.string(from: date)
    }
}

private struct MetricsShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
