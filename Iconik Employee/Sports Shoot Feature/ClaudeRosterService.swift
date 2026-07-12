//
//  ClaudeRosterService.swift
//  Iconik Employee
//
//  Updated with improved roster extraction prompt
//

import Foundation
import UIKit
import Supabase
import Vision
import SystemConfiguration

// Service to handle AI processing of roster images
class ClaudeRosterService {
    static let shared = ClaudeRosterService()

    // Flag for debugging
    private let debugMode = true

    // Initialize and clear any old cached API keys from UserDefaults
    init() {
        // Clear the old cached key from UserDefaults to force fresh retrieval from Info.plist/Config.xcconfig
        UserDefaults.standard.removeObject(forKey: "CLAUDE_API_KEY")
        if debugMode {
        }
    }
    
    // MARK: - Claude access via server-side proxy
    //
    // The Anthropic key used to live in the app_config table (readable by
    // EVERY authenticated employee) and was cached in UserDefaults. It now
    // lives ONLY as a secret on the `claude-proxy` Supabase Edge Function.
    // The app authenticates to the proxy with the signed-in user's Supabase
    // JWT and never sees the Anthropic key.

    private var proxyURL: URL? {
        URL(string: "\(AppEnvironment.current.supabaseURL)/functions/v1/claude-proxy")
    }

    /// Current user's access token, falling back to the anon key so the
    /// request still reaches the gateway (which rejects it if the proxy
    /// requires an authenticated user).
    private func currentAccessToken() async -> String {
        if let token = try? await SupabaseManager.shared.client.auth.session.accessToken {
            return token
        }
        return AppEnvironment.current.supabaseAnonKey
    }

    /// Build a POST request to the claude-proxy Edge Function carrying an
    /// Anthropic Messages API body. Returns nil if the URL is malformed or
    /// the body can't be serialized.
    private func buildProxyRequest(body: [String: Any], accessToken: String) -> URLRequest? {
        guard let url = proxyURL,
              let httpBody = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(AppEnvironment.current.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.httpBody = httpBody
        return request
    }

    // Claude model to use
    private let modelName = "claude-sonnet-4-6"  // Sonnet 4.6 - far less overloaded than Opus, fully capable for printed text
    
    // Get the next available Subject ID from existing roster
    func getNextAvailableSubjectID(existingRoster: [RosterEntry]) -> Int {
        // Find the highest Subject ID (First Name) value
        let highestID = existingRoster.compactMap { entry -> Int? in
            return Int(entry.firstName)
        }.max() ?? 100 // Start at 101 if no existing entries
        
        return highestID + 1
    }
    
    // Extract roster entries from an image - with a starting Subject ID and sportsJobId
    func extractRosterFromImage(_ image: UIImage, sportsJobId: UUID = UUID(), organizationId: String = "", startingSubjectID: Int = 101, completion: @escaping (Result<[RosterEntry], Error>) -> Void) {
        // The Claude key lives server-side now — go straight to extraction
        // through the proxy. No client-side key fetch or validation.
        proceedWithRosterExtraction(image, sportsJobId: sportsJobId, organizationId: organizationId, startingSubjectID: startingSubjectID, completion: completion)
    }
    
    // Helper function to compress image to stay under 5MB limit
    private func compressImageForAPI(_ image: UIImage) -> Data? {
        let maxSizeInBytes = 4 * 1024 * 1024 // 4MB to leave buffer (API limit is 5MB)
        let compressionQualities: [CGFloat] = [0.9, 0.7, 0.5, 0.3, 0.15, 0.1]
        
        // Try different compression qualities
        for quality in compressionQualities {
            if let imageData = image.jpegData(compressionQuality: quality) {
                let sizeInMB = Double(imageData.count) / (1024.0 * 1024.0)
                
                if debugMode {
                }
                
                if imageData.count <= maxSizeInBytes {
                    return imageData
                }
            }
        }
        
        // If still too large, resize the image
        let maxDimension: CGFloat = 1600 // Reduced to minimize API payload size and avoid 529 overloaded errors
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height)
        
        if scale < 1.0 {
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            if debugMode {
            }
            
            // Try compression again on resized image
            if let resizedImage = resizedImage {
                for quality in compressionQualities {
                    if let imageData = resizedImage.jpegData(compressionQuality: quality) {
                        let sizeInMB = Double(imageData.count) / (1024.0 * 1024.0)
                        
                        if debugMode {
                        }
                        
                        if imageData.count <= maxSizeInBytes {
                            return imageData
                        }
                    }
                }
            }
        }
        
        return nil
    }
    
