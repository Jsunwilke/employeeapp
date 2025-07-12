import SwiftUI
import Firebase
import FirebaseAuth
import FirebaseStorage

struct TemplateFormView: View {
    let template: ReportTemplate
    
    init(template: ReportTemplate) {
        self.template = template
        print("🚀 TemplateFormView INIT called with template: '\(template.name)'")
    }
    
    @StateObject private var templateService = TemplateService.shared
    @State private var formData: [String: Any] = [:]
    @State private var expandedSections: Set<String> = []
    @State private var isSubmitting = false
    @State private var showSuccessAlert = false
    @State private var errorMessage = ""
    @State private var selectedImages: [UIImage] = []
    @State private var showImagePicker = false
    @State private var tempImage: UIImage?
    @State private var selectedSchools: [SchoolItem] = []
    @State private var availableSchools: [SchoolItem] = []
    
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    
    private let fieldColors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .red]
    
    private var groupedFields: [String: [TemplateField]] {
        // Group fields by sections for better organization
        print("🔍 TemplateFormView: Processing template '\(template.name)' with \(template.fields.count) fields")
        
        for (index, field) in template.fields.enumerated() {
            print("🔍 Field \(index): id='\(field.id)', type='\(field.type)', label='\(field.label)', smartConfig=\(field.smartConfig != nil)")
        }
        
        let basicFields = template.fields.filter { field in
            ["date_auto", "time_auto", "user_name"].contains(field.type) || 
            ["photographer", "date", "time"].contains(field.id.lowercased())
        }
        print("🔍 Basic fields: \(basicFields.count) - \(basicFields.map { $0.id })")
        
        let dataFields = template.fields.filter { field in
            !basicFields.contains(where: { $0.id == field.id }) && 
            !["file", "location"].contains(field.type) &&
            field.smartConfig == nil
        }
        print("🔍 Data fields: \(dataFields.count) - \(dataFields.map { $0.id })")
        
        let smartFields = template.fields.filter { field in
            field.smartConfig != nil
        }
        print("🔍 Smart fields: \(smartFields.count) - \(smartFields.map { $0.id })")
        
        let mediaFields = template.fields.filter { field in
            ["file", "location"].contains(field.type)
        }
        print("🔍 Media fields: \(mediaFields.count) - \(mediaFields.map { $0.id })")
        
        var sections: [String: [TemplateField]] = [:]
        
        if !basicFields.isEmpty {
            sections["Basic Information"] = basicFields
        }
        if !dataFields.isEmpty {
            sections["Report Details"] = dataFields
        }
        if !smartFields.isEmpty {
            sections["Calculated Fields"] = smartFields
        }
        if !mediaFields.isEmpty {
            sections["Media & Location"] = mediaFields
        }
        
        print("🔍 Final sections: \(sections.keys.sorted()) with total \(sections.values.flatMap { $0 }.count) fields")
        return sections
    }
    
    var body: some View {
        print("🔍 TemplateFormView body called for template: \(template.name)")
        
        return ZStack {
            backgroundGradient
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                headerView
                progressView
                
                if groupedFields.isEmpty {
                    // Fallback content for empty template
                    VStack(spacing: 20) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 64))
                            .foregroundColor(.secondary)
                        
                        Text("No Fields Available")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("This template doesn't contain any fields to display.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        
                        Button("Go Back") {
                            presentationMode.wrappedValue.dismiss()
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(Array(groupedFields.keys.sorted()), id: \.self) { sectionName in
                                if let fields = groupedFields[sectionName] {
                                    sectionCard(sectionName: sectionName, fields: fields)
                                }
                            }
                            
                            submitButton
                                .padding(.vertical, 20)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
        .onAppear {
            print("🔍 TemplateFormView onAppear called")
            loadInitialData()
            expandAllSections()
        }
        .alert("Report Submitted", isPresented: $showSuccessAlert) {
            Button("OK") {
                presentationMode.wrappedValue.dismiss()
            }
        } message: {
            Text("Your daily report has been submitted successfully.")
        }
        .alert("Error", isPresented: .constant(!errorMessage.isEmpty)) {
            Button("OK") {
                errorMessage = ""
            }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImage: $tempImage)
                .onDisappear {
                    if let newImg = tempImage {
                        selectedImages.append(newImg)
                        tempImage = nil
                        updateFormDataFromImages()
                    }
                }
        }
    }
    
    // MARK: - Header and Progress
    
    private var headerView: some View {
        HStack {
            Button(action: {
                presentationMode.wrappedValue.dismiss()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Back")
                        .fontWeight(.medium)
                }
                .foregroundColor(.white)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(template.name)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                Text("v\(template.version)")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
    
    private var backgroundGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                colorScheme == .dark ? Color(UIColor.systemGray6) : Color(UIColor.systemGray5),
                colorScheme == .dark ? Color(UIColor.systemGray5) : Color(UIColor.systemGray4)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    private var progressView: some View {
        let completedFields = calculateCompletedFields()
        let totalFields = template.fields.filter { !($0.readOnly ?? false) }.count
        let progress = totalFields > 0 ? Double(completedFields) / Double(totalFields) : 0.0
        
        return VStack(spacing: 4) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.3))
                        .frame(height: 8)
                        .cornerRadius(4)
                    
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: geometry.size.width * CGFloat(progress), height: 8)
                        .cornerRadius(4)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 8)
            
            HStack {
                Text("\(completedFields)/\(totalFields) Fields Completed")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    // MARK: - Section Cards
    
    private func sectionCard(sectionName: String, fields: [TemplateField]) -> some View {
        let isExpanded = expandedSections.contains(sectionName)
        let sectionColor = fieldColors[abs(sectionName.hashValue) % fieldColors.count]
        
        return VStack(spacing: 0) {
            // Section header
            Button(action: {
                toggleSection(sectionName)
            }) {
                HStack {
                    Image(systemName: iconForSection(sectionName))
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(sectionColor)
                        )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sectionName)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("\(fields.count) field\(fields.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if isSectionCompleted(sectionName, fields: fields) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 20))
                    }
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Section content
            if isExpanded {
                VStack(spacing: 12) {
                    ForEach(fields) { field in
                        fieldView(field: field)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .background(Color(.systemBackground))
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    // MARK: - Field Views
    
    private func fieldView(field: TemplateField) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Field label
            HStack {
                Text(field.label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if field.required {
                    Text("*")
                        .foregroundColor(.red)
                }
                
                Spacer()
                
                if field.readOnly == true {
                    Text("AUTO")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(4)
                }
            }
            
            // Field input
            fieldInputView(field: field)
        }
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private func fieldInputView(field: TemplateField) -> some View {
        switch field.type {
        case "text", "email", "phone":
            textFieldInput(field: field)
            
        case "textarea":
            textAreaInput(field: field)
            
        case "number", "currency":
            numberFieldInput(field: field)
            
        case "date":
            dateFieldInput(field: field)
            
        case "time":
            timeFieldInput(field: field)
            
        case "select":
            selectFieldInput(field: field)
            
        case "multiselect":
            multiSelectFieldInput(field: field)
            
        case "radio":
            radioFieldInput(field: field)
            
        case "toggle":
            toggleFieldInput(field: field)
            
        case "file":
            fileFieldInput(field: field)
            
        case "mileage", "date_auto", "time_auto", "user_name", "school_name", "photo_count", "weather_conditions", "current_location":
            smartFieldInput(field: field)
            
        default:
            textFieldInput(field: field)
        }
    }
    
    private func textFieldInput(field: TemplateField) -> some View {
        TextField(field.placeholder ?? "Enter \(field.label.lowercased())", text: Binding(
            get: { formData[field.id] as? String ?? field.defaultValue ?? "" },
            set: { formData[field.id] = $0 }
        ))
        .textFieldStyle(RoundedBorderTextFieldStyle())
        .disabled(field.readOnly == true)
    }
    
    private func textAreaInput(field: TemplateField) -> some View {
        TextEditor(text: Binding(
            get: { formData[field.id] as? String ?? field.defaultValue ?? "" },
            set: { formData[field.id] = $0 }
        ))
        .frame(minHeight: 80)
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .disabled(field.readOnly == true)
    }
    
    private func numberFieldInput(field: TemplateField) -> some View {
        TextField(field.placeholder ?? "Enter number", text: Binding(
            get: { 
                if let number = formData[field.id] as? Double {
                    return String(number)
                }
                return formData[field.id] as? String ?? field.defaultValue ?? ""
            },
            set: { 
                if let number = Double($0) {
                    formData[field.id] = number
                } else {
                    formData[field.id] = $0
                }
            }
        ))
        .textFieldStyle(RoundedBorderTextFieldStyle())
        .keyboardType(.decimalPad)
        .disabled(field.readOnly == true)
    }
    
    private func dateFieldInput(field: TemplateField) -> some View {
        DatePicker(
            "",
            selection: Binding(
                get: {
                    if let dateString = formData[field.id] as? String,
                       let date = ISO8601DateFormatter().date(from: dateString) {
                        return date
                    }
                    return Date()
                },
                set: { date in
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withFullDate]
                    formData[field.id] = formatter.string(from: date)
                }
            ),
            displayedComponents: .date
        )
        .datePickerStyle(CompactDatePickerStyle())
        .disabled(field.readOnly == true)
    }
    
    private func timeFieldInput(field: TemplateField) -> some View {
        DatePicker(
            "",
            selection: Binding(
                get: {
                    if let timeString = formData[field.id] as? String {
                        let formatter = DateFormatter()
                        formatter.timeStyle = .short
                        return formatter.date(from: timeString) ?? Date()
                    }
                    return Date()
                },
                set: { date in
                    let formatter = DateFormatter()
                    formatter.timeStyle = .short
                    formData[field.id] = formatter.string(from: date)
                }
            ),
            displayedComponents: .hourAndMinute
        )
        .datePickerStyle(CompactDatePickerStyle())
        .disabled(field.readOnly == true)
    }
    
    private func selectFieldInput(field: TemplateField) -> some View {
        Picker("", selection: Binding(
            get: { formData[field.id] as? String ?? field.defaultValue ?? "" },
            set: { formData[field.id] = $0 }
        )) {
            Text("Select \(field.label.lowercased())").tag("")
            
            ForEach(field.options ?? [], id: \.self) { option in
                Text(option).tag(option)
            }
        }
        .pickerStyle(MenuPickerStyle())
        .disabled(field.readOnly == true)
    }
    
    private func multiSelectFieldInput(field: TemplateField) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(field.options ?? [], id: \.self) { option in
                ModernCheckboxRow(
                    title: option,
                    isSelected: (formData[field.id] as? [String] ?? []).contains(option)
                ) {
                    var selectedOptions = formData[field.id] as? [String] ?? []
                    if selectedOptions.contains(option) {
                        selectedOptions.removeAll { $0 == option }
                    } else {
                        selectedOptions.append(option)
                    }
                    formData[field.id] = selectedOptions
                }
            }
        }
    }
    
    private func radioFieldInput(field: TemplateField) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(field.options ?? [], id: \.self) { option in
                ModernSegmentButton(
                    title: option,
                    isSelected: formData[field.id] as? String == option
                ) {
                    formData[field.id] = option
                }
            }
        }
    }
    
    private func toggleFieldInput(field: TemplateField) -> some View {
        Toggle("", isOn: Binding(
            get: { formData[field.id] as? Bool ?? false },
            set: { formData[field.id] = $0 }
        ))
        .disabled(field.readOnly == true)
    }
    
    private func fileFieldInput(field: TemplateField) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if selectedImages.isEmpty {
                Button(action: {
                    showImagePicker = true
                }) {
                    HStack {
                        Image(systemName: "photo.fill")
                            .font(.title2)
                        Text("Add Photos")
                            .fontWeight(.medium)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .foregroundColor(.blue)
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            
                            Button(action: {
                                selectedImages.remove(at: index)
                                updateFormDataFromImages()
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(Color.black.opacity(0.7))
                                        .frame(width: 24, height: 24)
                                    
                                    Image(systemName: "xmark")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                            }
                            .padding(4)
                        }
                    }
                    
                    // Add more photos button
                    Button(action: {
                        showImagePicker = true
                    }) {
                        VStack {
                            Image(systemName: "plus")
                                .font(.title)
                                .foregroundColor(.blue)
                        }
                        .frame(width: 100, height: 100)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                
                Text("\(selectedImages.count) photo\(selectedImages.count == 1 ? "" : "s") selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func smartFieldInput(field: TemplateField) -> some View {
        Text(templateService.calculateSmartField(field, formData: formData))
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.systemGray6))
            .cornerRadius(8)
            .foregroundColor(.secondary)
    }
    
    // MARK: - Submit Button
    
    private var submitButton: some View {
        Button(action: {
            submitReport()
        }) {
            HStack {
                if isSubmitting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16))
                }
                
                Text(isSubmitting ? "Submitting..." : "Submit Report")
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue, Color.blue.opacity(0.8)]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(12)
        }
        .disabled(isSubmitting || !isFormValid())
        .opacity(isFormValid() ? 1.0 : 0.6)
    }
    
    // MARK: - Helper Functions
    
    private func loadInitialData() {
        print("🔍 TemplateFormView: Loading initial data for template '\(template.name)'")
        print("🔍 Template has \(template.fields.count) fields")
        
        // Calculate initial smart field values
        for field in template.fields {
            if let smartConfig = field.smartConfig {
                print("🔍 Calculating smart field: \(field.id)")
                let calculatedValue = templateService.calculateSmartField(field, formData: formData)
                formData[field.id] = calculatedValue
                print("🔍 Smart field \(field.id) = '\(calculatedValue)'")
            } else if let defaultValue = field.defaultValue {
                formData[field.id] = defaultValue
                print("🔍 Default field \(field.id) = '\(defaultValue)'")
            }
        }
        
        print("🔍 FormData initialized with \(formData.count) entries")
        
        // Load schools for smart field calculations
        Task {
            do {
                availableSchools = try await templateService.loadSchools()
                print("🔍 Loaded \(availableSchools.count) schools")
            } catch {
                print("❌ Failed to load schools: \(error)")
            }
        }
    }
    
    private func expandAllSections() {
        expandedSections = Set(groupedFields.keys)
        print("🔍 Expanded sections: \(expandedSections.sorted())")
    }
    
    private func toggleSection(_ sectionName: String) {
        if expandedSections.contains(sectionName) {
            expandedSections.remove(sectionName)
        } else {
            expandedSections.insert(sectionName)
        }
    }
    
    private func iconForSection(_ sectionName: String) -> String {
        switch sectionName {
        case "Basic Information": return "info.circle"
        case "Report Details": return "list.bullet"
        case "Calculated Fields": return "sparkles"
        case "Media & Location": return "photo"
        default: return "doc.text"
        }
    }
    
    private func isSectionCompleted(_ sectionName: String, fields: [TemplateField]) -> Bool {
        let requiredFields = fields.filter { $0.required && $0.readOnly != true }
        
        for field in requiredFields {
            if !templateService.validateField(field, value: formData[field.id]) {
                return false
            }
        }
        
        return true
    }
    
    private func calculateCompletedFields() -> Int {
        let editableFields = template.fields.filter { !($0.readOnly ?? false) }
        var completed = 0
        
        for field in editableFields {
            if templateService.validateField(field, value: formData[field.id]) {
                completed += 1
            }
        }
        
        return completed
    }
    
    private func isFormValid() -> Bool {
        for field in template.fields {
            if !templateService.validateField(field, value: formData[field.id]) {
                return false
            }
        }
        return true
    }
    
    private func updateFormDataFromImages() {
        // Update any photo count smart fields
        for field in template.fields {
            if field.smartConfig?.calculationType == "photo_count" {
                formData[field.id] = "\(selectedImages.count)"
            }
        }
    }
    
    private func submitReport() {
        isSubmitting = true
        errorMessage = ""
        
        // Add photo URLs to form data if images are selected
        var finalFormData = formData
        
        if !selectedImages.isEmpty {
            uploadImagesAndSubmit(formData: finalFormData)
        } else {
            submitReportData(formData: finalFormData)
        }
    }
    
    private func uploadImagesAndSubmit(formData: [String: Any]) {
        guard let user = Auth.auth().currentUser else {
            errorMessage = "User not signed in"
            isSubmitting = false
            return
        }
        
        let storageRef = Storage.storage().reference()
        let dispatchGroup = DispatchGroup()
        var photoURLs: [String] = []
        
        for image in selectedImages {
            dispatchGroup.enter()
            if let imageData = image.jpegData(compressionQuality: 0.8) {
                let fileName = "templateReports/\(user.uid)/\(Date().timeIntervalSince1970)_\(UUID().uuidString).jpg"
                let imageRef = storageRef.child(fileName)
                
                imageRef.putData(imageData, metadata: nil) { _, error in
                    if let error = error {
                        DispatchQueue.main.async {
                            self.errorMessage = "Upload error: \(error.localizedDescription)"
                        }
                        dispatchGroup.leave()
                        return
                    }
                    imageRef.downloadURL { url, error in
                        if let error = error {
                            DispatchQueue.main.async {
                                self.errorMessage = "URL error: \(error.localizedDescription)"
                            }
                        } else if let urlString = url?.absoluteString {
                            photoURLs.append(urlString)
                        }
                        dispatchGroup.leave()
                    }
                }
            } else {
                dispatchGroup.leave()
            }
        }
        
        dispatchGroup.notify(queue: .main) {
            var finalData = formData
            finalData["photoURLs"] = photoURLs
            self.submitReportData(formData: finalData)
        }
    }
    
    private func submitReportData(formData: [String: Any]) {
        Task {
            do {
                _ = try await templateService.submitTemplateReport(template: template, formData: formData)
                DispatchQueue.main.async {
                    self.isSubmitting = false
                    self.showSuccessAlert = true
                }
            } catch {
                DispatchQueue.main.async {
                    self.isSubmitting = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}


// MARK: - Preview

struct TemplateFormView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleTemplate = ReportTemplate(
            name: "Sample Sports Report",
            description: "A sample template for testing",
            shootType: "sports",
            organizationID: "test",
            fields: [
                TemplateField(
                    type: "text",
                    label: "Event Name",
                    required: true,
                    placeholder: "Enter event name"
                ),
                TemplateField(
                    type: "mileage",
                    label: "Round Trip Mileage",
                    smartConfig: SmartFieldConfig(calculationType: "mileage"),
                    readOnly: true
                )
            ],
            createdBy: "test"
        )
        
        TemplateFormView(template: sampleTemplate)
    }
}