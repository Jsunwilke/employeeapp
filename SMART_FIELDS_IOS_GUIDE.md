# Smart Fields Implementation Guide for iOS

This guide provides detailed implementation instructions for each smart field type in the template system. Each smart field automatically calculates or retrieves data from various sources.

## Overview

Smart fields are auto-populated form fields that require minimal user input. They pull data from:
- User profile data (Firestore)
- Device sensors (GPS, camera)
- External APIs (weather)
- System functions (date/time)
- Form context (selected schools, photos)

## Smart Field Types

### 1. Round Trip Mileage (`mileage`)

**Purpose**: Automatically calculates the total round-trip distance from user's home to all selected schools and back.

**Data Sources**:
- **User Home Coordinates**: `userProfile.userCoordinates` (from Firestore `users` collection)
  - Format: `"38.321991,-88.867400"` (latitude,longitude as string)
- **School Coordinates**: Selected schools from `schools` collection
  - Each school has `coordinates` field in same format
  - Fallback to address geocoding if coordinates missing

**Calculation Logic**:
```swift
// 1. Parse user coordinates: "lat,lng" -> (Double, Double)
let userCoords = userProfile.userCoordinates.split(separator: ",")
let userLat = Double(userCoords[0]), userLng = Double(userCoords[1])

// 2. Create route: home -> school1 -> school2 -> ... -> home
var totalDistance: Double = 0
var currentLat = userLat, currentLng = userLng

for school in selectedSchools {
    let schoolCoords = school.coordinates.split(separator: ",")
    let schoolLat = Double(schoolCoords[0]), schoolLng = Double(schoolCoords[1])
    
    // Calculate distance using Haversine formula
    totalDistance += haversineDistance(currentLat, currentLng, schoolLat, schoolLng)
    currentLat = schoolLat
    currentLng = schoolLng
}

// Add return trip to home
totalDistance += haversineDistance(currentLat, currentLng, userLat, userLng)
```

**Output Format**: `"123.4"` (decimal miles, rounded to 1 decimal place)

**iOS Implementation Notes**:
- Requires location permission for geocoding fallback
- Use CoreLocation for distance calculations
- Handle parsing errors gracefully
- Show loading state while calculating
- Cache results to avoid recalculation

**Error Handling**:
- Missing user coordinates: Show error, require setup
- Invalid coordinate format: Use fallback value "0"
- No schools selected: Show "0"
- Geocoding failure: Skip that school, continue with others

---

### 2. Auto Date (`date_auto`)

**Purpose**: Automatically fills the current date in specified format.

**Data Sources**:
- System date (`Date()`)
- No external dependencies

**Calculation Logic**:
```swift
let date = Date()
let formatter = DateFormatter()

switch field.smartConfig.format {
case "US", "MM/DD/YYYY":
    formatter.dateStyle = .short
    formatter.locale = Locale(identifier: "en_US")
    return formatter.string(from: date) // "7/8/2025"
    
case "YYYY-MM-DD":
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: date) // "2025-07-08"
    
default:
    formatter.dateStyle = .medium
    return formatter.string(from: date) // "Jul 8, 2025"
}
```

**Output Formats**:
- **US Format**: `"7/8/2025"` (default)
- **ISO Format**: `"2025-07-08"`
- **Medium**: `"Jul 8, 2025"`

**iOS Implementation Notes**:
- Updates automatically when form loads
- Should not update while user is actively editing form
- Use local timezone
- Read-only field (user cannot edit)

**Configuration Options**:
- `smartConfig.format`: `"US"`, `"ISO"`, `"medium"`
- `smartConfig.autoUpdate`: boolean (update on focus)

---

### 3. Auto Time (`time_auto`)

**Purpose**: Automatically fills the current time in specified format.

**Data Sources**:
- System time (`Date()`)
- No external dependencies

**Calculation Logic**:
```swift
let time = Date()
let formatter = DateFormatter()

switch field.smartConfig.format {
case "US", "12-hour":
    formatter.timeStyle = .short
    formatter.locale = Locale(identifier: "en_US")
    return formatter.string(from: time) // "2:30 PM"
    
case "24-hour", "HH:mm":
    formatter.dateFormat = "HH:mm"
    return formatter.string(from: time) // "14:30"
    
default:
    formatter.timeStyle = .short
    return formatter.string(from: time)
}
```

**Output Formats**:
- **US Format**: `"2:30 PM"` (default)
- **24-hour**: `"14:30"`

