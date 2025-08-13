import SwiftUI

struct AddClassGroupView: View {
    let jobId: String
    let jobType: String
    let onComplete: (Bool) -> Void
    
    @Environment(\.presentationMode) var presentationMode
    
    @State private var grade = ""
    @State private var teacher = ""
    @State private var imageNumbers = ""
    @State private var notes = ""
    
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showingErrorAlert = false
    @State private var showingWhiteboard = false
    
    @FocusState private var focusedField: Field?
    
    enum Field {
        case grade, teacher, images, notes
    }
    
    private let service = ClassGroupJobService.shared
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Form {
                Section(header: Text("\(jobType == "classGroups" ? "Class" : "Candid") Information")) {
                    // Grade with suggestions
                    HStack {
                        TextField("Grade", text: $grade)
                            .focused($focusedField, equals: .grade)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .teacher }
                        
                        Menu {
                            ForEach(ClassGroup.commonGrades, id: \.self) { gradeOption in
                                Button(gradeOption) {
                                    grade = gradeOption
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.down.circle")
                                .foregroundColor(.blue)
                        }
                    }
                    
                    TextField("Teacher Name", text: $teacher)
                        .focused($focusedField, equals: .teacher)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .images }
                }
                
                Section(header: Text("Images")) {
                    TextField("Image Numbers (comma-separated)", text: $imageNumbers)
                        .keyboardType(.numbersAndPunctuation)
                        .focused($focusedField, equals: .images)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .notes }
                    
                    if !imageNumbers.isEmpty {
                        let count = imageNumbers.split(separator: ",").count
                        Text("\(count) image\(count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Notes")) {
                    TextEditor(text: $notes)
                        .focused($focusedField, equals: .notes)
                        .frame(minHeight: 100)
                }
                
                if isLoading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }
                }
                
                // Whiteboard button at bottom
                Button(action: {
                    showingWhiteboard = true
                }) {
                    HStack {
                        Image(systemName: "rectangle.inset.filled")
                        Text("Show Whiteboard")
                    }
                    .font(.headline)
                    .foregroundColor(canShowWhiteboard ? .white : .gray)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canShowWhiteboard ? Color.blue : Color.gray.opacity(0.3))
                    .cornerRadius(10)
                }
                .disabled(!canShowWhiteboard)
                .padding()
            }
            .navigationTitle("Add \(jobType == "classGroups" ? "Class Group" : "Class Candid")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveClassGroup()
                    }
                    .disabled(isLoading || !isFormValid)
                }
            }
            .alert("Error", isPresented: $showingErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .fullScreenCover(isPresented: $showingWhiteboard) {
                ClassGroupSlateView(
                    grade: grade,
                    teacher: teacher,
                    schoolName: nil
                )
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    private var isFormValid: Bool {
        !grade.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var canShowWhiteboard: Bool {
        !grade.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func saveClassGroup() {
        isLoading = true
        
        let classGroup = ClassGroup(
            grade: grade.trimmingCharacters(in: .whitespacesAndNewlines),
            teacher: teacher.trimmingCharacters(in: .whitespacesAndNewlines),
            imageNumbers: imageNumbers.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        
        service.addClassGroup(toJobId: jobId, classGroup: classGroup) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                
                switch result {
                case .success:
                    self.onComplete(true)
                    self.presentationMode.wrappedValue.dismiss()
                case .failure(let error):
                    self.errorMessage = "Failed to save: \(error.localizedDescription)"
                    self.showingErrorAlert = true
                }
            }
        }
    }
}

// MARK: - Edit Class Group View
struct EditClassGroupView: View {
    let jobId: String
    let classGroup: ClassGroup
    let jobType: String
    let onComplete: (Bool) -> Void
    
    @Environment(\.dismiss) var dismiss
    
    @State private var grade = ""
    @State private var teacher = ""
    @State private var imageNumbers = ""
    @State private var notes = ""
    
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showingErrorAlert = false
    @State private var showingWhiteboard = false
    
    @FocusState private var focusedField: AddClassGroupView.Field?
    
    private let service = ClassGroupJobService.shared
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                Section(header: Text("\(jobType == "classGroups" ? "Class" : "Candid") Information")) {
                    // Grade with suggestions
                    HStack {
                        TextField("Grade", text: $grade)
                            .focused($focusedField, equals: .grade)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .teacher }
                        
                        Menu {
                            ForEach(ClassGroup.commonGrades, id: \.self) { gradeOption in
                                Button(gradeOption) {
                                    grade = gradeOption
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.down.circle")
                                .foregroundColor(.blue)
                        }
                    }
                    
                    TextField("Teacher Name", text: $teacher)
                        .focused($focusedField, equals: .teacher)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .images }
                }
                
                Section(header: Text("Images")) {
                    TextField("Image Numbers (comma-separated)", text: $imageNumbers)
                        .keyboardType(.numbersAndPunctuation)
                        .focused($focusedField, equals: .images)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .notes }
                    
                    if !imageNumbers.isEmpty {
                        let count = imageNumbers.split(separator: ",").count
                        Text("\(count) image\(count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Notes")) {
                    TextEditor(text: $notes)
                        .focused($focusedField, equals: .notes)
                        .frame(minHeight: 100)
                }
                
                if isLoading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }
                }
                
                // Whiteboard button at bottom
                Button(action: {
                    showingWhiteboard = true
                }) {
                    HStack {
                        Image(systemName: "rectangle.inset.filled")
                        Text("Show Whiteboard")
                    }
                    .font(.headline)
                    .foregroundColor(canShowWhiteboard ? .white : .gray)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canShowWhiteboard ? Color.blue : Color.gray.opacity(0.3))
                    .cornerRadius(10)
                }
                .disabled(!canShowWhiteboard)
                .padding()
            }
            .navigationTitle("Edit \(jobType == "classGroups" ? "Class Group" : "Class Candid")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveClassGroup()
                    }
                    .disabled(isLoading || !isFormValid)
                }
            }
            .alert("Error", isPresented: $showingErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                // Populate fields with existing values
                grade = classGroup.grade
                teacher = classGroup.teacher
                imageNumbers = classGroup.imageNumbers
                notes = classGroup.notes
            }
            .fullScreenCover(isPresented: $showingWhiteboard) {
                ClassGroupSlateView(
                    grade: grade,
                    teacher: teacher,
                    schoolName: nil
                )
            }
        }
    }
    
    private var isFormValid: Bool {
        !grade.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var canShowWhiteboard: Bool {
        !grade.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func saveClassGroup() {
        isLoading = true
        
        let updatedGroup = ClassGroup(
            id: classGroup.id, // Keep the same ID
            grade: grade.trimmingCharacters(in: .whitespacesAndNewlines),
            teacher: teacher.trimmingCharacters(in: .whitespacesAndNewlines),
            imageNumbers: imageNumbers.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        
        service.updateClassGroup(jobId: jobId, classGroup: updatedGroup) { result in
            DispatchQueue.main.async {
                self.isLoading = false
                
                switch result {
                case .success:
                    self.onComplete(true)
                    self.dismiss()
                case .failure(let error):
                    self.errorMessage = "Failed to update: \(error.localizedDescription)"
                    self.showingErrorAlert = true
                }
            }
        }
    }
}

// MARK: - Preview
struct AddClassGroupView_Previews: PreviewProvider {
    static var previews: some View {
        AddClassGroupView(jobId: "preview123", jobType: "classGroups") { _ in }
    }
}