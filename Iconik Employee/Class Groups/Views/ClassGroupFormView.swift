//  ClassGroupFormView.swift
//  Iconik Employee — adding and editing one row, converted to Ambient in AMB.10
//
//  ONE FORM FOR ADD AND EDIT. It replaces `AddClassGroupView.swift`, which is
//  DELETED in the same change: that file held TWO line-for-line duplicate views
//  (`AddClassGroupView` at :3 and `EditClassGroupView` at :178) differing only in
//  container, title, populate-on-appear and dismissal API — which is exactly how
//  they came to disagree about navigation style (`NavigationView` + Stack vs
//  `NavigationStack`, so the same form could render split on iPad from one entry
//  and not from the other) and to grow four separate copies of the same two
//  validation rules.
//
//  WHAT THIS FORM GAINED, and why each is in scope:
//    · THE GRADES ARE ON THE SURFACE. Fourteen of them lived behind a `Menu` you
//      had to know to open; they are chips now, and the tap target is the thing you
//      are choosing. Still not drawn for Clubs — a club name is not on a list.
//    · THE NOTES FIELD SAYS WHAT IT IS FOR. It was an unlabelled grey box.
//    · THE SLATE KNOWS THE SCHOOL. Both old form paths passed `schoolName: nil`
//      (`AddClassGroupView.swift:135`, `:315`), so the whiteboard opened from the
//      form was missing the one line that says which school you are standing in —
//      even though the form was reached from a job that knows. The detail screen
//      passes it down now.
//    · ONE SET OF RULES. The row title, the counts and the "is this saveable" test
//      all come from `ClassGroupsRules`, which is compiled and run by
//      `scripts/test_classgroups_rules.sh`.
//
//  UNCHANGED, deliberately: every field is optional except the grade; Save trims
//  all four; the failure alert wording; `onComplete(false)` is still never called
//  (a cancel is not a failure, and no caller distinguishes the two).

import SwiftUI

struct ClassGroupFormView: View {

    /// Add or edit. The edit case carries the row it opened on, which is the only
    /// difference between the two flows that survives into the body.
    enum Mode {
        case add
        case edit(ClassGroup)

        var existingGroup: ClassGroup? {
            if case .edit(let group) = self { return group }
            return nil
        }
    }

