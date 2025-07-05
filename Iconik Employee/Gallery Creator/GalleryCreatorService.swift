import Foundation
import GoogleSignIn
import GoogleAPIClientForREST
import UIKit

/// Service class that handles the business logic for the Gallery Creator feature
class GalleryCreatorService {
    // MARK: - Shared Instance
    static let shared = GalleryCreatorService()
    
    // MARK: - Properties
    private let capturaClientID = "1ab255f1-5a89-4ae8-b454-4da98b64afcb"
    private let capturaClientSecret = "18458cffbe1e0fe82b2c99d4ead741cc8271640b0020d8f61035945be374675913a32303e32ce6c6a78d88c91554419e19cd458ce28d490302d2c1dd020df03d"
    private let capturaTokenURL = "https://api.imagequix.com/api/oauth/token"
    private let capturaAccountID = "J98TA9W"
    private let createGalleryURL: String
    
    // Updated to use a fallback template mechanism
    private let templateSheetID = "1fT6I_U1Ag1lluo1mzO-qfRVCLzouwSadZBQFHI6jcxM"
    private let fallbackTemplateSheetID = "1oTZnq5KEGdpMxZeg56c9kNzHb3l-PW8XboIbqcZ9MUk" // Add a fallback template
    
    // Target folders for the Google Sheet
    private let primaryFolderID = "1bNNkQsqUYwk-XuoS_yP1trJkBgJ6axFF"
    private let fallbackFolderID = "1oKoJr4R9SKeqbo59LjpKcL5nRDKhFF7M"
    
    // Using the client ID extracted from the URL scheme
    private let googleClientID = "700201321131-uss5rsm5fl712l3eiurj9r7np9tlqkef.apps.googleusercontent.com"
    
    // Debug flag - set to true for verbose logging
    private let debug = true
    
    // MARK: - Initialization
    private init() {
        createGalleryURL = "https://api.imagequix.com/api/v1/account/\(capturaAccountID)/gallery"
    }
    
    // MARK: - Public Methods
    
