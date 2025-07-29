import Foundation
import FirebaseFirestore

struct TimeOffRequest: Identifiable, Codable {
    let id: String
    let organizationID: String
    let photographerId: String
    let photographerName: String
    let photographerEmail: String
    let startDate: Date
    let endDate: Date
    let reason: TimeOffReason
    let notes: String
    let status: TimeOffStatus
    let createdAt: Date
    let updatedAt: Date
    
    // Partial day support
    let isPartialDay: Bool
    let startTime: String? // Format: "09:00"
    let endTime: String? // Format: "17:00"
    
    // PTO fields
    let isPaidTimeOff: Bool
    let ptoHoursRequested: Double?
    let projectedPTOBalance: Double? // Expected balance at request date
    
    // Approval fields (optional)
    let approvedBy: String?
    let approverName: String?
    let approvedAt: Date?
    
    // Denial fields (optional)
    let deniedBy: String?
    let denierName: String?
    let deniedAt: Date?
    let denialReason: String?
    
    // Review fields (optional)
    let reviewedBy: String?
    let reviewerName: String?
    let reviewedAt: Date?
    
    // Firestore initializer
    init(id: String, data: [String: Any]) {
        self.id = id
        self.organizationID = data["organizationID"] as? String ?? ""
        self.photographerId = data["photographerId"] as? String ?? ""
        self.photographerName = data["photographerName"] as? String ?? ""
        self.photographerEmail = data["photographerEmail"] as? String ?? ""
        
        // Convert Firestore timestamps to dates
        if let startTimestamp = data["startDate"] as? Timestamp {
            self.startDate = startTimestamp.dateValue()
        } else {
            self.startDate = Date()
        }
        
        if let endTimestamp = data["endDate"] as? Timestamp {
            self.endDate = endTimestamp.dateValue()
        } else {
            self.endDate = Date()
        }
        
        // Enum conversions with fallbacks
        if let reasonString = data["reason"] as? String,
           let parsedReason = TimeOffReason(rawValue: reasonString) {
            self.reason = parsedReason
        } else {
            self.reason = .other
        }
        
        if let statusString = data["status"] as? String,
           let parsedStatus = TimeOffStatus(rawValue: statusString) {
            self.status = parsedStatus
        } else {
            self.status = .pending
        }
        
        self.notes = data["notes"] as? String ?? ""
        
        // Partial day support
        self.isPartialDay = data["isPartialDay"] as? Bool ?? false
        self.startTime = data["startTime"] as? String
        self.endTime = data["endTime"] as? String
        
        // PTO fields
        self.isPaidTimeOff = data["isPaidTimeOff"] as? Bool ?? false
        self.ptoHoursRequested = data["ptoHoursRequested"] as? Double
        self.projectedPTOBalance = data["projectedPTOBalance"] as? Double
        
        // Timestamps
        if let createdTimestamp = data["createdAt"] as? Timestamp {
            self.createdAt = createdTimestamp.dateValue()
        } else {
            self.createdAt = Date()
        }
        
        if let updatedTimestamp = data["updatedAt"] as? Timestamp {
            self.updatedAt = updatedTimestamp.dateValue()
        } else {
            self.updatedAt = Date()
        }
        
        // Optional approval fields
        self.approvedBy = data["approvedBy"] as? String
        self.approverName = data["approverName"] as? String
        if let approvedTimestamp = data["approvedAt"] as? Timestamp {
            self.approvedAt = approvedTimestamp.dateValue()
        } else {
            self.approvedAt = nil
        }
        
        // Optional denial fields
        self.deniedBy = data["deniedBy"] as? String
        self.denierName = data["denierName"] as? String
        if let deniedTimestamp = data["deniedAt"] as? Timestamp {
            self.deniedAt = deniedTimestamp.dateValue()
        } else {
            self.deniedAt = nil
        }
        self.denialReason = data["denialReason"] as? String
        
        // Optional review fields
        self.reviewedBy = data["reviewedBy"] as? String
        self.reviewerName = data["reviewerName"] as? String
        if let reviewedTimestamp = data["reviewedAt"] as? Timestamp {
            self.reviewedAt = reviewedTimestamp.dateValue()
        } else {
            self.reviewedAt = nil
        }
    }
    