    // This is the actual extraction logic, only called once we have a valid API key
    private func proceedWithRosterExtraction(_ image: UIImage, sportsJobId: UUID, organizationId: String = "", startingSubjectID: Int, retryCount: Int = 0, completion: @escaping (Result<[RosterEntry], Error>) -> Void) {
        // Convert and compress image to stay under 5MB
        guard let imageData = compressImageForAPI(image) else {
            let error = NSError(domain: "ClaudeRosterService", code: 100,
                                userInfo: [NSLocalizedDescriptionKey: "Failed to compress image to acceptable size (under 5MB)"])
            completion(.failure(error))
            return
        }

        let base64Image = imageData.base64EncodedString()

        // Updated prompt to match the requirements
        let promptText = """
        I have a photo of a sports team roster. Please extract athlete information from this image. For each athlete:

        1. Extract their full name.
        2. For 8th graders, mark their grade as "8".
        3. For 12th graders or seniors, mark their grade as "s" (lowercase).
        4. For coaches, mark them as "c" (lowercase).
        5. Leave grade blank for all other grades.
        6. Extract the sport/team name (should be the same for all athletes in this roster).
        7. Extract email addresses if present.

        Format your response as a JSON array of objects. Each object should have these fields:
        - "lastName": The athlete's full name in UPPERCASE (e.g., "JOHN SMITH")
        - "firstName": A sequential ID number starting at \(startingSubjectID) and incrementing by 1 for each athlete
        - "teacher": The special designation ("8" for 8th graders, "s" for seniors, "c" for coaches, or empty string for others)
        - "group": The sport/team name in UPPERCASE
        - "email": Any email address found for the athlete, or empty string if none

        Look for coach indicators like "Coach", "Assistant Coach", "Head Coach", or similar titles next to names.

        Example:
        ```json
        [
          {
            "lastName": "JOHN SMITH",
            "firstName": "101",
            "teacher": "s",
            "group": "BASKETBALL",
            "email": "jsmith@example.com"
          },
          {
            "lastName": "MARY JOHNSON",
            "firstName": "102",
            "teacher": "",
            "group": "BASKETBALL",
            "email": ""
          },
          {
            "lastName": "ROBERT WILLIAMS",
            "firstName": "103",
            "teacher": "c",
            "group": "BASKETBALL",
            "email": "rwilliams@example.com"
          }
        ]
        ```

        Only respond with the JSON, nothing else.
        """
        
        // Create the request body
        let requestBody: [String: Any] = [
            "model": modelName,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "text",
                            "text": promptText
                        ],
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ]
                    ]
                ]
            ],
            "max_tokens": 32000  // Max output for Opus 4.5
        ]
        
        Task { [weak self] in
            guard let self = self else { return }
            let token = await self.currentAccessToken()
            guard let request = self.buildProxyRequest(body: requestBody, accessToken: token) else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "ClaudeRosterService", code: 102,
                        userInfo: [NSLocalizedDescriptionKey: "Could not build request to Claude proxy"])))
                }
                return
            }

            // Make the request
            URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let self = self else { return }

                // Check for network error
                if let error = error {
                    let nsError = NSError(domain: "ClaudeRosterService", code: 103,
                                        userInfo: [NSLocalizedDescriptionKey: "Network error: \(error.localizedDescription)"])
                    DispatchQueue.main.async {
                        completion(.failure(nsError))
                    }
                    return
                }
                
                // Detailed error reporting for debugging
                if self.debugMode {
                    if let httpResponse = response as? HTTPURLResponse {
                    }
                    
                    if let data = data, let responseString = String(data: data, encoding: .utf8) {
                    }
                }
                
                // Check HTTP status code
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode != 200 {
                        // Extract API error message if available
                        var apiMessage: String? = nil
                        if let data = data, let responseJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let error = responseJSON["error"] as? [String: Any],
                           let message = error["message"] as? String {
                            apiMessage = message
                        }

                        // Provide clear, user-friendly error messages based on status code
                        let errorMessage: String
                        switch httpResponse.statusCode {
                        case 400:
                            errorMessage = "Bad request: \(apiMessage ?? "Invalid parameters sent to API")"
                        case 401:
                            errorMessage = "Invalid API key. Please check your Claude API key in Supabase."
                        case 403:
                            errorMessage = "Access denied. The model may not be available for your API key. \(apiMessage ?? "")"
                        case 404:
                            errorMessage = "Model not found: \(self.modelName). Please check the model name is correct."
                        case 429:
                            errorMessage = "Rate limit exceeded. Please wait a moment and try again."
                        case 500:
                            errorMessage = "Claude API server error. Please try again later."
                        case 529:
                            // Retry up to 3 times with escalating delay before surfacing the error
                            if retryCount < 3 {
                                let delay = Double(retryCount + 1) * 2.0  // 2s, 4s, 6s
                                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                                    self.proceedWithRosterExtraction(image, sportsJobId: sportsJobId, organizationId: organizationId, startingSubjectID: startingSubjectID, retryCount: retryCount + 1, completion: completion)
                                }
                                return
                            }
                            errorMessage = "Claude API is overloaded. Please try again in a few minutes."
                        default:
                            errorMessage = apiMessage ?? "HTTP Error \(httpResponse.statusCode)"
                        }

                        let nsError = NSError(domain: "ClaudeRosterService", code: httpResponse.statusCode,
                                            userInfo: [NSLocalizedDescriptionKey: errorMessage])
                        DispatchQueue.main.async {
                            completion(.failure(nsError))
                        }
                        return
                    }
                }
                
                // Process the successful response
                guard let data = data else {
                    let error = NSError(domain: "ClaudeRosterService", code: 105,
                                        userInfo: [NSLocalizedDescriptionKey: "No data received from API"])
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                    return
                }
                
                do {
                    // Parse the JSON response
                    let responseJSON = try JSONSerialization.jsonObject(with: data) as? [String: Any]

                    // Extract the content from the response
                    if let content = responseJSON?["content"] as? [[String: Any]],
                       let firstContent = content.first,
                       let text = firstContent["text"] as? String {

                        // Parse the JSON text to extract roster entries
                        self.parseJsonToRosterEntries(jsonString: text, sportsJobId: sportsJobId, organizationId: organizationId, startingSubjectID: startingSubjectID, completion: completion)
                    } else {
                        let error = NSError(domain: "ClaudeRosterService", code: 106,
                                            userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])
                        DispatchQueue.main.async {
                            completion(.failure(error))
                        }
                    }
                } catch {
                    let nsError = NSError(domain: "ClaudeRosterService", code: 107,
                                        userInfo: [NSLocalizedDescriptionKey: "Failed to parse response: \(error.localizedDescription)"])
                    DispatchQueue.main.async {
                        completion(.failure(nsError))
                    }
                }
            }.resume()
        }
    }

    // Parse JSON string to roster entries
    private func parseJsonToRosterEntries(jsonString: String, sportsJobId: UUID, organizationId: String = "", startingSubjectID: Int, completion: @escaping (Result<[RosterEntry], Error>) -> Void) {
        // Extract JSON from the response if it's wrapped in code blocks
        var cleanedJsonString = jsonString
        if let jsonStartRange = jsonString.range(of: "```json"),
           let jsonEndRange = jsonString.range(of: "```", options: .backwards) {
            let startIndex = jsonString.index(jsonStartRange.upperBound, offsetBy: 0)
            let endIndex = jsonString.index(jsonEndRange.lowerBound, offsetBy: 0)
            cleanedJsonString = String(jsonString[startIndex..<endIndex])
        } else if let jsonStartRange = jsonString.range(of: "```"),
                  let jsonEndRange = jsonString.range(of: "```", options: .backwards) {
            let startIndex = jsonString.index(jsonStartRange.upperBound, offsetBy: 0)
            let endIndex = jsonString.index(jsonEndRange.lowerBound, offsetBy: 0)
            cleanedJsonString = String(jsonString[startIndex..<endIndex])
        }
        
        // Create JSON decoder
        let decoder = JSONDecoder()
        
        do {
            // Create data from JSON string
            guard let jsonData = cleanedJsonString.data(using: .utf8) else {
                throw NSError(domain: "ClaudeRosterService", code: 109,
                              userInfo: [NSLocalizedDescriptionKey: "Failed to convert JSON string to data"])
            }
            
            // Try to decode as direct array first
            do {
                let entries = try decoder.decode([ClaudeRosterEntry].self, from: jsonData)
                var rosterEntries = entries.map { self.convertToRosterEntry($0, sportsJobId: sportsJobId, organizationId: organizationId) }
                // Sort alphabetically by lastName (which contains the full name)
                // Since names are in format "FIRSTNAME LASTNAME", this will sort by first name
                rosterEntries.sort { $0.lastName < $1.lastName }
                // Reassign Subject IDs sequentially after sorting
                for (index, _) in rosterEntries.enumerated() {
                    rosterEntries[index].firstName = String(startingSubjectID + index)
                }
                // Append 10 blank rows after the scanned entries
                let nextSubjectID = startingSubjectID + rosterEntries.count
                let groupName = rosterEntries.first?.groupName ?? ""
                self.appendBlankEntries(to: &rosterEntries, sportsJobId: sportsJobId, organizationId: organizationId, startingFromID: nextSubjectID, groupName: groupName)
                DispatchQueue.main.async {
                    completion(.success(rosterEntries))
                }
            } catch {
                // If direct decoding fails, try to decode with a root container
                do {
                    let container = try decoder.decode(ClaudeResponseContainer.self, from: jsonData)
                    var rosterEntries = container.entries.map { self.convertToRosterEntry($0, sportsJobId: sportsJobId, organizationId: organizationId) }
                    // Sort alphabetically by lastName (which contains the full name)
                    // Since names are in format "FIRSTNAME LASTNAME", this will sort by first name
                    rosterEntries.sort { $0.lastName < $1.lastName }
                    // Reassign Subject IDs sequentially after sorting
                    for (index, _) in rosterEntries.enumerated() {
                        rosterEntries[index].firstName = String(startingSubjectID + index)
                    }
                    // Append 10 blank rows after the scanned entries
                    let nextSubjectID = startingSubjectID + rosterEntries.count
                    let groupName = rosterEntries.first?.groupName ?? ""
                    self.appendBlankEntries(to: &rosterEntries, sportsJobId: sportsJobId, organizationId: organizationId, startingFromID: nextSubjectID, groupName: groupName)
                    DispatchQueue.main.async {
                        completion(.success(rosterEntries))
                    }
                } catch let containerError {
                    DispatchQueue.main.async {
                        completion(.failure(containerError))
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
    }
    
    // Convert Claude entry model to app's RosterEntry model
    // Note: sportsJobId will be set by the caller when saving to the database
    private func convertToRosterEntry(_ claudeEntry: ClaudeRosterEntry, sportsJobId: UUID = UUID(), organizationId: String = "") -> RosterEntry {
        return RosterEntry(
            sportsJobId: sportsJobId,
            organizationId: organizationId,
            lastName: claudeEntry.lastName,
            firstName: claudeEntry.firstName,
            teacher: claudeEntry.teacher,
            groupName: claudeEntry.group.uppercased(),
            email: claudeEntry.email
        )
    }

    // Append blank entries after scanned roster entries
    private func appendBlankEntries(to rosterEntries: inout [RosterEntry], sportsJobId: UUID, organizationId: String = "", startingFromID: Int, groupName: String, count: Int = 10) {
        for i in 0..<count {
            let blankEntry = RosterEntry(
                sportsJobId: sportsJobId,
                organizationId: organizationId,
                lastName: "",
                firstName: String(startingFromID + i),
                teacher: "",
                groupName: groupName,
                email: ""
            )
            rosterEntries.append(blankEntry)
        }
    }
    
    // Mock implementation for testing without using actual API
    // Note: sportsJobId will be set by the caller when saving to the database
    func mockExtractRoster(sportsJobId: UUID = UUID(), completion: @escaping (Result<[RosterEntry], Error>) -> Void) {
        // Simulate network delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            // Create example roster entries
            let rosterEntries = [
                RosterEntry(
                    sportsJobId: sportsJobId,
                    lastName: "SMITH JOHN",
                    firstName: "101",
                    teacher: "s",
                    groupName: "BASKETBALL",
                    email: "jsmith@school.edu"
                ),
                RosterEntry(
                    sportsJobId: sportsJobId,
                    lastName: "JOHNSON EMILY",
                    firstName: "102",
                    teacher: "",
                    groupName: "BASKETBALL"
                ),
                RosterEntry(
                    sportsJobId: sportsJobId,
                    lastName: "WILLIAMS MICHAEL",
                    firstName: "103",
                    teacher: "8",
                    groupName: "FOOTBALL",
                    email: "mwilliams@school.edu"
                ),
                RosterEntry(
                    sportsJobId: sportsJobId,
                    lastName: "DAVIS ROBERT",
                    firstName: "104",
                    teacher: "c",
                    groupName: "BASKETBALL",
                    email: "coach@school.edu"
                )
            ]

            completion(.success(rosterEntries))
        }
    }
}

// MARK: - FP Sports Subject Output Methods (parallel to RosterEntry methods)

extension ClaudeRosterService {

    /// Convert Claude entry to FPSubject (for FP Sports — writes to Production subjects table)
    func convertToFPSubject(_ claudeEntry: ClaudeRosterEntry, galleryId: String, organizationId: String = "") -> FPSubject {
        return FPSubject(
            galleryId: galleryId,
            organizationId: organizationId,
            firstName: "",
            lastName: claudeEntry.lastName,
            grade: "",
            teacher: claudeEntry.teacher,
            homeroom: "",
            studentId: "",
            rosterId: "",
            jerseyNumber: "",
            sport: claudeEntry.group.uppercased(),
            position: "",
            email: claudeEntry.email
        )
    }

    /// Append blank FPSubject entries after scanned ones
    func appendBlankFPSubjects(to subjects: inout [FPSubject], galleryId: String, organizationId: String = "", startingFromID: Int, sport: String, count: Int = 10) {
        for i in 0..<count {
            let blank = FPSubject(
                galleryId: galleryId,
                organizationId: organizationId,
                firstName: "",
                lastName: "",
                grade: "",
                teacher: "",
                homeroom: "",
                studentId: "",
                rosterId: String(startingFromID + i),
                jerseyNumber: "",
                sport: sport
            )
            subjects.append(blank)
        }
    }

    /// Extract roster from image and return as FPSubjects.
    /// Parses Claude's response and maps to FPSubject with actual first/last names
    /// (not the old Captura convention of full name in lastName).
    func extractSubjectsFromImage(
        _ image: UIImage,
        galleryId: String,
        organizationId: String,
        startingSubjectID: Int,
        completion: @escaping (Result<[FPSubject], Error>) -> Void
    ) {
        extractRosterFromImage(image, sportsJobId: UUID(), organizationId: organizationId, startingSubjectID: startingSubjectID) { result in
            switch result {
            case .success(let rosterEntries):
                var id = startingSubjectID
                var subjects: [FPSubject] = rosterEntries.map { entry in
                    // Claude returns full name in lastName field (e.g. "JOHN SMITH")
                    // Split into actual first and last name for FP Sports
                    let nameParts = entry.lastName.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
                    let first: String
                    let last: String
                    if nameParts.count >= 2 {
                        first = String(nameParts[0])
                        last = String(nameParts[1])
                    } else {
                        first = ""
                        last = String(nameParts.first ?? "")
                    }

                    let subject = FPSubject(
                        galleryId: galleryId,
                        organizationId: organizationId,
                        firstName: first,
                        lastName: last,
                        grade: "",
                        teacher: entry.teacher,
                        homeroom: "",
                        studentId: "",
                        rosterId: String(id),
                        jerseyNumber: "",
                        sport: entry.groupName,
                        position: "",
                        email: entry.email
                    )
                    id += 1
                    return subject
                }
                // Append blank entries
                let sport = subjects.first?.sport ?? ""
                self.appendBlankFPSubjects(to: &subjects, galleryId: galleryId, organizationId: organizationId, startingFromID: id, sport: sport)
                completion(.success(subjects))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Portrait Card Extraction

    /// Result includes whether on-device OCR was used (so caller can show a warning)
    struct PortraitCardResult {
        let subject: FPSubject
        let usedOnDeviceOCR: Bool
    }

    /// Extract student info from a handwritten portrait card (US card, walk-in card).
    /// Uses Claude API when online, falls back to on-device Vision OCR when offline.
    func extractPortraitCard(
        _ image: UIImage,
        galleryId: String,
        organizationId: String,
        completion: @escaping (Result<PortraitCardResult, Error>) -> Void
    ) {
        // Check internet connectivity
        let isOnline = isNetworkAvailable()

        if isOnline {
            // Try Claude via the proxy; fall back to on-device OCR on failure.
            proceedWithPortraitCardExtraction(image, galleryId: galleryId, organizationId: organizationId) { [weak self] result in
                switch result {
                case .success(let subject):
                    completion(.success(PortraitCardResult(subject: subject, usedOnDeviceOCR: false)))
                case .failure(let error):
                    // Claude failed (maybe brief connectivity loss) — fall back to on-device
                    if self?.debugMode == true { print("[ClaudeRosterService] Claude proxy failed, falling back to on-device OCR: \(error.localizedDescription)") }
                    self?.extractWithOnDeviceOCR(image, galleryId: galleryId, organizationId: organizationId, completion: completion)
                }
            }
        } else {
            // Offline — use on-device OCR
            extractWithOnDeviceOCR(image, galleryId: galleryId, organizationId: organizationId, completion: completion)
        }
    }

    private func isNetworkAvailable() -> Bool {
        // Simple reachability check — try to resolve a hostname
        let host = "api.anthropic.com"
        guard let ref = SCNetworkReachabilityCreateWithName(nil, host) else { return false }
        var flags = SCNetworkReachabilityFlags()
        guard SCNetworkReachabilityGetFlags(ref, &flags) else { return false }
        return flags.contains(.reachable) && !flags.contains(.connectionRequired)
    }

    // MARK: - On-Device OCR (Vision framework — works offline)

    private func extractWithOnDeviceOCR(
        _ image: UIImage,
        galleryId: String,
        organizationId: String,
        completion: @escaping (Result<PortraitCardResult, Error>) -> Void
    ) {
        guard let cgImage = image.cgImage else {
            completion(.failure(NSError(domain: "ClaudeRosterService", code: 110,
                userInfo: [NSLocalizedDescriptionKey: "Could not get CGImage from scanned image"])))
            return
        }

        let request = VNRecognizeTextRequest { request, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    completion(.failure(NSError(domain: "ClaudeRosterService", code: 111,
                        userInfo: [NSLocalizedDescriptionKey: "No text recognized on card"])))
                    return
                }

                // Collect all recognized lines
                let lines = observations.compactMap { obs -> String? in
                    obs.topCandidates(1).first?.string
                }.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

                if self.debugMode { print("[ClaudeRosterService] On-device OCR lines: \(lines)") }

                // Parse lines into fields using heuristics
                let subject = self.parseOCRLines(lines, galleryId: galleryId, organizationId: organizationId)
                completion(.success(PortraitCardResult(subject: subject, usedOnDeviceOCR: true)))
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }

    /// Parse OCR text lines into subject fields using simple heuristics.
    /// Looks for labeled fields (e.g. "Name: John Smith") or positional guesses.
    private func parseOCRLines(_ lines: [String], galleryId: String, organizationId: String) -> FPSubject {
        var firstName = ""
        var lastName = ""
        var grade = ""
        var teacher = ""
        var studentId = ""

        for line in lines {
            let lower = line.lowercased().trimmingCharacters(in: .whitespaces)

            // Try labeled patterns: "Name: ...", "Grade: ...", "Teacher: ...", "ID: ..."
            if lower.hasPrefix("name") || lower.hasPrefix("student name") {
                let value = extractAfterLabel(line)
                let parts = value.split(separator: " ", maxSplits: 1)
                if parts.count >= 2 {
                    firstName = String(parts[0])
                    lastName = String(parts[1])
                } else if parts.count == 1 {
                    lastName = String(parts[0])
                }
            } else if lower.hasPrefix("first") {
                firstName = extractAfterLabel(line)
            } else if lower.hasPrefix("last") {
                lastName = extractAfterLabel(line)
            } else if lower.hasPrefix("grade") || lower.hasPrefix("gr") {
                grade = extractAfterLabel(line)
            } else if lower.hasPrefix("teacher") || lower.hasPrefix("tchr") || lower.hasPrefix("hr") || lower.hasPrefix("homeroom") {
                teacher = extractAfterLabel(line)
            } else if lower.hasPrefix("id") || lower.hasPrefix("student id") || lower.hasPrefix("sid") {
                studentId = extractAfterLabel(line)
            }
        }

        // If no labeled fields found, try positional: first line = name, second = grade/teacher
        if firstName.isEmpty && lastName.isEmpty && lines.count >= 1 {
            let parts = lines[0].split(separator: " ", maxSplits: 1)
            if parts.count >= 2 {
                firstName = String(parts[0])
                lastName = String(parts[1])
            } else if parts.count == 1 {
                lastName = String(parts[0])
            }
        }
        if grade.isEmpty && teacher.isEmpty && lines.count >= 2 {
            // Second line might be grade or teacher
            let second = lines[1].trimmingCharacters(in: .whitespaces)
            if second.count <= 3 || second.allSatisfy({ $0.isNumber || $0 == "K" || $0 == "k" }) {
                grade = second
            } else {
                teacher = second
            }
        }
        if grade.isEmpty && lines.count >= 3 {
            grade = lines[2].trimmingCharacters(in: .whitespaces)
        }

        return FPSubject(
            galleryId: galleryId,
            organizationId: organizationId,
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            lastName: lastName.trimmingCharacters(in: .whitespaces),
            grade: grade.trimmingCharacters(in: .whitespaces),
            teacher: teacher.trimmingCharacters(in: .whitespaces),
            studentId: studentId.trimmingCharacters(in: .whitespaces)
        )
    }

    /// Extract the value after a label like "Name: John Smith" → "John Smith"
    private func extractAfterLabel(_ line: String) -> String {
        if let colonRange = line.range(of: ":") {
            return String(line[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        // Try space after first word
        let parts = line.split(separator: " ", maxSplits: 1)
        return parts.count >= 2 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
    }

    private func proceedWithPortraitCardExtraction(
        _ image: UIImage,
        galleryId: String,
        organizationId: String,
        completion: @escaping (Result<FPSubject, Error>) -> Void
    ) {
        guard let imageData = compressImageForAPI(image) else {
            completion(.failure(NSError(domain: "ClaudeRosterService", code: 100,
                userInfo: [NSLocalizedDescriptionKey: "Failed to compress image"])))
            return
        }

        let base64Image = imageData.base64EncodedString()

        let promptText = """
        This is a photo of a handwritten student portrait card. Please extract the student's information.

        Extract these fields:
        - "firstName": The student's first name
        - "lastName": The student's last name
        - "grade": The student's grade level (e.g. "3", "K", "Pre-K", "10")
        - "teacher": The student's teacher name
        - "studentId": Any student ID number if written on the card

        Format your response as a single JSON object. Use empty string for any field you cannot read.

        Example:
        ```json
        {
          "firstName": "Emma",
          "lastName": "Johnson",
          "grade": "3",
          "teacher": "Mrs. Smith",
          "studentId": "12345"
        }
        ```

        Only respond with the JSON, nothing else.
        """

        let requestBody: [String: Any] = [
            "model": modelName,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": promptText],
                        ["type": "image", "source": [
                            "type": "base64",
                            "media_type": "image/jpeg",
                            "data": base64Image
                        ]]
                    ]
                ]
            ],
            "max_tokens": 500
        ]

        Task { [weak self] in
            guard let self = self else { return }
            let token = await self.currentAccessToken()
            guard let request = self.buildProxyRequest(body: requestBody, accessToken: token) else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "ClaudeRosterService", code: 103,
                        userInfo: [NSLocalizedDescriptionKey: "Could not build request to Claude proxy"])))
                }
                return
            }

            URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                guard let data = data else {
                    completion(.failure(NSError(domain: "ClaudeRosterService", code: 104,
                        userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                    return
                }

                // Parse Claude response
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let content = json["content"] as? [[String: Any]],
                       let textBlock = content.first(where: { ($0["type"] as? String) == "text" }),
                       let text = textBlock["text"] as? String {

                        // Extract JSON from response (may be wrapped in ```json ... ```)
                        let cleaned = text
                            .replacingOccurrences(of: "```json", with: "")
                            .replacingOccurrences(of: "```", with: "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)

                        if let cardData = cleaned.data(using: .utf8),
                           let cardJson = try JSONSerialization.jsonObject(with: cardData) as? [String: String] {
                            let subject = FPSubject(
                                galleryId: galleryId,
                                organizationId: organizationId,
                                firstName: cardJson["firstName"] ?? "",
                                lastName: cardJson["lastName"] ?? "",
                                grade: cardJson["grade"] ?? "",
                                teacher: cardJson["teacher"] ?? "",
                                studentId: cardJson["studentId"] ?? ""
                            )
                            completion(.success(subject))
                        } else {
                            completion(.failure(NSError(domain: "ClaudeRosterService", code: 105,
                                userInfo: [NSLocalizedDescriptionKey: "Could not parse card data from response"])))
                        }
                    } else {
                        // Check for error response
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let errorObj = json["error"] as? [String: Any],
                           let message = errorObj["message"] as? String {
                            completion(.failure(NSError(domain: "ClaudeRosterService", code: 106,
                                userInfo: [NSLocalizedDescriptionKey: message])))
                        } else {
                            completion(.failure(NSError(domain: "ClaudeRosterService", code: 105,
                                userInfo: [NSLocalizedDescriptionKey: "Unexpected API response format"])))
                        }
                    }
                } catch {
                    completion(.failure(error))
                }
            }
            }.resume()
        }
    }

    /// Mock extraction returning FPSubjects
    func mockExtractFPSubjects(galleryId: String, organizationId: String = "", completion: @escaping (Result<[FPSubject], Error>) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let subjects = [
                FPSubject(galleryId: galleryId, organizationId: organizationId, firstName: "", lastName: "SMITH JOHN", grade: "", teacher: "s", homeroom: "", studentId: "", rosterId: "101", jerseyNumber: "", sport: "BASKETBALL", position: "", email: "jsmith@school.edu"),
                FPSubject(galleryId: galleryId, organizationId: organizationId, firstName: "", lastName: "JOHNSON EMILY", grade: "", teacher: "", homeroom: "", studentId: "", rosterId: "102", jerseyNumber: "", sport: "BASKETBALL"),
                FPSubject(galleryId: galleryId, organizationId: organizationId, firstName: "", lastName: "WILLIAMS MICHAEL", grade: "", teacher: "8", homeroom: "", studentId: "", rosterId: "103", jerseyNumber: "", sport: "FOOTBALL", position: "", email: "mwilliams@school.edu"),
                FPSubject(galleryId: galleryId, organizationId: organizationId, firstName: "", lastName: "DAVIS ROBERT", grade: "", teacher: "c", homeroom: "", studentId: "", rosterId: "104", jerseyNumber: "", sport: "BASKETBALL", position: "", email: "coach@school.edu"),
            ]
            completion(.success(subjects))
        }
    }
}

// Claude response models
struct ClaudeRosterEntry: Codable {
    let lastName: String
    let firstName: String
    let teacher: String
    let group: String
    let email: String
    
    // Initialize with default values for optional fields
    init(lastName: String, firstName: String, teacher: String, group: String, email: String = "") {
        self.lastName = lastName
        self.firstName = firstName
        self.teacher = teacher
        self.group = group
        self.email = email
    }
}

// Container for when Claude responds with a wrapper object
struct ClaudeResponseContainer: Codable {
    let entries: [ClaudeRosterEntry]
}