    /// Creates a gallery in both Captura and Google Sheets
    /// - Parameters:
    ///   - galleryName: The base name for the gallery
    ///   - eventDate: The date of the event
    ///   - completion: Completion handler with result
    func createGallery(galleryName: String, eventDate: Date, completion: @escaping (Result<GalleryCreationResult, GalleryCreatorError>) -> Void) {
        // Format date as required by API: YYYY-MM-DD
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let eventDateString = dateFormatter.string(from: eventDate)
        
        // Format date for title: MM-DD-YY
        dateFormatter.dateFormat = "M-d-yy"
        let formattedDateForTitle = dateFormatter.string(from: eventDate)
        
        // Create the new title that will be used for both systems
        let newTitle = "\(galleryName) \(formattedDateForTitle)"
        
        debugLog("Starting gallery creation for: \(newTitle) with date \(eventDateString)")
        
        // Start the sequence of API calls
        getCapturaToken { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let token):
                self.debugLog("Successfully got Captura token")
                self.createCapturaGallery(token: token, title: newTitle, eventDate: eventDateString) { capturaResult in
                    switch capturaResult {
                    case .success(let galleryID):
                        self.debugLog("Successfully created Captura gallery with ID: \(galleryID)")
                        // Captura gallery created successfully, now create Google Sheet
                        self.authenticateWithGoogle { authResult in
                            switch authResult {
                            case .success:
                                self.debugLog("Successfully authenticated with Google")
                                self.createGoogleSheet(title: newTitle) { copyResult in
                                    switch copyResult {
                                    case .success(let sheetID):
                                        self.debugLog("Successfully created Google Sheet with ID: \(sheetID)")
                                        self.updateGoogleSheet(spreadsheetID: sheetID, title: galleryName, eventDate: eventDateString) { updateResult in
                                            switch updateResult {
                                            case .success:
                                                self.debugLog("Successfully updated Google Sheet")
                                                let result = GalleryCreationResult(
                                                    capturaGalleryID: galleryID,
                                                    googleSheetID: sheetID
                                                )
                                                completion(.success(result))
                                                
                                            case .failure(let error):
                                                // Created sheet but failed to update it
                                                self.debugLog("Failed to update Google Sheet: \(error.localizedDescription)")
                                                completion(.failure(error))
                                            }
                                        }
                                        
                                    case .failure(let error):
                                        self.debugLog("Failed to create Google Sheet: \(error.localizedDescription)")
                                        completion(.failure(error))
                                    }
                                }
                                
                            case .failure(let error):
                                self.debugLog("Failed to authenticate with Google: \(error.localizedDescription)")
                                completion(.failure(error))
                            }
                        }
                        
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
    }
    
    // MARK: - Captura API Methods
    
    private func getCapturaToken(completion: @escaping (Result<String, GalleryCreatorError>) -> Void) {
        debugLog("Getting Captura token...")
        
        // Don't encode the client ID and secret - use them directly in the form data
        let body = "grant_type=client_credentials&client_id=\(capturaClientID)&client_secret=\(capturaClientSecret)"
        
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
    
    // MARK: - Google API Methods
    
    private func authenticateWithGoogle(completion: @escaping (Result<Void, GalleryCreatorError>) -> Void) {
        debugLog("Authenticating with Google...")
        
        // Get the current user if already signed in
        if GIDSignIn.sharedInstance.currentUser != nil {
            debugLog("User already signed in to Google")
            completion(.success(()))
            return
        }
        
        // No user signed in, need to show the sign-in UI
        DispatchQueue.main.async {
            // Find a UIViewController to present from
            guard let rootViewController = self.topViewController() else {
                self.debugLog("Cannot find root view controller for Google sign-in")
                completion(.failure(.googleAuthError))
                return
            }
            
            // Updated method to use the correct Google Sign-In API
            // This matches the API used in your version of the Google Sign-In SDK
            GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { signInResult, error in
                if let error = error {
                    self.debugLog("Google sign-in error: \(error.localizedDescription)")
                    completion(.failure(.googleAuthError))
                    return
                }
                
                guard signInResult != nil else {
                    self.debugLog("No sign-in result")
                    completion(.failure(.googleAuthError))
                    return
                }
                
                self.debugLog("Google sign-in successful")
                completion(.success(()))
            }
        }
    }
    
    // Helper method to find the top most view controller
    private func topViewController() -> UIViewController? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            return nil
        }
        
        var topController = rootViewController
        while let presentedController = topController.presentedViewController {
            topController = presentedController
        }
        
        return topController
    }
    
    // Modified: Enhanced method that attempts to create a new sheet and copy it to the specified folder
    private func createGoogleSheet(title: String, completion: @escaping (Result<String, GalleryCreatorError>) -> Void) {
        debugLog("Creating Google Sheet with title: \(title)")
        
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            debugLog("No Google user available")
            completion(.failure(.googleAuthError))
            return
        }
        
        // Create a Drive service using the authenticated user's credentials
        let service = GTLRDriveService()
        service.authorizer = user.fetcherAuthorizer
        
        // First try to copy from the template and move to primary folder
        copyGoogleSheet(service: service, templateID: templateSheetID, title: title) { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let fileID):
                // Successfully copied the template, now move to primary folder
                self.moveFileToFolder(service: service, fileID: fileID, folderID: self.primaryFolderID) { moveResult in
                    switch moveResult {
                    case .success(let movedFileID):
                        // Successfully moved to primary folder
                        self.debugLog("Successfully moved sheet to primary folder")
                        completion(.success(movedFileID))
                        
                    case .failure:
                        // Failed to move to primary folder, try fallback folder
                        self.debugLog("Failed to move to primary folder, trying fallback folder")
                        self.moveFileToFolder(service: service, fileID: fileID, folderID: self.fallbackFolderID) { fallbackMoveResult in
                            switch fallbackMoveResult {
                            case .success(let fallbackMovedFileID):
                                // Successfully moved to fallback folder
                                self.debugLog("Successfully moved sheet to fallback folder")
                                completion(.success(fallbackMovedFileID))
                                
                            case .failure:
                                // Failed to move to either folder, return original file ID
                                self.debugLog("Failed to move to any folder, returning original file ID")
                                completion(.success(fileID))
                            }
                        }
                    }
                }
                
            case .failure:
                // If first template fails, try the fallback template
                self.debugLog("Primary template copy failed, trying fallback template")
                self.copyGoogleSheet(service: service, templateID: self.fallbackTemplateSheetID, title: title) { [weak self] fallbackResult in
                    guard let self = self else { return }
                    
                    switch fallbackResult {
                    case .success(let fallbackFileID):
                        // Successfully copied the fallback template, now try to move it
                        self.moveFileToFolder(service: service, fileID: fallbackFileID, folderID: self.primaryFolderID) { moveResult in
                            switch moveResult {
                            case .success(let movedFileID):
                                self.debugLog("Successfully moved fallback sheet to primary folder")
                                completion(.success(movedFileID))
                                
                            case .failure:
                                // Try fallback folder
                                self.moveFileToFolder(service: service, fileID: fallbackFileID, folderID: self.fallbackFolderID) { fallbackMoveResult in
                                    switch fallbackMoveResult {
                                    case .success(let fallbackMovedFileID):
                                        self.debugLog("Successfully moved fallback sheet to fallback folder")
                                        completion(.success(fallbackMovedFileID))
                                        
                                    case .failure:
                                        // Return original file ID
                                        self.debugLog("Failed to move fallback sheet to any folder")
                                        completion(.success(fallbackFileID))
                                    }
                                }
                            }
                        }
                        
                    case .failure:
                        // If fallback template also fails, create a new spreadsheet from scratch
                        self.debugLog("Fallback template copy failed, creating new spreadsheet")
                        self.createNewGoogleSheet(service: service, title: title) { newFileResult in
                            switch newFileResult {
                            case .success(let newFileID):
                                // Try to move the new sheet to primary folder
                                self.moveFileToFolder(service: service, fileID: newFileID, folderID: self.primaryFolderID) { moveResult in
                                    switch moveResult {
                                    case .success(let movedFileID):
                                        self.debugLog("Successfully moved new sheet to primary folder")
                                        completion(.success(movedFileID))
                                        
                                    case .failure:
                                        // Try fallback folder
                                        self.moveFileToFolder(service: service, fileID: newFileID, folderID: self.fallbackFolderID) { fallbackMoveResult in
                                            switch fallbackMoveResult {
                                            case .success(let fallbackMovedFileID):
                                                self.debugLog("Successfully moved new sheet to fallback folder")
                                                completion(.success(fallbackMovedFileID))
                                                
                                            case .failure:
                                                // Return original file ID
                                                self.debugLog("Failed to move new sheet to any folder")
                                                completion(.success(newFileID))
                                            }
                                        }
                                    }
                                }
                                
                            case .failure(let error):
                                self.debugLog("Failed to create new spreadsheet: \(error.localizedDescription)")
                                completion(.failure(error))
                            }
                        }
                    }
                }
            }
        }
    }
    
    // Simple copy operation
    private func copyGoogleSheet(service: GTLRDriveService, templateID: String, title: String, completion: @escaping (Result<String, GalleryCreatorError>) -> Void) {
        // Create a request to copy the template file
        let copyFile = GTLRDrive_File()
        copyFile.name = title
        
        let query = GTLRDriveQuery_FilesCopy.query(withObject: copyFile, fileId: templateID)
        query.fields = "id"
        
        debugLog("Sending Google Drive copy request for template: \(templateID)")
        
        service.executeQuery(query) { [weak self] (ticket, response, error) in
            guard let self = self else { return }
            
            if let error = error {
                self.debugLog("Error copying template: \(error.localizedDescription)")
                completion(.failure(.googleSheetError))
                return
            }
            
            guard let response = response as? GTLRDrive_File,
                  let fileID = response.identifier else {
                self.debugLog("Invalid response when copying template")
                completion(.failure(.invalidResponse))
                return
            }
            
            self.debugLog("Successfully copied template with ID: \(fileID)")
            completion(.success(fileID))
        }
    }
    
    // Create a new blank spreadsheet
    private func createNewGoogleSheet(service: GTLRDriveService, title: String, completion: @escaping (Result<String, GalleryCreatorError>) -> Void) {
        debugLog("Creating new blank Google Sheet with title: \(title)")
        
        // Create a new file object for a Google Sheet
        let newFile = GTLRDrive_File()
        newFile.name = title
        newFile.mimeType = "application/vnd.google-apps.spreadsheet"
        
        let query = GTLRDriveQuery_FilesCreate.query(withObject: newFile, uploadParameters: nil)
        query.fields = "id"
        
        service.executeQuery(query) { [weak self] (ticket, response, error) in
            guard let self = self else { return }
            
            if let error = error {
                self.debugLog("Error creating new sheet: \(error.localizedDescription)")
                completion(.failure(.googleSheetError))
                return
            }
            
            guard let response = response as? GTLRDrive_File,
                  let fileID = response.identifier else {
                self.debugLog("Invalid response when creating new sheet")
                completion(.failure(.invalidResponse))
                return
            }
            
            self.debugLog("Successfully created new sheet with ID: \(fileID)")
            completion(.success(fileID))
        }
    }
    
    // Move a file to a specific folder
    private func moveFileToFolder(service: GTLRDriveService, fileID: String, folderID: String, completion: @escaping (Result<String, GalleryCreatorError>) -> Void) {
        // First, get the current parents of the file
        let getQuery = GTLRDriveQuery_FilesGet.query(withFileId: fileID)
        getQuery.fields = "parents"
        
        service.executeQuery(getQuery) { [weak self] (ticket, response, error) in
            guard let self = self else { return }
            
            if let error = error {
                self.debugLog("Error getting file parents: \(error.localizedDescription)")
                completion(.failure(.googleSheetError))
                return
            }
            
            guard let file = response as? GTLRDrive_File,
                  let parents = file.parents else {
                self.debugLog("File has no parents or couldn't get file info")
                completion(.failure(.invalidResponse))
                return
            }
            
            // Now move the file to the specified folder
            let updateFile = GTLRDrive_File()
            let updateQuery = GTLRDriveQuery_FilesUpdate.query(withObject: updateFile, fileId: fileID, uploadParameters: nil)
            updateQuery.addParents = folderID
            updateQuery.removeParents = parents.joined(separator: ",")
            
            service.executeQuery(updateQuery) { [weak self] (ticket, response, error) in
                guard let self = self else { return }
                
                if let error = error {
                    self.debugLog("Error moving file to folder: \(error.localizedDescription)")
                    completion(.failure(.googleSheetError))
                    return
                }
                
                guard let updatedFile = response as? GTLRDrive_File,
                      let updatedFileID = updatedFile.identifier else {
                    self.debugLog("Invalid response when moving file")
                    completion(.failure(.invalidResponse))
                    return
                }
                
                self.debugLog("Successfully moved file to folder: \(folderID)")
                completion(.success(updatedFileID))
            }
        }
    }
    
    // Updated method to populate cells in the Blank Sports Roster template
    private func updateGoogleSheet(spreadsheetID: String, title: String, eventDate: String, completion: @escaping (Result<Void, GalleryCreatorError>) -> Void) {
        debugLog("Updating Google Sheet with ID: \(spreadsheetID), title: \(title), date: \(eventDate)")
        
        guard let user = GIDSignIn.sharedInstance.currentUser else {
            debugLog("No Google user available")
            completion(.failure(.googleAuthError))
            return
        }
        
        // Create a Sheets service using the authenticated user's credentials
        let service = GTLRSheetsService()
        service.authorizer = user.fetcherAuthorizer
        
        // Convert the event date to MM-DD-YY format for the sheet
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let parsedDate = dateFormatter.date(from: eventDate) ?? Date()
        
        dateFormatter.dateFormat = "M-d-yy"
        let formattedDate = dateFormatter.string(from: parsedDate)
        
        // Get the sheets in the spreadsheet to identify the right sheet to update
        let getQuery = GTLRSheetsQuery_SpreadsheetsGet.query(withSpreadsheetId: spreadsheetID)
        
        service.executeQuery(getQuery) { [weak self] (ticket, response, error) in
            guard let self = self else { return }
            
            if let error = error {
                self.debugLog("Error retrieving spreadsheet info: \(error.localizedDescription)")
                completion(.failure(.googleSheetError))
                return
            }
            
            guard let spreadsheet = response as? GTLRSheets_Spreadsheet,
                  let sheets = spreadsheet.sheets else {
                self.debugLog("Invalid spreadsheet structure")
                completion(.failure(.invalidResponse))
                return
            }
            
            // Check if we have the Photographer sheet or Sheet1 - otherwise use the first sheet
            var targetSheetName = "Sheet1" // Default sheet name
            
            for sheet in sheets {
                if let properties = sheet.properties, let sheetName = properties.title {
                    // Look for "Sheet1" or "Photographer" in the sheet titles
                    if sheetName == "Sheet1" || sheetName == "Photographer" {
                        targetSheetName = sheetName
                        break
                    }
                }
            }
            
            if sheets.isEmpty {
                self.debugLog("No sheets found in the spreadsheet")
                completion(.failure(.googleSheetError))
                return
            } else if targetSheetName.isEmpty, let firstSheet = sheets.first, let properties = firstSheet.properties, let sheetName = properties.title {
                // Use the first sheet if we couldn't find Sheet1 or Photographer
                targetSheetName = sheetName
            }
            
            self.debugLog("Using sheet: \(targetSheetName) for updates")
            
            // Create value ranges to update the relevant cells
            // For "Job name" - update cell B7 (this is where the gallery name will go)
            let jobNameVR = GTLRSheets_ValueRange()
            jobNameVR.range = "\(targetSheetName)!B7"
            jobNameVR.values = [[title]]
            
            // For "Event Date" - update cell B9 (this is where the date will go)
            let dateVR = GTLRSheets_ValueRange()
            dateVR.range = "\(targetSheetName)!B9"
            dateVR.values = [[formattedDate]]
            
            // Batch update the values
            let batchUpdateRequest = GTLRSheets_BatchUpdateValuesRequest()
            batchUpdateRequest.data = [jobNameVR, dateVR]
            batchUpdateRequest.valueInputOption = "USER_ENTERED" // Use USER_ENTERED to enable date formatting
            
            let batchQuery = GTLRSheetsQuery_SpreadsheetsValuesBatchUpdate.query(
                withObject: batchUpdateRequest,
                spreadsheetId: spreadsheetID
            )
            
            service.executeQuery(batchQuery) { (ticket, response, error) in
                if let error = error {
                    self.debugLog("Error updating spreadsheet values: \(error.localizedDescription)")
                    completion(.failure(.googleSheetError))
                    return
                }
                
                self.debugLog("Successfully updated spreadsheet with job name and date")
                completion(.success(()))
            }
        }
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
    let googleSheetID: String
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
    case googleAuthError
    case googleSheetError
    case folderAccessError
    
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
        case .googleAuthError:
            return "Google authentication error"
        case .googleSheetError:
            return "Error creating or updating Google Sheet"
        case .folderAccessError:
            return "Error accessing Google Drive folder"
        }
    }
}
