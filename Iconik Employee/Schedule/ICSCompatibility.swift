import Foundation

/// Compatibility layer: ICSEvent backed by Session data
/// This maintains backward compatibility for existing code while using Supabase sessions
struct ICSEvent: Identifiable, Equatable {
    let id: String
    let summary: String
    let startDate: Date?
    let endDate: Date?
    let description: String?
    let location: String?
    let url: String?
    
    // Computed properties that parse the summary
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
    
    // Create ICSEvent from Session for a specific photographer
    init(from session: Session, photographerID: String) {
        // Get photographer-specific info
        let photographerInfo = session.getPhotographerInfo(for: photographerID)
        let photographerName = photographerInfo?.name ?? "Unknown"
        let photographerNotes = photographerInfo?.notes ?? ""
        
        // Create unique ID for this photographer's event
        self.id = "\(session.id)-\(photographerID)"
        self.summary = "\(photographerName) - \(session.sessionType.first ?? "Photographer") - \(session.schoolName)"
        self.startDate = session.startDate
        self.endDate = session.endDate
        self.description = photographerNotes.isEmpty ? session.description : photographerNotes
        self.location = session.location
        self.url = nil // Sessions don't have URLs
    }
    
    // Create ICSEvent from Session (legacy - uses first photographer)
    init(from session: Session) {
        self.id = session.id
        self.summary = "\(session.employeeName) - \(session.position) - \(session.schoolName)"
        self.startDate = session.startDate
        self.endDate = session.endDate
        self.description = session.description
        self.location = session.location
        self.url = nil // Sessions don't have URLs
    }
    
    // Direct initializer for compatibility
    init(id: String, summary: String, startDate: Date?, endDate: Date?, description: String?, location: String?, url: String?) {
        self.id = id
        self.summary = summary
        self.startDate = startDate
        self.endDate = endDate
        self.description = description
        self.location = location
        self.url = url
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

/// Compatibility layer: ICSParser that uses SessionService instead of parsing ICS files
/// This provides the same interface but gets data from Supabase sessions
class ICSParser {
    private static let sessionService = SessionService.shared

    // Legacy interface: parseICS now returns sessions converted to ICSEvents
    static func parseICS(from content: String) -> [ICSEvent] {
        print("ICSParser.parseICS called - this is now a compatibility layer using Supabase sessions")
        
        // For backward compatibility, we'll return an empty array and rely on the real-time listeners
        // The actual data loading should be done through SessionService in the calling code
        return []
    }
    
    // New method: Get current sessions as ICSEvents
    static func getCurrentSessionsAsICSEvents(completion: @escaping ([ICSEvent]) -> Void) {
        let organizationID = UserDefaults.standard.string(forKey: "userOrganizationID") ?? ""
        guard !organizationID.isEmpty else {
            print("❌ Cannot load sessions: no organization ID")
            completion([])
            return
        }

        // Create a unique subscription ID for this one-time fetch
        let subscriptionId = UUID()

        Task { @MainActor in
            sessionService.startListeningToSessions(
                subscriptionId: subscriptionId,
                organizationID: organizationID,
                includeUnpublished: false  // ICS export shows only published
            ) { sessions in
                let icsEvents = sessions.map { session in
                    ICSEvent(from: session)
                }
                completion(icsEvents)

                // Clean up the subscription after returning results
                sessionService.stopListeningToSessions(subscriptionId: subscriptionId)
            }
        }
    }
    
    // Helper method: Convert sessions to ICSEvents (creates one event per photographer)
    static func convertSessionsToICSEvents(_ sessions: [Session]) -> [ICSEvent] {
        var allEvents: [ICSEvent] = []
        
        print("🔄 Converting \(sessions.count) sessions to ICSEvents")
        
        for session in sessions {
            let photographerIDs = session.getPhotographerIDs()
            print("🔄 Session \(session.schoolName): found \(photographerIDs.count) photographer IDs: \(photographerIDs)")
            
            if photographerIDs.isEmpty {
                // Fallback: create one event using legacy method
                print("🔄 Using legacy method for session \(session.schoolName)")
                allEvents.append(ICSEvent(from: session))
            } else {
                // Create one event for each photographer
                for photographerID in photographerIDs {
                    print("🔄 Creating event for photographer \(photographerID) in session \(session.schoolName)")
                    allEvents.append(ICSEvent(from: session, photographerID: photographerID))
                }
            }
        }
        
        print("🔄 Total events created: \(allEvents.count)")
        return allEvents
    }
}