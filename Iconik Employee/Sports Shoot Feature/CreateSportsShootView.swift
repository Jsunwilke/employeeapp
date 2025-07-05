import SwiftUI
import Firebase
import FirebaseFirestore

struct CreateSportsShootView: View {
    @Environment(\.presentationMode) var presentationMode
    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""
    
    // Match the expected function signature
    let onComplete: (_ success: Bool) -> Void
    
    // Form fields
    @State private var schoolName: String = ""
    @State private var sportName: String = ""
    @State private var shootDate = Date()
    @State private var location: String = ""
    @State private var photographer: String = ""
    @State private var additionalNotes: String = ""
    
    // State
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    
    init(onComplete: @escaping (_ success: Bool) -> Void) {
        self.onComplete = onComplete
    }
    
    var body: some View {
        NavigationView {
            Form {
                // Basic information section
                Section(header: Text("Basic Information")) {
                    TextField("School Name", text: $schoolName)
                    TextField("Sport Name", text: $sportName)
                    DatePicker("Shoot Date", selection: $shootDate, displayedComponents: .date)
                    TextField("Location", text: $location)
                    TextField("Photographer", text: $photographer)
                }
                
                // Notes section
                Section(header: Text("Additional Notes")) {
                    TextEditor(text: $additionalNotes)
                        .frame(minHeight: 100)
                }
                
                // Create button section
                Section {
                    Button(action: createSportsShoot) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Text("Create Sports Shoot")
                                .bold()
                                .foregroundColor(.blue)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .disabled(isLoading || schoolName.isEmpty || sportName.isEmpty)
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
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text(alertTitle),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK")) {
                        if alertTitle == "Success" {
                            onComplete(true)
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                )
            }
        }
    }
    
    private func createSportsShoot() {
        guard !storedUserOrganizationID.isEmpty else {
            alertTitle = "Error"
            alertMessage = "No organization ID found. Please sign in again."
            showAlert = true
            return
        }
        
        guard !schoolName.isEmpty, !sportName.isEmpty else {
            alertTitle = "Error"
            alertMessage = "School name and sport name are required."
            showAlert = true
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
            organizationID: storedUserOrganizationID,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // Save to Firestore
        let db = Firestore.firestore()
        let docRef = db.collection("sportsJobs").document(newShoot.id)
        
        // Convert to Firestore data
        var data: [String: Any] = [
            "schoolName": newShoot.schoolName,
            "sportName": newShoot.sportName,
            "shootDate": Timestamp(date: newShoot.shootDate),
            "location": newShoot.location,
            "photographer": newShoot.photographer,
            "roster": [],  // Empty roster initially
            "groupImages": [],  // Empty group images initially
            "additionalNotes": newShoot.additionalNotes,
            "organizationID": newShoot.organizationID,
            "createdAt": Timestamp(date: newShoot.createdAt),
            "updatedAt": Timestamp(date: newShoot.updatedAt)
        ]
        
        docRef.setData(data) { error in
            DispatchQueue.main.async {
                isLoading = false
                
                if let error = error {
                    alertTitle = "Error"
                    alertMessage = "Failed to create sports shoot: \(error.localizedDescription)"
                } else {
                    alertTitle = "Success"
                    alertMessage = "Sports shoot created successfully."
                }
                
                showAlert = true
            }
        }
    }
}

struct CreateSportsShootView_Previews: PreviewProvider {
    static var previews: some View {
        CreateSportsShootView(onComplete: { _ in })
    }
}