    // Standard initializer for creating new requests
    init(
        id: String = UUID().uuidString,
        organizationID: String,
        photographerId: String,
        photographerName: String,
        photographerEmail: String,
        startDate: Date,
        endDate: Date,
        reason: TimeOffReason,
        notes: String = "",
        isPartialDay: Bool = false,
        startTime: String? = nil,
        endTime: String? = nil,
        isPaidTimeOff: Bool = false,
        ptoHoursRequested: Double? = nil,
        projectedPTOBalance: Double? = nil
    ) {
        self.id = id
        self.organizationID = organizationID
        self.photographerId = photographerId
        self.photographerName = photographerName
        self.photographerEmail = photographerEmail
        self.startDate = startDate
        self.endDate = endDate
        self.reason = reason
        self.notes = notes
        self.status = .pending
        self.createdAt = Date()
        self.updatedAt = Date()
        
        // Partial day support
        self.isPartialDay = isPartialDay
        self.startTime = startTime
        self.endTime = endTime
        
        // PTO fields
        self.isPaidTimeOff = isPaidTimeOff
        self.ptoHoursRequested = ptoHoursRequested
        self.projectedPTOBalance = projectedPTOBalance
        
        // Optional fields start as nil
        self.approvedBy = nil
        self.approverName = nil
        self.approvedAt = nil
        self.deniedBy = nil
        self.denierName = nil
        self.deniedAt = nil
        self.denialReason = nil
        self.reviewedBy = nil
        self.reviewerName = nil
        self.reviewedAt = nil
    }
}

// MARK: - Computed Properties
extension TimeOffRequest {
    
    // Duration in days for full day requests
    var durationInDays: Int {
        guard !isPartialDay else { return 0 }
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 0
        return days + 1 // Include both start and end dates
    }
    
    // Duration in hours for partial day requests
    var durationInHours: Double? {
        guard isPartialDay,
              let startTimeString = startTime,
              let endTimeString = endTime else { return nil }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        
        guard let startTime = formatter.date(from: startTimeString),
              let endTime = formatter.date(from: endTimeString) else { return nil }
        
        let timeInterval = endTime.timeIntervalSince(startTime)
        return timeInterval / 3600 // Convert seconds to hours
    }
    
    // Formatted duration string for display
    var formattedDuration: String {
        if isPartialDay {
            if let hours = durationInHours {
                if hours == 1 {
                    return "1 hour"
                } else if hours.truncatingRemainder(dividingBy: 1) == 0 {
                    return "\(Int(hours)) hours"
                } else {
                    return String(format: "%.1f hours", hours)
                }
            } else {
                return "Invalid time range"
            }
        } else {
            let days = durationInDays
            return days == 1 ? "1 day" : "\(days) days"
        }
    }
    
    // Formatted date range for display
    var formattedDateRange: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        
        if isPartialDay {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            
            if let startTimeString = startTime,
               let endTimeString = endTime,
               let startTime = timeFromString(startTimeString),
               let endTime = timeFromString(endTimeString) {
                return "\(formatter.string(from: startDate)) (\(timeFormatter.string(from: startTime)) - \(timeFormatter.string(from: endTime)))"
            } else {
                return "\(formatter.string(from: startDate)) (Partial Day)"
            }
        } else {
            if Calendar.current.isDate(startDate, inSameDayAs: endDate) {
                return formatter.string(from: startDate)
            } else {
                return "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
            }
        }
    }
    
    // Helper to convert time string to Date for formatting
    private func timeFromString(_ timeString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.date(from: timeString)
    }
    
    // Check if request can be edited (only pending requests by the same user)
    var canBeEdited: Bool {
        return status == .pending || status == .underReview
    }
    
    // Check if request can be cancelled
    var canBeCancelled: Bool {
        return status == .pending || status == .underReview
    }
    
    // Status color for UI
    var statusColor: String {
        switch status {
        case .pending:
            return "orange"
        case .underReview:
            return "blue"
        case .approved:
            return "green"
        case .denied:
            return "red"
        case .cancelled:
            return "gray"
        }
    }
}

// MARK: - Firestore Conversion
extension TimeOffRequest {
    
