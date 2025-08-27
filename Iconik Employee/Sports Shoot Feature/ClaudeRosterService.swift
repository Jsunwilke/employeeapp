//
//  ClaudeRosterService.swift
//  Iconik Employee
//
//  Updated with improved roster extraction prompt
//

import Foundation
import UIKit
import Firebase
import FirebaseFirestore

// Service to handle AI processing of roster images
class ClaudeRosterService {
    static let shared = ClaudeRosterService()
    
    // Flag for debugging
    private let debugMode = true
    
    // Claude API key from Info.plist (compiled from Config.xcconfig)
    private var apiKey: String {
        // First check Info.plist for the API key
        if let infoPlistKey = Bundle.main.object(forInfoDictionaryKey: "CLAUDE_API_KEY") as? String, !infoPlistKey.isEmpty {
            if debugMode {
                print("Using API key from Info.plist: \(infoPlistKey.prefix(5))...")
            }
            return infoPlistKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Fallback to UserDefaults for existing installations
        if let key = UserDefaults.standard.string(forKey: "CLAUDE_API_KEY"), !key.isEmpty {
            if debugMode {
                print("Using API key from UserDefaults: \(key.prefix(5))...")
            }
            return key.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Try to load from environment (development only)
        if let envKey = ProcessInfo.processInfo.environment["CLAUDE_API_KEY"], !envKey.isEmpty {
            if debugMode {
                print("Using API key from Environment: \(envKey.prefix(5))...")
            }
            return envKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Then try the organization-level settings - this is a placeholder
        // The actual key will be fetched asynchronously by fetchAPIKeyFromFirestore
        if debugMode {
            print("No API key found in Info.plist or UserDefaults. Will try to fetch from Firestore.")
        }
        
        if let cachedKey = self.cachedAPIKey, !cachedKey.isEmpty {
            if debugMode {
                print("Using cached API key: \(cachedKey.prefix(5))...")
            }
            return cachedKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Return an empty string if no key is available yet
        return ""
    }
    
    // Property to cache the API key after fetching from Firestore
    private var cachedAPIKey: String? = nil
    
    // Fetch API key from Firestore organization settings and return it via completion handler
    func fetchAPIKeyFromFirestore(completion: @escaping (String?) -> Void) {
        guard let orgID = UserDefaults.standard.string(forKey: "userOrganizationID"),
              !orgID.isEmpty else {
            if debugMode {
                print("No organization ID found in UserDefaults.")
            }
            completion(nil)
            return
        }
        
        if debugMode {
            print("Fetching API key from Firestore for organization: \(orgID)")
        }
        
        let db = Firestore.firestore()
        db.collection("organizations").document(orgID).getDocument { [weak self] snapshot, error in
            if let error = error {
                print("Error fetching org document: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            if let data = snapshot?.data(),
               let apiKey = data["claudeAPIKey"] as? String,
               !apiKey.isEmpty {
                
                if self?.debugMode == true {
                    print("Successfully retrieved Claude API key from Firestore: \(apiKey.prefix(5))...")
                }
                
                // Store it in UserDefaults for future use (will be replaced by Info.plist value in production)
                UserDefaults.standard.set(apiKey, forKey: "CLAUDE_API_KEY")
                
                // Also cache it in memory
                self?.cachedAPIKey = apiKey
                
                completion(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                if self?.debugMode == true {
                    print("No API key found in organization settings")
                }
                completion(nil)
            }
        }
    }
    
    // Claude model to use
    private let modelName = "claude-3-5-sonnet-20241022"  // Latest Claude 3.5 Sonnet model
    
    // Get the next available Subject ID from existing roster
    func getNextAvailableSubjectID(existingRoster: [RosterEntry]) -> Int {
        // Find the highest Subject ID (First Name) value
        let highestID = existingRoster.compactMap { entry -> Int? in
            return Int(entry.firstName)
        }.max() ?? 100 // Start at 101 if no existing entries
        
        return highestID + 1
    }
    
    // Verify the API key is valid before attempting to use it
    func verifyAPIKey(apiKey: String, completion: @escaping (Bool, String?) -> Void) {
        // Create a simple request to the Anthropic API to check if the key is valid
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            completion(false, "Invalid API URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Use the API key directly in the x-api-key header without "Bearer " prefix
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        
        // Updated API version
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        // Create a minimal valid request body
        let requestBody: [String: Any] = [
            "model": modelName,
            "messages": [
                ["role": "user", "content": [["type": "text", "text": "Hello"]]]
            ],
            "max_tokens": 10
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody, options: [])
            request.httpBody = jsonData
        } catch {
            completion(false, "Error creating request body: \(error.localizedDescription)")
            return
        }
        
        // Make the request
        URLSession.shared.dataTask(with: request) { data, response, error in
            // Check for network error
            if let error = error {
                completion(false, "Network error: \(error.localizedDescription)")
                return
            }
            
            // Check HTTP status code
            if let httpResponse = response as? HTTPURLResponse {
                // Print full response data for debugging
                if self.debugMode, let data = data, let responseString = String(data: data, encoding: .utf8) {
                    print("Full API response: \(responseString)")
                }
                
                if httpResponse.statusCode == 200 {
                    completion(true, nil)
                } else if httpResponse.statusCode == 401 {
                    // API key is invalid
                    var errorMessage = "Invalid API key (HTTP 401)"
                    
                    // Try to extract more detailed error message from response body
                    if let data = data, let responseJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let error = responseJSON["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        errorMessage = message
                    }
                    
                    completion(false, errorMessage)
                } else {
                    var errorMessage = "HTTP Error: \(httpResponse.statusCode)"
                    
                    // Try to extract more detailed error message from response body
                    if let data = data, let responseJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let error = responseJSON["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        errorMessage = message
                    }
                    
                    completion(false, errorMessage)
                }
            } else {
                completion(false, "Invalid response from server")
            }
        }.resume()
    }
    
    // Extract roster entries from an image - with a starting Subject ID
    func extractRosterFromImage(_ image: UIImage, startingSubjectID: Int = 101, completion: @escaping (Result<[RosterEntry], Error>) -> Void) {
        // Get and verify API key first
        if apiKey.isEmpty {
            // Try to fetch the API key from Firestore
            fetchAPIKeyFromFirestore { [weak self] fetchedKey in
                guard let self = self else { return }
                
                if let key = fetchedKey, !key.isEmpty {
                    // Verify the key before using it
                    self.verifyAPIKey(apiKey: key) { isValid, errorMessage in
                        if isValid {
                            // Now try the extraction again with the valid key
                            self.proceedWithRosterExtraction(image, startingSubjectID: startingSubjectID, apiKey: key, completion: completion)
                        } else {
                            let error = NSError(domain: "ClaudeRosterService", code: 101,
                                                userInfo: [NSLocalizedDescriptionKey: "API key validation failed: \(errorMessage ?? "Unknown error")"])
                            completion(.failure(error))
                        }
                    }
                } else {
                    let error = NSError(domain: "ClaudeRosterService", code: 101,
                                        userInfo: [NSLocalizedDescriptionKey: "Could not find a valid Claude API key. Please contact your administrator."])
                    completion(.failure(error))
                }
            }
        } else {
            // We have an API key, let's verify it first
            verifyAPIKey(apiKey: apiKey) { [weak self] isValid, errorMessage in
                guard let self = self else { return }
                
                if isValid {
                    self.proceedWithRosterExtraction(image, startingSubjectID: startingSubjectID, apiKey: self.apiKey, completion: completion)
                } else {
                    // The API key we had is invalid
                    // Don't clear from UserDefaults in case it's a temporary issue
                    self.cachedAPIKey = nil
                    
                    let error = NSError(domain: "ClaudeRosterService", code: 101,
                                        userInfo: [NSLocalizedDescriptionKey: "Invalid API key: \(errorMessage ?? "Unknown error"). Please contact your administrator."])
                    completion(.failure(error))
                }
            }
        }
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
                    print("Image size at quality \(quality): \(String(format: "%.2f", sizeInMB)) MB")
                }
                
                if imageData.count <= maxSizeInBytes {
                    return imageData
                }
            }
        }
        
        // If still too large, resize the image
        let maxDimension: CGFloat = 1920 // Reduced from 2048 for better compression
        let scale = min(maxDimension / image.size.width, maxDimension / image.size.height)
        
        if scale < 1.0 {
            let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            
            UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
            image.draw(in: CGRect(origin: .zero, size: newSize))
            let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            if debugMode {
                print("Resized image from \(image.size) to \(newSize)")
            }
            
            // Try compression again on resized image
            if let resizedImage = resizedImage {
                for quality in compressionQualities {
                    if let imageData = resizedImage.jpegData(compressionQuality: quality) {
                        let sizeInMB = Double(imageData.count) / (1024.0 * 1024.0)
                        
                        if debugMode {
                            print("Resized image size at quality \(quality): \(String(format: "%.2f", sizeInMB)) MB")
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
    private func proceedWithRosterExtraction(_ image: UIImage, startingSubjectID: Int, apiKey: String, completion: @escaping (Result<[RosterEntry], Error>) -> Void) {
        // Convert and compress image to stay under 5MB
        guard let imageData = compressImageForAPI(image) else {
            let error = NSError(domain: "ClaudeRosterService", code: 100,
                                userInfo: [NSLocalizedDescriptionKey: "Failed to compress image to acceptable size (under 5MB)"])
            completion(.failure(error))
            return
        }
        
        let sizeInMB = Double(imageData.count) / (1024.0 * 1024.0)
        if debugMode {
            print("Final image size for API: \(String(format: "%.2f", sizeInMB)) MB")
        }
        
        let base64Image = imageData.base64EncodedString()
        
        // Prepare the request to the Anthropic API
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            let error = NSError(domain: "ClaudeRosterService", code: 102,
                                userInfo: [NSLocalizedDescriptionKey: "Invalid API URL"])
            completion(.failure(error))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Use the API key directly in the x-api-key header without "Bearer " prefix
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
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
            "max_tokens": 4000
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody, options: [])
            request.httpBody = jsonData
            
            if debugMode {
                print("Sending request to Claude API with key: \(apiKey.prefix(5))...")
                print("Using starting Subject ID: \(startingSubjectID)")
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
                        print("Claude API response status code: \(httpResponse.statusCode)")
                    }
                    
                    if let data = data, let responseString = String(data: data, encoding: .utf8) {
                        print("Response data: \(responseString.prefix(500))...")
                    }
                }
                
                // Check HTTP status code
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode != 200 {
                        var errorMessage = "HTTP Error: \(httpResponse.statusCode)"
                        
                        // Try to extract more detailed error message from response body
                        if let data = data, let responseJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let error = responseJSON["error"] as? [String: Any],
                           let message = error["message"] as? String {
                            errorMessage = message
                        }
                        
                        let nsError = NSError(domain: "ClaudeRosterService", code: 104,
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
                        self.parseJsonToRosterEntries(jsonString: text, completion: completion)
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
            
        } catch {
            let nsError = NSError(domain: "ClaudeRosterService", code: 108,
                                userInfo: [NSLocalizedDescriptionKey: "Failed to create request: \(error.localizedDescription)"])
            completion(.failure(nsError))
        }
    }
    
    // Parse JSON string to roster entries
    private func parseJsonToRosterEntries(jsonString: String, completion: @escaping (Result<[RosterEntry], Error>) -> Void) {
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
                let rosterEntries = entries.map { self.convertToRosterEntry($0) }
                DispatchQueue.main.async {
                    completion(.success(rosterEntries))
                }
            } catch {
                // If direct decoding fails, try to decode with a root container
                do {
                    let container = try decoder.decode(ClaudeResponseContainer.self, from: jsonData)
                    let rosterEntries = container.entries.map { self.convertToRosterEntry($0) }
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
    private func convertToRosterEntry(_ claudeEntry: ClaudeRosterEntry) -> RosterEntry {
        return RosterEntry(
            id: UUID().uuidString,
            lastName: claudeEntry.lastName,
            firstName: claudeEntry.firstName,
            teacher: claudeEntry.teacher,
            group: claudeEntry.group,
            email: claudeEntry.email,
            phone: "",
            imageNumbers: "",
            notes: ""
        )
    }
    
    // Mock implementation for testing without using actual API
    func mockExtractRoster(completion: @escaping (Result<[RosterEntry], Error>) -> Void) {
        // Simulate network delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            // Create example roster entries
            let rosterEntries = [
                RosterEntry(
                    id: UUID().uuidString,
                    lastName: "SMITH JOHN",
                    firstName: "101",
                    teacher: "s",
                    group: "BASKETBALL",
                    email: "jsmith@school.edu",
                    phone: "",
                    imageNumbers: "",
                    notes: ""
                ),
                RosterEntry(
                    id: UUID().uuidString,
                    lastName: "JOHNSON EMILY",
                    firstName: "102",
                    teacher: "",
                    group: "BASKETBALL",
                    email: "",
                    phone: "",
                    imageNumbers: "",
                    notes: ""
                ),
                RosterEntry(
                    id: UUID().uuidString,
                    lastName: "WILLIAMS MICHAEL",
                    firstName: "103",
                    teacher: "8",
                    group: "FOOTBALL",
                    email: "mwilliams@school.edu",
                    phone: "",
                    imageNumbers: "",
                    notes: ""
                ),
                RosterEntry(
                    id: UUID().uuidString,
                    lastName: "DAVIS ROBERT",
                    firstName: "104",
                    teacher: "c",
                    group: "BASKETBALL",
                    email: "coach@school.edu",
                    phone: "",
                    imageNumbers: "",
                    notes: ""
                )
            ]
            
            completion(.success(rosterEntries))
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
