import Foundation

/// Lightweight, always-on diagnostics for the Captura roster image-number
/// save path. Added to chase an intermittent "image numbers not saving"
/// bug: we log every save/upload/watch event with the actual image_numbers
/// value so that, when a number goes missing on a shoot, the log shows
/// exactly where it was lost (typed value never reached the save vs. a
/// later sync overwrote it).
///
/// Writes to Documents/roster_debug.log (retrievable + shareable) and
/// mirrors to the console. Size-capped so it never grows unbounded. This
/// is additive and lives in its own file — it touches none of the
/// protected Captura roster files.
final class RosterEditDiagnostics {
    static let shared = RosterEditDiagnostics()

    /// Flip to false to silence all roster diagnostics.
    static let enabled = true

    private let queue = DispatchQueue(label: "com.iconikschools.roster-diagnostics")
    private let fileURL: URL
    private let maxBytes = 512 * 1024   // 0.5 MB; trims oldest half when exceeded

    private lazy var stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private init() {
        let docs = (try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        fileURL = docs.appendingPathComponent("roster_debug.log")
    }

    /// The log file, for a share sheet / export button.
    var logFileURL: URL { fileURL }

    /// Record one event. `numbers` is quoted so empty values are visible
    /// as '' and trailing spaces are obvious.
    func log(_ event: String, entryId: String? = nil, numbers: String? = nil, extra: String? = nil) {
        guard Self.enabled else { return }
        // Build the line off the caller's thread work but capture time now.
        let time = stamp.string(from: Date())
        var parts = ["[\(time)] \(event)"]
        if let entryId { parts.append("id=\(entryId.suffix(6))") }   // last 6 chars is enough to correlate
        if let numbers { parts.append("numbers='\(numbers)'") }
        if let extra { parts.append(extra) }
        let line = parts.joined(separator: " ")

        print("🩺 \(line)")

        queue.async { [fileURL, maxBytes] in
            guard let data = (line + "\n").data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                try? data.write(to: fileURL)
            }
            // Trim if the file has grown past the cap.
            if let size = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int,
               size > maxBytes,
               let contents = try? Data(contentsOf: fileURL) {
                let trimmed = contents.suffix(maxBytes / 2)
                try? trimmed.write(to: fileURL)
            }
        }
    }

    /// Wipe the log (e.g. before a fresh reproduction run).
    func reset() {
        queue.async { [fileURL] in
            try? "".data(using: .utf8)?.write(to: fileURL)
        }
    }
}
