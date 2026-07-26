//
//  CreateTaskView.swift
//  Iconik Employee
//
//  View for creating a new task.
//
//  AMB.5 RESTYLED THIS IN PLACE, AND DELIBERATELY DID NOT REDESIGN IT.
//      This screen was never mocked — AMB_BATCH1_PARITY.md recorded that at the
//      time — and D10 is a hard gate: nothing is redesigned before the operator
//      has approved a running mockup of it. So the change here is the minimum that
//      stops a plain grouped Form opening over a washed, glass screen and reading
//      as a different app: the ambient wash behind it, a transparent Form scroll
//      background so the wash shows, and the shared priority colours.
//
//      Every section, control, bound value, validation and label is untouched.
//      Real input design — fields, pickers, form rhythm — is AMB.7's, which the
//      plan already names as the arc's first form-heavy phase.
//

import SwiftUI

struct CreateTaskView: View {
    @Environment(\.presentationMode) var presentationMode
    let onTaskCreated: (TaskItem) -> Void

    private var feature: Color { FeatureTheme.color(for: "tasks") }

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
            // Same shape AMB.3 settled on for every Equipment form: the wash
            // behind, the Form's own grouped background hidden, the feature colour
            // as the tint for controls.
            ZStack {
                AmbientBackdrop(tint: feature, intensity: 0.7)
                form.scrollContentBackground(.hidden)
            }
            .navigationTitle("New Task")
            .navigationBarTitleDisplayMode(.inline)
            .tint(feature)
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
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var form: some View {
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
                                    .fill(priority.tint)
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
}

struct CreateTaskView_Previews: PreviewProvider {
    static var previews: some View {
        CreateTaskView { task in
            print("Created task item: \(task.title)")
        }
    }
}
