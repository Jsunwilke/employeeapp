import Foundation
// import GoogleSignIn - REMOVED: Not compatible with Supabase auth flow
// import GoogleAPIClientForREST - REMOVED: Not compatible with Supabase auth flow
import UIKit

/// Service class that handles the business logic for the Gallery Creator feature
///
/// NOTE: Google Sheets integration is currently DISABLED due to removal of GoogleSignIn SDK.
/// The Captura gallery creation still works, but Google Sheets creation/update functionality
/// will fail. To re-enable, implement OAuth using a different approach (e.g., Supabase OAuth +
/// server-side Google API calls, or implement a web-based OAuth flow).
class GalleryCreatorService {
    // MARK: - Shared Instance
    static let shared = GalleryCreatorService()
    
    // MARK: - Properties
    private let capturaTokenURL = "https://api.imagequix.com/api/oauth/token"
    private var createGalleryURL: String = ""

    // API credentials will be fetched from CapturaAPIKeyManager
    private var capturaCredentials: CapturaAPIKeyManager.CapturaCredentials?

    // Debug flag - set to true for verbose logging
    private let debug = true
    
    // MARK: - Initialization
    private init() {
        // createGalleryURL will be set when credentials are loaded
    }
    
    // MARK: - Public Methods
    
    /// Creates a gallery in both Captura and Google Sheets
    /// - Parameters:
    ///   - galleryName: The base name for the gallery
    ///   - eventDate: The date of the event
    ///   - completion: Completion handler with result
    func createGallery(galleryName: String, eventDate: Date, completion: @escaping (Result<GalleryCreationResult, GalleryCreatorError>) -> Void) {
        // First, ensure we have valid credentials
        CapturaAPIKeyManager.shared.getCredentials { [weak self] credentialsResult in
            guard let self = self else { return }
            
            switch credentialsResult {
            case .success(let credentials):
                self.capturaCredentials = credentials
                self.createGalleryURL = "https://api.imagequix.com/api/v1/account/\(credentials.accountID)/gallery"
                self.debugLog("Successfully loaded Captura credentials")
                
                // Format date as required by API: YYYY-MM-DD
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd"
                let eventDateString = dateFormatter.string(from: eventDate)
                
                // Format date for title: MM-DD-YY
                dateFormatter.dateFormat = "M-d-yy"
                let formattedDateForTitle = dateFormatter.string(from: eventDate)
                
                // Create the new title that will be used for both systems
                let newTitle = "\(galleryName) \(formattedDateForTitle)"
                
                self.debugLog("Starting gallery creation for: \(newTitle) with date \(eventDateString)")
                
                // Start the sequence of API calls
                self.getCapturaToken { [weak self] result in
                    guard let self = self else { return }
                    
                    switch result {
                    case .success(let token):
                self.debugLog("Successfully got Captura token")
                self.createCapturaGallery(token: token, title: newTitle, eventDate: eventDateString) { capturaResult in
                    switch capturaResult {
                    case .success(let galleryID):
                        self.debugLog("Successfully created Captura gallery with ID: \(galleryID)")
                        // NOTE: Google Sheets integration disabled - GoogleSignIn SDK removed
                        self.debugLog("⚠️ Google Sheets integration is disabled. Only Captura gallery created.")
                        let result = GalleryCreationResult(
                            capturaGalleryID: galleryID,
                            googleSheetID: nil // No Google Sheet created
                        )
                        completion(.success(result))

                        // DISABLED: Google Sheets creation (requires GoogleSignIn SDK)
                        // self.authenticateWithGoogle { authResult in
                        //     ... Google Sheets code removed ...
                        // }
                        
                    case .failure(let error):
                        self.debugLog("Failed to create Captura gallery: \(error.localizedDescription)")
                        completion(.failure(error))
                    }
                }
                
                    case .failure(let error):
                        self.debugLog("Failed to get Captura token: \(error.localizedDescription)")
                        completion(.failure(error))
                    }
                }
                
            case .failure(let error):
                // Failed to get credentials
                self.debugLog("Failed to get Captura credentials: \(error.localizedDescription)")
                completion(.failure(.missingCredentials))
            }
        }
    }
    
    // MARK: - Captura API Methods
    
