// Phase J — iPad metrics substrate (FROM_SCRATCH_ARCHITECTURE.md §10 + §13 J).
//
// Mirror of the Surface metrics module (src/utils/metrics.js + src-tauri/
// src/metrics.rs): four metric kinds (counter / gauge / histogram /
// timestamp), per-day jsonl file rotation under Documents/metrics/
// metrics-{YYYY-MM-DD}.jsonl, in-memory ring buffer for the SettingsView
// dashboard, and a shareable email export.
//
// This module is non-blocking: emit calls return immediately. The hot
// path (sendSubjectCommand, command_ack receive, requestThumbnailOverHTTP)
// is unaffected. File writes happen async on a serial dispatch queue.
//
// §17.10 retention list: this file is NEW. It does not touch any of the
// retained Captura roster files (SportsShootListView, SportsShootDetailView,
// AddRosterEntryView, etc.). Phase J emission points are added inside
// FocalPointSyncClient.swift at existing sites that already mutate state
// (sendSubjectCommand, command_ack case, handleDisconnect, request*OverHTTP)
// — adding metric emissions is permitted per the kickoff brief because
// routing/lifecycle logic is unchanged.

import Foundation
import Combine

public enum MetricKind: String {
    case counter
    case gauge
    case histogram
    case timestamp
}

public struct MetricEntry: Codable, Identifiable, Equatable {
    public let id: UUID
    public let ts: String
    public let kind: String
    public let layer: String
    public let module: String
    public let name: String
    public let value: Double
    public let labels: [String: String]?

    public init(kind: MetricKind, module: String, name: String, value: Double, labels: [String: String]? = nil) {
        self.id = UUID()
        self.ts = Self.iso8601Now()
        self.kind = kind.rawValue
        self.layer = "ipad"
        self.module = module
        self.name = name
        self.value = value
        self.labels = (labels?.isEmpty ?? true) ? nil : labels
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func iso8601Now() -> String {
        return isoFormatter.string(from: Date())
    }
}

public final class FocalPointMetrics: ObservableObject {
    public static let shared = FocalPointMetrics()

    /// Most recent emissions (capped) for the SettingsView dashboard. The
    /// dashboard observes this @Published directly; updates render live.
    @Published public private(set) var recent: [MetricEntry] = []

    private let ringBufferLimit = 5000
    private let writeQueue = DispatchQueue(label: "com.focalpoint.metrics.writer", qos: .utility)
    private let metricsDir: URL
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.metricsDir = docs.appendingPathComponent("metrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: metricsDir, withIntermediateDirectories: true)
    }

    // MARK: - Emit API

    public func counter(_ name: String, value: Double = 1, module: String = "ipad", labels: [String: String]? = nil) {
        emit(MetricEntry(kind: .counter, module: module, name: name, value: value, labels: labels))
    }

    public func gauge(_ name: String, value: Double, module: String = "ipad", labels: [String: String]? = nil) {
        emit(MetricEntry(kind: .gauge, module: module, name: name, value: value, labels: labels))
    }

    public func histogram(_ name: String, value: Double, module: String = "ipad", labels: [String: String]? = nil) {
        emit(MetricEntry(kind: .histogram, module: module, name: name, value: value, labels: labels))
    }

    public func timestamp(_ name: String, value: Double, module: String = "ipad", labels: [String: String]? = nil) {
        emit(MetricEntry(kind: .timestamp, module: module, name: name, value: value, labels: labels))
    }

    /// Start a histogram timer. Returns a closure; call it to emit the
    /// histogram with elapsed_ms as the value. Optionally pass extra
    /// labels to merge into the labels dict at emit time.
    public func startTimer(_ name: String, module: String = "ipad", labels: [String: String]? = nil) -> ([String: String]?) -> Void {
        let start = Date()
        return { [weak self] extra in
            let elapsed = Date().timeIntervalSince(start) * 1000.0
            var merged = labels ?? [:]
            for (k, v) in (extra ?? [:]) { merged[k] = v }
            self?.histogram(name, value: elapsed, module: module, labels: merged.isEmpty ? nil : merged)
        }
    }

    // MARK: - Ring buffer + file write

    private func emit(_ entry: MetricEntry) {
        // Ring buffer — main-actor publish for SwiftUI. Bounded so a long
        // shoot doesn't bloat memory.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.recent.append(entry)
            if self.recent.count > self.ringBufferLimit {
                self.recent.removeFirst(self.recent.count - self.ringBufferLimit)
            }
        }