    let mode: Mode
    let jobId: String
    let jobType: String
    /// The job's school, so the whiteboard opened from here is complete. Optional
    /// because the detail screen may still be loading its job.
    let schoolName: String?
    let onComplete: (Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var grade = ""
    @State private var teacher = ""
    @State private var imageNumbers = ""
    @State private var notes = ""

    @State private var isSaving = false
    @State private var errorMessage = ""
    @State private var showingErrorAlert = false
    @State private var showingWhiteboard = false

    @FocusState private var focusedField: ClassGroupFormField?

    /// Populate ONCE. `onAppear` refires when the whiteboard's `fullScreenCover`
    /// closes (a cover removes the presenting view), and re-populating there would
    /// silently revert everything typed since the sheet opened — the same guard
    /// `YearbookItemDetailView` carries for the same reason.
    @State private var didPopulate = false

    private let service = ClassGroupJobService.shared

    private var tint: Color { ClassGroupsStyle.tint }

    private var trimmedGrade: String {
        grade.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isFormValid: Bool {
        ClassGroupsRules.isFormValid(grade: grade)
    }

    private var imageCount: Int {
        ClassGroupsRules.imageCount(imageNumbers)
    }

    private var title: String {
        switch mode {
        case .add:  return "Add \(ClassGroupJobType.singularTitle(jobType))"
        case .edit: return "Edit \(ClassGroupJobType.singularTitle(jobType))"
        }
    }

    var body: some View {
        // NavigationView + Stack style on BOTH modes. The edit form used a
        // `NavigationStack` and the add form a `NavigationView` + Stack, so one of
        // them could render split on iPad and the other could not.
        NavigationView {
            ZStack {
                AmbientBackdrop(tint: tint, intensity: 0.6)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        informationSection
                        imagesSection
                        notesSection
                        ClassGroupWhiteboardButton(
                            primaryFieldLabel: ClassGroupJobType.primaryFieldLabel(jobType),
                            isEnabled: isFormValid,
                            tint: tint) { showingWhiteboard = true }
                        if isSaving { savingLine }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .ambientNoBounceWhenShort()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isSaving || !isFormValid)
                }
            }
            .alert("Error", isPresented: $showingErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear(perform: populate)
        .fullScreenCover(isPresented: $showingWhiteboard) {
            ClassGroupSlateView(grade: trimmedGrade,
                                teacher: teacher,
                                schoolName: schoolName)
        }
    }

    // MARK: - Sections

    /// "Class Information" / "Candid Information" / "Club Information", with the
    /// field labels following: Grade / Club Name, Teacher Name / Advisor Name.
    private var informationSection: some View {
        AmbientFormSection(
            title: "\(ClassGroupJobType.formNoun(jobType)) Information",
            status: trimmedGrade.isEmpty ? "required" : trimmedGrade,
            statusTint: trimmedGrade.isEmpty ? .orange : nil
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ClassGroupTextField(label: ClassGroupJobType.primaryFieldLabel(jobType),
                                    text: $grade,
                                    focus: $focusedField,
                                    field: .primary) {
                    focusedField = .secondary
                }

                if ClassGroupJobType.showsGradeSuggestions(jobType) {
                    ClassGroupGradeChips(grade: $grade, tint: tint)
                }

                Divider()

                ClassGroupTextField(label: ClassGroupJobType.secondaryFieldLabel(jobType),
                                    text: $teacher,
                                    focus: $focusedField,
                                    field: .secondary) {
                    focusedField = .images
                }
                Text("Optional. A row with no \(ClassGroupJobType.secondaryFieldLabel(jobType).lowercased()) shows the \(ClassGroupJobType.primaryFieldLabel(jobType).lowercased()) alone — not a dangling dash.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var imagesSection: some View {
        AmbientFormSection(
            title: "Images",
            status: ClassGroupsRules.imagesFieldStatus(count: imageCount),
            statusTint: imageCount == 0 ? nil : .blue
        ) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("1042, 1043, 1051", text: $imageNumbers)
                    .font(.subheadline)
                    .keyboardType(.numbersAndPunctuation)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .images)
                    .onSubmit { focusedField = .notes }
                Text("Comma separated. These are frame NUMBERS, not photos — nothing in this feature stores an image.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var notesSection: some View {
        AmbientFormSection(
            title: "Notes",
            status: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "optional" : "written",
            statusTint: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : .orange
        ) {
            ClassGroupNotesEditor(notes: $notes, focus: $focusedField)
        }
    }

    private var savingLine: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("Saving…").font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Data

    private func populate() {
        guard !didPopulate, let existing = mode.existingGroup else { return }
        didPopulate = true
        grade = existing.grade
        teacher = existing.teacher
        imageNumbers = existing.imageNumbers
        notes = existing.notes
    }

    private func save() {
        guard !isSaving, isFormValid else { return }
        isSaving = true

        let trimmed = ClassGroup(
            // The edit path KEEPS THE ROW'S ID. `updateClassGroup` matches on it
            // case-sensitively and silently persists the unmodified array when it
            // misses, so a new id here would be a save that reports success and
            // changes nothing.
            id: mode.existingGroup?.id ?? UUID().uuidString,
            grade: trimmedGrade,
            teacher: teacher.trimmingCharacters(in: .whitespacesAndNewlines),
            imageNumbers: imageNumbers.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        let completion: (Result<Void, Error>) -> Void = { result in
            DispatchQueue.main.async {
                self.isSaving = false
                switch result {
                case .success:
                    AmbientHaptics.impact(.medium)
                    self.onComplete(true)
                    self.dismiss()
                case .failure(let error):
                    switch self.mode {
                    case .add:  self.errorMessage = "Failed to save: \(error.localizedDescription)"
                    case .edit: self.errorMessage = "Failed to update: \(error.localizedDescription)"
                    }
                    self.showingErrorAlert = true
                }
            }
        }

        switch mode {
        case .add:
            service.addClassGroup(toJobId: jobId, classGroup: trimmed, completion: completion)
        case .edit:
            service.updateClassGroup(jobId: jobId, classGroup: trimmed, completion: completion)
        }
    }
}
