//
//  AnthropicClient.swift
//  Iconik Employee
//
//  Created by administrator on 5/16/25.
//

import Foundation

// MARK: - Error Handling
struct AnthropicAPIError: Error, LocalizedError {
    enum ErrorType {
        case invalidAPIKey
        case requestFailed
        case responseParsingFailed
        case rateLimitExceeded
        case serverError
        case unknown
    }
    
    let type: ErrorType
    let message: String
    let statusCode: Int?
    
    var errorDescription: String? {
        return message
    }
    
    init(type: ErrorType, message: String, statusCode: Int? = nil) {
        self.type = type
        self.message = message
        self.statusCode = statusCode
    }
}

// MARK: - Anthropic Client
class Anthropic {
    let apiKey: String
    let baseURL = "https://api.anthropic.com/v1/messages"
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func messages(request: inout AnthropicMessageRequest) async throws -> MessageResponse {
        // Create URL
        guard let url = URL(string: baseURL) else {
            throw AnthropicAPIError(type: .requestFailed, message: "Invalid API URL")
        }
        
        // Create URLRequest
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("anthropic-swift/0.1", forHTTPHeaderField: "User-Agent")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        // Add request body
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        urlRequest.httpBody = try encoder.encode(request)
        
        // Send request
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        // Check for HTTP status code
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AnthropicAPIError(type: .requestFailed, message: "Invalid HTTP response")
        }
        
        // Check status code
        switch httpResponse.statusCode {
        case 200..<300:
            // Success, continue
            break
        case 401:
            throw AnthropicAPIError(type: .invalidAPIKey, message: "Invalid API key", statusCode: httpResponse.statusCode)
        case 429:
            throw AnthropicAPIError(type: .rateLimitExceeded, message: "Rate limit exceeded", statusCode: httpResponse.statusCode)
        case 500..<600:
            throw AnthropicAPIError(type: .serverError, message: "Server error", statusCode: httpResponse.statusCode)
        default:
            throw AnthropicAPIError(type: .unknown, message: "Unknown error: \(httpResponse.statusCode)", statusCode: httpResponse.statusCode)
        }
        
        // Decode response
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        do {
            return try decoder.decode(MessageResponse.self, from: data)
        } catch {
            print("Decoding error: \(error)")
            throw AnthropicAPIError(type: .responseParsingFailed, message: "Failed to parse response: \(error.localizedDescription)")
        }
    }
}

// MARK: - Model Definitions

struct AnthropicMessageRequest: Encodable {
    let model: String
    let messages: [AnthropicMessage]
    let maxTokens: Int
    let system: String?
    
    init(model: String, messages: [AnthropicMessage], maxTokens: Int, system: String? = nil) {
        self.model = model
        self.messages = messages
        self.maxTokens = maxTokens
        self.system = system
    }
    
    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case system
    }
}

struct AnthropicMessage: Encodable {
    let role: Role
    let content: [AnthropicMessageContent]
    
    init(role: Role, content: [AnthropicMessageContent]) {
        self.role = role
        self.content = content
    }
}

enum Role: String, Codable {
    case user
    case assistant
}

enum AnthropicMessageContent: Encodable {
    case text(String)
    case image(String)
    
    enum CodingKeys: String, CodingKey {
        case type
        case text
        case source
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let base64Image):
            try container.encode("image", forKey: .type)
            
            // Encode the source object as a nested dictionary
            let sourceDict: [String: String] = [
                "type": "base64",
                "media_type": "image/jpeg",
                "data": base64Image
            ]
            try container.encode(sourceDict, forKey: .source)
        }
    }
    
    var text: String? {
        if case .text(let string) = self {
            return string
        }
        return nil
    }
}

struct MessageResponse: Decodable {
    let id: String
    let type: String
    let role: String
    let content: [ContentBlock]
    let model: String
    let stopReason: String?
    let usage: Usage
    
    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }
    
    struct Usage: Decodable {
        let inputTokens: Int
        let outputTokens: Int
    }
}
