//
//  FPSportsAddSubjectView.swift
//  Iconik Employee
//
//  Add/edit a single FPSubject for FP Sports.
//  Parallel to AddRosterEntryView but writes to Production subjects table.
//

import SwiftUI
import Combine

struct FPSportsAddSubjectView: View {
    let galleryId: String
    let organizationId: String
    let existingSubject: FPSubject?
    let shootType: String?
    /// Called on save complete. Second arg is the optimistic subject the
    /// caller can splice into its in-memory list so the UI shows the edit
    /// immediately (without waiting for Surface→Supabase→PowerSync round-trip).
    /// Nil on cancel/failure. See 2026-04-22 walk-in name loss analysis.
    let onComplete: (Bool, FPSubject?) -> Void


    @State private var lastName: String = ""
    @State private var firstName: String = ""
    @State private var rosterId: String = ""
    @State private var teacher: String = ""
    @State private var sport: String = ""
    @State private var grade: String = ""
    @State private var jerseyNumber: String = ""
    @State private var position: String = ""
    @State private var email: String = ""
    @State private var phone: String = ""
    @State private var imageNumbers: String = ""
    @State private var notes: String = ""

    // Extended fields (Production parity)
    @State private var homeroom: String = ""
    @State private var studentId: String = ""
    @State private var onlineCode: String = ""
    @State private var organizationName: String = ""
    @State private var year: String = ""
    @State private var subjectType: String = ""
    @State private var title: String = ""
    @State private var referenceNumber: String = ""
    @State private var photographer: String = ""
    @State private var photoSessionDate: String = ""
    @State private var expirationDate: String = ""
    @State private var phone2: String = ""
    @State private var address1: String = ""
    @State private var address2: String = ""
    @State private var city: String = ""
    @State private var state: String = ""
    @State private var zip: String = ""
    @State private var country: String = ""
    @State private var mother: String = ""
    @State private var father: String = ""
    @State private var personalization: String = ""
    @State private var discountCode: String = ""
    @State private var customValues: [String] = Array(repeating: "", count: 20)

    @State private var showAllFields = false

    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showingErrorAlert = false
    @State private var isLoadingSubjectID = false
    @State private var existingSubjects: [FPSubject] = []

    // Duplicate roster ID warning
    @State private var showingDuplicateWarning = false
    @State private var duplicateSubjectName = ""

    // Lock state
    @State private var lockAcquired = false
    @State private var lockError: String?
    @State private var isAcquiringLock = false

    @FocusState private var focusedField: String?
    @Environment(\.presentationMode) var presentationMode

    var isEditing: Bool { existingSubject != nil }

    // MARK: - Per-field visibility

    private var isEvents: Bool {
        let st = shootType?.lowercased() ?? ""
        return st == "events" || st == "event"
    }

    private func anyHas(_ keyPath: KeyPath<FPSubject, String>) -> Bool {
        existingSubjects.contains { !$0[keyPath: keyPath].isEmpty }
    }

    private var showHomeroom: Bool { showAllFields || anyHas(\.homeroom) }
    private var showStudentId: Bool { showAllFields || anyHas(\.studentId) }
    private var showOnlineCode: Bool { showAllFields || anyHas(\.onlineCode) }
    private var showOrganization: Bool { showAllFields || isEvents || anyHas(\.organizationName) }
    private var showYear: Bool { showAllFields || anyHas(\.year) }
    private var showSubjectType: Bool { showAllFields || anyHas(\.subjectType) }
    private var showTitle: Bool { showAllFields || anyHas(\.title) }
    private var showReferenceNumber: Bool { showAllFields || anyHas(\.referenceNumber) }
    private var showPhotographer: Bool { showAllFields || anyHas(\.photographer) }
    private var showPhotoSessionDate: Bool { showAllFields || anyHas(\.photoSessionDate) }
    private var showExpirationDate: Bool { showAllFields || anyHas(\.expirationDate) }
    private var showPhone2: Bool { showAllFields || anyHas(\.phone2) }
    private var showAddress1: Bool { showAllFields || anyHas(\.address1) }
    private var showAddress2: Bool { showAllFields || anyHas(\.address2) }
    private var showCity: Bool { showAllFields || anyHas(\.city) }
    private var showState: Bool { showAllFields || anyHas(\.state) }
    private var showZip: Bool { showAllFields || anyHas(\.zip) }
    private var showCountry: Bool { showAllFields || anyHas(\.country) }
    private var showMother: Bool { showAllFields || anyHas(\.mother) }
    private var showFather: Bool { showAllFields || anyHas(\.father) }
    private var showPersonalization: Bool { showAllFields || anyHas(\.personalization) }
    private var showDiscountCode: Bool { showAllFields || anyHas(\.discountCode) }