    private func getCapturaToken(completion: @escaping (Result<String, GalleryCreatorError>) -> Void) {
        debugLog("Getting Captura token...")
        
        guard let credentials = capturaCredentials else {
            debugLog("No Captura credentials available")
            completion(.failure(.missingCredentials))
            return
        }
        
        // Don't encode the client ID and secret - use them directly in the form data
        let body = "grant_type=client_credentials&client_id=\(credentials.clientID)&client_secret=\(credentials.clientSecret)"
        
        guard let url = URL(string: capturaTokenURL) else {
            debugLog("Invalid Captura token URL")
            completion(.failure(.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)
        
        debugLog("Sending Captura token request with body: \(body)")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                self.debugLog("Captura token network error: \(error.localizedDescription)")
                completion(.failure(.networkError(error)))
                return
            }
            
            // Log HTTP response info
            if let httpResponse = response as? HTTPURLResponse {
                self.debugLog("Captura token HTTP response: \(httpResponse.statusCode)")
            }
            
            guard let data = data else {
                self.debugLog("Captura token empty response")
                completion(.failure(.emptyResponse))
                return
            }
            
            // Log raw response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                self.debugLog("Captura token raw response: \(responseString)")
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let error = json["error"] as? String {
                        self.debugLog("Captura token API error: \(error)")
                        completion(.failure(.capturaError))
                        return
                    }
                    
                    if let accessToken = json["access_token"] as? String {
                        self.debugLog("Captura token obtained successfully")
                        completion(.success(accessToken))
                    } else {
                        self.debugLog("Captura token missing from response")
                        completion(.failure(.invalidResponse))
                    }
                } else {
                    self.debugLog("Captura token invalid JSON")
                    completion(.failure(.jsonParsingError))
                }
            } catch {
                self.debugLog("Captura token JSON parsing error: \(error.localizedDescription)")
                completion(.failure(.jsonParsingError))
            }
        }.resume()
    }
    
    private func createCapturaGallery(token: String, title: String, eventDate: String, completion: @escaping (Result<String, GalleryCreatorError>) -> Void) {
        debugLog("Creating Captura gallery with title: \(title)")
        
        guard let url = URL(string: createGalleryURL) else {
            debugLog("Invalid create gallery URL")
            completion(.failure(.invalidURL))
            return
        }
        
        // Create the gallery payload according to API requirements
        let payload: [String: Any] = [
            "disableFaceDetection": true,
            "eventDate": eventDate,
            "galleryConfigID": 199639,
            "isGreenScreen": true,
            "jobType": "sports",
            "keyword": "Sports2425",
            "priceSheetID": 79350,
            "sourceSize": 6000,
            "title": title,
            "shopBetaOptIn": true,
            "manualOnlineCodes": false,
            "status": "inactive",
            "customDataSpecID": 1972,
            "type": "subject"
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            // Log the request payload for debugging
            self.debugLog("Gallery creation payload: \(payload)")
        } catch {
            debugLog("JSON serialization error: \(error.localizedDescription)")
            completion(.failure(.jsonSerializationError))
            return
        }
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            if let error = error {
                self.debugLog("Gallery creation network error: \(error.localizedDescription)")
                completion(.failure(.networkError(error)))
                return
            }
            
            // Log HTTP response info
            if let httpResponse = response as? HTTPURLResponse {
                self.debugLog("Gallery creation HTTP response: \(httpResponse.statusCode)")
            }
            
            guard let data = data else {
                self.debugLog("Gallery creation empty response")
                completion(.failure(.emptyResponse))
                return
            }
            
            // Log raw response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                self.debugLog("Gallery creation raw response: \(responseString)")
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    // Check for API error
                    if let error = json["error"] as? String {
                        self.debugLog("Gallery creation API error: \(error)")
                        completion(.failure(.capturaError))
                        return
                    }
                    
                    // Check for id field - could be a number or string
                    if let galleryIDNum = json["id"] as? Int {
                        let galleryID = String(galleryIDNum)
                        self.debugLog("Gallery created with numeric ID: \(galleryID)")
                        completion(.success(galleryID))
                    } else if let galleryID = json["id"] as? String {
                        self.debugLog("Gallery created with string ID: \(galleryID)")
                        completion(.success(galleryID))
                    } else {
                        // If we can't find the id field, dump all keys for debugging
                        let keys = json.keys.joined(separator: ", ")
                        self.debugLog("Gallery ID not found in response. Available keys: \(keys)")
                        completion(.failure(.invalidResponse))
                    }
                } else {
                    self.debugLog("Gallery creation invalid JSON")
                    completion(.failure(.jsonParsingError))
                }
            } catch {
                self.debugLog("Gallery creation JSON parsing error: \(error.localizedDescription)")
                completion(.failure(.jsonParsingError))
            }
        }.resume()
    }
    
    // MARK: - Debug Helper
    
    private func debugLog(_ message: String) {
        if debug {
            print("🖼️ GalleryCreatorService: \(message)")
        }
    }
}

// MARK: - Models

/// Result of a successful gallery creation
struct GalleryCreationResult {
    let capturaGalleryID: String
    let googleSheetID: String? // Optional - nil when Google Sheets integration is disabled
}

/// Errors that can occur during gallery creation
enum GalleryCreatorError: Error {
    case invalidURL
    case networkError(Error)
    case emptyResponse
    case invalidResponse
    case jsonParsingError
    case jsonSerializationError
    case capturaError
    case missingCredentials

    var localizedDescription: String {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .emptyResponse:
            return "Empty response from server"
        case .invalidResponse:
            return "Invalid response from server"
        case .jsonParsingError:
            return "Error parsing response"
        case .jsonSerializationError:
            return "Error creating request"
        case .capturaError:
            return "Error with Captura service"
        case .missingCredentials:
            return "Captura API credentials not configured. Please add them in Settings."
        }
    }
}