        // File write — async on the serial writer queue so emit() never
        // blocks the hot path. JSONL: one row per emission.
        writeQueue.async { [weak self] in
            self?.appendToTodayFile(entry)
        }
    }

    private func appendToTodayFile(_ entry: MetricEntry) {
        let today = dateFormatter.string(from: Date())
        let filename = "metrics-\(today).jsonl"
        let url = metricsDir.appendingPathComponent(filename)

        guard let data = try? JSONEncoder().encode(entry) else { return }
        var line = data
        line.append(0x0A)  // newline

        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: line)
            }
        } else {
            try? line.write(to: url)
        }
    }

    // MARK: - File access (for SettingsView export and dashboard)

    /// Returns all metric jsonl files in the metrics directory, newest first.
    public func listFiles() -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: metricsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return items
            .filter { $0.pathExtension == "jsonl" }
            .sorted { (a, b) in
                let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return da > db
            }
    }

    /// Returns the URL of today's metrics file (whether it exists yet or
    /// not). Used by the email-export flow.
    public func todayFileURL() -> URL {
        let today = dateFormatter.string(from: Date())
        return metricsDir.appendingPathComponent("metrics-\(today).jsonl")
    }

    /// Returns a single combined export bundle URL (today's jsonl) for
    /// share-sheet handoff. The combined-multi-day case is handled by
    /// listFiles() returning every day; SettingsView lets the operator
    /// pick. For the simple case (today only), this URL is what the
    /// email-export passes to UIActivityViewController.
    public func exportURL() -> URL {
        return todayFileURL()
    }

    // MARK: - Reducers (used by the SettingsView dashboard)

    public func summarizeCounters() -> [(name: String, labels: [String: String]?, total: Double)] {
        var buckets: [String: (name: String, labels: [String: String]?, total: Double)] = [:]
        for e in recent where e.kind == MetricKind.counter.rawValue {
            let key = e.name + "|" + (e.labels.map { String(describing: $0) } ?? "")
            var b = buckets[key] ?? (name: e.name, labels: e.labels, total: 0)
            b.total += e.value
            buckets[key] = b
        }
        return Array(buckets.values)
    }

    public func summarizeGauges() -> [(name: String, labels: [String: String]?, value: Double, ts: String)] {
        var buckets: [String: (name: String, labels: [String: String]?, value: Double, ts: String)] = [:]
        for e in recent where e.kind == MetricKind.gauge.rawValue {
            let key = e.name + "|" + (e.labels.map { String(describing: $0) } ?? "")
            buckets[key] = (name: e.name, labels: e.labels, value: e.value, ts: e.ts)
        }
        return Array(buckets.values)
    }

    public func summarizeHistograms() -> [(name: String, labels: [String: String]?, count: Int, p50: Double, p95: Double, p99: Double, min: Double, max: Double)] {
        var buckets: [String: (name: String, labels: [String: String]?, samples: [Double])] = [:]
        for e in recent where e.kind == MetricKind.histogram.rawValue {
            let key = e.name + "|" + (e.labels.map { String(describing: $0) } ?? "")
            var b = buckets[key] ?? (name: e.name, labels: e.labels, samples: [])
            b.samples.append(e.value)
            buckets[key] = b
        }
        return buckets.values.map { bucket in
            let sorted = bucket.samples.sorted()
            let count = sorted.count
            func quantile(_ p: Double) -> Double {
                guard !sorted.isEmpty else { return 0 }
                let idx = min(count - 1, Int(p * Double(count)))
                return sorted[idx]
            }
            return (
                name: bucket.name,
                labels: bucket.labels,
                count: count,
                p50: quantile(0.50),
                p95: quantile(0.95),
                p99: quantile(0.99),
                min: sorted.first ?? 0,
                max: sorted.last ?? 0
            )
        }
    }

    public func summarizeTimestamps() -> [(name: String, labels: [String: String]?, value: Double, ts: String)] {
        var buckets: [String: (name: String, labels: [String: String]?, value: Double, ts: String)] = [:]
        for e in recent where e.kind == MetricKind.timestamp.rawValue {
            let key = e.name + "|" + (e.labels.map { String(describing: $0) } ?? "")
            buckets[key] = (name: e.name, labels: e.labels, value: e.value, ts: e.ts)
        }
        return Array(buckets.values)
    }
}
