//  PhotoshootNotesView.swift
//  Iconik Employee — Photoshoot Notes, converted in AMB.7
//
//  Replaces Misc Features/PhotoshootNotesView.swift, deleted in the same commit.
//
//  THE TYPE NAME IS KEPT ON PURPOSE. `DashboardWidgets` presents this whole view
//  in an iPad sheet with its own NavigationView and a Done button, so it renders
//  under TWO different containers. Renaming it would push churn into a screen
//  this phase has no business touching — the same call AMB.6 made for
//  TaskDetailView.
//
//  ONE ORG FLAG SELECTS WHICH OF TWO WORKFLOWS THIS SCREEN IS IN
//      usePhotoshootNotesOnly TRUE   this screen is the whole reporting
//                                    workflow: it gains a Submit button and a
//                                    Submitted Notes list, and the three daily
//                                    report features are hidden from the app.
//      usePhotoshootNotesOnly FALSE  this is a LOCAL scratchpad whose notes reach
//                                    the server only by being attached to a
//                                    daily job report.
//      Both are drawn. A design that only draws one strands the other org.
//
//  ONE ORDER FOR ONE LIST
//      The full screen showed notes in INSERTION order (oldest first) while the
//      iPad widget showed them newest first and capped at five. Two orders for
//      one list is a defect rather than a preference, so the strip is newest
//      first here — which is what the operator approved.
//
//  DEFECTS CARRIED, NOT REPAIRED — all three need the data layer (arc DJR.1 /
//  a photoshoot-note repair), and all three are recorded in AMB_BATCH2_PARITY.md
//      R1  The submitted-notes fetch sends `deleted_at=is.true` against a
//          TIMESTAMPTZ column; the intent was `is.null`. It cannot succeed.
//      R2  And if it could, every row would be dropped: the DTO parses the date
//          column with a plain ISO8601 formatter, which returns nil for
//          "2026-07-26", and the row is discarded by a compactMap.
//      R3  The photographer id used for that fetch is ALWAYS the empty string —
//          AppStorage "userID" is read in three places and written nowhere.
//      R8  Submitting DELETES the only local copy, and the round trip that would
//          show it again is broken by R1 and R2.
//      R9  Three screens read-modify-write the same AppStorage blob and none
//          observes the others.

import SwiftUI

struct PhotoshootNotesView: View {

    @AppStorage("photoshootNotes") private var storedNotesData: Data = Data()
    @AppStorage("userFirstName") private var storedUserFirstName: String = ""
    @AppStorage("userLastName") private var storedUserLastName: String = ""
    @AppStorage("userOrganizationID") private var organizationID: String = ""
    @AppStorage("userID") private var storedUserID: String = ""

    @State private var notes: [PhotoshootNote] = []
    @State private var selectedID: UUID?
    @State private var schoolOptions: [SchoolItem] = []
    @State private var isLoadingSchools = true

    @State private var todaySessions: [Session] = []
    @State private var showSchoolDialog = false
    @State private var pendingNoteID: UUID?
    @State private var showDeleteConfirmation = false

    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var tempImage: UIImage?
    @State private var isUploadingImage = false

    @State private var isSubmitting = false
    @State private var successMessage = ""
    @State private var errorMessage = ""

    @State private var submittedNotes: [PhotoshootNote] = []
    @State private var isLoadingSubmitted = false
    @State private var showSubmitted = false
    @State private var hasLoadedSubmitted = false

    private let sessionService = SessionService.shared
    private let subscriptionID = UUID()
    @ObservedObject private var organizationService = OrganizationService.shared

    private var feature: Color { FeatureTheme.color(for: "photoshootNotes") }

    /// Notes newest first — one order for one list.
    private var strip: [PhotoshootNote] {
        notes.sorted { $0.timestamp > $1.timestamp }
    }

