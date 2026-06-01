import Foundation
import SwiftUI
import Supabase
import CoreLocation
import MapKit

@MainActor
class TemplateService: ObservableObject {
    static let shared = TemplateService()
    private let supabase = SupabaseManager.shared.client

    @Published var templates: [ReportTemplate] = []
    @Published var isLoading = false
    @Published var errorMessage = ""

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

    /// Fetch templates from Supabase for an organization
    func fetchTemplates(for organizationID: String) async throws -> [ReportTemplate] {
        print("🔍 TemplateService: Fetching templates for organizationID: \(organizationID)")

        do {
            let fetchedTemplates: [ReportTemplate] = try await supabase
                .from("report_templates")
                .select()
                .eq("organization_id", value: organizationID)
                .eq("is_active", value: true)
                .order("created_at", ascending: false)
                .execute()
                .value

            print("📄 TemplateService: Found \(fetchedTemplates.count) templates")

            if fetchedTemplates.isEmpty {
                print("❌ No templates found for organizationID: \(organizationID)")
                throw TemplateError.noTemplatesFound
            }

            self.templates = fetchedTemplates
            return fetchedTemplates

        } catch let error as TemplateError {
            throw error
        } catch {
            print("❌ Error fetching templates: \(error)")
            throw TemplateError.networkError(error)
        }
    }

    /// Get a single template by ID
    func getTemplate(templateId: String) async throws -> ReportTemplate? {
        let templates: [ReportTemplate] = try await supabase
            .from("report_templates")
            .select()
            .eq("id", value: templateId)
            .limit(1)
            .execute()
            .value

        return templates.first
    }

