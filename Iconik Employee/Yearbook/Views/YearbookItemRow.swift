import SwiftUI

struct YearbookItemRow: View {
    let item: YearbookItem
    let onToggle: () -> Void
    let onTap: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Button(action: onToggle) {
                Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(item.completed ? .green : .gray)
                    .animation(.easeInOut(duration: 0.2), value: item.completed)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.name)
                        .font(.body)
                        .fontWeight(item.required ? .medium : .regular)
                        .strikethrough(item.completed)
                        .foregroundColor(item.completed ? .secondary : .primary)
                    
                    if item.required {
                        Text("REQUIRED")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .cornerRadius(4)
                    }
                }
                
                if let description = item.description, !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                // Metadata
                HStack(spacing: 12) {
                    if item.completed {
                        if let photographer = item.photographerName {
                            Label(photographer, systemImage: "person.fill")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        if let date = item.completedDate {
                            Label(itemDateFormatter.string(from: date), systemImage: "calendar")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if let imageNumbers = item.imageNumbers, !imageNumbers.isEmpty {
                        Label("\(imageNumbers.count) images", systemImage: "photo")
                            .font(.caption2)
                            .foregroundColor(.blue)
                    }
                    
                    if item.notes != nil {
                        Image(systemName: "note.text")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Spacer()
            
            // Chevron for details
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .scaleEffect(isPressed ? 0.98 : 1.0)
        .onTapGesture {
            onTap()
        }
        .onLongPressGesture(
            minimumDuration: 0.1,
            maximumDistance: .infinity,
            pressing: { pressing in
                withAnimation(.easeInOut(duration: 0.1)) {
                    isPressed = pressing
                }
            },
            perform: {}
        )
    }
    
    private var itemDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }
}

// MARK: - Item Detail View
struct YearbookItemDetailView: View {
    @Environment(\.presentationMode) var presentationMode
    
    let item: YearbookItem
    let listId: String
    @ObservedObject var viewModel: YearbookShootListViewModel
    
    @State private var notes: String = ""
    @State private var imageNumbersText: String = ""
    @State private var showingImagePicker = false
    @State private var isSaving = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Item Details")) {
                    HStack {
                        Text("Name")
                        Spacer()
                        Text(item.name)
                            .foregroundColor(.secondary)
                    }
                    
                    if let description = item.description {
                        HStack(alignment: .top) {
                            Text("Description")
                            Spacer()
                            Text(description)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    
                    HStack {
                        Text("Category")
                        Spacer()
                        Text(item.category)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Status")
                        Spacer()
                        HStack {
                            Image(systemName: item.completed ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(item.completed ? .green : .gray)
                            Text(item.completed ? "Completed" : "Incomplete")
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    if item.required {
                        HStack {
                            Text("Priority")
                            Spacer()
                            Text("REQUIRED")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color.red.opacity(0.1))
                                .foregroundColor(.red)
                                .cornerRadius(4)
                        }
                    }
                }
                
                if item.completed {
                    Section(header: Text("Completion Details")) {
                        if let photographer = item.photographerName {
                            HStack {
                                Text("Photographer")
                                Spacer()
                                Text(photographer)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if let date = item.completedDate {
                            HStack {
                                Text("Date Completed")
                                Spacer()
                                Text(date, formatter: detailDateFormatter)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if let sessionId = item.completedBySession {
                            HStack {
                                Text("Session")
                                Spacer()
                                Text(sessionId)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
                
                Section(header: Text("Image Numbers")) {
                    TextField("Enter image numbers (comma separated)", text: $imageNumbersText)
                        .autocapitalization(.none)
                    
                    if !imageNumbersText.isEmpty {
                        Text("Images: \(imageNumbersArray.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Notes")) {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
                
                Section {
                    Button(action: toggleCompletion) {
                        HStack {
                            Image(systemName: item.completed ? "xmark.circle" : "checkmark.circle")
                            Text(item.completed ? "Mark as Incomplete" : "Mark as Complete")
                        }
                        .foregroundColor(item.completed ? .red : .green)
                    }
                }
            }
            .navigationTitle("Item Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear {
                notes = item.notes ?? ""
                imageNumbersText = item.imageNumbers?.joined(separator: ", ") ?? ""
            }
        }
    }
    
    private var imageNumbersArray: [String] {
        imageNumbersText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    private var detailDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
    
    private func toggleCompletion() {
        Task {
            await viewModel.toggleItemCompletion(item)
            presentationMode.wrappedValue.dismiss()
        }
    }
    
    private func saveChanges() {
        isSaving = true
        
        Task {
            // Save notes
            let notesToSave = notes.isEmpty ? nil : notes
            await viewModel.updateItemNotes(item, notes: notesToSave)
            
            // Save image numbers
            await viewModel.updateItemImageNumbers(item, imageNumbers: imageNumbersArray)
            
            isSaving = false
            presentationMode.wrappedValue.dismiss()
        }
    }
}

// MARK: - Preview
struct YearbookItemRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            YearbookItemRow(
                item: YearbookItem(
                    name: "Team Photo",
                    description: "Full team photo with coaches",
                    category: "Sports",
                    required: true,
                    completed: false,
                    order: 1
                ),
                onToggle: {},
                onTap: {}
            )
            .padding()
            
            YearbookItemRow(
                item: YearbookItem(
                    name: "Individual Player Photos",
                    description: "Portrait shots of each player",
                    category: "Sports",
                    required: true,
                    completed: true,
                    completedDate: Date(),
                    photographerName: "John Doe",
                    imageNumbers: ["IMG_1234", "IMG_1235", "IMG_1236"],
                    notes: "Completed during morning session",
                    order: 2
                ),
                onToggle: {},
                onTap: {}
            )
            .padding()
        }
    }
}