# Daily Report Template System - Firebase Schema & iOS Integration

## Overview

The template system allows dynamic form creation using Firestore collections. Templates define form structure and field types, which iOS apps render dynamically. All data is organization-scoped for security.

## Firestore Collections

### 1. Templates Collection: `reportTemplates`

```swift
// Collection: "reportTemplates"
// Security: organizationID filter required

struct ReportTemplate: Codable, Identifiable {
    let id: String // Auto-generated document ID
    let name: String // "Fall Sports Report"
    let description: String? // Optional template description
    let shootType: String // "sports", "portraits", "events", "general", "commercial", "yearbook"
    let organizationID: String // User's organization ID (REQUIRED for queries)
    let fields: [TemplateField] // Form fields array
    let isDefault: Bool // Default template for this shootType
    let isActive: Bool // Available for use
    let version: Int // Template version (default: 1)
    let createdAt: Timestamp
    let updatedAt: Timestamp
    let createdBy: String // Creator's user ID
}
```

### 2. Template Fields Structure

```swift
struct TemplateField: Codable, Identifiable {
    let id: String // Unique field ID within template
    let type: String // Field type (see Field Types below)
    let label: String // Display label
    let required: Bool // Required field validation
    let options: [String]? // For select/multiselect/radio fields
    let placeholder: String? // Input placeholder text
    let defaultValue: String? // Default field value
    let smartConfig: SmartFieldConfig? // Smart field configuration
    let readOnly: Bool? // Smart fields are typically read-only
}

struct SmartFieldConfig: Codable {
    let calculationType: String // Smart calculation type
    let fallbackValue: String? // Value if calculation fails
    let autoUpdate: Bool // Auto-recalculate on context change
}
```

### 3. Reports Collection: `dailyJobReports`

```swift
// Collection: "dailyJobReports"
// Security: organizationID filter required

struct DailyJobReport: Codable, Identifiable {
    let id: String // Auto-generated document ID
    let organizationID: String // User's organization ID (REQUIRED)
    let userId: String // Creator's user ID
    let date: String // ISO date: "2024-01-15"
    let photographer: String // Photographer name
    
    // Template metadata
    let templateId: String? // Template used (nil for legacy reports)
    let templateName: String? // Template name snapshot
    let templateVersion: Int? // Template version used
    let reportType: String // "template" or "legacy"
    let smartFieldsUsed: [String]? // Smart field IDs used
    
    // Dynamic form data - stored as [String: Any]
    // Field values stored with field.id as key
    // Examples:
    // "job_type": "Fall Sports"
    // "weather": "Sunny, 72°F"
    // "mileage": "24.8 miles"
    
    let createdAt: Timestamp
    let updatedAt: Timestamp
}
```

## Field Types Reference

### Basic Input Fields
```swift
"text"        // Single line text input
"textarea"    // Multi-line text area
"number"      // Numeric input
"email"       // Email with validation
"phone"       // Phone number input
"date"        // Date picker
"time"        // Time picker
```

### Selection Fields
```swift
"select"      // Single selection dropdown (requires options array)
"multiselect" // Multiple checkboxes (requires options array)
"radio"       // Radio buttons (requires options array)
"toggle"      // Yes/No boolean switch
```

### Advanced Fields
```swift
"file"        // File/image upload (multiple files)
"location"    // Address/GPS input
"currency"    // Money amount input
```

### Smart Auto-Calculated Fields
```swift
"mileage"              // Round-trip mileage calculation
"date_auto"            // Auto-fills current date
"time_auto"            // Auto-fills current time
"user_name"            // Auto-fills photographer name
"school_name"          // Auto-fills selected school names
"photo_count"          // Counts attached photos
"current_location"     // GPS coordinates
"weather_conditions"   // Current weather
"calculation"          // Custom calculation
```

## Data Sources for Smart Fields

