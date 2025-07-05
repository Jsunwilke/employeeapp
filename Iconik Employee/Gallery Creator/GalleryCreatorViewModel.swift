import Foundation
import SwiftUI
import Combine

/// ViewModel for the GalleryCreatorView
class GalleryCreatorViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var galleryName = ""
    @Published var eventDate = Date()
    
    @Published var isSubmitting = false
    @Published var errorMessage = ""
    @Published var successMessage = ""
    @Published var capturaGalleryID = ""
    @Published var googleSheetID = ""
    
    // MARK: - Private Properties
    private let service: GalleryCreatorService
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    init(service: GalleryCreatorService = GalleryCreatorService.shared) {
        self.service = service
    }
    
    // MARK: - Public Methods
    
    /// Validates inputs and creates a gallery
    func createGallery() {
        // Validate inputs
        guard !galleryName.isEmpty else {
            errorMessage = "Please enter a gallery name"
            return
        }
        
        // Reset status
        isSubmitting = true
        errorMessage = ""
        successMessage = ""
        capturaGalleryID = ""
        googleSheetID = ""
        
        // Log the start of gallery creation
        print("Starting gallery creation process for: \(galleryName)")
        
        // Call the service to create the gallery
        service.createGallery(galleryName: galleryName, eventDate: eventDate) { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isSubmitting = false
                
                switch result {
                case .success(let galleryResult):
                    print("Gallery creation successful!")
                    self.capturaGalleryID = galleryResult.capturaGalleryID
                    self.googleSheetID = galleryResult.googleSheetID
                    self.successMessage = "Successfully created gallery and Google Sheet!"
                    
                case .failure(let error):
                    print("Gallery creation failed: \(error.localizedDescription)")
                    
                    // Provide more detailed error messages to the user
                    switch error {
                    case .networkError:
                        self.errorMessage = "Network connection error. Please check your internet connection and try again."
                    case .capturaError:
                        self.errorMessage = "Error connecting to the gallery service. Please try again later."
                    case .googleAuthError:
                        self.errorMessage = "Google authentication failed. Please sign in to your Google account and try again."
                    case .googleSheetError:
                        self.errorMessage = "Error creating Google Sheet. Please check your Google permissions and try again."
                    default:
                        self.errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }
    
    /// Format date for display in the UI
    func formatDateForDisplay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    /// Clears the form and results
    func resetForm() {
        galleryName = ""
        errorMessage = ""
        successMessage = ""
        capturaGalleryID = ""
        googleSheetID = ""
    }
    
    /// Copy gallery ID to clipboard
    func copyGalleryID() {
        UIPasteboard.general.string = capturaGalleryID
    }
    
    /// Copy sheet ID to clipboard
    func copySheetID() {
        UIPasteboard.general.string = googleSheetID
    }
}