**iOS Implementation Notes**:
- Updates when form loads
- Can update periodically if autoUpdate enabled
- Use local timezone
- Read-only field

**Configuration Options**:
- `smartConfig.format`: `"US"`, `"24-hour"`
- `smartConfig.autoUpdate`: boolean

---

### 4. Photographer Name (`user_name`)

**Purpose**: Auto-fills the current user's name.

**Data Sources**:
- **User Profile**: `userProfile.firstName` + `userProfile.lastName` (from Firestore)
- **Fallback**: `smartConfig.fallbackValue` or "Photographer"

**Calculation Logic**:
```swift
func calculatePhotographerName() -> String {
    let firstName = userProfile.firstName ?? ""
    let lastName = userProfile.lastName ?? ""
    
    if !firstName.isEmpty && !lastName.isEmpty {
        return "\(firstName) \(lastName)"
    } else if !firstName.isEmpty {
        return firstName
    } else {
        return smartConfig.fallbackValue ?? "Photographer"
    }
}
```

**Output Format**: `"John Smith"` or `"John"` or fallback value

**iOS Implementation Notes**:
- Loads once when form initializes
- Does not update during session
- Read-only field
- Handle missing profile data gracefully

**Error Handling**:
- Missing firstName: Use lastName only
- Missing both: Use fallback value
- No user profile: Show error state

---

### 5. School Name (`school_name`)

**Purpose**: Auto-fills the names of selected schools.

**Data Sources**:
- **Selected Schools**: Array of school objects chosen by user
- Each school has `value` field containing display name

**Calculation Logic**:
```swift
func calculateSchoolNames(selectedSchools: [School]) -> String {
    let schoolNames = selectedSchools.compactMap { school in
        school.value.isEmpty ? nil : school.value
    }
    
    if schoolNames.isEmpty {
        return smartConfig.fallbackValue ?? "No schools selected"
    }
    
    return schoolNames.joined(separator: ", ")
}
```

**Output Formats**:
- Single school: `"Adams School - Marion"`
- Multiple schools: `"Adams School - Marion, Lincoln Elementary"`
- No selection: Fallback value

**iOS Implementation Notes**:
- Updates when school selection changes
- Auto-updates if smartConfig.autoUpdate = true
- May be editable if readOnly = false
- Show selection interface above this field

**Error Handling**:
- No schools selected: Show fallback message
- Empty school names: Filter out empty values

---

### 6. Current Location (`current_location`)

**Purpose**: Gets the device's current GPS coordinates.

**Data Sources**:
- **Device GPS**: CoreLocation services
- **Permissions**: Location permission required

**Calculation Logic**:
```swift
import CoreLocation

func getCurrentLocation() async -> String {
    guard CLLocationManager.locationServicesEnabled() else {
        return smartConfig.fallbackValue ?? "Location services disabled"
    }
    
    let manager = CLLocationManager()
    
    // Request permission if needed
    if manager.authorizationStatus == .notDetermined {
        manager.requestWhenInUseAuthorization()
    }
    
    guard manager.authorizationStatus == .authorizedWhenInUse || 
          manager.authorizationStatus == .authorizedAlways else {
        return smartConfig.fallbackValue ?? "Location permission denied"
    }
    
    do {
        let location = try await manager.requestLocation()
        let lat = location.coordinate.latitude
        let lng = location.coordinate.longitude
        
        switch smartConfig.format {
        case "coordinates":
            return "\(lat.formatted(.number.precision(.fractionLength(6)))),\(lng.formatted(.number.precision(.fractionLength(6))))"
        default:
            return "\(lat.formatted(.number.precision(.fractionLength(6)))), \(lng.formatted(.number.precision(.fractionLength(6))))"
        }
    } catch {
        return smartConfig.fallbackValue ?? "Location unavailable"
    }
}
```

**Output Formats**:
- **Coordinates**: `"38.321991,-88.867400"` (matches user coordinate format)
- **Readable**: `"38.321991, -88.867400"` (with space)