### User Profile Data (`users` collection)
```swift
// Required field: userCoordinates
// Format: "latitude,longitude" (e.g., "38.321991,-88.867400")

struct UserProfile {
    let userCoordinates: String // GPS coordinates for mileage
    let firstName: String       // For user_name smart field
    let lastName: String        // For user_name smart field
    // ... other user fields
}
```

### Schools Data (`schools` collection)
```swift
// Used for mileage calculations and school selection

struct School: Codable, Identifiable {
    let id: String
    let value: String           // Display name: "Adams School - Marion"
    let street: String          // "123 Main St"
    let city: String           // "Marion"
    let state: String          // "IL"
    let zipCode: String        // "62959"
    let coordinates: String    // "lat,lng" format for distance calculation
    let organizationID: String // Organization filter
}
```

## Firebase Operations

### 1. Fetch Templates for Organization
```swift
func fetchTemplates(for organizationID: String) async throws -> [ReportTemplate] {
    let db = Firestore.firestore()
    let snapshot = try await db.collection("reportTemplates")
        .whereField("organizationID", isEqualTo: organizationID)
        .whereField("isActive", isEqualTo: true)
        .order(by: "createdAt", descending: true)
        .getDocuments()
    
    return snapshot.documents.compactMap { doc in
        try? doc.data(as: ReportTemplate.self)
    }
}
```

### 2. Fetch Schools for Mileage Calculation
```swift
func fetchSchools(for organizationID: String) async throws -> [School] {
    let db = Firestore.firestore()
    let snapshot = try await db.collection("schools")
        .whereField("organizationID", isEqualTo: organizationID)
        .order(by: "value")
        .getDocuments()
    
    return snapshot.documents.compactMap { doc in
        try? doc.data(as: School.self)
    }
}
```

### 3. Submit Completed Report
```swift
func submitReport(formData: [String: Any], template: ReportTemplate, user: UserProfile) async throws -> String {
    let db = Firestore.firestore()
    
    let reportData: [String: Any] = [
        "organizationID": user.organizationID,
        "userId": user.uid,
        "date": ISO8601DateFormatter().string(from: Date()),
        "photographer": "\(user.firstName) \(user.lastName)",
        "templateId": template.id,
        "templateName": template.name,
        "templateVersion": template.version,
        "reportType": "template",
        "smartFieldsUsed": template.fields.compactMap { $0.smartConfig != nil ? $0.id : nil },
        "createdAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp()
    ]
    
    // Merge form data with report metadata
    let finalData = reportData.merging(formData) { (current, _) in current }
    
    let docRef = try await db.collection("dailyJobReports").addDocument(data: finalData)
    return docRef.documentID
}
```

## Smart Field Calculation Examples

### Mileage Calculation
```swift
// Smart field: "mileage"
// Input: User coordinates + selected school coordinates
// Output: "123.4 miles"

func calculateMileage(userCoords: String, selectedSchools: [School]) -> String {
    // Parse user coordinates: "lat,lng"
    let userComponents = userCoords.split(separator: ",")
    guard userComponents.count == 2,
          let userLat = Double(userComponents[0]),
          let userLng = Double(userComponents[1]) else {
        return "0 miles"
    }
    
    var totalDistance: Double = 0
    var currentLat = userLat
    var currentLng = userLng
    
    // Calculate route: home -> school1 -> school2 -> ... -> home
    for school in selectedSchools {
        let schoolComponents = school.coordinates.split(separator: ",")
        guard schoolComponents.count == 2,
              let schoolLat = Double(schoolComponents[0]),
              let schoolLng = Double(schoolComponents[1]) else { continue }
        
        totalDistance += haversineDistance(
            lat1: currentLat, lng1: currentLng,
            lat2: schoolLat, lng2: schoolLng
        )
        
        currentLat = schoolLat
        currentLng = schoolLng
    }
    
    // Return trip home
    totalDistance += haversineDistance(
        lat1: currentLat, lng1: currentLng,
        lat2: userLat, lng2: userLng
    )
    
    return String(format: "%.1f miles", totalDistance)
}
```