    /// Create a new template
    func createTemplate(_ template: ReportTemplate) async throws -> ReportTemplate {
        isLoading = true
        errorMessage = ""

        defer { isLoading = false }

        // Convert fields array to JSONB format
        let fieldsJSON: [AnyJSON] = template.fields.map { field in
            var fieldDict: [String: AnyJSON] = [
                "id": .string(field.id),
                "type": .string(field.type),
                "label": .string(field.label),
                "required": .bool(field.required)
            ]

            if let options = field.options {
                fieldDict["options"] = .array(options.map { .string($0) })
            }
            if let placeholder = field.placeholder {
                fieldDict["placeholder"] = .string(placeholder)
            }
            if let defaultValue = field.defaultValue {
                fieldDict["defaultValue"] = .string(defaultValue)
            }
            if let readOnly = field.readOnly {
                fieldDict["readOnly"] = .bool(readOnly)
            }
            if let smartConfig = field.smartConfig {
                var smartConfigDict: [String: AnyJSON] = [
                    "calculationType": .string(smartConfig.calculationType),
                    "autoUpdate": .bool(smartConfig.autoUpdate)
                ]
                if let fallbackValue = smartConfig.fallbackValue {
                    smartConfigDict["fallbackValue"] = .string(fallbackValue)
                }
                if let format = smartConfig.format {
                    smartConfigDict["format"] = .string(format)
                }
                fieldDict["smartConfig"] = .object(smartConfigDict)
            }

            return .object(fieldDict)
        }

        // Only include columns that exist in the database schema
        let templateData: [String: AnyJSON] = [
            "id": .string(template.id),
            "organization_id": .string(template.organization_id),
            "name": .string(template.name),
            "sections": .array(fieldsJSON),  // DB uses 'sections', not 'fields'
            "is_active": .bool(template.is_active)
        ]

        do {
            let createdTemplate: ReportTemplate = try await supabase
                .from("report_templates")
                .insert(templateData)
                .select()
                .single()
                .execute()
                .value

            return createdTemplate
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// Update an existing template
    func updateTemplate(_ template: ReportTemplate) async throws {
        isLoading = true
        errorMessage = ""

        defer { isLoading = false }

        // Convert fields array to JSONB format
        let fieldsJSON: [AnyJSON] = template.fields.map { field in
            var fieldDict: [String: AnyJSON] = [
                "id": .string(field.id),
                "type": .string(field.type),
                "label": .string(field.label),
                "required": .bool(field.required)
            ]

            if let options = field.options {
                fieldDict["options"] = .array(options.map { .string($0) })
            }
            if let placeholder = field.placeholder {
                fieldDict["placeholder"] = .string(placeholder)
            }
            if let defaultValue = field.defaultValue {
                fieldDict["defaultValue"] = .string(defaultValue)
            }
            if let readOnly = field.readOnly {
                fieldDict["readOnly"] = .bool(readOnly)
            }
            if let smartConfig = field.smartConfig {
                var smartConfigDict: [String: AnyJSON] = [
                    "calculationType": .string(smartConfig.calculationType),
                    "autoUpdate": .bool(smartConfig.autoUpdate)
                ]
                if let fallbackValue = smartConfig.fallbackValue {
                    smartConfigDict["fallbackValue"] = .string(fallbackValue)
                }
                if let format = smartConfig.format {
                    smartConfigDict["format"] = .string(format)
                }
                fieldDict["smartConfig"] = .object(smartConfigDict)
            }

            return .object(fieldDict)
        }

        // Only include columns that exist in the database schema
        let updateData: [String: AnyJSON] = [
            "name": .string(template.name),
            "sections": .array(fieldsJSON),  // DB uses 'sections', not 'fields'
            "is_active": .bool(template.is_active)
        ]

        do {
            try await supabase
                .from("report_templates")
                .update(updateData)
                .eq("id", value: template.id)
                .execute()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// Delete a template
    func deleteTemplate(templateId: String) async throws {
        isLoading = true
        errorMessage = ""

        defer { isLoading = false }

        do {
            try await supabase
                .from("report_templates")
                .delete()
                .eq("id", value: templateId)
                .execute()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
    
    func loadTemplatesAsync() {
        guard !storedUserOrganizationID.isEmpty else {
            self.errorMessage = "No organization ID found"
            return
        }

        isLoading = true
        errorMessage = ""

        Task {
            do {
                _ = try await fetchTemplates(for: storedUserOrganizationID)
                self.isLoading = false
            } catch {
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - School Data Loading

    /// Load schools from Supabase via SchoolService
    func loadSchools() async throws -> [SchoolItem] {
        guard !storedUserOrganizationID.isEmpty else {
            throw TemplateError.noOrganization
        }

        // Use SchoolService to get schools from Supabase
        let schools = try await SchoolService.shared.getSchools(organizationID: storedUserOrganizationID)

        // Convert School models to SchoolItem for template use
        let schoolItems = schools.map { school -> SchoolItem in
            // Build address from available fields
            var addressComponents: [String] = []
            if let street = school.street, !street.isEmpty {
                addressComponents.append(street)
            }
            if let city = school.city, !city.isEmpty {
                addressComponents.append(city)
            }
            if let state = school.state, !state.isEmpty {
                addressComponents.append(state)
            }
            if let zip = school.zip, !zip.isEmpty {
                addressComponents.append(zip)
            }

            let address = addressComponents.isEmpty ? school.value : addressComponents.joined(separator: ", ")

            return SchoolItem(
                id: school.id,
                name: school.value,
                address: address,
                coordinates: school.coordinates
            )
        }

        self.schoolOptions = schoolItems
        return schoolItems
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

    /// Submit a template-based report using DailyJobReportService
    func submitTemplateReport(
        template: ReportTemplate,
        formData: [String: Any]
    ) async throws -> String {
        guard let currentUserId = UserManager.shared.getCurrentUserIDUnified() else {
            throw TemplateError.permissionDenied
        }

        let yourName = "\(storedUserFirstName) \(storedUserLastName)".trimmingCharacters(in: .whitespaces)

        // Extract fields from formData that map to DailyJobReport fields
        let schoolOrDestination = formData["schoolOrDestination"] as? String
            ?? formData["school_or_destination"] as? String
            ?? (formData["selectedSchools"] as? [SchoolItem])?.map { $0.name }.joined(separator: ", ")

        let totalMileage = formData["totalMileage"] as? Double
            ?? formData["total_mileage"] as? Double
            ?? (formData["mileage"] as? String).flatMap { Double($0) }
            ?? 0.0

        let photoURLs = formData["photoURLs"] as? [String]
            ?? formData["photo_urls"] as? [String]
            ?? []

        let jobDescriptions = formData["jobDescriptions"] as? [String]
            ?? formData["job_descriptions"] as? [String]

        let extraItems = formData["extraItems"] as? [String]
            ?? formData["extra_items"] as? [String]

        let jobDescriptionText = formData["jobDescriptionText"] as? String
            ?? formData["job_description_text"] as? String
            ?? formData["notes"] as? String

        // Session link captured by TemplateFormView (SR1); nil for off-schedule
        let sessionId = formData["session_id"] as? String
        let sessionName = formData["session_name"] as? String

        // Convert form data to AnyCodable for storage
        var formDataAnyCodable: [String: AnyCodable] = [:]
        for (key, value) in formData {
            formDataAnyCodable[key] = AnyCodable(value)
        }

        // Build the report
        let report = DailyJobReport(
            id: UUID().uuidString,
            organizationID: storedUserOrganizationID,
            userId: currentUserId,
            date: Date(),
            yourName: yourName.isEmpty ? storedUserFirstName : yourName,
            schoolOrDestination: schoolOrDestination,
            sessionId: sessionId,
            sessionName: sessionName,
            totalMileage: totalMileage,
            jobDescriptions: jobDescriptions,
            extraItems: extraItems,
            jobDescriptionText: jobDescriptionText,
            photoURLs: photoURLs,
            templateId: template.id,
            templateName: template.name,
            templateVersion: template.version,
            reportType: "template",
            smartFieldsUsed: template.fields.compactMap { $0.smartConfig != nil ? $0.id : nil },
            formData: formDataAnyCodable
        )

        // Use DailyJobReportService to create the report
        let createdReport = try await DailyJobReportService.shared.createReport(report)
        return createdReport.id
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