    private static let customKeyPaths: [KeyPath<FPSubject, String>] = [
        \.custom1, \.custom2, \.custom3, \.custom4, \.custom5,
        \.custom6, \.custom7, \.custom8, \.custom9, \.custom10,
        \.custom11, \.custom12, \.custom13, \.custom14, \.custom15,
        \.custom16, \.custom17, \.custom18, \.custom19, \.custom20
    ]
    private func showCustom(_ index: Int) -> Bool {
        showAllFields || existingSubjects.contains { !$0[keyPath: FPSportsAddSubjectView.customKeyPaths[index]].isEmpty }
    }
    private var anySchoolExtraVisible: Bool { showHomeroom || showStudentId || showOnlineCode }
    private var anyEventInfoVisible: Bool {
        showYear || showSubjectType || showTitle || showReferenceNumber ||
        showPhotographer || showPhotoSessionDate || showExpirationDate
    }
    private var anyAddressVisible: Bool {
        showPhone2 || showAddress1 || showAddress2 || showCity || showState || showZip || showCountry
    }
    private var anyFamilyVisible: Bool { showMother || showFather }
    private var anyAdditionalVisible: Bool { showPersonalization || showDiscountCode }
    private var anyCustomVisible: Bool { (0..<20).contains { showCustom($0) } }

    var body: some View {
        NavigationView {
            if let error = lockError {
                lockErrorView(error)
            } else if isAcquiringLock {
                VStack(spacing: 16) {
                    ProgressView().scaleEffect(1.5)
                    Text("Acquiring lock...").foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationBarTitle(isEditing ? "Edit Athlete" : "Add Athlete", displayMode: .inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                    }
                }
            } else {
                formContent
            }
        }
        .task { await acquireLockIfNeeded() }
        .onDisappear { releaseLockIfNeeded() }
    }

    // MARK: - Lock Error View

