//
//  CreateSportsShootViewModel.swift
//  Iconik Employee
//
//  Created by administrator on 5/20/25.
//


import SwiftUI
import Firebase
import FirebaseFirestore
import Combine

class CreateSportsShootViewModel: ObservableObject {
    // Form fields
    @Published var schoolName: String = ""
    @Published var sportName: String = ""
    @Published var shootDate = Date()
    @Published var location: String = ""
    @Published var photographer: String = ""
    @Published var additionalNotes: String = ""
    
    // State
    @Published var isLoading = false
    @Published var showAlert = false
    @Published var alertTitle = ""
    @Published var alertMessage = ""
    
    // Organization info
    private let organizationID: String
    private var repository = SportsShootRepository.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Get stored organization ID
        self.organizationID = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.userOrganizationID) ?? ""
    }
    
    func createSportsShoot(completion: @escaping (Bool) -> Void) {
        guard !organizationID.isEmpty else {
            alertTitle = "Error"
            alertMessage = "No organization ID found. Please sign in again."
            showAlert = true
            completion(false)
            return
        }
        
        guard !schoolName.isEmpty, !sportName.isEmpty else {
            alertTitle = "Error"
            alertMessage = "School name and sport name are required."
            showAlert = true
            completion(false)
            return
        }
        
        isLoading = true
        
        // Create a new SportsShoot object
        let newShoot = SportsShoot(
            id: UUID().uuidString,
            schoolName: schoolName,
            sportName: sportName,
            shootDate: shootDate,
            location: location,
            photographer: photographer,
            roster: [],
            groupImages: [],
            additionalNotes: additionalNotes,
            organizationID: organizationID,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // Save to Firestore using the repository
        let db = Firestore.firestore()
        let docRef = db.collection(Constants.FirestoreCollections.sportsJobs).document(newShoot.id)
        
        // Convert to Firestore data
        let data = newShoot.toDictionary()
        
        docRef.setData(data) { [weak self] error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                if let error = error {
                    self?.alertTitle = "Error"
                    self?.alertMessage = "Failed to create sports shoot: \(error.localizedDescription)"
                    self?.showAlert = true
                    completion(false)
                } else {
                    self?.alertTitle = "Success"
                    self?.alertMessage = "Sports shoot created successfully."
                    self?.showAlert = true
                    completion(true)
                }
            }
        }
    }
}

struct CreateSportsShootView: View {
    @StateObject private var viewModel = CreateSportsShootViewModel()
    @Environment(\.presentationMode) var presentationMode
    var onComplete: (Bool) -> Void
    
    var body: some View {
        NavigationView {
            Form {
                // Basic information section
                Section(header: Text("Basic Information")) {
                    TextField("School Name", text: $viewModel.schoolName)
                    TextField("Sport Name", text: $viewModel.sportName)
                    DatePicker("Shoot Date", selection: $viewModel.shootDate, displayedComponents: .date)
                    TextField("Location", text: $viewModel.location)
                    TextField("Photographer", text: $viewModel.photographer)
                }
                
                // Notes section
                Section(header: Text("Additional Notes")) {
                    TextEditor(text: $viewModel.additionalNotes)
                        .frame(minHeight: 100)
                }
                
                // Create button section
                Section {
                    Button(action: {
                        viewModel.createSportsShoot { success in
                            if success {
                                onComplete(true)
                                presentationMode.wrappedValue.dismiss()
                            }
                        }
                    }) {
                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Create Sports Shoot")
                                .bold()
                                .foregroundColor(.blue)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(viewModel.isLoading || viewModel.schoolName.isEmpty || viewModel.sportName.isEmpty)
                }
            }
            .navigationTitle("New Sports Shoot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .alert(isPresented: $viewModel.showAlert) {
                Alert(
                    title: Text(viewModel.alertTitle),
                    message: Text(viewModel.alertMessage),
                    dismissButton: .default(Text("OK")) {
                        if viewModel.alertTitle == "Success" {
                            onComplete(true)
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                )
            }
        }
    }
}