    // Convert to dictionary for Firestore
    func toFirestoreData() -> [String: Any] {
        var data: [String: Any] = [
            "organizationID": organizationID,
            "photographerId": photographerId,
            "photographerName": photographerName,
            "photographerEmail": photographerEmail,
            "startDate": Timestamp(date: startDate),
            "endDate": Timestamp(date: endDate),
            "reason": reason.rawValue,
            "notes": notes,
            "status": status.rawValue,
            "createdAt": Timestamp(date: createdAt),
            "updatedAt": Timestamp(date: updatedAt),
            "isPartialDay": isPartialDay,
            "isPaidTimeOff": isPaidTimeOff
        ]
        
        // Add PTO fields if applicable
        if let ptoHoursRequested = ptoHoursRequested {
            data["ptoHoursRequested"] = ptoHoursRequested
        }
        if let projectedPTOBalance = projectedPTOBalance {
            data["projectedPTOBalance"] = projectedPTOBalance
        }
        
        // Add partial day fields if applicable
        if isPartialDay {
            if let startTime = startTime {
                data["startTime"] = startTime
            }
            if let endTime = endTime {
                data["endTime"] = endTime
            }
        }
        
        // Add optional approval fields
        if let approvedBy = approvedBy {
            data["approvedBy"] = approvedBy
        }
        if let approverName = approverName {
            data["approverName"] = approverName
        }
        if let approvedAt = approvedAt {
            data["approvedAt"] = Timestamp(date: approvedAt)
        }
        
        // Add optional denial fields
        if let deniedBy = deniedBy {
            data["deniedBy"] = deniedBy
        }
        if let denierName = denierName {
            data["denierName"] = denierName
        }
        if let deniedAt = deniedAt {
            data["deniedAt"] = Timestamp(date: deniedAt)
        }
        if let denialReason = denialReason {
            data["denialReason"] = denialReason
        }
        
        // Add optional review fields
        if let reviewedBy = reviewedBy {
            data["reviewedBy"] = reviewedBy
        }
        if let reviewerName = reviewerName {
            data["reviewerName"] = reviewerName
        }
        if let reviewedAt = reviewedAt {
            data["reviewedAt"] = Timestamp(date: reviewedAt)
        }
        
        return data
    }
}

// MARK: - Validation
extension TimeOffRequest {
    
    // Validate the request data
    func validate() -> (isValid: Bool, error: String?) {
        // Check required fields
        if organizationID.isEmpty {
            return (false, "Organization ID is required")
        }
        
        if photographerId.isEmpty {
            return (false, "Photographer ID is required")
        }
        
        if photographerName.isEmpty {
            return (false, "Photographer name is required")
        }
        
        // Date validation
        if isPartialDay {
            // Partial day must be same day
            if !Calendar.current.isDate(startDate, inSameDayAs: endDate) {
                return (false, "Partial day requests must be for the same day")
            }
            
            // Time validation
            guard let startTimeString = startTime,
                  let endTimeString = endTime else {
                return (false, "Start time and end time are required for partial day requests")
            }
            
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            
            guard let startTime = formatter.date(from: startTimeString),
                  let endTime = formatter.date(from: endTimeString) else {
                return (false, "Invalid time format")
            }
            
            if endTime <= startTime {
                return (false, "End time must be after start time")
            }
            
            // Minimum duration check (30 minutes)
            let timeInterval = endTime.timeIntervalSince(startTime)
            if timeInterval < 1800 { // 30 minutes in seconds
                return (false, "Minimum duration is 30 minutes")
            }
        } else {
            // Full day validation
            if endDate < startDate {
                return (false, "End date must be after start date")
            }
        }
        
        // Start date cannot be in the past
        let calendar = Calendar.current
        if calendar.startOfDay(for: startDate) < calendar.startOfDay(for: Date()) {
            return (false, "Start date cannot be in the past")
        }
        
        return (true, nil)
    }
}

// MARK: - TimeOffCalendarEntry

struct TimeOffCalendarEntry: Identifiable, Codable {
    let id: String
    let requestId: String
    let title: String
    let date: Date
    let startTime: String
    let endTime: String
    let photographerId: String
    let photographerName: String
    let status: TimeOffStatus
    let isPartialDay: Bool
    let reason: TimeOffReason
    let notes: String
    
    init(
        id: String,
        requestId: String,
        title: String,
        date: Date,
        startTime: String,
        endTime: String,
        photographerId: String,
        photographerName: String,
        status: TimeOffStatus,
        isPartialDay: Bool,
        reason: TimeOffReason,
        notes: String
    ) {
        self.id = id
        self.requestId = requestId
        self.title = title
        self.date = date
        self.startTime = startTime
        self.endTime = endTime
        self.photographerId = photographerId
        self.photographerName = photographerName
        self.status = status
        self.isPartialDay = isPartialDay
        self.reason = reason
        self.notes = notes
    }
}