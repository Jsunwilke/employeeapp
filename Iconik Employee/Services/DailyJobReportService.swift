import Foundation
import Supabase

@MainActor
class DailyJobReportService: ObservableObject {
    static let shared = DailyJobReportService()
    private let supabase = SupabaseManager.shared.client

    @Published var reports: [DailyJobReport] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private init() {}

    // MARK: - Decoder Error Helper

    /// Extract detailed information from decoding errors
    private func describeDecodingError(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return error.localizedDescription
        }

        switch decodingError {
        case .keyNotFound(let key, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Missing field '\(key.stringValue)' at: \(path.isEmpty ? "root" : path)"
        case .typeMismatch(let type, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Type mismatch for \(type) at: \(path.isEmpty ? "root" : path) - \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Null value for \(type) at: \(path.isEmpty ? "root" : path)"
        case .dataCorrupted(let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Corrupted data at: \(path.isEmpty ? "root" : path) - \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    // MARK: - Get Reports for User

    /// Get all reports for a specific user in an organization
    func getReports(userId: String, organizationID: String) async throws -> [DailyJobReport] {
        do {
            let reports: [DailyJobReport] = try await supabase
                .from("daily_job_reports")
                .select()
                .eq("user_id", value: userId)
                .eq("organization_id", value: organizationID)
                .order("date", ascending: false)
                .execute()
                .value

            return reports
        } catch {
            print("❌ DailyJobReport decode error: \(describeDecodingError(error))")
            throw error
        }
    }

    // MARK: - Get Reports by Date Range

    /// Get all reports in an organization within a date range
    func getReports(organizationID: String, startDate: Date, endDate: Date) async throws -> [DailyJobReport] {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        let startDateString = dateFormatter.string(from: startDate)
        let endDateString = dateFormatter.string(from: endDate)

        do {
            let reports: [DailyJobReport] = try await supabase
                .from("daily_job_reports")
                .select()
                .eq("organization_id", value: organizationID)
                .gte("date", value: startDateString)
                .lte("date", value: endDateString)
                .order("date", ascending: false)
                .execute()
                .value

            return reports
        } catch {
            print("❌ DailyJobReport decode error (date range): \(describeDecodingError(error))")
            throw error
        }
    }

    // MARK: - Get Reports by Photographer Name (Legacy Support)

    /// Get reports for a specific photographer by name in an organization within a date range
    /// Used for backward compatibility with existing queries that use yourName field
    func getReports(yourName: String, organizationID: String, startDate: Date, endDate: Date) async throws -> [DailyJobReport] {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        let startDateString = dateFormatter.string(from: startDate)
        let endDateString = dateFormatter.string(from: endDate)

        do {
            let reports: [DailyJobReport] = try await supabase
                .from("daily_job_reports")
                .select()
                .eq("organization_id", value: organizationID)
                .eq("your_name", value: yourName)
                .gte("date", value: startDateString)
                .lte("date", value: endDateString)
                .order("date", ascending: false)
                .execute()
                .value

            return reports
        } catch {
            print("❌ DailyJobReport decode error (photographer): \(describeDecodingError(error))")
            throw error
        }
    }

    // MARK: - Get Reports by User ID and Date Range

    /// Get reports for a specific user within a date range
    func getReports(userId: String, startDate: Date, endDate: Date) async throws -> [DailyJobReport] {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        let startDateString = dateFormatter.string(from: startDate)
        let endDateString = dateFormatter.string(from: endDate)

        do {
            let reports: [DailyJobReport] = try await supabase
                .from("daily_job_reports")
                .select()
                .eq("user_id", value: userId)
                .gte("date", value: startDateString)
                .lte("date", value: endDateString)
                .order("date", ascending: false)
                .execute()
                .value

            return reports
        } catch {
            print("❌ DailyJobReport decode error (user+date): \(describeDecodingError(error))")
            throw error
        }
    }

    // MARK: - Check Existing Report for Date

    /// Check if a report already exists for a user on a specific date
    func checkExistingReport(userId: String, date: Date) async throws -> DailyJobReport? {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        let dateString = dateFormatter.string(from: date)

        let reports: [DailyJobReport] = try await supabase
            .from("daily_job_reports")
            .select()
            .eq("user_id", value: userId)
            .eq("date", value: dateString)
            .limit(1)
            .execute()
            .value

        return reports.first
    }

    // MARK: - Get Report by ID

    /// Get a single report by its ID
    func getReport(reportId: String) async throws -> DailyJobReport? {
        let reports: [DailyJobReport] = try await supabase
            .from("daily_job_reports")
            .select()
            .eq("id", value: reportId)
            .limit(1)
            .execute()
            .value

        return reports.first
    }

    // MARK: - Create Report

    /// Create a new daily job report
    func createReport(_ report: DailyJobReport) async throws -> DailyJobReport {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        // Build report data dictionary
        var reportData: [String: AnyJSON] = [
            "id": .string(report.id),
            "organization_id": .string(report.organization_id),
            "user_id": .string(report.user_id),
            "your_name": .string(report.your_name),
            "total_mileage": .double(report.total_mileage)
        ]

        // Handle date - convert to ISO date string for Supabase DATE column
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        reportData["date"] = .string(dateFormatter.string(from: report.date))

        // Add optional fields
        if let schoolOrDestination = report.school_or_destination {
            reportData["school_or_destination"] = .string(schoolOrDestination)
        }

        // Handle JSONB arrays
        if let jobDescriptions = report.job_descriptions {
            reportData["job_descriptions"] = .array(jobDescriptions.map { .string($0) })
        }
        if let extraItems = report.extra_items {
            reportData["extra_items"] = .array(extraItems.map { .string($0) })
        }
        if let photoURLs = report.photo_urls {
            reportData["photo_urls"] = .array(photoURLs.map { .string($0) })
        }
        if let smartFieldsUsed = report.smart_fields_used {
            reportData["smart_fields_used"] = .array(smartFieldsUsed.map { .string($0) })
        }

        // Add string fields if present
        if let cardsScannedChoice = report.cards_scanned_choice {
            reportData["cards_scanned_choice"] = .string(cardsScannedChoice)
        }
        if let jobBoxAndCameraCards = report.job_box_and_camera_cards {
            reportData["job_box_and_camera_cards"] = .string(jobBoxAndCameraCards)
        }
        if let sportsBackgroundShot = report.sports_background_shot {
            reportData["sports_background_shot"] = .string(sportsBackgroundShot)
        }
        if let jobDescriptionText = report.job_description_text {
            reportData["job_description_text"] = .string(jobDescriptionText)
        }
        if let photoshootNoteText = report.photoshoot_note_text {
            reportData["photoshoot_note_text"] = .string(photoshootNoteText)
        }

        // Template fields
        if let templateId = report.template_id {
            reportData["template_id"] = .string(templateId)
        }
        if let templateName = report.template_name {
            reportData["template_name"] = .string(templateName)
        }
        if let templateVersion = report.template_version {
            reportData["template_version"] = .integer(templateVersion)
        }
        if let reportType = report.report_type {
            reportData["report_type"] = .string(reportType)
        }

        // Handle form_data (JSONB object)
        if let formData = report.form_data, !formData.isEmpty {
            // Convert [String: AnyCodable] to AnyJSON
            var formDataJSON: [String: AnyJSON] = [:]
            for (key, value) in formData {
                formDataJSON[key] = convertAnyCodableToAnyJSON(value)
            }
            reportData["form_data"] = .object(formDataJSON)
        }

        // Log photo URLs if present
        if let photoURLs = report.photo_urls, !photoURLs.isEmpty {
            print("📸 DailyJobReport: Saving \(photoURLs.count) photo URL(s)")
            for (index, url) in photoURLs.enumerated() {
                print("   Photo \(index + 1): \(url.prefix(80))...")
            }
        } else {
            print("📋 DailyJobReport: No photos attached")
        }

        do {
            let createdReport: DailyJobReport = try await supabase
                .from("daily_job_reports")
                .insert(reportData)
                .select()
                .single()
                .execute()
                .value

            print("✅ DailyJobReport created successfully with ID: \(createdReport.id)")
            if let savedPhotos = createdReport.photo_urls, !savedPhotos.isEmpty {
                print("   📸 Confirmed \(savedPhotos.count) photo(s) saved")
            }

            return createdReport
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Update Report

    /// Update an existing daily job report
    func updateReport(_ report: DailyJobReport) async throws {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        // Build update data dictionary
        var updateData: [String: AnyJSON] = [
            "your_name": .string(report.your_name),
            "total_mileage": .double(report.total_mileage)
        ]

        // Handle date
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        updateData["date"] = .string(dateFormatter.string(from: report.date))

        // Update optional fields
        if let schoolOrDestination = report.school_or_destination {
            updateData["school_or_destination"] = .string(schoolOrDestination)
        }

        // Handle JSONB arrays
        if let jobDescriptions = report.job_descriptions {
            updateData["job_descriptions"] = .array(jobDescriptions.map { .string($0) })
        }
        if let extraItems = report.extra_items {
            updateData["extra_items"] = .array(extraItems.map { .string($0) })
        }
        if let photoURLs = report.photo_urls {
            updateData["photo_urls"] = .array(photoURLs.map { .string($0) })
        }
        if let smartFieldsUsed = report.smart_fields_used {
            updateData["smart_fields_used"] = .array(smartFieldsUsed.map { .string($0) })
        }

        // Update string fields
        if let cardsScannedChoice = report.cards_scanned_choice {
            updateData["cards_scanned_choice"] = .string(cardsScannedChoice)
        }
        if let jobBoxAndCameraCards = report.job_box_and_camera_cards {
            updateData["job_box_and_camera_cards"] = .string(jobBoxAndCameraCards)
        }
        if let sportsBackgroundShot = report.sports_background_shot {
            updateData["sports_background_shot"] = .string(sportsBackgroundShot)
        }
        if let jobDescriptionText = report.job_description_text {
            updateData["job_description_text"] = .string(jobDescriptionText)
        }
        if let photoshootNoteText = report.photoshoot_note_text {
            updateData["photoshoot_note_text"] = .string(photoshootNoteText)
        }

        // Template fields
        if let templateId = report.template_id {
            updateData["template_id"] = .string(templateId)
        }
        if let templateName = report.template_name {
            updateData["template_name"] = .string(templateName)
        }
        if let templateVersion = report.template_version {
            updateData["template_version"] = .integer(templateVersion)
        }
        if let reportType = report.report_type {
            updateData["report_type"] = .string(reportType)
        }

        // Handle form_data
        if let formData = report.form_data, !formData.isEmpty {
            var formDataJSON: [String: AnyJSON] = [:]
            for (key, value) in formData {
                formDataJSON[key] = convertAnyCodableToAnyJSON(value)
            }
            updateData["form_data"] = .object(formDataJSON)
        }

        do {
            try await supabase
                .from("daily_job_reports")
                .update(updateData)
                .eq("id", value: report.id)
                .execute()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Delete Report

    /// Delete a report by its ID
    func deleteReport(reportId: String) async throws {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            try await supabase
                .from("daily_job_reports")
                .delete()
                .eq("id", value: reportId)
                .execute()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Load Reports with Loading State

    /// Load reports for current user with loading state management
    func loadReports(userId: String, organizationID: String) async {
        isLoading = true
        errorMessage = nil

        do {
            reports = try await getReports(userId: userId, organizationID: organizationID)
        } catch {
            errorMessage = error.localizedDescription
            print("Error loading reports: \(error)")
        }

        isLoading = false
    }

    // MARK: - Helper Methods

    /// Convert AnyCodable to AnyJSON for Supabase
    private func convertAnyCodableToAnyJSON(_ anyCodable: AnyCodable) -> AnyJSON {
        switch anyCodable.value {
        case let intValue as Int:
            return .integer(intValue)
        case let doubleValue as Double:
            return .double(doubleValue)
        case let stringValue as String:
            return .string(stringValue)
        case let boolValue as Bool:
            return .bool(boolValue)
        case let arrayValue as [Any]:
            return .array(arrayValue.map { convertAnyToAnyJSON($0) })
        case let dictValue as [String: Any]:
            var result: [String: AnyJSON] = [:]
            for (key, value) in dictValue {
                result[key] = convertAnyToAnyJSON(value)
            }
            return .object(result)
        default:
            return .null
        }
    }

    /// Convert Any to AnyJSON
    private func convertAnyToAnyJSON(_ value: Any) -> AnyJSON {
        switch value {
        case let intValue as Int:
            return .integer(intValue)
        case let doubleValue as Double:
            return .double(doubleValue)
        case let stringValue as String:
            return .string(stringValue)
        case let boolValue as Bool:
            return .bool(boolValue)
        case let arrayValue as [Any]:
            return .array(arrayValue.map { convertAnyToAnyJSON($0) })
        case let dictValue as [String: Any]:
            var result: [String: AnyJSON] = [:]
            for (key, value) in dictValue {
                result[key] = convertAnyToAnyJSON(value)
            }
            return .object(result)
        case let anyCodable as AnyCodable:
            return convertAnyCodableToAnyJSON(anyCodable)
        default:
            return .null
        }
    }
}

// MARK: - Mileage Query Extensions

extension DailyJobReportService {
    /// Get total mileage for a user in a date range
    func getTotalMileage(userId: String, startDate: Date, endDate: Date) async throws -> Double {
        let reports = try await getReports(userId: userId, startDate: startDate, endDate: endDate)
        return reports.reduce(0.0) { $0 + $1.total_mileage }
    }

    /// Get total mileage for an organization in a date range
    func getTotalMileage(organizationID: String, startDate: Date, endDate: Date) async throws -> Double {
        let reports = try await getReports(organizationID: organizationID, startDate: startDate, endDate: endDate)
        return reports.reduce(0.0) { $0 + $1.total_mileage }
    }

    /// Get mileage by school (aggregated by school_or_destination)
    func getMileageBySchool(organizationID: String, startDate: Date, endDate: Date) async throws -> [String: Double] {
        let reports = try await getReports(organizationID: organizationID, startDate: startDate, endDate: endDate)

        var mileageBySchool: [String: Double] = [:]
        for report in reports {
            if let school = report.school_or_destination, !school.isEmpty {
                mileageBySchool[school, default: 0.0] += report.total_mileage
            }
        }

        return mileageBySchool
    }

    /// Get reports for a specific school within a date range
    func getReportsForSchool(schoolName: String, organizationID: String, startDate: Date, endDate: Date) async throws -> [DailyJobReport] {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        let startDateString = dateFormatter.string(from: startDate)
        let endDateString = dateFormatter.string(from: endDate)

        do {
            let reports: [DailyJobReport] = try await supabase
                .from("daily_job_reports")
                .select()
                .eq("organization_id", value: organizationID)
                .eq("school_or_destination", value: schoolName)
                .gte("date", value: startDateString)
                .lte("date", value: endDateString)
                .order("date", ascending: false)
                .execute()
                .value

            return reports
        } catch {
            print("❌ DailyJobReport decode error (school): \(describeDecodingError(error))")
            throw error
        }
    }

    /// Get total mileage for a specific school within a date range
    func getMileageForSchool(schoolName: String, organizationID: String, startDate: Date, endDate: Date) async throws -> Double {
        let reports = try await getReportsForSchool(schoolName: schoolName, organizationID: organizationID, startDate: startDate, endDate: endDate)
        return reports.reduce(0.0) { $0 + $1.total_mileage }
    }
}
