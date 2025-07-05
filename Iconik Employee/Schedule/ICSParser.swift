import Foundation

/// Represents an ICS event with common fields (UID, SUMMARY, DTSTART, DTEND, DESCRIPTION, LOCATION, URL).
/// Also splits summary on " - " to get employeeName, position, schoolName.
struct ICSEvent: Identifiable, Equatable {
    let id: String
    let summary: String
    let startDate: Date?
    let endDate: Date?
    let description: String?
    let location: String?
    let url: String?
    
    var employeeName: String {
        let parts = summary.components(separatedBy: " - ")
        return parts.first?.trimmingCharacters(in: .whitespaces) ?? ""
    }
    var position: String {
        let parts = summary.components(separatedBy: " - ")
        return parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
    }
    var schoolName: String {
        let parts = summary.components(separatedBy: " - ")
        return parts.count > 2 ? parts[2].trimmingCharacters(in: .whitespaces) : ""
    }
    
    static func == (lhs: ICSEvent, rhs: ICSEvent) -> Bool {
        lhs.id == rhs.id &&
        lhs.summary == rhs.summary &&
        lhs.startDate == rhs.startDate &&
        lhs.endDate == rhs.endDate &&
        lhs.description == rhs.description &&
        lhs.location == rhs.location &&
        lhs.url == rhs.url
    }
}

/// A custom ICS parser that:
///   - Unfolds lines beginning with a space or tab.
///   - Treats everything from DESCRIPTION: until LAST-MODIFIED as part of the DESCRIPTION field (joining with spaces).
///   - Unescapes literal "\n" to newlines and "\," to commas in DESCRIPTION.
///   - Also cleans the LOCATION field by removing "\" before commas.
class ICSParser {
    
    static func parseICS(from content: String) -> [ICSEvent] {
        print("=== ICS Content (first 500 chars) ===")
        print(content.prefix(500))
        print("=== END ICS Content ===")
        
        // 1) Unfold lines that start with space or tab.
        let rawLines = content.components(separatedBy: .newlines)
        let unfoldedLines = unfoldICSLines(rawLines)
        
        var events: [ICSEvent] = []
        var currentEvent: [String: String] = [:]
        var insideEvent = false
        
        // Flag to track if we're reading the DESCRIPTION block.
        var inDescriptionBlock = false
        var descriptionAccum = ""
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        
        for line in unfoldedLines {
            if line == "BEGIN:VEVENT" {
                insideEvent = true
                currentEvent = [:]
                inDescriptionBlock = false
                descriptionAccum = ""
                continue
            }
            if line == "END:VEVENT" {
                // If we are in a description block, store the accumulated text.
                if inDescriptionBlock {
                    currentEvent["DESCRIPTION"] = descriptionAccum
                    inDescriptionBlock = false
                }
                insideEvent = false
                
                // Build event from currentEvent.
                let id = currentEvent["UID"] ?? UUID().uuidString
                let summary = currentEvent["SUMMARY"] ?? "No Title"
                
                var start: Date? = nil
                if let dtstart = currentEvent["DTSTART"] {
                    start = dateFormatter.date(from: dtstart)
                }
                var end: Date? = nil
                if let dtend = currentEvent["DTEND"] {
                    end = dateFormatter.date(from: dtend)
                }
                
                // Unescape DESCRIPTION: replace literal "\n" with newline and "\," with comma.
                let rawDesc = currentEvent["DESCRIPTION"] ?? ""
                let desc = rawDesc
                    .replacingOccurrences(of: "\\n", with: "\n")
                    .replacingOccurrences(of: "\\,", with: ",")
                
                // Clean LOCATION: remove "\" before commas.
                let rawLoc = currentEvent["LOCATION"]
                let loc = rawLoc?.replacingOccurrences(of: "\\,", with: ",")
                
                let url = currentEvent["URL"]
                
                let event = ICSEvent(
                    id: id,
                    summary: summary,
                    startDate: start,
                    endDate: end,
                    description: desc,
                    location: loc,
                    url: url
                )
                events.append(event)
                continue
            }
            
            // Only process lines inside an event.
            guard insideEvent else { continue }
            
            // If we're in the description block, check if we hit LAST-MODIFIED.
            if inDescriptionBlock {
                if line.hasPrefix("LAST-MODIFIED") {
                    // End of description block.
                    currentEvent["DESCRIPTION"] = descriptionAccum
                    inDescriptionBlock = false
                    // Process LAST-MODIFIED normally.
                    if let range = line.range(of: ":") {
                        let key = String(line[..<range.lowerBound])
                        let value = String(line[range.upperBound...])
                        currentEvent[key] = value
                    }
                    continue
                } else {
                    // Append line to descriptionAccum.
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if descriptionAccum.isEmpty {
                        descriptionAccum = trimmed
                    } else {
                        // Append with a space if needed.
                        if let lastChar = descriptionAccum.last,
                           !CharacterSet.whitespaces.contains(lastChar.unicodeScalars.first!) {
                            descriptionAccum += " " + trimmed
                        } else {
                            descriptionAccum += trimmed
                        }
                    }
                    continue
                }
            }
            
            // Check if this line starts the DESCRIPTION field.
            if line.hasPrefix("DESCRIPTION:") {
                inDescriptionBlock = true
                if let range = line.range(of: ":") {
                    let afterColon = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    descriptionAccum = afterColon
                }
                continue
            }
            
            // Normal processing: lines with a colon become key-value pairs.
            if let range = line.range(of: ":") {
                let key = String(line[..<range.lowerBound])
                let value = String(line[range.upperBound...])
                if let existing = currentEvent[key] {
                    currentEvent[key] = existing + "\n" + value
                } else {
                    currentEvent[key] = value
                }
            } else {
                // If not in DESCRIPTION block and no colon, skip.
                print("Skipping line: \(line)")
            }
        }
        
        // Debug prints.
        print("=== Parsed ICS Events ===")
        for e in events {
            print("ID: \(e.id)")
            print("Summary: \(e.summary)")
            print("Start: \(String(describing: e.startDate))")
            print("End: \(String(describing: e.endDate))")
            print("Description: \(e.description ?? "nil")")
            print("Location: \(e.location ?? "nil")")
            print("URL: \(e.url ?? "nil")")
            print("------")
        }
        print("Total events parsed: \(events.count)")
        
        return events
    }
    
    /// Unfolds ICS lines: if a line starts with a space or tab, it's a continuation of the previous line.
    private static func unfoldICSLines(_ lines: [String]) -> [String] {
        var unfolded: [String] = []
        for line in lines {
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                if let last = unfolded.popLast() {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    unfolded.append(last + trimmed)
                } else {
                    unfolded.append(line.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            } else {
                unfolded.append(line)
            }
        }
        return unfolded
    }
}