### Date/Time Auto Fields
```swift
// date_auto: Current date in US format
let dateFormatter = DateFormatter()
dateFormatter.dateStyle = .short
dateFormatter.locale = Locale(identifier: "en_US")
return dateFormatter.string(from: Date()) // "1/15/24"

// time_auto: Current time in US format
let timeFormatter = DateFormatter()
timeFormatter.timeStyle = .short
timeFormatter.locale = Locale(identifier: "en_US")
return timeFormatter.string(from: Date()) // "2:30 PM"
```

## Form Data Structure

### Template-Based Report Data
```swift
// Example form data for submission
let formData: [String: Any] = [
    // Built-in fields
    "date": "2024-01-15",
    "photographer": "John Smith",
    
    // Template fields (field.id as key)
    "job_type": "Fall Sports",
    "weather": "Sunny, 72°F",
    "mileage": "24.8 miles",
    "notes": "Great lighting conditions",
    "schools_visited": ["Adams School - Marion", "Lincoln Elementary"],
    
    // Multi-select example
    "equipment_used": ["Camera", "Tripod", "Flash"],
    
    // Toggle example
    "backup_completed": true,
    
    // Number field example
    "photos_taken": 150
]
```

## Error Handling

### Template Loading Errors
```swift
enum TemplateError: Error {
    case noOrganization
    case noTemplatesFound
    case networkError(Error)
    case permissionDenied
}

// Handle template loading failures
do {
    let templates = try await fetchTemplates(for: organizationID)
    if templates.isEmpty {
        throw TemplateError.noTemplatesFound
    }
} catch {
    // Show appropriate error message to user
    handleTemplateError(error)
}
```

### Smart Field Calculation Fallbacks
```swift
func calculateSmartField(_ field: TemplateField) -> String {
    guard let smartConfig = field.smartConfig else { return "" }
    
    do {
        // Attempt calculation
        let result = try performSmartCalculation(field)
        return result
    } catch {
        // Use fallback value or show error
        return smartConfig.fallbackValue ?? "Calculation failed"
    }
}
```

## Security & Validation

### Organization-Scoped Queries
```swift
// ALWAYS filter by organizationID for security
let query = db.collection("reportTemplates")
    .whereField("organizationID", isEqualTo: user.organizationID)
    .whereField("isActive", isEqualTo: true)
```

### Field Validation
```swift
func validateField(_ field: TemplateField, value: Any?) -> Bool {
    if field.required && (value == nil || isEmpty(value)) {
        return false
    }
    
    switch field.type {
    case "email":
        return isValidEmail(value as? String)
    case "number":
        return value is Double || value is Int
    default:
        return true
    }
}
```

## Real Template Example

```json
{
  "id": "fall_sports_template",
  "name": "Fall Sports Daily Report",
  "description": "Standard report for fall sports photography sessions",
  "shootType": "sports",
  "organizationID": "org_123",
  "isDefault": true,
  "isActive": true,
  "version": 1,
  "fields": [
    {
      "id": "job_type",
      "type": "select",
      "label": "Job Type",
      "required": true,
      "options": ["Fall Sports", "Team Photos", "Individual Photos"]
    },
    {
      "id": "mileage_calc",
      "type": "mileage",
      "label": "Round Trip Mileage",
      "required": false,
      "smartConfig": {
        "calculationType": "mileage",
        "fallbackValue": "0 miles",
        "autoUpdate": true
      },
      "readOnly": true
    },
    {
      "id": "weather",
      "type": "weather_conditions",
      "label": "Weather Conditions",
      "smartConfig": {
        "calculationType": "weather_conditions",
        "fallbackValue": "Unknown"
      }
    },
    {
      "id": "notes",
      "type": "textarea",
      "label": "Additional Notes",
      "placeholder": "Any additional observations..."
    }
  ]
}
```

This schema provides everything needed to build iOS forms that integrate with the existing Firestore template system.