**iOS Implementation Notes**:
- Requires location permission
- Show permission request if needed
- Cache location for session (don't request repeatedly)
- Show loading indicator while getting location
- Handle all permission states

**Configuration Options**:
- `smartConfig.format`: `"coordinates"` or `"readable"`
- `smartConfig.accuracy`: Location accuracy requirement

**Error Handling**:
- Permission denied: Show clear message
- Location unavailable: Use fallback
- Timeout: Use fallback after reasonable wait

---

### 7. Weather Conditions (`weather_conditions`)

**Purpose**: Gets current weather conditions at user's location.

**Data Sources**:
- **Location**: Device GPS (via Current Location)
- **Weather API**: Open-Meteo (free, no API key required)

**Calculation Logic**:
```swift
func getWeatherConditions() async -> String {
    // First get current location
    guard let location = await getCurrentLocationCoordinates() else {
        return smartConfig.fallbackValue ?? "Location required for weather"
    }
    
    // Call weather API
    let url = "https://api.open-meteo.com/v1/forecast?latitude=\(location.latitude)&longitude=\(location.longitude)&current_weather=true&temperature_unit=fahrenheit"
    
    do {
        let (data, _) = try await URLSession.shared.data(from: URL(string: url)!)
        let weather = try JSONDecoder().decode(WeatherResponse.self, from: data)
        
        let temp = Int(weather.current_weather.temperature.rounded())
        let condition = mapWeatherCode(weather.current_weather.weathercode)
        
        return "\(condition), \(temp)°F"
    } catch {
        return smartConfig.fallbackValue ?? "Weather unavailable"
    }
}

func mapWeatherCode(_ code: Int) -> String {
    switch code {
    case 0: return "Clear"
    case 1: return "Mainly Clear"
    case 2: return "Partly Cloudy"
    case 3: return "Overcast"
    case 45, 48: return "Foggy"
    case 51: return "Light Drizzle"
    case 53: return "Drizzle"
    case 55: return "Heavy Drizzle"
    case 61: return "Light Rain"
    case 63: return "Rain"
    case 65: return "Heavy Rain"
    case 71: return "Light Snow"
    case 73: return "Snow"
    case 75: return "Heavy Snow"
    case 80: return "Rain Showers"
    case 81: return "Heavy Showers"
    case 95: return "Thunderstorm"
    case 96: return "Thunderstorm with Hail"
    default: return "Unknown"
    }
}
```

**Output Format**: `"Sunny, 72°F"` or `"Rain, 45°F"`

**iOS Implementation Notes**:
- Requires location permission (same as current_location)
- Network request required - handle offline state
- Cache weather data (valid for ~15 minutes)
- Show loading state while fetching
- No API key needed for Open-Meteo

**API Details**:
- **URL**: `https://api.open-meteo.com/v1/forecast`
- **Parameters**: `latitude`, `longitude`, `current_weather=true`, `temperature_unit=fahrenheit`
- **Free tier**: 10,000 requests/day
- **Response format**: JSON with current_weather object

**Error Handling**:
- No location: "Location required for weather"
- Network error: "Weather unavailable"
- API error: Use fallback value
- Invalid response: Use fallback value

---

### 8. Photo Count (`photo_count`)

**Purpose**: Counts the number of photos attached to the current report.

**Data Sources**:
- **Attached Photos**: Array of photos selected/uploaded by user
- Real-time count as photos are added/removed

**Calculation Logic**:
```swift
func calculatePhotoCount(attachedPhotos: [PhotoData]) -> String {
    return "\(attachedPhotos.count)"
}
```

**Output Format**: `"5"` (number as string)

**iOS Implementation Notes**:
- Updates in real-time as photos are added/removed
- Auto-updates without user interaction
- Links to photo attachment component
- Read-only field

**Integration Requirements**:
- Connect to photo picker/camera functionality
- Update when photos array changes
- Handle photo deletion
- Show zero when no photos attached

---

## Implementation Checklist

### Required Permissions
- [ ] Location permission (for mileage, current_location, weather)
- [ ] Camera permission (for photo_count integration)

### Firebase Data Requirements
- [ ] User profile with `userCoordinates`, `firstName`, `lastName`
- [ ] Schools collection with `coordinates`, `value`, address fields
- [ ] Proper Firestore security rules

### Error Handling
- [ ] Network connectivity checks
- [ ] Permission request flows
- [ ] Graceful fallbacks for each field type
- [ ] Loading states for async operations

### UI Components
- [ ] Read-only field styling
- [ ] Loading indicators
- [ ] Error state displays
- [ ] Auto-update indicators

### Performance Considerations
- [ ] Cache location data
- [ ] Cache weather data (15-minute expiry)
- [ ] Debounce rapid updates
- [ ] Handle background/foreground app states

This guide provides all the technical details needed to implement each smart field type correctly in iOS, matching the behavior of the web template system.