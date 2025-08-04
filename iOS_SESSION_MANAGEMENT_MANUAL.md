# iOS Session Management Implementation Manual

This manual provides comprehensive guidance for implementing session creation and editing functionality in the iOS app to match the web application's behavior.

## Table of Contents
1. [Overview](#overview)
2. [Firebase Data Structure](#firebase-data-structure)
3. [Required Firestore Collections](#required-firestore-collections)
4. [Data Models](#data-models)
5. [Fetching Required Data](#fetching-required-data)
6. [Creating Sessions](#creating-sessions)
7. [Editing Sessions](#editing-sessions)
8. [Session Color Management](#session-color-management)
9. [Best Practices](#best-practices)

## Overview

The session management system allows users to:
- Create photography sessions for schools
- Assign photographers to sessions
- Set session types (e.g., Sports Photography, Portrait Day)
- Add notes for photographers
- Edit existing sessions
- Manage session colors for calendar display

## Firebase Data Structure

### Sessions Collection (`sessions`)
```javascript
{
  // Core Fields
  id: String,                    // Auto-generated document ID
  organizationID: String,        // Required - links to organization
  schoolId: String,              // Required - links to school document
  schoolName: String,            // Denormalized for performance
  
  // Date & Time
  date: String,                  // Format: "YYYY-MM-DD"
  startTime: String,             // Format: "HH:MM" (24-hour)
  endTime: String,               // Format: "HH:MM" (24-hour)
  
  // Session Types (now supports multiple)
  sessionTypes: [String],        // Array of session type IDs
  customSessionType: String?,    // Only used if 'other' is in sessionTypes
  
  // Photographers
  photographers: [{
    id: String,
    name: String,
    email: String,
    notes: String               // Individual notes for this photographer
  }],
  
  // Metadata
  notes: String,                // General session notes
  status: String,               // "scheduled", "completed", "cancelled"
  sessionColor: String,         // Hex color for calendar display
  
  // Publishing (optional)
  published: Boolean?,          // If organization has publishing enabled
  publishedAt: Timestamp?,      // When it was published
  
  // Tracking
  createdAt: Timestamp,
  createdBy: {
    id: String,
    name: String,
    email: String
  },
  updatedAt: Timestamp?,
  
  // Special flags
  isTimeOff: Boolean?           // For time-off sessions (color: #666)
}
```

### Schools Collection (`schools`)
```javascript
{
  id: String,                   // Auto-generated document ID
  organizationID: String,       // Required
  value: String,                // School name (legacy field name)
  isActive: Boolean,           // Default: true
  createdAt: Timestamp,
  updatedAt: Timestamp
}
```

### Users Collection (`users`)
```javascript
{
  id: String,                   // User UID from Firebase Auth
  organizationID: String,       // Links to organization
  email: String,
  firstName: String,
  lastName: String,
  photoURL: String?,            // Profile photo URL
  isActive: Boolean,            // Can be assigned to sessions
  role: String,                 // "admin", "photographer", etc.
  displayName: String?,         // Optional display name
  createdAt: Timestamp,
  updatedAt: Timestamp
}
```

### Organizations Collection (`organizations`)
```javascript
{
  id: String,
  name: String,
  
  // Session Configuration
  sessionTypes: [{
    id: String,                // Unique identifier (e.g., "sports", "portrait")
    name: String,              // Display name
    color: String,             // Hex color (e.g., "#3b82f6")
    order: Number              // Sort order (1-based, 'other' is always 9999)
  }],
  
  sessionOrderColors: [String]?, // Array of 8 hex colors for session ordering
  enableSessionPublishing: Boolean?, // Enable session publishing feature
  
  // Other organization settings...
}
```


## Fetching Required Data

### 1. Get Schools for Organization

```swift
func getSchools(organizationID: String) async throws -> [School] {
    let db = Firestore.firestore()
    
    let query = db.collection("schools")
        .whereField("organizationID", isEqualTo: organizationID)
    
    let snapshot = try await query.getDocuments()
    
    let schools = snapshot.documents.compactMap { doc -> School? in
        var data = doc.data()
        data["id"] = doc.documentID
        return try? JSONDecoder().decode(School.self, from: JSONSerialization.data(withJSONObject: data))
    }
    
    // Sort alphabetically by name
    return schools.sorted { $0.value.localizedCaseInsensitiveCompare($1.value) == .orderedAscending }
}
```

### 2. Get Team Members (Photographers)

```swift
func getTeamMembers(organizationID: String) async throws -> [TeamMember] {
    let db = Firestore.firestore()
    
    let query = db.collection("users")
        .whereField("organizationID", isEqualTo: organizationID)
    
    let snapshot = try await query.getDocuments()
    
    let members = snapshot.documents.compactMap { doc -> TeamMember? in
        var data = doc.data()
        data["id"] = doc.documentID
        return try? JSONDecoder().decode(TeamMember.self, from: JSONSerialization.data(withJSONObject: data))
    }
    
    // Sort by active status first, then by name
    return members.sorted { lhs, rhs in
        if lhs.isActive != rhs.isActive {
            return lhs.isActive
        }
        let lhsName = lhs.displayName ?? "\(lhs.firstName) \(lhs.lastName)"
        let rhsName = rhs.displayName ?? "\(rhs.firstName) \(rhs.lastName)"
        return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
    }
}
```

### 3. Get Session Types from Organization

```swift
func getOrganizationSessionTypes(organization: Organization) -> [SessionType] {
    var customTypes = organization.sessionTypes ?? []
    
    // Add order field to types that don't have it
    customTypes = customTypes.enumerated().map { index, type in
        var updatedType = type
        if updatedType.order == 0 {
            updatedType.order = type.id == "other" ? 9999 : index + 1
        }
        return updatedType
    }
    
    // Always ensure "Other" is available
    let hasOther = customTypes.contains { $0.id == "other" }
    if !hasOther {
        customTypes.append(SessionType(
            id: "other",
            name: "Other",
            color: "#000000",
            order: 9999
        ))
    }
    
    // Sort by order, ensuring "Other" is always last
    return customTypes.sorted { lhs, rhs in
        if lhs.id == "other" { return false }
        if rhs.id == "other" { return true }
        return lhs.order < rhs.order
    }
}
```

## Creating Sessions

### Step 1: Validate Input

```swift
func validateSessionInput(formData: SessionFormData) -> [String: String] {
    var errors: [String: String] = [:]
    
    if formData.schoolId.isEmpty {
        errors["schoolId"] = "School is required"
    }
    
    if formData.date.isEmpty {
        errors["date"] = "Date is required"
    }
    
    if formData.startTime.isEmpty {
        errors["startTime"] = "Start time is required"
    }
    
    if formData.endTime.isEmpty {
        errors["endTime"] = "End time is required"
    }
    
    if formData.sessionTypes.isEmpty {
        errors["sessionTypes"] = "At least one session type is required"
    }
    
    if formData.sessionTypes.contains("other") && formData.customSessionType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        errors["customSessionType"] = "Please specify a custom session type"
    }
    
    // Validate time range
    if !formData.startTime.isEmpty && !formData.endTime.isEmpty {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        
        if let start = formatter.date(from: formData.startTime),
           let end = formatter.date(from: formData.endTime),
           end <= start {
            errors["endTime"] = "End time must be after start time"
        }
    }
    
    return errors
}
```

### Step 2: Calculate Session Color

```swift
func calculateSessionColor(
    organizationID: String,
    date: String,
    startTime: String,
    isTimeOff: Bool = false
) async throws -> String {
    // Time off sessions always get gray
    if isTimeOff {
        return "#666"
    }
    
    let db = Firestore.firestore()
    
    // Get existing sessions for the same date
    let query = db.collection("sessions")
        .whereField("organizationID", isEqualTo: organizationID)
        .whereField("date", isEqualTo: date)
    
    let snapshot = try await query.getDocuments()
    
    // Filter out time-off sessions and convert to array
    var existingSessions = snapshot.documents
        .compactMap { doc -> (id: String, startTime: String, schoolId: String)? in
            let data = doc.data()
            guard let isTimeOff = data["isTimeOff"] as? Bool, !isTimeOff,
                  let startTime = data["startTime"] as? String,
                  let schoolId = data["schoolId"] as? String else { return nil }
            return (id: doc.documentID, startTime: startTime, schoolId: schoolId)
        }
    
    // Add the new session temporarily for color calculation
    existingSessions.append((id: "temp", startTime: startTime, schoolId: ""))
    
    // Sort by start time, then by school ID for consistency
    existingSessions.sort { lhs, rhs in
        if lhs.startTime != rhs.startTime {
            return lhs.startTime < rhs.startTime
        }
        return lhs.schoolId < rhs.schoolId
    }
    
    // Find the index of our new session
    let orderIndex = existingSessions.firstIndex { $0.id == "temp" } ?? 0
    
    // Get organization colors or use defaults
    let organization = try await getOrganization(organizationID: organizationID)
    let customColors = organization.sessionOrderColors
    let defaultColors = [
        "#3b82f6", "#10b981", "#8b5cf6", "#f59e0b",
        "#ef4444", "#06b6d4", "#8b5a3c", "#6b7280"
    ]
    let colors = (customColors?.count ?? 0) >= 8 ? customColors! : defaultColors
    
    return colors[min(orderIndex, colors.count - 1)]
}
```

### Step 3: Create Session Document

```swift
func createSession(
    organizationID: String,
    formData: SessionFormData,
    currentUser: User,
    teamMembers: [TeamMember],
    schools: [School]
) async throws -> String {
    let db = Firestore.firestore()
    
    // Get organization settings
    let organization = try await getOrganization(organizationID: organizationID)
    let enablePublishing = organization.enableSessionPublishing ?? false
    
    // Calculate session color
    let sessionColor = try await calculateSessionColor(
        organizationID: organizationID,
        date: formData.date,
        startTime: formData.startTime,
        isTimeOff: formData.isTimeOff
    )
    
    // Get photographer details
    let selectedPhotographers = formData.photographerIds.compactMap { photographerId in
        guard let member = teamMembers.first(where: { $0.id == photographerId }) else { return nil }
        return SessionPhotographer(
            id: member.id,
            name: "\(member.firstName) \(member.lastName)",
            email: member.email,
            notes: formData.photographerNotes[member.id] ?? ""
        )
    }
    
    // Get school name
    let schoolName = schools.first { $0.id == formData.schoolId }?.value ?? ""
    
    // Prepare session data
    var sessionData: [String: Any] = [
        "organizationID": organizationID,
        "schoolId": formData.schoolId,
        "schoolName": schoolName,
        "date": formData.date,
        "startTime": formData.startTime,
        "endTime": formData.endTime,
        "sessionTypes": formData.sessionTypes,
        "notes": formData.notes,
        "status": formData.status,
        "sessionColor": sessionColor,
        "createdAt": FieldValue.serverTimestamp(),
        "createdBy": [
            "id": currentUser.uid,
            "name": currentUser.displayName ?? "\(currentUser.firstName) \(currentUser.lastName)",
            "email": currentUser.email
        ]
    ]
    
    // Add photographers array (Firebase doesn't like encoding structs directly)
    sessionData["photographers"] = selectedPhotographers.map { photographer in
        [
            "id": photographer.id,
            "name": photographer.name,
            "email": photographer.email,
            "notes": photographer.notes
        ]
    }
    
    // Add optional fields
    if formData.sessionTypes.contains("other") {
        sessionData["customSessionType"] = formData.customSessionType.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    if formData.isTimeOff {
        sessionData["isTimeOff"] = true
    }
    
    if enablePublishing {
        sessionData["published"] = false
    }
    
    // Create the session
    let docRef = try await db.collection("sessions").addDocument(data: sessionData)
    
    // Recalculate colors for all sessions on this date
    try await recalculateSessionColorsForDate(
        organizationID: organizationID,
        date: formData.date,
        organization: organization
    )
    
    return docRef.documentID
}
```

## Editing Sessions

### Step 1: Fetch Existing Session

```swift
func getSession(sessionId: String) async throws -> Session {
    let db = Firestore.firestore()
    let doc = try await db.collection("sessions").document(sessionId).getDocument()
    
    guard doc.exists, var data = doc.data() else {
        throw SessionError.notFound
    }
    
    data["id"] = doc.documentID
    return try JSONDecoder().decode(Session.self, from: JSONSerialization.data(withJSONObject: data))
}
```

### Step 2: Update Session

```swift
func updateSession(
    sessionId: String,
    formData: SessionFormData,
    teamMembers: [TeamMember],
    schools: [School]
) async throws {
    let db = Firestore.firestore()
    
    // Get current session data
    let currentSession = try await getSession(sessionId: sessionId)
    
    // Check if date or time changed (affects color ordering)
    let affectsOrdering = formData.date != currentSession.date || 
                         formData.startTime != currentSession.startTime
    let oldDate = currentSession.date
    let newDate = formData.date
    
    // Get photographer details
    let selectedPhotographers = formData.photographerIds.compactMap { photographerId in
        guard let member = teamMembers.first(where: { $0.id == photographerId }) else { return nil }
        return [
            "id": member.id,
            "name": "\(member.firstName) \(member.lastName)",
            "email": member.email,
            "notes": formData.photographerNotes[member.id] ?? ""
        ]
    }
    
    // Get school name
    let schoolName = schools.first { $0.id == formData.schoolId }?.value ?? ""
    
    // Prepare update data
    var updateData: [String: Any] = [
        "schoolId": formData.schoolId,
        "schoolName": schoolName,
        "date": formData.date,
        "startTime": formData.startTime,
        "endTime": formData.endTime,
        "sessionTypes": formData.sessionTypes,
        "photographers": selectedPhotographers,
        "notes": formData.notes,
        "status": formData.status,
        "updatedAt": FieldValue.serverTimestamp()
    ]
    
    // Handle custom session type
    if formData.sessionTypes.contains("other") {
        updateData["customSessionType"] = formData.customSessionType.trimmingCharacters(in: .whitespacesAndNewlines)
    } else {
        updateData["customSessionType"] = FieldValue.delete()
    }
    
    // Update the session
    try await db.collection("sessions").document(sessionId).updateData(updateData)
    
    // Recalculate colors if ordering changed
    if affectsOrdering {
        // Recalculate for old date if date changed
        if oldDate != newDate {
            try await recalculateSessionColorsForDate(
                organizationID: currentSession.organizationID,
                date: oldDate
            )
        }
        
        // Recalculate for new date
        try await recalculateSessionColorsForDate(
            organizationID: currentSession.organizationID,
            date: newDate
        )
    }
}
```

## Session Color Management

### Recalculate Colors for Date

```swift
func recalculateSessionColorsForDate(
    organizationID: String,
    date: String,
    organization: Organization? = nil
) async throws {
    let db = Firestore.firestore()
    
    // Get organization if not provided
    let org = try organization ?? (await getOrganization(organizationID: organizationID))
    
    // Get all sessions for this date
    let query = db.collection("sessions")
        .whereField("organizationID", isEqualTo: organizationID)
        .whereField("date", isEqualTo: date)
    
    let snapshot = try await query.getDocuments()
    
    let allSessions = snapshot.documents.map { doc -> (id: String, data: [String: Any]) in
        (id: doc.documentID, data: doc.data())
    }
    
    // Separate time off from regular sessions
    let regularSessions = allSessions.filter { session in
        !(session.data["isTimeOff"] as? Bool ?? false)
    }
    let timeOffSessions = allSessions.filter { session in
        session.data["isTimeOff"] as? Bool ?? false
    }
    
    // Sort regular sessions by start time, then school ID
    let sortedRegularSessions = regularSessions.sorted { lhs, rhs in
        let lhsStart = lhs.data["startTime"] as? String ?? ""
        let rhsStart = rhs.data["startTime"] as? String ?? ""
        if lhsStart != rhsStart {
            return lhsStart < rhsStart
        }
        let lhsSchool = lhs.data["schoolId"] as? String ?? ""
        let rhsSchool = rhs.data["schoolId"] as? String ?? ""
        return lhsSchool < rhsSchool
    }
    
    // Get color array
    let customColors = org.sessionOrderColors
    let defaultColors = [
        "#3b82f6", "#10b981", "#8b5cf6", "#f59e0b",
        "#ef4444", "#06b6d4", "#8b5a3c", "#6b7280"
    ]
    let colors = (customColors?.count ?? 0) >= 8 ? customColors! : defaultColors
    
    // Batch update colors
    let batch = db.batch()
    var hasUpdates = false
    
    // Update regular sessions
    for (index, session) in sortedRegularSessions.enumerated() {
        let expectedColor = colors[min(index, colors.count - 1)]
        let currentColor = session.data["sessionColor"] as? String
        
        if currentColor != expectedColor {
            let docRef = db.collection("sessions").document(session.id)
            batch.updateData(["sessionColor": expectedColor], forDocument: docRef)
            hasUpdates = true
        }
    }
    
    // Update time off sessions
    for session in timeOffSessions {
        let expectedColor = "#666"
        let currentColor = session.data["sessionColor"] as? String
        
        if currentColor != expectedColor {
            let docRef = db.collection("sessions").document(session.id)
            batch.updateData(["sessionColor": expectedColor], forDocument: docRef)
            hasUpdates = true
        }
    }
    
    // Commit batch if there are updates
    if hasUpdates {
        try await batch.commit()
    }
}
```

## Best Practices

### 1. Error Handling

```swift
enum SessionError: LocalizedError {
    case notFound
    case invalidInput(field: String, message: String)
    case permissionDenied
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Session not found"
        case .invalidInput(let field, let message):
            return "\(field): \(message)"
        case .permissionDenied:
            return "You don't have permission to perform this action"
        case .networkError:
            return "Network error. Please check your connection"
        }
    }
}
```

### 3. UI/UX Guidelines

1. **Loading States**: Show loading indicators during data fetches
2. **Validation**: Validate on-the-fly and show inline errors
3. **Time Selection**: Use 15-minute intervals for time pickers
4. **Photographer Selection**: Show active members first, with profile photos
5. **Session Types**: Display with their associated colors
6. **Date Constraints**: Consider limiting dates to reasonable future range

### 4. Performance Optimization

```swift
// Batch fetch related data
func loadSessionFormData(organizationID: String) async throws -> SessionFormData {
    async let schools = getSchools(organizationID: organizationID)
    async let teamMembers = getTeamMembers(organizationID: organizationID)
    async let organization = getOrganization(organizationID: organizationID)
    
    return try await SessionFormData(
        schools: schools,
        teamMembers: teamMembers,
        sessionTypes: getOrganizationSessionTypes(organization: organization)
    )
}
```

### 5. Security Rules

Ensure your Firebase Security Rules match the web app:

```javascript
// Sessions collection
match /sessions/{sessionId} {
  allow read: if request.auth != null && 
    request.auth.token.organizationID == resource.data.organizationID;
  
  allow create: if request.auth != null && 
    request.auth.token.organizationID == request.resource.data.organizationID &&
    request.auth.token.role in ['admin', 'manager'];
  
  allow update: if request.auth != null && 
    request.auth.token.organizationID == resource.data.organizationID &&
    request.auth.token.role in ['admin', 'manager'];
  
  allow delete: if request.auth != null && 
    request.auth.token.organizationID == resource.data.organizationID &&
    request.auth.token.role == 'admin';
}
```

## Summary

This implementation guide provides everything needed to add session creation and editing to your iOS app. Key points to remember:

1. Sessions now support multiple session types (array instead of single string)
2. Session colors are automatically calculated based on order within a day
3. Time-off sessions always get gray color (#666)
4. Always recalculate colors when dates or times change
5. Validate all inputs before submission
6. Handle offline scenarios gracefully with Firestore's offline persistence

For any questions or clarifications, refer to the web app implementation in the `/src/components/sessions/` directory.