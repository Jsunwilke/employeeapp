import Foundation
import SwiftUI
import Firebase
import FirebaseAuth
import FirebaseFirestore
import CoreLocation
import MapKit

class TemplateService: ObservableObject {
    static let shared = TemplateService()
    
    @Published var templates: [ReportTemplate] = []
    @Published var isLoading = false
    @Published var errorMessage = ""
    
    private let db = Firestore.firestore()
    private let weatherService = WeatherService()
    private var schoolOptions: [SchoolItem] = []
    
    // User profile data for smart fields
    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""
    @AppStorage("userFirstName") private var storedUserFirstName: String = ""
    @AppStorage("userLastName") private var storedUserLastName: String = ""
    @AppStorage("userHomeAddress") private var storedUserHomeAddress: String = ""
    @AppStorage("userCoordinates") private var storedUserCoordinates: String = ""
    
    private init() {}
    
    // MARK: - Template Management
    
    func fetchTemplates(for organizationID: String) async throws -> [ReportTemplate] {
        print("🔍 TemplateService: Fetching templates for organizationID: \(organizationID)")
        
        // Try a simplified query first to see if templates exist at all
        print("🔍 First trying simplified query (organizationID only)...")
        let simplifiedSnapshot = try await db.collection("reportTemplates")
            .whereField("organizationID", isEqualTo: organizationID)
            .getDocuments()
        
        print("📄 Simplified query found \(simplifiedSnapshot.documents.count) documents")
        
        // Now try the full query (but remove ordering by createdAt since it might not exist)
        print("🔍 Now trying full query with filters (no ordering)...")
        var snapshot: QuerySnapshot
        
        do {
            // Try with ordering first
            snapshot = try await db.collection("reportTemplates")
                .whereField("organizationID", isEqualTo: organizationID)
                .whereField("isActive", isEqualTo: true)
                .order(by: "createdAt", descending: true)
                .getDocuments()
        } catch {
            print("⚠️ Query with ordering failed: \(error)")
            print("🔍 Trying query without ordering...")
            // Fall back to query without ordering
            snapshot = try await db.collection("reportTemplates")
                .whereField("organizationID", isEqualTo: organizationID)
                .whereField("isActive", isEqualTo: true)
                .getDocuments()
        }
        
        print("📄 TemplateService: Found \(snapshot.documents.count) documents in reportTemplates collection")
        
        var successfulTemplates: [ReportTemplate] = []
        var failedDecodes = 0
        
        for (index, doc) in snapshot.documents.enumerated() {
            print("📋 Document \(index + 1): ID = \(doc.documentID)")
            let data = doc.data()
            print("📋 Document \(index + 1) fields: \(data.keys.sorted())")
            
            // Log key fields to debug
            if let orgID = data["organizationID"] as? String {
                print("   organizationID: \(orgID)")
            } else {
                print("   ❌ organizationID missing or wrong type")
            }
            
            if let isActive = data["isActive"] as? Bool {
                print("   isActive: \(isActive)")
            } else {
                print("   ❌ isActive missing or wrong type")
            }
            
            if let name = data["name"] as? String {
                print("   name: \(name)")
            } else {
                print("   ❌ name missing or wrong type")
            }
            
            if let fields = data["fields"] as? [[String: Any]] {
                print("   fields: \(fields.count) field(s)")
            } else {
                print("   ❌ fields missing or wrong type")
            }
            
            // Try to decode
            do {
                let template = try doc.data(as: ReportTemplate.self)
                successfulTemplates.append(template)
                print("   ✅ Successfully decoded template: \(template.name)")
            } catch {
                failedDecodes += 1
                print("   ❌ Failed to decode template: \(error)")
                print("   ❌ Full document data: \(data)")
            }
        }
        
        print("📊 TemplateService Summary:")
        print("   Total documents: \(snapshot.documents.count)")
        print("   Successfully decoded: \(successfulTemplates.count)")
        print("   Failed to decode: \(failedDecodes)")
        
        if successfulTemplates.isEmpty {
            if snapshot.documents.isEmpty {
                print("❌ No templates found with filters - organizationID: \(organizationID), isActive: true")
                throw TemplateError.noTemplatesFound
            } else {
                print("❌ Templates found but none could be decoded - data structure mismatch")
                throw TemplateError.invalidTemplate
            }
        }
        
        DispatchQueue.main.async {
            self.templates = successfulTemplates
        }
        
        return successfulTemplates
    }
    
