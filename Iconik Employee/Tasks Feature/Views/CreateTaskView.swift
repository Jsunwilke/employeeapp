//
//  CreateTaskView.swift
//  Iconik Employee
//
//  View for creating a new task
//

import SwiftUI

struct CreateTaskView: View {
    @Environment(\.presentationMode) var presentationMode
    let onTaskCreated: (TaskItem) -> Void

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var priority: TaskPriority = .medium
    @State private var dueDate: Date = Date()
    @State private var hasDueDate: Bool = false
    @State private var estimatedHours: Double = 0
    @State private var subtasks: [Subtask] = []
    @State private var newSubtaskTitle: String = ""

    private var currentUserId: String {
        return UserManager.shared.getCurrentUserIDUnified() ?? ""
    }

    private var currentOrganizationId: String {
        return UserManager.shared.getCachedOrganizationID()
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Basic Information")) {
                    TextField("Task Title", text: $title)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Description")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextEditor(text: $description)
                            .frame(height: 100)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                            )
                    }
                }

                Section(header: Text("Priority")) {
                    Picker("Priority", selection: $priority) {
                        ForEach(TaskPriority.allCases, id: \.self) { priority in
                            HStack {
                                Text(priority.displayName)
                                Spacer()
                                Circle()
                                    .fill(priorityColor(priority))
                                    .frame(width: 12, height: 12)
                            }
                            .tag(priority)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }

                Section(header: Text("Due Date")) {
                    Toggle("Set Due Date", isOn: $hasDueDate)

                    if hasDueDate {
                        DatePicker("Due Date", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    }
                }

                Section(header: Text("Estimation")) {
                    Stepper(value: $estimatedHours, in: 0...100, step: 0.5) {
                        HStack {
                            Text("Estimated Hours")
                            Spacer()
                            Text(estimatedHours == 0 ? "Not set" : "\(estimatedHours, specifier: "%.1f")h")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("Subtasks")) {
                    // Add new subtask
                    HStack {
                        TextField("New subtask", text: $newSubtaskTitle)
                            .textFieldStyle(RoundedBorderTextFieldStyle())

                        Button(action: addSubtask) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundColor(.blue)
                        }
                        .disabled(newSubtaskTitle.isEmpty)
                    }

                    // List of added subtasks
                    if !subtasks.isEmpty {
                        ForEach(subtasks) { subtask in
                            HStack {
                                Image(systemName: "circle")
                                    .foregroundColor(.gray)
                                    .font(.caption)

                                Text(subtask.title)
                                    .font(.body)

                                Spacer()

                                Button(action: {
                                    deleteSubtask(subtask)
                                }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }

                Section {
                    Text("You will be automatically assigned to this task and set as a watcher.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        createTask()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }

    private func createTask() {
        let task = TaskItem(
            organizationID: currentOrganizationId,
            createdBy: currentUserId,
            title: title,
            description: description.isEmpty ? nil : description,
            priority: priority,
            assignedTo: [currentUserId],  // Auto-assign to creator
            watchers: [currentUserId],     // Auto-watch for creator
            dueDate: hasDueDate ? dueDate : nil,
            estimatedHours: estimatedHours,
            subtasks: subtasks
        )

        onTaskCreated(task)
    }

    private func addSubtask() {
        guard !newSubtaskTitle.isEmpty else { return }
        let newSubtask = Subtask(title: newSubtaskTitle)
        subtasks.append(newSubtask)
        newSubtaskTitle = ""
    }

    private func deleteSubtask(_ subtask: Subtask) {
        subtasks.removeAll { $0.id == subtask.id }
    }

    private func priorityColor(_ priority: TaskPriority) -> Color {
        switch priority {
        case .low: return .gray
        case .medium: return .blue
        case .high: return .orange
        case .urgent: return .red
        }
    }
}

struct CreateTaskView_Previews: PreviewProvider {
    static var previews: some View {
        CreateTaskView { task in
            print("Created task item: \(task.title)")
        }
    }
}
