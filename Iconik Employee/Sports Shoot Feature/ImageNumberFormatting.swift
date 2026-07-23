//
//  ImageNumberFormatting.swift
//  Iconik Employee
//
//  Single source of truth for parsing and formatting image-number strings
//  used across all sports views. Format: semicolon-separated with abbreviated
//  end ranges, e.g. "1456-58;1462" means [1456, 1457, 1458, 1462].
//
//  Replaces three byte-identical copies of these helpers that previously
//  lived in FPSportsRosterView_iPad.swift, CapturaSportsView.swift, and
//  PoserStationView.swift. Keep ALL callers using these — divergent copies
//  caused the "ImageNumbersMerger" complexity.
//

import Foundation

/// Parse "1456-58;1462" into [1456, 1457, 1458, 1462].
/// Handles full ranges (1456-1458), abbreviated ranges (1456-58), and
/// single numbers. Whitespace tolerant. Invalid parts silently dropped.
public func parseImageNumberRanges(_ field: String) -> [Int] {
    var numbers: [Int] = []
    let parts = field.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
    for part in parts {
        if part.contains("-") {
            let rangeParts = part.split(separator: "-").map { String($0).trimmingCharacters(in: .whitespaces) }
            if rangeParts.count == 2, let start = Int(rangeParts[0]) {
                let endStr = rangeParts[1]
                if let end = Int(endStr) {
                    if end > start {
                        // Full range: 1456-1458
                        for n in start...end { numbers.append(n) }
                    } else {
                        // Abbreviated: 1456-58 → 1456-1458
                        let startStr = "\(start)"
                        let prefix = String(startStr.prefix(startStr.count - endStr.count))
                        if let fullEnd = Int(prefix + endStr), fullEnd > start {
                            for n in start...fullEnd { numbers.append(n) }
                        } else {
                            numbers.append(start)
                        }
                    }
                }
            }
        } else if let n = Int(part) {
            numbers.append(n)
        }
    }
    return numbers
}

/// Format [1456, 1457, 1458, 1462] into "1456-58;1462".
/// Sorts ascending, collapses consecutive runs into ranges, abbreviates
/// the end of each range when at least two leading digits are shared
/// AND the abbreviated suffix is at least 2 digits.
public func formatImageNumberRanges(_ numbers: [Int]) -> String {
    guard !numbers.isEmpty else { return "" }
    let sorted = numbers.sorted()
    var ranges: [(Int, Int)] = []
    var start = sorted[0], end = sorted[0]
    for i in 1..<sorted.count {
        if sorted[i] == end + 1 {
            end = sorted[i]
        } else {
            ranges.append((start, end))
            start = sorted[i]
            end = sorted[i]
        }
    }
    ranges.append((start, end))

    return ranges.map { (s, e) in
        if s == e { return "\(s)" }
        let startStr = "\(s)"
        let endStr = "\(e)"
        let shared = zip(startStr, endStr).prefix(while: { $0 == $1 }).count
        let suffix = String(endStr.dropFirst(shared))
        if suffix.count >= 2 && shared > 0 {
            return "\(s)-\(suffix)"
        }
        if suffix.count == 1 && shared > 0 && endStr.count >= 2 {
            return "\(s)-\(String(endStr.suffix(2)))"
        }
        return "\(s)-\(e)"
    }.joined(separator: ";")
}