    func loadTemplatesAsync() {
        guard !storedUserOrganizationID.isEmpty else {
            DispatchQueue.main.async {
                self.errorMessage = "No organization ID found"
            }
            return
        }
        
        isLoading = true
        errorMessage = ""
        
        Task {
            do {
                _ = try await fetchTemplates(for: storedUserOrganizationID)
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    // MARK: - School Data Loading
    
    func loadSchools() async throws -> [SchoolItem] {
        guard !storedUserOrganizationID.isEmpty else {
            throw TemplateError.noOrganization
        }
        
        let snapshot = try await db.collection("schools")
            .whereField("organizationID", isEqualTo: storedUserOrganizationID)
            .order(by: "value")
            .getDocuments()
        
        let schools = snapshot.documents.compactMap { doc -> SchoolItem? in
            let data = doc.data()
            guard let id = doc.documentID as String?,
                  let name = data["value"] as? String else { return nil }
            
            // Build address from available fields
            var addressComponents: [String] = []
            if let street = data["street"] as? String, !street.isEmpty {
                addressComponents.append(street)
            }
            if let city = data["city"] as? String, !city.isEmpty {
                addressComponents.append(city)
            }
            if let state = data["state"] as? String, !state.isEmpty {
                addressComponents.append(state)
            }
            if let zipCode = data["zipCode"] as? String, !zipCode.isEmpty {
                addressComponents.append(zipCode)
            }
            
            let address = addressComponents.isEmpty ? name : addressComponents.joined(separator: ", ")
            let coordinates = data["coordinates"] as? String
            
            return SchoolItem(id: id, name: name, address: address, coordinates: coordinates)
        }
        
        self.schoolOptions = schools
        return schools
    }
    
    // MARK: - Smart Field Calculations
    
    func calculateSmartField(_ field: TemplateField, formData: [String: Any] = [:]) -> String {
        guard let smartConfig = field.smartConfig else { return field.defaultValue ?? "" }
        
        do {
            let result = try performSmartCalculation(field, formData: formData)
            return result
        } catch {
            print("Smart field calculation failed for \(field.id): \(error)")
            return smartConfig.fallbackValue ?? "Calculation failed"
        }
    }
    
    private func performSmartCalculation(_ field: TemplateField, formData: [String: Any]) throws -> String {
        guard let smartConfig = field.smartConfig else {
            throw TemplateError.calculationFailed
        }
        
        switch smartConfig.calculationType {
        case "date_auto":
            let date = Date()
            let formatter = DateFormatter()
            
            // Check for format configuration
            let format = smartConfig.format ?? "US"
            
            switch format {
            case "US", "MM/DD/YYYY":
                formatter.dateStyle = .short
                formatter.locale = Locale(identifier: "en_US")
                return formatter.string(from: date) // "7/8/2025"
                
            case "ISO", "YYYY-MM-DD":
                formatter.dateFormat = "yyyy-MM-dd"
                return formatter.string(from: date) // "2025-07-08"
                
            case "medium":
                formatter.dateStyle = .medium
                formatter.locale = Locale(identifier: "en_US")
                return formatter.string(from: date) // "Jul 8, 2025"
                
            default:
                formatter.dateStyle = .short
                formatter.locale = Locale(identifier: "en_US")
                return formatter.string(from: date)
            }
            
        case "time_auto":
            let time = Date()
            let formatter = DateFormatter()
            
            // Check for format configuration
            let format = smartConfig.format ?? "US"
            
            switch format {
            case "US", "12-hour":
                formatter.timeStyle = .short
                formatter.locale = Locale(identifier: "en_US")
                return formatter.string(from: time) // "2:30 PM"
                
            case "24-hour", "HH:mm":
                formatter.dateFormat = "HH:mm"
                return formatter.string(from: time) // "14:30"
                
            default:
                formatter.timeStyle = .short
                formatter.locale = Locale(identifier: "en_US")
                return formatter.string(from: time)
            }
            
        case "user_name":
            let firstName = storedUserFirstName.trimmingCharacters(in: .whitespaces)
            let lastName = storedUserLastName.trimmingCharacters(in: .whitespaces)
            
            if !firstName.isEmpty && !lastName.isEmpty {
                return "\(firstName) \(lastName)"
            } else if !firstName.isEmpty {
                return firstName
            } else if !lastName.isEmpty {
                return lastName
            } else {
                return smartConfig.fallbackValue ?? "Photographer"
            }
            
        case "school_name":
            if let selectedSchools = formData["selectedSchools"] as? [SchoolItem] {
                let schoolNames = selectedSchools.map { $0.name }
                return schoolNames.isEmpty ? (smartConfig.fallbackValue ?? "No schools selected") : schoolNames.joined(separator: ", ")
            } else if let schoolNames = formData["selectedSchools"] as? [String] {
                // Fallback for string array
                return schoolNames.isEmpty ? (smartConfig.fallbackValue ?? "No schools selected") : schoolNames.joined(separator: ", ")
            }
            return smartConfig.fallbackValue ?? "No schools selected"
            
        case "photo_count":
            // Check various possible photo field names
            if let photoURLs = formData["photoURLs"] as? [String] {
                return "\(photoURLs.count)"
            } else if let selectedImages = formData["selectedImages"] as? [Any] {
                return "\(selectedImages.count)"
            } else if let photos = formData["photos"] as? [Any] {
                return "\(photos.count)"
            } else if let attachedPhotos = formData["attachedPhotos"] as? [Any] {
                return "\(attachedPhotos.count)"
            }
            return "0"
            
        case "mileage":
            return calculateMileageSync(formData: formData)
            
        case "weather_conditions":
            // For synchronous context, return placeholder - actual weather needs async
            return smartConfig.fallbackValue ?? "Weather loading..."
            
        case "current_location":
            // For synchronous context, return placeholder
            return smartConfig.fallbackValue ?? "Location pending..."
            
        default:
            throw TemplateError.calculationFailed
        }
    }
    
    private func calculateMileageSync(formData: [String: Any]) -> String {
        // Check if user has coordinates
        guard !storedUserCoordinates.isEmpty else { 
            print("⚠️ Mileage calculation: No user coordinates found")
            return "0.0"
        }
        
        // Parse user coordinates
        let userCoordParts = storedUserCoordinates.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard userCoordParts.count == 2,
              let userLat = Double(userCoordParts[0]),
              let userLng = Double(userCoordParts[1]) else {
            print("⚠️ Mileage calculation: Invalid user coordinates format")
            return "0.0"
        }
        
        // Get selected schools from formData
        guard let selectedSchools = formData["selectedSchools"] as? [SchoolItem], !selectedSchools.isEmpty else {
            print("⚠️ Mileage calculation: No schools selected")
            return "0.0"
        }
        
        // Calculate route: home -> school1 -> school2 -> ... -> home
        var totalDistance: Double = 0.0
        var currentLat = userLat
        var currentLng = userLng
        
        for school in selectedSchools {
            // Try to use school coordinates first
            if let coordString = school.coordinates,
               let schoolCoordinates = parseCoordinateString(coordString) {
                totalDistance += haversineDistance(
                    lat1: currentLat, lon1: currentLng,
                    lat2: schoolCoordinates.latitude, lon2: schoolCoordinates.longitude
                )
                currentLat = schoolCoordinates.latitude
                currentLng = schoolCoordinates.longitude
                print("✅ Mileage: Added school \(school.name) at coordinates \(coordString)")
            } else {
                print("⚠️ Mileage: School \(school.name) has no coordinates, skipping")
            }
        }
        
        // Add return trip to home
        totalDistance += haversineDistance(
            lat1: currentLat, lon1: currentLng,
            lat2: userLat, lon2: userLng
        )
        
        return String(format: "%.1f", totalDistance)
    }
    
    private func calculateStraightLineDistance(from origin: String, to destination: String) -> Double? {
        // Try to parse as coordinates first
        if let originCoord = parseCoordinateString(origin),
           let destCoord = parseCoordinateString(destination) {
            return haversineDistance(
                lat1: originCoord.latitude, lon1: originCoord.longitude,
                lat2: destCoord.latitude, lon2: destCoord.longitude
            )
        }
        
        // For addresses, we'd need geocoding - return nil for now
        // In production, you'd cache geocoded coordinates
        return nil
    }
    
    private func parseCoordinateString(_ text: String) -> CLLocationCoordinate2D? {
        let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              let lat = Double(parts[0]),
              let lon = Double(parts[1]) else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    private func haversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 3959.0 // Earth's radius in miles
        
        let dLat = (lat2 - lat1) * .pi / 180.0
        let dLon = (lon2 - lon1) * .pi / 180.0
        
        let a = sin(dLat/2) * sin(dLat/2) +
                cos(lat1 * .pi / 180.0) * cos(lat2 * .pi / 180.0) *
                sin(dLon/2) * sin(dLon/2)
        let c = 2 * atan2(sqrt(a), sqrt(1-a))
        
        return R * c
    }
    
    
    // MARK: - Form Validation
    
    func validateField(_ field: TemplateField, value: Any?) -> Bool {
        if field.required && (value == nil || isEmpty(value)) {
            return false
        }
        
        switch field.type {
        case "email":
            guard let stringValue = value as? String else { return !field.required }
            return isValidEmail(stringValue)
        case "number":
            return value is Double || value is Int || value is String
        case "phone":
            guard let stringValue = value as? String else { return !field.required }
            return isValidPhoneNumber(stringValue)
        default:
            return true
        }
    }
    
    private func isEmpty(_ value: Any?) -> Bool {
        if let stringValue = value as? String {
            return stringValue.trimmingCharacters(in: .whitespaces).isEmpty
        }
        if let arrayValue = value as? [Any] {
            return arrayValue.isEmpty
        }
        return value == nil
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        return NSPredicate(format: "SELF MATCHES %@", emailRegex).evaluate(with: email)
    }
    
    private func isValidPhoneNumber(_ phone: String) -> Bool {
        let phoneRegex = "^[\\d\\s\\-\\(\\)\\+\\.]{10,}$"
        return NSPredicate(format: "SELF MATCHES %@", phoneRegex).evaluate(with: phone)
    }
    
    // MARK: - Report Submission
    
    func submitTemplateReport(
        template: ReportTemplate,
        formData: [String: Any]
    ) async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw TemplateError.permissionDenied
        }
        
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        
        let reportData: [String: Any] = [
            "organizationID": storedUserOrganizationID,
            "userId": user.uid,
            "date": dateFormatter.string(from: Date()),
            "photographer": "\(storedUserFirstName) \(storedUserLastName)".trimmingCharacters(in: .whitespaces),
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
    
    // MARK: - Weather Integration
    
    func calculateWeatherField(for location: CLLocationCoordinate2D? = nil) async -> String {
        // Get location - either provided or current location
        let coordinates: CLLocationCoordinate2D
        
        if let location = location {
            coordinates = location
        } else {
            // Try to get current location
            do {
                let locationCoords = try await getCurrentLocationCoordinates()
                coordinates = locationCoords
            } catch {
                return "Location required for weather"
            }
        }
        
        // Call Open-Meteo API
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(coordinates.latitude)&longitude=\(coordinates.longitude)&current_weather=true&temperature_unit=fahrenheit"
        
        guard let url = URL(string: urlString) else {
            return "Weather unavailable"
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let weather = try JSONDecoder().decode(WeatherResponse.self, from: data)
            
            let temp = Int(weather.current_weather.temperature.rounded())
            let condition = mapWeatherCode(weather.current_weather.weathercode)
            
            return "\(condition), \(temp)°F"
        } catch {
            print("❌ Weather API error: \(error)")
            return "Weather unavailable"
        }
    }
    
    private func mapWeatherCode(_ code: Int) -> String {
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
    
    private func getCurrentLocationCoordinates() async throws -> CLLocationCoordinate2D {
        // This would need proper CoreLocation implementation
        // For now, throw an error
        throw TemplateError.calculationFailed
    }
}

// MARK: - Template Categories

extension TemplateService {
    func getTemplatesByCategory() -> [String: [ReportTemplate]] {
        let categories = Dictionary(grouping: templates) { template in
            template.shootType.capitalized
        }
        return categories
    }
    
    func getDefaultTemplate(for shootType: String) -> ReportTemplate? {
        return templates.first { $0.shootType == shootType && $0.isDefault }
    }
}