    private func lockErrorView(_ error: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill").font(.system(size: 60)).foregroundColor(.red)
            Text("Cannot Edit").font(.title2).fontWeight(.bold)
            Text(error).multilineTextAlignment(.center).foregroundColor(.secondary).padding(.horizontal)
            Button("Go Back") { presentationMode.wrappedValue.dismiss() }
                .padding().background(Color.blue).foregroundColor(.white).cornerRadius(10)
        }
        .padding()
        .navigationBarTitle("Locked", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { presentationMode.wrappedValue.dismiss() }
            }
        }
    }

    // MARK: - Form

    private var formContent: some View {
        Form {
            Section(header: Text("Athlete Information")) {
                TextField("First Name", text: $firstName)
                    .autocapitalization(.words)
                    .focused($focusedField, equals: "firstName")
                    .submitLabel(.next)
                    .onSubmit { focusedField = "lastName" }

                TextField("Last Name", text: $lastName)
                    .autocapitalization(.words)
                    .focused($focusedField, equals: "lastName")
                    .submitLabel(.next)
                    .onSubmit { focusedField = "rosterId" }

                TextField("Roster ID", text: $rosterId)
                    .focused($focusedField, equals: "rosterId")
                    .submitLabel(.next)
                    .onSubmit { focusedField = "sport" }

                TextField("Sport/Team", text: $sport)
                    .autocapitalization(.words)
                    .focused($focusedField, equals: "sport")
                    .submitLabel(.next)
                    .onSubmit { focusedField = "teacher" }

                TextField("Special", text: $teacher)
                    .autocapitalization(.words)
                    .focused($focusedField, equals: "teacher")
                    .submitLabel(.next)
                    .onSubmit { focusedField = "grade" }

                TextField("Grade", text: $grade)
                    .focused($focusedField, equals: "grade")
                    .submitLabel(.next)
                    .onSubmit { focusedField = "jerseyNumber" }

                TextField("Jersey Number", text: $jerseyNumber)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: "jerseyNumber")

                TextField("Position", text: $position)
                    .focused($focusedField, equals: "position")
                    .submitLabel(.next)
                    .onSubmit { focusedField = "email" }
            }

            if showOrganization {
                Section(header: Text("Organization")) {
                    TextField("Organization", text: $organizationName)
                }
            }

            if anySchoolExtraVisible {
                Section(header: Text("School")) {
                    if showHomeroom { TextField("Homeroom", text: $homeroom) }
                    if showStudentId { TextField("Student ID", text: $studentId) }
                    if showOnlineCode { TextField("Online Code", text: $onlineCode) }
                }
            }

            if anyEventInfoVisible {
                Section(header: Text("Event Info")) {
                    if showYear { TextField("Year", text: $year) }
                    if showSubjectType { TextField("Subject Type", text: $subjectType) }
                    if showTitle { TextField("Title", text: $title) }
                    if showReferenceNumber { TextField("Reference #", text: $referenceNumber) }
                    if showPhotographer { TextField("Photographer", text: $photographer) }
                    if showPhotoSessionDate { TextField("Session Date (YYYY-MM-DD)", text: $photoSessionDate) }
                    if showExpirationDate { TextField("Expiration Date (YYYY-MM-DD)", text: $expirationDate) }
                }
            }

            Section(header: Text("Contact Information")) {
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .focused($focusedField, equals: "email")
                    .submitLabel(.next)
                    .onSubmit { focusedField = "phone" }

                TextField("Phone", text: $phone)
                    .keyboardType(.phonePad)
                    .focused($focusedField, equals: "phone")

                if showPhone2 { TextField("Phone 2", text: $phone2).keyboardType(.phonePad) }
                if showAddress1 { TextField("Address", text: $address1) }
                if showAddress2 { TextField("Address 2", text: $address2) }
                if showCity { TextField("City", text: $city) }
                if showState { TextField("State", text: $state) }
                if showZip { TextField("Zip", text: $zip).keyboardType(.numbersAndPunctuation) }
                if showCountry { TextField("Country", text: $country) }
            }

            if anyFamilyVisible {
                Section(header: Text("Family")) {
                    if showMother { TextField("Mother / Guardian", text: $mother) }
                    if showFather { TextField("Father / Guardian", text: $father) }
                }
            }

            if anyAdditionalVisible {
                Section(header: Text("Additional")) {
                    if showPersonalization { TextField("Personalization", text: $personalization) }
                    if showDiscountCode { TextField("Discount Code", text: $discountCode) }
                }
            }

            Section(header: Text("Image Information")) {
                TextField("Image Numbers (semicolon-separated)", text: $imageNumbers)
                    .focused($focusedField, equals: "imageNumbers")

                TextView(text: $notes, placeholder: "Notes (optional)")
                    .frame(minHeight: 100)
            }

            if anyCustomVisible {
                Section(header: Text("Custom Fields")) {
                    ForEach(0..<20, id: \.self) { i in
                        if showCustom(i) {
                            TextField("Custom \(i + 1)", text: $customValues[i])
                        }
                    }
                }
            }

            Section {
                Button(action: { showAllFields.toggle() }) {
                    Label(showAllFields ? "Hide empty fields" : "Show all fields",
                          systemImage: showAllFields ? "eye.slash" : "eye")
                }
            }

            if isLoading {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        }
        .navigationBarTitle(isEditing ? "Edit Athlete" : "Add Athlete", displayMode: .inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") { presentationMode.wrappedValue.dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(isEditing ? "Update" : "Save") { saveSubject() }
                    .disabled(isLoading)
            }
        }
        .alert(isPresented: $showingErrorAlert) {
            Alert(title: Text("Error"), message: Text(errorMessage), dismissButton: .default(Text("OK")))
        }
        .alert(isPresented: $showingDuplicateWarning) {
            Alert(
                title: Text("Duplicate Roster ID"),
                message: Text("Roster ID \(rosterId) is already assigned to \(duplicateSubjectName). Save anyway?"),
                primaryButton: .default(Text("Save Anyway")) {
                    executeSave()
                },
                secondaryButton: .cancel()
            )
        }
        .onAppear {
            if let s = existingSubject {
                lastName = s.lastName
                firstName = s.firstName
                rosterId = s.rosterId
                teacher = s.teacher
                sport = s.sport
                grade = s.grade
                jerseyNumber = s.jerseyNumber
                position = s.position
                email = s.email
                phone = s.phone
                imageNumbers = s.imageNumbers
                notes = s.notes
                // Extended fields
                homeroom = s.homeroom
                studentId = s.studentId
                onlineCode = s.onlineCode
                organizationName = s.organizationName
                year = s.year
                subjectType = s.subjectType
                title = s.title
                referenceNumber = s.referenceNumber
                photographer = s.photographer
                photoSessionDate = s.photoSessionDate
                expirationDate = s.expirationDate
                phone2 = s.phone2
                address1 = s.address1
                address2 = s.address2
                city = s.city
                state = s.state
                zip = s.zip
                country = s.country
                mother = s.mother
                father = s.father
                personalization = s.personalization
                discountCode = s.discountCode
                customValues = [
                    s.custom1, s.custom2, s.custom3, s.custom4, s.custom5,
                    s.custom6, s.custom7, s.custom8, s.custom9, s.custom10,
                    s.custom11, s.custom12, s.custom13, s.custom14, s.custom15,
                    s.custom16, s.custom17, s.custom18, s.custom19, s.custom20
                ]
                // Load roster so per-field visibility can detect what other subjects have.
                // Phase H4 — subject read source is the SubscriptionCache.
                // The PowerSync getSubjects call this replaced was deleted in
                // the same commit per FROM_SCRATCH_ARCHITECTURE.md rule 19.1.
                Task {
                    let loaded = SubscriptionCache.shared.subjects(forGalleryId: galleryId)
                    await MainActor.run { existingSubjects = loaded }
                }
            } else {
                loadNextRosterId()
            }
        }
    }

    // MARK: - Lock Management (uses subjects table, not roster_entries)

    private func acquireLockIfNeeded() async {
        guard let subject = existingSubject else {
            // New subject — no lock needed
            lockAcquired = true
            return
        }
        isAcquiringLock = true
        let acquired = await LockManager.shared.acquireSubjectLock(subjectId: subject.id)
        await MainActor.run {
            isAcquiringLock = false
            if acquired {
                lockAcquired = true
            } else {
                lockError = subject.lockedByName.map { "This athlete is being edited by \($0)." }
                    ?? "This athlete is being edited by another device."
            }
        }
    }

    private func releaseLockIfNeeded() {
        guard let subject = existingSubject, lockAcquired else { return }
        Task { await LockManager.shared.releaseSubjectLock(subjectId: subject.id) }
    }

    // MARK: - Data Loading

    private func loadNextRosterId() {
        isLoadingSubjectID = true
        Task {
            // Phase H4 — subject read source is the SubscriptionCache.
            // The PowerSync getSubjects call this replaced was deleted in
            // the same commit per FROM_SCRATCH_ARCHITECTURE.md rule 19.1.
            // Synchronous + non-throwing; the prior do/catch fallback
            // (rosterId = "101") is now redundant with the existing
            // `?? 100` default that produces 101 from an empty list.
            let subjects = SubscriptionCache.shared.subjects(forGalleryId: galleryId)
            let highestID = subjects.compactMap { Int($0.rosterId) }.max() ?? 100
            await MainActor.run {
                existingSubjects = subjects
                rosterId = "\(highestID + 1)"
                isLoadingSubjectID = false
            }
        }
    }

    // MARK: - Save

    private func cap(_ s: String, _ max: Int) -> String { String(s.prefix(max)) }

    private func saveSubject() {
        let trimmedRosterId = cap(rosterId.trimmingCharacters(in: .whitespacesAndNewlines), 50)

        // Check for duplicate roster ID (only for new subjects, not edits)
        if !isEditing && !trimmedRosterId.isEmpty {
            let dup = existingSubjects.first { $0.rosterId == trimmedRosterId }
            if let dup = dup {
                let name = [dup.firstName, dup.lastName].filter { !$0.isEmpty }.joined(separator: " ")
                duplicateSubjectName = name.isEmpty ? "ID \(dup.rosterId)" : name
                showingDuplicateWarning = true
                return
            }
        }

        executeSave()
    }

    private func executeSave() {
        let trimmedCustoms = customValues.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let subject = FPSubject(
            id: existingSubject?.id ?? UUID(),
            galleryId: galleryId,
            organizationId: organizationId,
            firstName: cap(firstName.trimmingCharacters(in: .whitespacesAndNewlines), 200),
            lastName: cap(lastName.trimmingCharacters(in: .whitespacesAndNewlines), 200),
            grade: cap(grade.trimmingCharacters(in: .whitespacesAndNewlines), 50),
            teacher: cap(teacher.trimmingCharacters(in: .whitespacesAndNewlines), 50),
            homeroom: cap(homeroom.trimmingCharacters(in: .whitespacesAndNewlines), 100),
            studentId: cap(studentId.trimmingCharacters(in: .whitespacesAndNewlines), 100),
            rosterId: cap(rosterId.trimmingCharacters(in: .whitespacesAndNewlines), 50),
            jerseyNumber: cap(jerseyNumber.trimmingCharacters(in: .whitespacesAndNewlines), 50),
            sport: cap(sport.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), 100),
            position: cap(position.trimmingCharacters(in: .whitespacesAndNewlines), 100),
            organizationName: cap(organizationName.trimmingCharacters(in: .whitespacesAndNewlines), 200),
            year: cap(year.trimmingCharacters(in: .whitespacesAndNewlines), 50),
            subjectType: cap(subjectType.trimmingCharacters(in: .whitespacesAndNewlines), 50),
            title: cap(title.trimmingCharacters(in: .whitespacesAndNewlines), 200),
            referenceNumber: cap(referenceNumber.trimmingCharacters(in: .whitespacesAndNewlines), 100),
            photographer: cap(photographer.trimmingCharacters(in: .whitespacesAndNewlines), 200),
            photoSessionDate: photoSessionDate.trimmingCharacters(in: .whitespacesAndNewlines),
            expirationDate: expirationDate.trimmingCharacters(in: .whitespacesAndNewlines),
            email: cap(email.trimmingCharacters(in: .whitespacesAndNewlines), 254),
            phone: phone.trimmingCharacters(in: .whitespacesAndNewlines),
            phone2: phone2.trimmingCharacters(in: .whitespacesAndNewlines),
            address1: cap(address1.trimmingCharacters(in: .whitespacesAndNewlines), 200),
            address2: cap(address2.trimmingCharacters(in: .whitespacesAndNewlines), 200),
            city: cap(city.trimmingCharacters(in: .whitespacesAndNewlines), 100),
            state: cap(state.trimmingCharacters(in: .whitespacesAndNewlines), 100),
            zip: cap(zip.trimmingCharacters(in: .whitespacesAndNewlines), 50),
            country: cap(country.trimmingCharacters(in: .whitespacesAndNewlines), 100),
            mother: cap(mother.trimmingCharacters(in: .whitespacesAndNewlines), 200),
            father: cap(father.trimmingCharacters(in: .whitespacesAndNewlines), 200),
            onlineCode: cap(onlineCode.trimmingCharacters(in: .whitespacesAndNewlines), 100),
            personalization: cap(personalization.trimmingCharacters(in: .whitespacesAndNewlines), 200),
            discountCode: cap(discountCode.trimmingCharacters(in: .whitespacesAndNewlines), 100),
            custom1: trimmedCustoms[0],
            custom2: trimmedCustoms[1],
            custom3: trimmedCustoms[2],
            custom4: trimmedCustoms[3],
            custom5: trimmedCustoms[4],
            custom6: trimmedCustoms[5],
            custom7: trimmedCustoms[6],
            custom8: trimmedCustoms[7],
            custom9: trimmedCustoms[8],
            custom10: trimmedCustoms[9],
            custom11: trimmedCustoms[10],
            custom12: trimmedCustoms[11],
            custom13: trimmedCustoms[12],
            custom14: trimmedCustoms[13],
            custom15: trimmedCustoms[14],
            custom16: trimmedCustoms[15],
            custom17: trimmedCustoms[16],
            custom18: trimmedCustoms[17],
            custom19: trimmedCustoms[18],
            custom20: trimmedCustoms[19],
            imageNumbers: imageNumbers.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: existingSubject?.createdAt ?? Date(),
            updatedAt: Date()
        )

        isLoading = true

        // Sync rewrite — for edits, route through SubjectSyncService.updateSubject.
        // The service:
        //   - applies the optimistic overlay so views see the new value
        //     immediately and PERSISTENTLY (no revert until cloud catches up)
        //   - decides write-locally vs broadcast-only based on connection state
        //   - emits structured events
        // Creates still take the legacy path because the service expects a
        // currentSubject to merge fields into; new-subject flow lacks one.
        if isEditing, let existing = existingSubject {
            // Build a SubjectSyncFields from the form values. Only include
            // fields that actually changed from the existing subject so the
            // overlay carries user intent precisely. ALL editable fields
            // are diffed — silent omission would mean the overlay misses
            // the change and the UI reverts to the pre-edit value.
            var fields = SubjectSyncFields()
            if subject.firstName        != existing.firstName        { fields.firstName        = subject.firstName }
            if subject.lastName         != existing.lastName         { fields.lastName         = subject.lastName }
            if subject.grade            != existing.grade            { fields.grade            = subject.grade }
            if subject.teacher          != existing.teacher          { fields.teacher          = subject.teacher }
            if subject.homeroom         != existing.homeroom         { fields.homeroom         = subject.homeroom }
            if subject.studentId        != existing.studentId        { fields.studentId        = subject.studentId }
            if subject.rosterId         != existing.rosterId         { fields.rosterId         = subject.rosterId }
            if subject.onlineCode       != existing.onlineCode       { fields.onlineCode       = subject.onlineCode }
            if subject.jerseyNumber     != existing.jerseyNumber     { fields.jerseyNumber     = subject.jerseyNumber }
            if subject.sport            != existing.sport            { fields.sport            = subject.sport }
            if subject.position         != existing.position         { fields.position         = subject.position }
            if subject.organizationName != existing.organizationName { fields.organizationName = subject.organizationName }
            if subject.year             != existing.year             { fields.year             = subject.year }
            if subject.subjectType      != existing.subjectType      { fields.subjectType      = subject.subjectType }
            if subject.title            != existing.title            { fields.title            = subject.title }
            if subject.referenceNumber  != existing.referenceNumber  { fields.referenceNumber  = subject.referenceNumber }
            if subject.photographer     != existing.photographer     { fields.photographer     = subject.photographer }
            if subject.photoSessionDate != existing.photoSessionDate { fields.photoSessionDate = subject.photoSessionDate }
            if subject.expirationDate   != existing.expirationDate   { fields.expirationDate   = subject.expirationDate }
            if subject.email            != existing.email            { fields.email            = subject.email }
            if subject.phone            != existing.phone            { fields.phone            = subject.phone }
            if subject.phone2           != existing.phone2           { fields.phone2           = subject.phone2 }
            if subject.address1         != existing.address1         { fields.address1         = subject.address1 }
            if subject.address2         != existing.address2         { fields.address2         = subject.address2 }
            if subject.city             != existing.city             { fields.city             = subject.city }
            if subject.state            != existing.state            { fields.state            = subject.state }
            if subject.zip              != existing.zip              { fields.zip              = subject.zip }
            if subject.country          != existing.country          { fields.country          = subject.country }
            if subject.mother           != existing.mother           { fields.mother           = subject.mother }
            if subject.father           != existing.father           { fields.father           = subject.father }
            if subject.personalization  != existing.personalization  { fields.personalization  = subject.personalization }
            if subject.discountCode     != existing.discountCode     { fields.discountCode     = subject.discountCode }
            if subject.custom1          != existing.custom1          { fields.custom1          = subject.custom1 }
            if subject.custom2          != existing.custom2          { fields.custom2          = subject.custom2 }
            if subject.custom3          != existing.custom3          { fields.custom3          = subject.custom3 }
            if subject.custom4          != existing.custom4          { fields.custom4          = subject.custom4 }
            if subject.custom5          != existing.custom5          { fields.custom5          = subject.custom5 }
            if subject.custom6          != existing.custom6          { fields.custom6          = subject.custom6 }
            if subject.custom7          != existing.custom7          { fields.custom7          = subject.custom7 }
            if subject.custom8          != existing.custom8          { fields.custom8          = subject.custom8 }
            if subject.custom9          != existing.custom9          { fields.custom9          = subject.custom9 }
            if subject.custom10         != existing.custom10         { fields.custom10         = subject.custom10 }
            if subject.custom11         != existing.custom11         { fields.custom11         = subject.custom11 }
            if subject.custom12         != existing.custom12         { fields.custom12         = subject.custom12 }
            if subject.custom13         != existing.custom13         { fields.custom13         = subject.custom13 }
            if subject.custom14         != existing.custom14         { fields.custom14         = subject.custom14 }
            if subject.custom15         != existing.custom15         { fields.custom15         = subject.custom15 }
            if subject.custom16         != existing.custom16         { fields.custom16         = subject.custom16 }
            if subject.custom17         != existing.custom17         { fields.custom17         = subject.custom17 }
            if subject.custom18         != existing.custom18         { fields.custom18         = subject.custom18 }
            if subject.custom19         != existing.custom19         { fields.custom19         = subject.custom19 }
            if subject.custom20         != existing.custom20         { fields.custom20         = subject.custom20 }
            if subject.notes            != existing.notes            { fields.notes            = subject.notes }
            if subject.imageNumbers     != existing.imageNumbers     { fields.imageNumbers     = subject.imageNumbers }
            if subject.isAbsent         != existing.isAbsent         { fields.isAbsent         = subject.isAbsent }
            if subject.needsRetake      != existing.needsRetake      { fields.needsRetake      = subject.needsRetake }
            if subject.isPhotographed   != existing.isPhotographed   { fields.isPhotographed   = subject.isPhotographed }
            if subject.checkedInAt      != existing.checkedInAt      { fields.checkedInAt      = subject.checkedInAt }
            Task {
                _ = await SubjectSyncService.shared.updateSubject(
                    SubjectMutationRequest(
                        subjectId: subject.id.uuidString.lowercased(),
                        galleryId: subject.galleryId,
                        fields: fields,
                        sourcePath: "FPSportsAddSubjectView.executeSave"
                    ),
                    currentSubject: existing
                )
                await MainActor.run {
                    onComplete(true, subject)
                    presentationMode.wrappedValue.dismiss()
                }
            }
            return
        }

        // Phase C C.4: route CREATE through SubjectSyncService.createSubject.
        // The previous code had two parallel branches — one for connected
        // (broadcastSubjectCreated + sendSubjectFullUpdate) and one for
        // standalone (3-retry PowerSync write + broadcast). Both collapse
        // here: createSubject's connected branch sends an insert_subjects
        // command (Surface owns the cloud write); its fallback path emits
        // broadcastSubjectCreated + sendSubjectFullUpdate after the local
        // PowerSync write so peer iPads still see the new subject when
        // offline. The 3-retry loop and the failure alert disappear with
        // the migration; failures now flow through SubjectSyncEvents
        // (Phase J restores user-visible failure UX).
        Task {
            _ = await SubjectSyncService.shared.createSubject(
                subject,
                sourcePath: "FPSportsAddSubjectView.executeSave"
            )
            await MainActor.run {
                onComplete(true, subject)
                presentationMode.wrappedValue.dismiss()
            }
        }
    }
}
