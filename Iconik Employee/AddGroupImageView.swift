//
//  AddGroupImageView.swift
//  Iconik Employee
//
//  Created by administrator on 5/13/25.
//


import SwiftUI
import Firebase
import FirebaseFirestore

struct AddGroupImageView: View {
    let shootID: String
    let existingGroup: GroupImage?
    let onComplete: (Bool) -> Void
    
    @State private var description: String = ""
    @State private var imageNumbers: String = ""
    @State private var notes: String = ""
    
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showingErrorAlert = false
    
    @Environment(\.presentationMode) var presentationMode
    
    var isEditing: Bool {
        existingGroup != nil
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Group Information")) {
                    TextField("Description", text: $description)
                        .autocapitalization(.sentences)
                }
                
                Section(header: Text("Image Information")) {
                    TextField("Image Numbers", text: $imageNumbers)
                        .keyboardType(.asciiCapable)
                        .autocapitalization(.none)
                    
                    TextView(text: $notes, placeholder: "Notes (optional)")
                        .frame(minHeight: 100)
                }
                
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
            .navigationBarTitle(isEditing ? "Edit Group" : "Add Group", displayMode: .inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isEditing ? "Update" : "Save") {
                        saveGroupImage()
                    }
                    .disabled(description.isEmpty)
                }
            }
            .alert(isPresented: $showingErrorAlert) {
                Alert(
                    title: Text("Error"),
                    message: Text(errorMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onAppear {
                if let group = existingGroup {
                    description = group.description
                    imageNumbers = group.imageNumbers
                    notes = group.notes
                }
            }
        }
    }
    
    private func saveGroupImage() {
        isLoading = true
        
        let group = GroupImage(
            id: existingGroup?.id ?? UUID().uuidString,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            imageNumbers: imageNumbers.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        
        if isEditing {
            SportsShootService.shared.updateGroupImage(shootID: shootID, groupImage: group) { result in
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    switch result {
                    case .success:
                        self.onComplete(true)
                        self.presentationMode.wrappedValue.dismiss()
                    case .failure(let error):
                        self.errorMessage = "Failed to update group: \(error.localizedDescription)"
                        self.showingErrorAlert = true
                    }
                }
            }
        } else {
            SportsShootService.shared.addGroupImage(shootID: shootID, groupImage: group) { result in
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    switch result {
                    case .success:
                        self.onComplete(true)
                        self.presentationMode.wrappedValue.dismiss()
                    case .failure(let error):
                        self.errorMessage = "Failed to add group: \(error.localizedDescription)"
                        self.showingErrorAlert = true
                    }
                }
            }
        }
    }
}

struct AddGroupImageView_Previews: PreviewProvider {
    static var previews: some View {
        AddGroupImageView(
            shootID: "previewID",
            existingGroup: nil,
            onComplete: { _ in }
        )
    }
}