    private var selectedIndex: Int? {
        selectedID.flatMap { id in notes.firstIndex { $0.id == id } }
    }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: feature, intensity: 0.75)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    actionRow
                    noteStrip
                    if let index = selectedIndex {
                        editor(index)
                        photos(index)
                        syncRow(index)
                        if organizationService.usePhotoshootNotesOnly { submitBlock(index) }
                    } else {
                        AmbientEmptyState(
                            title: notes.isEmpty ? "No notes created yet" : "No note selected",
                            message: notes.isEmpty
                                ? "A note is where you write down what happened on a shoot."
                                : "Select a note to edit or create a new one.",
                            systemImage: "note.text",
                            actionTitle: "New Note",
                            actionIcon: "plus.circle.fill",
                            action: createNewNote,
                            actionTint: feature)
                    }
                    if organizationService.usePhotoshootNotesOnly { submittedSection }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .ambientNoBounceWhenShort()
        }
        .navigationTitle("Photoshoot Notes")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) { banners }
        .onAppear(perform: load)
        .onDisappear { sessionService.stopListeningToSessions(subscriptionId: subscriptionID) }
        .onReceive(NotificationCenter.default.publisher(for: .appDidBecomeActive)) { _ in
            loadScheduleForToday()
        }
        .sheet(isPresented: $showCamera) {
            NotePhotoPicker(selectedImage: $tempImage, sourceType: .camera)
                .onDisappear(perform: consumePickedImage)
        }
        .sheet(isPresented: $showLibrary) {
            NotePhotoPicker(selectedImage: $tempImage, sourceType: .photoLibrary)
                .onDisappear(perform: consumePickedImage)
        }
        .confirmationDialog("Delete this note?", isPresented: $showDeleteConfirmation,
                            titleVisibility: .visible) {
            Button("Delete Note", role: .destructive) { deleteSelectedNote() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This permanently deletes the note and any attached photos. This can't be undone.")
        }
        .confirmationDialog("Select School for Note", isPresented: $showSchoolDialog,
                            titleVisibility: .visible) {
            ForEach(sortedTodaySessions, id: \.id) { session in
                Button(sessionOptionLabel(session)) { selectSchool(from: session) }
            }
            Button("Cancel", role: .cancel) { pendingNoteID = nil }
        } message: {
            Text("You have multiple photoshoots today. Which school would you like to use for this note?")
        }
    }

    // MARK: - Header

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button(action: createNewNote) {
                Label("New", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    // ambient-allow: a filled primary action is a control.
                    .background(Capsule().fill(feature))
            }
            .buttonStyle(.plain)

            if selectedIndex != nil {
                Button { showDeleteConfirmation = true } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        // ambient-allow: a control, not a card.
                        .background(Capsule().fill(Color.red.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)

            if !todaySessions.isEmpty {
                Text("\(todaySessions.count) session\(todaySessions.count == 1 ? "" : "s") today")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    // ambient-allow: a status pill, not a card.
                    .background(Capsule().fill(Color.green.opacity(0.16)))
            }
        }
    }

    @ViewBuilder
    private var noteStrip: some View {
        if notes.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(strip) { note in
                        Button {
                            withAnimation(AmbientMotion.snappy) { selectedID = note.id }
                            AmbientHaptics.selection()
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(Formatters.shortTime.string(from: note.timestamp))
                                    .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                                Text(note.school.isEmpty ? "No school yet" : note.school)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(note.school.isEmpty ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
                                    .lineLimit(1)
                                Text(note.noteText.isEmpty ? "(No content)" : note.noteText)
                                    .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                            }
                            .frame(width: 168, alignment: .leading)
                            .ambientCard(density: .compact,
                                         state: selectedID == note.id ? .highlighted : .normal,
                                         border: selectedID == note.id
                                            ? .strong(feature)
                                            : .hairline(Color.primary.opacity(0.08)),
                                         fillWidth: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)
        }
    }

    // MARK: - Editor

    /// The School section sits ABOVE the note body, deliberately and unchanged —
    /// which school a note belongs to is the thing that makes it useful later.
    private func editor(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("School")

            if isLoadingSchools && schoolOptions.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Loading schools…").font(.subheadline).foregroundStyle(.secondary)
                }
                .ambientCard(density: .compact, fillWidth: true)
            } else {
                Menu {
                    ForEach(schoolOptions) { school in
                        Button(school.name) { setSchool(school.name, at: index) }
                    }
                } label: {
                    HStack {
                        Text(notes[index].school.isEmpty ? "Choose a school" : notes[index].school)
                            .font(.subheadline)
                            .foregroundStyle(notes[index].school.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .ambientCard(density: .compact, fillWidth: true)
                }
            }

            AmbientSectionTitle("Note", trailing: "\(notes[index].noteText.count) characters")
            // EVERY KEYSTROKE SAVES. There is no Save button anywhere, and there
            // never has been.
            TextEditor(text: Binding(
                get: { notes[index].noteText },
                set: { newValue in
                    notes[index].noteText = newValue
                    saveNotes()
                }))
                .frame(minHeight: 150)
                .font(.subheadline)
                .scrollContentBackground(.hidden)
                .ambientCard(density: .compact, fillWidth: true)
                .overlay(alignment: .topLeading) {
                    if notes[index].noteText.isEmpty {
                        Text("What happened on this shoot.")
                            .font(.subheadline).foregroundStyle(.tertiary)
                            .padding(.horizontal, 17).padding(.vertical, 18)
                            .allowsHitTesting(false)
                    }
                }

            Text("Saves on every keystroke. There is no Save button.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    // MARK: - Photos

    /// The ONLY screen in this family that offers the camera, and that stays.
    private func photos(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            AmbientSectionTitle("Photos",
                                trailing: notes[index].photoURLs.isEmpty ? nil : "\(notes[index].photoURLs.count)")

            HStack(spacing: 8) {
                Button { showCamera = true } label: {
                    Label("Camera", systemImage: "camera")
                        .font(.caption.weight(.semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        // ambient-allow: a control, not a card.
                        .background(Capsule().fill(Color.blue))
                }
                .buttonStyle(.plain)
                Button { showLibrary = true } label: {
                    Label("Library", systemImage: "photo.on.rectangle")
                        .font(.caption.weight(.semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        // ambient-allow: a control, not a card.
                        .background(Capsule().fill(Color.green))
                }
                .buttonStyle(.plain)
            }

            if isUploadingImage {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Uploading photo…").font(.caption).foregroundStyle(.secondary)
                }
            }

            if notes[index].photoURLs.isEmpty {
                Text("No photos added").font(.caption).foregroundStyle(.tertiary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(notes[index].photoURLs, id: \.self) { urlString in
                            thumbnail(urlString, size: 100) {
                                deletePhoto(urlString, at: index)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.horizontal, -16)
            }
        }
    }

    /// Three states, unchanged: a spinner, the image, and a glyph on failure —
    /// so a photo that will not load is visible as a photo that will not load.
    private func thumbnail(_ urlString: String, size: CGFloat,
                           onDelete: (() -> Void)? = nil) -> some View {
        AsyncImage(url: URL(string: urlString)) { phase in
            switch phase {
            case .empty:
                ProgressView().frame(width: size, height: size)
            case .success(let image):
                image.resizable().scaledToFill().frame(width: size, height: size)
                    // ambient-allow: a photo thumbnail is content, not a card.
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            case .failure:
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
                    // ambient-allow: a placeholder tile, not a card.
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.15)))
            @unknown default:
                EmptyView()
            }
        }
        .overlay(alignment: .topTrailing) {
            if let onDelete {
                // No confirmation, exactly as before.
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(.white, .black.opacity(0.55))
                        .padding(3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove photo")
            }
        }
    }

    // MARK: - Sync and submit

    private func syncRow(_ index: Int) -> some View {
        let note = notes[index]
        return HStack(spacing: 7) {
            Circle()
                .fill(note.syncedToServer ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            if note.syncedToServer {
                if note.status == .submitted {
                    Text("Submitted").font(.caption.weight(.semibold)).foregroundStyle(.green)
                    if let submittedAt = note.submittedAt {
                        Text("• \(Self.relativeTime(submittedAt))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Synced to server").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            } else {
                Text("Local only (not synced)").font(.caption.weight(.semibold)).foregroundStyle(.orange)
            }
            Spacer(minLength: 0)
        }
        .ambientCard(density: .compact, fillWidth: true)
    }

    @ViewBuilder
    private func submitBlock(_ index: Int) -> some View {
        let note = notes[index]
        if note.status == .draft {
            let ready = !note.school.isEmpty && !note.noteText.isEmpty
            VStack(spacing: 6) {
                Button { submitNote(at: index) } label: {
                    HStack(spacing: 8) {
                        if isSubmitting {
                            ProgressView().tint(.white).scaleEffect(0.8)
                            Text("Submitting…")
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Submit Note")
                        }
                    }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 13)
                    // ambient-allow: a filled primary action is a control.
                    .background(Capsule().fill(ready ? Color.green : Color.gray))
                }
                .buttonStyle(.plain)
                .disabled(!ready || isSubmitting)

                if !ready {
                    Text(note.school.isEmpty
                         ? "Please select a school before submitting"
                         : "Please add some notes before submitting")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        } else {
            HStack(spacing: 7) {
                Image(systemName: "lock.fill")
                Text("Note submitted (read-only)").font(.callout)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .ambientCard(density: .compact, fillWidth: true)
        }
    }

    private var submittedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if !hasLoadedSubmitted { loadSubmittedNotes() }
                withAnimation(AmbientMotion.snappy) { showSubmitted.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: showSubmitted ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.bold)).foregroundStyle(feature)
                    Text("Submitted notes").font(.headline)
                    Spacer(minLength: 0)
                    if isLoadingSubmitted {
                        ProgressView().scaleEffect(0.8)
                    } else if !submittedNotes.isEmpty {
                        AmbientBadge(text: "\(submittedNotes.count)", tint: feature)
                    }
                }
                .ambientCard(density: .compact, fillWidth: true)
            }
            .buttonStyle(.plain)

            if showSubmitted {
                if isLoadingSubmitted {
                    HStack(spacing: 8) {
                        ProgressView().scaleEffect(0.8)
                        Text("Loading submitted notes…").font(.caption).foregroundStyle(.secondary)
                    }
                } else if submittedNotes.isEmpty {
                    Text("No submitted notes found").font(.caption).foregroundStyle(.tertiary)
                } else {
                    ForEach(submittedNotes) { note in
                        submittedCard(note)
                    }
                }
                Text("The last 30 days.").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func submittedCard(_ note: PhotoshootNote) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.school.isEmpty ? "No school" : note.school)
                        .font(.subheadline.weight(.semibold))
                    Text(Formatters.mediumDateTime.string(from: note.timestamp))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    AmbientBadge(text: "Submitted", systemImage: "checkmark", tint: .green)
                    if let submittedAt = note.submittedAt {
                        Text(Self.relativeTime(submittedAt))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Text(note.noteText)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !note.photoURLs.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(note.photoURLs, id: \.self) { urlString in
                            thumbnail(urlString, size: 80)
                        }
                    }
                }
            }
        }
        .ambientCard(density: .compact,
                     border: .hairline(Color.green.opacity(0.35)), fillWidth: true)
    }

    @ViewBuilder
    private var banners: some View {
        VStack(spacing: 6) {
            if !errorMessage.isEmpty {
                banner(errorMessage, tint: .red)
            }
            if !successMessage.isEmpty {
                banner(successMessage, tint: .green)
            }
        }
        .padding(.bottom, 16)
        .animation(AmbientMotion.gentle, value: errorMessage)
        .animation(AmbientMotion.gentle, value: successMessage)
    }

    private func banner(_ message: String, tint: Color) -> some View {
        Text(message)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14).padding(.vertical, 10)
            // ambient-allow: a transient banner, not a card.
            .background(Capsule().fill(tint.opacity(0.92)))
            .padding(.horizontal, 24)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Relative time

    static func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }

    // MARK: - Notes

    private func load() {
        loadNotes()
        loadSchoolOptions()
        loadScheduleForToday()
        if !organizationID.isEmpty {
            organizationService.startListeningToOrganization(organizationID: organizationID)
        }
    }

    private func loadNotes() {
        notes = (try? JSONDecoder().decode([PhotoshootNote].self, from: storedNotesData)) ?? []
        if selectedID == nil { selectedID = strip.first?.id }
    }

    private func saveNotes() {
        if let encoded = try? JSONEncoder().encode(notes) {
            storedNotesData = encoded
        }
    }

    private func createNewNote() {
        let note = PhotoshootNote(
            id: UUID(),
            timestamp: Date(),
            school: "",
            noteText: "",
            photoURLs: [],
            status: .draft,
            submittedAt: nil,
            dailyReportId: nil,
            syncedToServer: false,
            lastSyncedAt: nil,
            photographerName: "\(storedUserFirstName) \(storedUserLastName)".trimmingCharacters(in: .whitespaces),
            photographerID: storedUserID,
            shootType: "photoshoot")
        withAnimation(AmbientMotion.snappy) {
            notes.append(note)
            selectedID = note.id
        }
        saveNotes()
        // A new note immediately tries to set its school from the schedule, and
        // with more than one session today it ASKS.
        setSchoolFromSchedule(for: note.id)
        show(success: "New note created")
    }

    private func deleteSelectedNote() {
        guard let index = selectedIndex else { return }
        for urlString in notes[index].photoURLs {
            deletePhotoFromStorage(urlString)
        }
        withAnimation(AmbientMotion.snappy) {
            notes.remove(at: index)
            selectedID = strip.first?.id
        }
        saveNotes()
        show(success: "Note deleted")
    }

    private func setSchool(_ name: String, at index: Int) {
        guard notes.indices.contains(index) else { return }
        withAnimation(AmbientMotion.snappy) { notes[index].school = name }
        saveNotes()
    }

    // MARK: - Photos

    private func consumePickedImage() {
        guard let image = tempImage, let index = selectedIndex else {
            tempImage = nil
            return
        }
        tempImage = nil
        uploadImage(image, at: index)
    }

    private func uploadImage(_ image: UIImage, at index: Int) {
        guard notes.indices.contains(index) else { return }
        guard let data = image.downsampledJPEGData(maxDimension: 2048, quality: 0.8) else {
            show(error: "Could not compress image")
            return
        }
        guard !organizationID.isEmpty else {
            show(error: "Cannot upload photo: no organization ID found")
            return
        }

        let noteID = notes[index].id
        isUploadingImage = true

        Task {
            let storage = SupabaseManager.shared.client.storage
            let path = "photoshoot-notes/\(organizationID)/\(noteID.uuidString)/\(UUID().uuidString).jpg"
            do {
                _ = try await storage.from("daily-reports").upload(path, data: data)
                let signed = try await storage.from("daily-reports")
                    .createSignedURL(path: path, expiresIn: 31_536_000)
                await MainActor.run {
                    isUploadingImage = false
                    // Resolve the note by ID rather than by the index captured
                    // when the picker opened — the strip can have re-sorted.
                    guard let current = notes.firstIndex(where: { $0.id == noteID }) else { return }
                    notes[current].photoURLs.append(signed.absoluteString)
                    saveNotes()
                    show(success: "Photo added successfully")
                }
            } catch {
                await MainActor.run {
                    isUploadingImage = false
                    show(error: "Error uploading photo: \(error.localizedDescription)")
                }
            }
        }
    }

    private func deletePhoto(_ urlString: String, at index: Int) {
        deletePhotoFromStorage(urlString)
        guard notes.indices.contains(index) else { return }
        notes[index].photoURLs.removeAll { $0 == urlString }
        saveNotes()
        show(success: "Photo removed")
    }

    private func deletePhotoFromStorage(_ urlString: String) {
        guard urlString.contains("supabase") else {
            print("⚠️ PhotoshootNotes: cannot delete legacy photo \(urlString.prefix(50))…")
            return
        }
        guard let url = URL(string: urlString),
              let bucketIndex = url.pathComponents.firstIndex(of: "daily-reports"),
              bucketIndex + 1 < url.pathComponents.count else {
            print("❌ PhotoshootNotes: could not extract a storage path from the URL")
            return
        }
        let path = url.pathComponents[(bucketIndex + 1)...].joined(separator: "/")
        Task {
            do {
                try await SupabaseManager.shared.client.storage
                    .from("daily-reports").remove(paths: [path])
            } catch {
                print("❌ PhotoshootNotes: error deleting photo — \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Schools and schedule

    private func loadSchoolOptions() {
        guard !organizationID.isEmpty else {
            isLoadingSchools = false
            return
        }
        Task {
            do {
                let schools = try await SchoolService.shared.getSchools(organizationID: organizationID)
                await MainActor.run {
                    schoolOptions = schools.map {
                        SchoolItem(id: $0.id, name: $0.name, address: $0.address ?? "", coordinates: $0.coordinates)
                    }
                    isLoadingSchools = false
                    if let index = selectedIndex, notes[index].school.isEmpty {
                        setSchoolFromSchedule(for: notes[index].id)
                    }
                }
            } catch {
                await MainActor.run {
                    isLoadingSchools = false
                    show(error: "Error loading schools: \(error.localizedDescription)")
                }
            }
        }
    }

    private var sortedTodaySessions: [Session] {
        todaySessions.sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    private func sessionOptionLabel(_ session: Session) -> String {
        guard let start = session.startDate else { return session.schoolName }
        return "\(session.schoolName) - \(Formatters.shortTime.string(from: start))"
    }

    private func loadScheduleForToday() {
        guard let currentUserID = UserManager.shared.getCurrentUserID(),
              !organizationID.isEmpty else { return }
        let currentUserEmail = UserDefaults.standard.string(forKey: "userEmail")
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }

        sessionService.startListeningToSessions(
            subscriptionId: subscriptionID,
            organizationID: organizationID,
            includeUnpublished: false
        ) { all in
            Task { @MainActor in
                let mine = all.filter { session in
                    guard let start = session.startDate else { return false }
                    guard start >= startOfDay, start < endOfDay else { return false }
                    return session.isUserAssigned(userID: currentUserID, userEmail: currentUserEmail)
                }
                todaySessions = mine
                if let index = selectedIndex, notes[index].school.isEmpty {
                    setSchoolFromSchedule(for: notes[index].id)
                }
            }
        }
    }

    /// One session today: fill it in. Several: ask.
    private func setSchoolFromSchedule(for noteID: UUID) {
        guard !todaySessions.isEmpty, !schoolOptions.isEmpty else { return }
        guard let index = notes.firstIndex(where: { $0.id == noteID }), notes[index].school.isEmpty else { return }

        if todaySessions.count == 1,
           let session = todaySessions.first,
           let match = schoolOptions.first(where: { $0.name == session.schoolName }) {
            setSchool(match.name, at: index)
            show(success: "Auto-selected school from your schedule")
        } else if todaySessions.count > 1 {
            pendingNoteID = noteID
            showSchoolDialog = true
        }
    }

    private func selectSchool(from session: Session) {
        defer { pendingNoteID = nil }
        guard let noteID = pendingNoteID,
              let index = notes.firstIndex(where: { $0.id == noteID }),
              let match = schoolOptions.first(where: { $0.name == session.schoolName }) else { return }
        setSchool(match.name, at: index)
        show(success: "Selected \(session.schoolName) for this note")
    }

    // MARK: - Submitting

    private func submitNote(at index: Int) {
        guard !isSubmitting, notes.indices.contains(index) else { return }
        let note = notes[index]
        guard !note.school.isEmpty else {
            show(error: "Please select a school before submitting")
            return
        }
        guard !note.noteText.isEmpty else {
            show(error: "Please add some notes before submitting")
            return
        }

        isSubmitting = true
        errorMessage = ""

        var toSubmit = note
        let photographerName = "\(storedUserFirstName) \(storedUserLastName)".trimmingCharacters(in: .whitespaces)
        toSubmit.photographerName = photographerName.isEmpty ? "Unknown" : photographerName
        toSubmit.photographerID = storedUserID
        toSubmit.shootType = "photoshoot"
        let organization = organizationID

        Task {
            do {
                _ = try await PhotoshootNoteService.shared.submitNote(toSubmit, organizationID: organization)
                await MainActor.run {
                    isSubmitting = false
                    // The local copy is removed because the note now lives on the
                    // server. Finding R8: the round trip that would show it again
                    // is broken, so this is the only copy going.
                    notes.removeAll { $0.id == note.id }
                    selectedID = strip.first?.id
                    saveNotes()
                    hasLoadedSubmitted = false
                    show(success: "Note submitted successfully!")
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    show(error: "Failed to submit note: \(error.localizedDescription)")
                }
            }
        }
    }

    private func loadSubmittedNotes() {
        guard !isLoadingSubmitted else { return }
        isLoadingSubmitted = true
        Task {
            let end = Date()
            guard let start = Calendar.current.date(byAdding: .day, value: -30, to: end) else {
                await MainActor.run { isLoadingSubmitted = false }
                return
            }
            do {
                let fetched = try await PhotoshootNoteService.shared.fetchNotes(
                    photographerID: storedUserID, startDate: start, endDate: end)
                await MainActor.run {
                    submittedNotes = fetched.filter { $0.status == .submitted }
                    isLoadingSubmitted = false
                    hasLoadedSubmitted = true
                }
            } catch {
                await MainActor.run {
                    isLoadingSubmitted = false
                    hasLoadedSubmitted = true
                    show(error: "Failed to load submitted notes: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Banners

    private func show(success message: String) {
        successMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                if successMessage == message { successMessage = "" }
            }
        }
    }

    private func show(error message: String) {
        errorMessage = message
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await MainActor.run {
                if errorMessage == message { errorMessage = "" }
            }
        }
    }
}

// MARK: - Picker

/// A camera-or-library picker. Photoshoot Notes is the only screen in this
/// family that offers the camera, so this is the only picker that takes a source.
struct NotePhotoPicker: UIViewControllerRepresentable {
    @Environment(\.presentationMode) private var presentationMode
    @Binding var selectedImage: UIImage?
    let sourceType: UIImagePickerController.SourceType

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        // A simulator has no camera, and asking for one it does not have is a
        // crash rather than an empty screen.
        picker.sourceType = (sourceType == .camera && UIImagePickerController.isSourceTypeAvailable(.camera))
            ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: NotePhotoPicker
        init(_ parent: NotePhotoPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.selectedImage = image }
            parent.presentationMode.wrappedValue.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
