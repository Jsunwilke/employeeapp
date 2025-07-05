import Foundation
import UIKit
import Anthropic

// Service to handle AI processing of roster images
class ClaudeRosterService {
    static let shared = ClaudeRosterService()
    
    // Claude API key would typically be stored securely or fetched from your backend
    private var apiKey: String {
        // In a real implementation, this would be retrieved from a secure storage
        return ProcessInfo.processInfo.environment["CLAUDE_API_KEY"] ?? "YOUR_CLAUDE_API_KEY_HERE"
    }
    
    // Claude model to use
    private let modelName = "claude-3-7-sonnet-20250219"
    
    // Anthropic client for Claude API
    private lazy var client: Anthropic = {
        let client = Anthropic(apiKey: apiKey)
        return client
    }()
    
    // Extract roster entries from an image
    func extractRosterFromImage(_ image: UIImage, completion: @escaping (Result<[RosterEntry], Error>) -> Void) {
        // First convert image to base64
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            let error = NSError(domain: "ClaudeRosterService", code: 100, 
                                userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to data"])
            completion(.failure(error))
            return
        }
        
        let base64Image = imageData.base64EncodedString()
        
        // Create message content with image
        let content: [MessageContent] = [
            .text("""
            I have a photo of a sports roster. Please extract the following fields for each athlete:
            - Name (Last Name)
            - Subject ID (First Name)
            - Special (can be S for Senior, C for Coach, 8 for 8th Grader)
            - Sport/Team
            
            Format your response as a JSON array of objects, with each object having these fields:
            lastName, firstName, teacher, group
            
            The 'teacher' field should contain the Special code (S, C, 8, etc.)
            The 'group' field should contain the Sport/Team name.
            
            JSON format example:
            ```json
            [
              {
                "lastName": "Smith",
                "firstName": "John",
                "teacher": "S",
                "group": "Basketball"
              },
              {
                "lastName": "Johnson",
                "firstName": "Mary",
                "teacher": "",
                "group": "Volleyball"
              }
            ]
            ```
            
            Only respond with the JSON, nothing else.
            """),
            .image(base64Image)
        ]
        
        // Set up Claude API request
        var request = MessageRequest(
            model: modelName,
            messages: [Message(role: .user, content: content)],
            maxTokens: 4000
        )
        
        // Send request to Claude API
        Task {
            do {
                let response = try await client.messages(request: &request)
                
                // Extract the JSON response from Claude
                if let textContent = response.content.first?.text {
                    // Parse the JSON and create roster entries
                    self.parseJsonToRosterEntries(jsonString: textContent, completion: completion)
                } else {
                    let error = NSError(domain: "ClaudeRosterService", code: 102, 
                                        userInfo: [NSLocalizedDescriptionKey: "No text content in response"])
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
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
                throw NSError(domain: "ClaudeRosterService", code: 103, 
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
            email: "",
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
                    lastName: "Smith",
                    firstName: "John",
                    teacher: "S",
                    group: "Basketball",
                    email: "",
                    phone: "",
                    imageNumbers: "",
                    notes: ""
                ),
                RosterEntry(
                    id: UUID().uuidString,
                    lastName: "Johnson",
                    firstName: "Emily",
                    teacher: "",
                    group: "Basketball",
                    email: "",
                    phone: "",
                    imageNumbers: "",
                    notes: ""
                ),
                RosterEntry(
                    id: UUID().uuidString,
                    lastName: "Williams",
                    firstName: "Michael",
                    teacher: "8",
                    group: "Football",
                    email: "",
                    phone: "",
                    imageNumbers: "",
                    notes: ""
                ),
                RosterEntry(
                    id: UUID().uuidString,
                    lastName: "Davis",
                    firstName: "Sarah",
                    teacher: "",
                    group: "Volleyball",
                    email: "",
                    phone: "",
                    imageNumbers: "",
                    notes: ""
                ),
                RosterEntry(
                    id: UUID().uuidString,
                    lastName: "Miller",
                    firstName: "David",
                    teacher: "C",
                    group: "Football",
                    email: "",
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
}

// Container for when Claude responds with a wrapper object
struct ClaudeResponseContainer: Codable {
    let entries: [ClaudeRosterEntry]
}