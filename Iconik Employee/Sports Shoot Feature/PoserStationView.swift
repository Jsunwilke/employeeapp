//
//  PoserStationView.swift
//  Iconik Employee
//
//  iPad poser station for spring/underclass portrait shoots.
//  Full roster with grade/teacher filters, tap to select on camera,
//  view/edit subject info, show captured images with live thumbnails.
//

import SwiftUI

struct PoserStationView: View {
    let gallery: SportsShoot

    private let powerSync = PowerSyncManager.shared
    @StateObject private var fpSync = FocalPointSyncClient.shared

    // Subjects
    @State private var subjects: [FPSubject] = []
    @State private var subjectWatchTask: Task<Void, Never>?
    @State private var isLoading = true

    // Selection
    @State private var selectedSubjectId: UUID?
    @State private var activeSubjectId: String?
    @State private var scrollTargetId: UUID?
    @State private var autoSelectEnabled: Bool = false  // Toggle: tap auto-selects on Surface

    // Photo tracking (WebSocket thumbnails — same pipeline as sports)
    @State private var subjectThumbnails: [String: [CaptureThumb]] = [:]
    @State private var pendingImageNumbers: [String: [Int]] = [:]
    @State private var photoCountMap: [String: Int] = [:]

    // Photo viewer
    @State private var showPhotoViewer = false
    @State private var photoViewerSubjectName = ""
    @State private var photoViewerSubjectId = ""
    @State private var photoViewerThumbs: [CaptureThumb] = []

    // Move photo to another subject
    @State private var showMoveImagePicker = false
    @State private var moveImageNumber: Int = 0
    @State private var moveSearchText = ""

    // Filters
    @State private var searchText = ""
    @State private var activeFilters: [String: Set<String>] = [:]  // field_key -> selected values (multiple fields, AND logic)
    @State private var sortField: String = "last_name"

    // Layout
    @State private var detailPanelVisible = true

    // Add subject
    @State private var showingAddSubject = false

    // US Card scan flow
    @State private var showingUSCardQRScan = false
    @State private var usCardSubject: FPSubject?
    @State private var showingUSCardDocScan = false
    @State private var scanProcessing = false
    @State private var scanError: String?

    // Selection confirmation from Surface Pro
    @State private var confirmedSubjectId: String?
    @State private var confirmedSubjectName: String?

    // Move confirmation from Surface Pro
    @State private var moveConfirmationMessage: String?
    @State private var moveConfirmationIsError = false
    @State private var pendingMoveTimer: DispatchWorkItem?

    // Verification warning from Surface Pro
    @State private var verificationWarning: String?
    @State private var verificationSubjectId: String?
    @State private var verificationDismissTimer: DispatchWorkItem?

    // Sync
    @State private var showingSyncSheet = false

    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""

    // MARK: - Computed

    var galleryId: String {
        gallery.galleryId ?? gallery.id.uuidString.lowercased()
    }

    /// All possible filterable fields — dynamically shows any that have data
    static let allFilterFields: [(key: String, label: String)] = [
        ("last_name", "Last Name"),
        ("first_name", "First Name"),
        ("grade", "Grade"),
        ("teacher", "Teacher"),
        ("organization_name", "Organization"),
        ("homeroom", "Homeroom"),
        ("sport", "Sport"),
        ("email", "Email"),
        ("student_id", "Student ID"),
        ("roster_id", "Roster ID"),
        ("jersey_number", "Jersey #"),
        ("position", "Position"),
    ]

    /// Get unique non-empty values for a given field key
    func uniqueValues(for field: String) -> [String] {
        let values: [String] = subjects.compactMap { subject in
            let val = fieldValue(subject, field)
            return val.isEmpty ? nil : val
        }
        return Array(Set(values)).sorted()
    }

    /// Only show fields that actually have data in this gallery
    var availableFilterFields: [(key: String, label: String)] {
        Self.allFilterFields.filter { !uniqueValues(for: $0.key).isEmpty }
    }

    /// Get a subject's value for a given field key
    private func fieldValue(_ subject: FPSubject, _ field: String) -> String {
        switch field {
        case "first_name": return subject.firstName
        case "last_name": return subject.lastName
        case "grade": return subject.grade
        case "teacher": return subject.teacher
        case "organization_name": return subject.organizationName
        case "homeroom": return subject.homeroom
        case "sport": return subject.sport
        case "email": return subject.email
        case "student_id": return subject.studentId
        case "roster_id": return subject.rosterId
        case "jersey_number": return subject.jerseyNumber
        case "position": return subject.position
        default: return ""
        }
    }

    var hasActiveFilters: Bool {
        !activeFilters.isEmpty || !searchText.isEmpty
    }

    var filteredSubjects: [FPSubject] {
        var list = subjects
        // Apply all active filters (AND logic — must match every field)
        for (field, values) in activeFilters {
            if !values.isEmpty {
                list = list.filter { values.contains(fieldValue($0, field)) }
            }
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            list = list.filter {
                $0.firstName.lowercased().contains(q) ||
                $0.lastName.lowercased().contains(q) ||
                $0.studentId.lowercased().contains(q) ||
                $0.rosterId.lowercased().contains(q) ||
                $0.organizationName.lowercased().contains(q)
            }
        }
        return list.sorted {
            // Blank/no-name subjects always sort last
            let a_blank = $0.firstName.trimmingCharacters(in: .whitespaces).isEmpty && $0.lastName.trimmingCharacters(in: .whitespaces).isEmpty
            let b_blank = $1.firstName.trimmingCharacters(in: .whitespaces).isEmpty && $1.lastName.trimmingCharacters(in: .whitespaces).isEmpty
            if a_blank != b_blank { return !a_blank }

            switch sortField {
            case "organization_name":
                return $0.organizationName.localizedCaseInsensitiveCompare($1.organizationName) == .orderedAscending
            case "grade": return $0.grade < $1.grade
            case "teacher": return $0.teacher < $1.teacher
            case "roster_id": return $0.rosterId < $1.rosterId
            default: return $0.lastName.localizedCaseInsensitiveCompare($1.lastName) == .orderedAscending
            }
        }
    }

    var selectedSubject: FPSubject? {
        guard let id = selectedSubjectId else { return nil }
        return subjects.first { $0.id == id }
    }

    var shotCount: Int {
        subjects.filter { $0.isPhotographed || (photoCountMap[$0.id.uuidString.lowercased()] ?? 0) > 0 }.count
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            filterBar

            if isLoading {
                ProgressView("Loading roster...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    subjectList
                        .frame(maxWidth: .infinity)

                    if detailPanelVisible {
                        Rectangle().fill(Color(.separator)).frame(width: 1)
                    }

                    if detailPanelVisible, let subject = selectedSubject {
                        SubjectDetailPanel(
                            subject: subject,
                            thumbnails: subjectThumbnails[subject.id.uuidString.lowercased()] ?? [],
                            photoCount: photoCountMap[subject.id.uuidString.lowercased()] ?? 0,
                            galleryId: galleryId,
                            onSave: { updated in saveSubject(updated) },
                            onSelect: { selectOnCamera(subject) },
                            onViewPhotos: { name, thumbs in
                                photoViewerSubjectName = name
                                photoViewerSubjectId = subject.id.uuidString.lowercased()
                                photoViewerThumbs = thumbs
                                showPhotoViewer = true
                            }
                        )
                        .frame(width: 360)
                    } else if detailPanelVisible {
                        VStack(spacing: 12) {
                            Image(systemName: "person.crop.rectangle")
                                .font(.system(size: 40))
                                .foregroundColor(.secondary)
                            Text("Select a student")
                                .font(.headline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxHeight: .infinity)
                        .frame(width: 360)
                        .background(Color(.secondarySystemBackground))
                    }
                }
            }
        }
        .navigationTitle("")
        .navigationBarHidden(true)
        .task {
            await loadSubjects()
            await loadCachedThumbnails()
            startWatching()
            setupSyncCallbacks()
        }
        .onDisappear { subjectWatchTask?.cancel() }
        .sheet(isPresented: $showingSyncSheet) { syncSheet }
        .sheet(isPresented: $showingAddSubject) { addSubjectSheet }
        .sheet(isPresented: $showingUSCardQRScan) { usCardQRSheet }
        .sheet(isPresented: $showingUSCardDocScan) { usCardDocScanSheet }
        .overlay(alignment: .top) {
            if let error = scanError {
                Text(error)
                    .font(.subheadline).fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(error.contains("on-device") ? Color.orange : Color.red)
                    )
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            withAnimation { scanError = nil }
                        }
                    }
            }
        }
        .fullScreenCover(isPresented: $showPhotoViewer) {
            CapturePhotoViewer(
                subjectName: photoViewerSubjectName,
                thumbs: photoViewerThumbs,
                isPresented: $showPhotoViewer,
                onMoveRequested: fpSync.isConnected ? { imageNumber in
                    moveImageNumber = imageNumber
                    moveSearchText = ""
                    showMoveImagePicker = true
                } : nil
            )
        }
        .sheet(isPresented: $showMoveImagePicker) {
            NavigationView {
                List {
                    let filtered = subjects.filter { entry in
                        guard entry.id.uuidString.lowercased() != photoViewerSubjectId else { return false }
                        if moveSearchText.isEmpty { return true }
                        let q = moveSearchText.lowercased()
                        return entry.firstName.lowercased().contains(q)
                            || entry.lastName.lowercased().contains(q)
                            || entry.rosterId.lowercased().contains(q)
                    }
                    ForEach(filtered) { entry in
                        Button(action: {
                            let targetId = entry.id.uuidString.lowercased()
                            fpSync.sendMoveCapture(
                                imageNumber: moveImageNumber,
                                fromSubjectId: photoViewerSubjectId,
                                toSubjectId: targetId,
                                fromRosterEntryId: photoViewerSubjectId,
                                toRosterEntryId: targetId
                            )
                            // Move thumbnail locally for instant UI update
                            if var fromThumbs = subjectThumbnails[photoViewerSubjectId] {
                                if let idx = fromThumbs.firstIndex(where: { $0.imageNumber == moveImageNumber }) {
                                    let moved = fromThumbs.remove(at: idx)
                                    subjectThumbnails[photoViewerSubjectId] = fromThumbs.isEmpty ? nil : fromThumbs
                                    var toThumbs = subjectThumbnails[targetId] ?? []
                                    toThumbs.append(moved)
                                    subjectThumbnails[targetId] = toThumbs
                                }
                            }
                            // Start timeout — if no confirmation in 5 seconds, show failure
                            pendingMoveTimer?.cancel()
                            let timer = DispatchWorkItem {
                                if moveConfirmationMessage == nil {
                                    moveConfirmationMessage = "Move failed — no confirmation from Surface Pro"
                                    moveConfirmationIsError = true
                                    let generator = UINotificationFeedbackGenerator()
                                    generator.notificationOccurred(.error)
                                }
                            }
                            pendingMoveTimer = timer
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timer)
                            showMoveImagePicker = false
                            showPhotoViewer = false
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(entry.firstName) \(entry.lastName)")
                                        .font(.headline)
                                    if !entry.rosterId.isEmpty {
                                        Text("ID: \(entry.rosterId)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                if !entry.grade.isEmpty {
                                    Text(entry.grade)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .searchable(text: $moveSearchText, prompt: "Search subjects")
                .navigationTitle("Move Image #\(moveImageNumber) to...")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") { showMoveImagePicker = false }
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(gallery.schoolName)
                        .font(.headline).fontWeight(.bold)
                    Text("\(shotCount) of \(filteredSubjects.count) photographed")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                Spacer()

                Button(action: { showingUSCardQRScan = true }) {
                    Label("Scan US Card", systemImage: "qrcode.viewfinder")
                        .font(.subheadline).fontWeight(.medium)
                }
                .buttonStyle(.bordered).tint(.orange)

                Button(action: { showingAddSubject = true }) {
                    Label("Add Student", systemImage: "person.badge.plus")
                        .font(.subheadline).fontWeight(.medium)
                }
                .buttonStyle(.bordered).tint(.blue)

                // Toggle detail panel
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { detailPanelVisible.toggle() } }) {
                    Image(systemName: detailPanelVisible ? "sidebar.trailing" : "sidebar.leading")
                        .font(.title3).foregroundColor(.secondary)
                }
                .frame(width: 44, height: 44)

                // Auto-select toggle: blue = taps select on camera, gray = browse only
                if fpSync.isConnected {
                    Button(action: { withAnimation { autoSelectEnabled.toggle() } }) {
                        Image(systemName: "camera.viewfinder")
                            .font(.title3)
                            .foregroundColor(autoSelectEnabled ? .blue : .secondary)
                    }
                    .frame(width: 44, height: 44)
                }

                Button(action: { showingSyncSheet = true }) {
                    Image(systemName: fpSync.isConnected ? "wifi" : "wifi.slash")
                        .font(.title3)
                        .foregroundColor(fpSync.isConnected ? .green : .secondary)
                }
                .frame(width: 44, height: 44)
            }
            .padding(.horizontal, 20).padding(.vertical, 10)

            // Progress bar
            GeometryReader { geo in
                let progress = filteredSubjects.isEmpty ? 0.0 : Double(shotCount) / Double(filteredSubjects.count)
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color(.systemGray5)).frame(height: 4)
                    Rectangle().fill(Color.green).frame(width: geo.size.width * progress, height: 4)
                }
            }
            .frame(height: 4)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary).font(.caption)
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain).font(.subheadline)
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Color(.systemGray6)).cornerRadius(8)
                .frame(width: 180)

                // Filter — single menu with all fields + checkboxes
                Menu {
                    ForEach(availableFilterFields, id: \.key) { field in
                        let values = uniqueValues(for: field.key)
                        let selected = activeFilters[field.key] ?? []
                        Menu(field.label) {
                            Button(selected.count == values.count ? "Deselect All" : "Select All") {
                                if selected.count == values.count {
                                    activeFilters.removeValue(forKey: field.key)
                                } else {
                                    activeFilters[field.key] = Set(values)
                                }
                            }
                            Divider()
                            ForEach(values, id: \.self) { value in
                                Button(action: {
                                    var current = activeFilters[field.key] ?? []
                                    if current.contains(value) {
                                        current.remove(value)
                                        if current.isEmpty { activeFilters.removeValue(forKey: field.key) }
                                        else { activeFilters[field.key] = current }
                                    } else {
                                        current.insert(value)
                                        activeFilters[field.key] = current
                                    }
                                }) {
                                    Label(value, systemImage: selected.contains(value) ? "checkmark.square.fill" : "square")
                                }
                            }
                        }
                    }
                    if !activeFilters.isEmpty {
                        Divider()
                        Button("Clear All Filters", role: .destructive) { activeFilters.removeAll() }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease").font(.caption)
                        Text("Filter").font(.subheadline)
                        if !activeFilters.isEmpty {
                            Text("\(activeFilters.count)")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(99)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(!activeFilters.isEmpty ? Color.blue.opacity(0.12) : Color(.systemGray6))
                    .foregroundColor(!activeFilters.isEmpty ? .blue : .primary)
                    .cornerRadius(8)
                }

                // Sort
                Menu {
                    ForEach([("last_name", "Last Name"), ("organization_name", "Organization"), ("grade", "Grade"), ("teacher", "Teacher")], id: \.0) { key, label in
                        Button(action: { sortField = key }) {
                            Label(label, systemImage: sortField == key ? "checkmark" : "")
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down").font(.caption)
                        Text("Sort").font(.subheadline)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }

                if hasActiveFilters {
                    Button("Clear") { activeFilters.removeAll(); searchText = "" }
                        .font(.subheadline).foregroundColor(.red)
                }

                Spacer()

                Text("\(filteredSubjects.count) student\(filteredSubjects.count == 1 ? "" : "s")")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
        .overlay(Rectangle().frame(height: 1).foregroundColor(Color(.separator)), alignment: .bottom)
    }

    // MARK: - Subject List

    private var subjectList: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                // Confirmation banner — shows when Surface Pro confirms subject selection
                if let name = confirmedSubjectName {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 16, weight: .bold))
                        Text("Selected on Camera: \(name)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.green)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.25), value: confirmedSubjectName)
                }

                // Move confirmation banner
                if let msg = moveConfirmationMessage {
                    HStack(spacing: 8) {
                        Image(systemName: moveConfirmationIsError ? "exclamationmark.circle.fill" : "arrow.right.circle.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 16, weight: .bold))
                        Text(msg)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                        Button(action: { moveConfirmationMessage = nil }) {
                            Image(systemName: "xmark").foregroundColor(.white.opacity(0.8)).font(.caption)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(moveConfirmationIsError ? Color.red : Color.blue)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.25), value: moveConfirmationMessage)
                }

                // Verification warning banner
                if let warning = verificationWarning {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 16, weight: .bold))
                        Text(warning)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        Spacer()
                        Button(action: {
                            verificationDismissTimer?.cancel()
                            if let sid = verificationSubjectId { fpSync.sendVerificationResponse(subjectId: sid, confirmed: true) }
                            verificationWarning = nil
                            verificationSubjectId = nil
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "person.fill.checkmark")
                                    .font(.system(size: 12))
                                Text("Same Subject")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.25))
                            .cornerRadius(6)
                        }
                        Button(action: {
                            verificationDismissTimer?.cancel()
                            if let sid = verificationSubjectId { fpSync.sendVerificationResponse(subjectId: sid, confirmed: false) }
                            verificationWarning = nil
                            verificationSubjectId = nil
                        }) {
                            Image(systemName: "xmark").foregroundColor(.white.opacity(0.8)).font(.caption)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.orange)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.25), value: verificationWarning)
                }

                List {
                    ForEach(filteredSubjects) { subject in
                        subjectRow(subject)
                    }
                }
                .listStyle(.plain)
            }
            .onChange(of: scrollTargetId) { target in
                if let target = target {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(target, anchor: .center)
                    }
                    scrollTargetId = nil
                }
            }
        }
    }

    @ViewBuilder
    private func subjectRow(_ subject: FPSubject) -> some View {
        let sid = subject.id.uuidString.lowercased()
        let isSelected = selectedSubjectId == subject.id
        let isActive = activeSubjectId == sid
        let hasPhotos = subject.isPhotographed || (photoCountMap[sid] ?? 0) > 0
        let latestThumb = subjectThumbnails[sid]?.last?.image
        let count = photoCountMap[sid] ?? 0

        HStack(spacing: 12) {
            if let thumb = latestThumb {
                Image(uiImage: thumb)
                    .resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text(initialsDisplay(subject))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 44, height: 44)
                    .background(Color(.systemGray5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(primaryDisplay(subject))
                    .font(.system(size: 16, weight: .semibold))
                let info = secondaryDisplay(subject)
                if !info.isEmpty {
                    Text(info).font(.caption).foregroundColor(.secondary)
                }
            }

            if subject.isAbsent {
                Text("ABSENT").font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.red).cornerRadius(4)
            }
            if subject.needsRetake {
                Text("RETAKE").font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.orange).cornerRadius(4)
            }

            Spacer()

            if !detailPanelVisible {
                if !subject.grade.isEmpty { Text(subject.grade).font(.caption).foregroundColor(.secondary) }
                if !subject.teacher.isEmpty { Text(subject.teacher).font(.caption).foregroundColor(.secondary) }
            }

            if count > 0 {
                Text("+\(count)").font(.caption).fontWeight(.bold)
                    .foregroundColor(.green).padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.green.opacity(0.12)).cornerRadius(99)
            }

            if hasPhotos {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green).font(.caption)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isActive ? Color.green.opacity(0.12) :
                      isSelected ? Color.blue.opacity(0.08) :
                      subject.isAbsent ? Color.red.opacity(0.04) :
                      Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isActive ? Color.green.opacity(0.4) :
                        isSelected ? Color.blue.opacity(0.3) :
                        Color.clear, lineWidth: 2)
        )
        .opacity(subject.isAbsent ? 0.4 : (hasPhotos && !isSelected && !isActive ? 0.5 : 1.0))
        .contentShape(Rectangle())
        .onTapGesture {
            selectedSubjectId = subject.id
            confirmedSubjectId = nil
            confirmedSubjectName = nil
            if autoSelectEnabled && fpSync.isConnected && fpSync.pairedCameraId != nil {
                selectOnCamera(subject)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(subject.isAbsent ? "Present" : "Absent") {
                toggleAbsent(subject)
            }
            .tint(subject.isAbsent ? .green : .red)
        }
        .id(subject.id)
    }

    // MARK: - Helpers

    // Parse display_config JSON or fall back to shoot_type defaults
    private var displayPrimary: String {
        if let json = gallery.displayConfig, let data = json.data(using: .utf8),
           let config = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let primary = config["primary"], !primary.isEmpty { return primary }
        let st = gallery.shootType ?? ""
        if st == "events" || st == "event" { return "organization_name" }
        if st == "faculty" { return "name" }
        return "name"
    }

    private var displaySecondary: String {
        if let json = gallery.displayConfig, let data = json.data(using: .utf8),
           let config = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let secondary = config["secondary"], !secondary.isEmpty { return secondary }
        let st = gallery.shootType ?? ""
        if st == "events" || st == "event" { return "name" }
        if st == "faculty" { return "title" }
        return "grade_teacher"
    }

    private func resolveField(_ subject: FPSubject, _ key: String) -> String {
        switch key {
        case "name":
            let n = "\(subject.firstName) \(subject.lastName)".trimmingCharacters(in: .whitespaces)
            return n.isEmpty ? (subject.rosterId.isEmpty ? "(no name)" : subject.rosterId) : n
        case "roster_name":
            let prefix = subject.rosterId.isEmpty ? "" : "\(subject.rosterId) "
            return "\(prefix)\(subject.firstName) \(subject.lastName)".trimmingCharacters(in: .whitespaces)
        case "organization_name": return subject.organizationName.isEmpty ? "(no org)" : subject.organizationName
        case "grade_teacher": return subjectInfo(subject)
        case "sport": return subject.sport
        case "grade": return subject.grade
        case "teacher": return subject.teacher
        case "email": return subject.email
        case "title": return subject.homeroom // title maps to homeroom field
        case "homeroom": return subject.homeroom
        case "student_id": return subject.studentId
        case "roster_id": return subject.rosterId
        default: return ""
        }
    }

    private func primaryDisplay(_ subject: FPSubject) -> String {
        return resolveField(subject, displayPrimary)
    }

    private func secondaryDisplay(_ subject: FPSubject) -> String {
        let value = resolveField(subject, displaySecondary)
        // If secondary is "name" and primary is also name-based, add teacher
        if displaySecondary == "name" && displayPrimary != "name" && !subject.teacher.isEmpty {
            return value.isEmpty ? subject.teacher : "\(value) \u{00B7} \(subject.teacher)"
        }
        return value
    }

    private func initialsDisplay(_ subject: FPSubject) -> String {
        let primary = resolveField(subject, displayPrimary)
        let words = primary.split(separator: " ")
        if words.count >= 2 { return "\(words[0].prefix(1))\(words[1].prefix(1))" }
        return String(primary.prefix(2)).uppercased()
    }

    private func subjectInfo(_ subject: FPSubject) -> String {
        if !subject.homeroom.isEmpty { return subject.homeroom }
        var parts: [String] = []
        if !subject.grade.isEmpty { parts.append(subject.grade) }
        if !subject.teacher.isEmpty { parts.append(subject.teacher) }
        return parts.joined(separator: " \u{00B7} ")
    }

    // MARK: - Actions

    private func toggleAbsent(_ subject: FPSubject) {
        var updated = subject
        updated.isAbsent = !subject.isAbsent
        updated.updatedAt = Date()
        Task {
            do {
                try await powerSync.saveSubject(updated)
                let sid = subject.id.uuidString.lowercased()
                fpSync.markSubjectAbsent(subjectId: sid, rosterEntryId: nil, isAbsent: updated.isAbsent)
            } catch { print("Toggle absent failed: \(error)") }
        }
    }

    private func triggerCaptureHaptic() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    private func selectOnCamera(_ subject: FPSubject) {
        let sid = subject.id.uuidString.lowercased()
        activeSubjectId = sid
        fpSync.selectSubject(subjectId: sid, rosterEntryId: nil, subjectName: "\(subject.firstName) \(subject.lastName)")
    }

    private func saveSubject(_ updated: FPSubject) {
        Task {
            do {
                try await powerSync.saveSubject(updated)
                let sid = updated.id.uuidString.lowercased()
                fpSync.sendSubjectUpdated(subjectId: sid, rosterEntryId: sid, firstName: updated.firstName, lastName: updated.lastName, rosterId: updated.rosterId)
            } catch { print("Save subject failed: \(error)") }
        }
    }

    // MARK: - Data Loading

    private func loadSubjects() async {
        isLoading = true
        do { subjects = try await powerSync.getSubjects(forGalleryId: galleryId) }
        catch { print("Failed to load subjects: \(error)") }
        isLoading = false
    }

    private func loadCachedThumbnails() async {
        let shootId = galleryId
        let cached = await Task.detached(priority: .utility) {
            ThumbnailCache.shared.loadAll(shootId: shootId)
        }.value
        if !cached.isEmpty {
            subjectThumbnails = cached
            // Update photo counts from cached data
            for (sid, thumbs) in cached {
                photoCountMap[sid] = thumbs.count
            }
        }
    }

    private func startWatching() {
        subjectWatchTask?.cancel()
        subjectWatchTask = Task {
            let stream = powerSync.watchSubjects(forGalleryId: galleryId)
            do {
                for try await updated in stream {
                    if !Task.isCancelled {
                        subjects = updated
                        if isLoading { isLoading = false }
                    }
                }
            } catch {
                if !Task.isCancelled { print("Subject watch error: \(error)") }
            }
        }
    }

    // MARK: - Sync Callbacks

    private func setupSyncCallbacks() {
        // When camera station selects a subject: auto-select + scroll on iPad + confirm
        fpSync.onActiveSubjectChanged = { (subjectId: String) in
            DispatchQueue.main.async {
                activeSubjectId = subjectId
                // Auto-select and scroll to the subject
                if let subject = subjects.first(where: { $0.id.uuidString.lowercased() == subjectId.lowercased() }) {
                    selectedSubjectId = subject.id
                    scrollTargetId = subject.id
                    // Confirm selection — shows banner + haptic
                    confirmedSubjectId = subjectId
                    confirmedSubjectName = "\(subject.firstName) \(subject.lastName)"
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.success)
                }
            }
        }

        // Stage 1: capture completed — queue the image number + haptic, clear selection confirmation
        fpSync.onCaptureCompleted = { (event: FPCaptureEvent) in
            DispatchQueue.main.async {
                let sid = event.subjectId
                photoCountMap[sid] = (photoCountMap[sid] ?? 0) + 1
                if let imgNum = event.imageNumber {
                    var pending = pendingImageNumbers[sid] ?? []
                    pending.append(imgNum)
                    pendingImageNumbers[sid] = pending
                }
                confirmedSubjectId = nil
                confirmedSubjectName = nil
                triggerCaptureHaptic()
            }
        }

        // Stage 2: thumbnail arrives — decode base64, pair with queued image number
        fpSync.onSubjectPhotographed = { (subjectId: String, thumbnail: String?, _: Int?) in
            DispatchQueue.main.async {
                guard let thumbStr = thumbnail, !thumbStr.isEmpty else { return }

                // Strip data URI prefix if present
                let base64 = thumbStr.replacingOccurrences(of: "data:image/jpeg;base64,", with: "")
                    .replacingOccurrences(of: "data:image/webp;base64,", with: "")

                guard let data = Data(base64Encoded: base64),
                      let image = UIImage(data: data) else { return }

                // Pop oldest pending image number
                var imgNum: Int? = nil
                if var pending = pendingImageNumbers[subjectId], !pending.isEmpty {
                    imgNum = pending.removeFirst()
                    pendingImageNumbers[subjectId] = pending.isEmpty ? nil : pending
                }

                // Append thumbnail
                var thumbs = subjectThumbnails[subjectId] ?? []
                thumbs.append(CaptureThumb(image: image, imageNumber: imgNum))
                if thumbs.count > 20 { thumbs = Array(thumbs.suffix(20)) }
                subjectThumbnails[subjectId] = thumbs

                // Save to disk cache
                ThumbnailCache.shared.save(shootId: galleryId, subjectId: subjectId, imageNumber: imgNum, image: image)
            }
        }

        // Verification warning — show banner when Surface detects face/QR mismatch
        fpSync.onVerificationWarning = { subjectId, subjectName, status, message, qrData in
            DispatchQueue.main.async {
                let prefix = status == "mismatch" ? "⚠ Mismatch" : "⚠ Warning"
                verificationWarning = "\(prefix): \(subjectName) — \(message)"
                verificationSubjectId = subjectId
                // Auto-dismiss after 20 seconds
                verificationDismissTimer?.cancel()
                let sid = subjectId
                let timer = DispatchWorkItem { fpSync.sendVerificationResponse(subjectId: sid, confirmed: false); verificationWarning = nil; verificationSubjectId = nil }
                verificationDismissTimer = timer
                DispatchQueue.main.asyncAfter(deadline: .now() + 20, execute: timer)
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.warning)
            }
        }

        // New subject created on another device — add to local list
        fpSync.onSubjectCreated = { (rosterEntryId: String, firstName: String, lastName: String, rosterId: String, grade: String, groupName: String) in
            DispatchQueue.main.async {
                // Skip if we already have this subject
                guard !subjects.contains(where: { $0.id.uuidString.lowercased() == rosterEntryId.lowercased() }) else { return }
                if let uuid = UUID(uuidString: rosterEntryId) {
                    var newSubject = FPSubject(id: uuid, galleryId: galleryId)
                    newSubject.firstName = firstName
                    newSubject.lastName = lastName
                    newSubject.rosterId = rosterId
                    newSubject.grade = grade
                    newSubject.sport = groupName
                    subjects.append(newSubject)
                    subjects.sort { $0.lastName.localizedCaseInsensitiveCompare($1.lastName) == .orderedAscending }
                }
            }
        }

        // Move photo confirmed by Surface Pro — update local thumbnails + confirm
        fpSync.onCaptureReassigned = { (imageNumber: Int, oldSubjectId: String, newSubjectId: String) in
            DispatchQueue.main.async {
                if var fromThumbs = subjectThumbnails[oldSubjectId] {
                    if let idx = fromThumbs.firstIndex(where: { $0.imageNumber == imageNumber }) {
                        let moved = fromThumbs.remove(at: idx)
                        subjectThumbnails[oldSubjectId] = fromThumbs.isEmpty ? nil : fromThumbs
                        var toThumbs = subjectThumbnails[newSubjectId] ?? []
                        toThumbs.append(moved)
                        subjectThumbnails[newSubjectId] = toThumbs
                    }
                }
                // Cancel failure timeout and show success
                pendingMoveTimer?.cancel()
                pendingMoveTimer = nil
                let targetName = subjects.first(where: { $0.id.uuidString.lowercased() == newSubjectId.lowercased() })
                    .map { "\($0.firstName) \($0.lastName)" } ?? "subject"
                moveConfirmationMessage = "Image #\(imageNumber) moved to \(targetName)"
                moveConfirmationIsError = false
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                // Auto-dismiss success after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if moveConfirmationIsError == false { moveConfirmationMessage = nil }
                }
            }
        }
    }

    // MARK: - Sync Sheet

    private var syncSheet: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: fpSync.isConnected ? "wifi" : "wifi.slash")
                    .font(.system(size: 48))
                    .foregroundColor(fpSync.isConnected ? .green : .secondary)
                Text(fpSync.isConnected ? "Connected to Surface Pro" : "Not Connected")
                    .font(.headline)
                if !fpSync.isConnected {
                    Text("Make sure the Surface Pro has networking started and both devices are on the same WiFi.")
                        .font(.subheadline).foregroundColor(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 40)
                    Button("Connect") { fpSync.startDiscovery(galleryId: galleryId, authToken: nil) }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Disconnect") { fpSync.disconnect() }
                        .buttonStyle(.bordered).tint(.red)
                }

                if fpSync.isConnected && fpSync.cameraDevices.count > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Camera Pairing")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        ForEach(fpSync.cameraDevices) { device in
                            Button {
                                fpSync.pairWithCamera(deviceId: device.id)
                            } label: {
                                HStack {
                                    Label(device.name, systemImage: "camera")
                                    Spacer()
                                    if device.id == fpSync.pairedCameraId {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                if fpSync.isConnected && !fpSync.devices.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connected Devices")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        ForEach(fpSync.devices) { device in
                            HStack {
                                Image(systemName: device.stationMode == "camera" ? "camera" : (device.stationMode == "ios_roster" ? "ipad" : "desktopcomputer"))
                                VStack(alignment: .leading) {
                                    Text(device.name).font(.body)
                                    Text(device.stationMode.replacingOccurrences(of: "_", with: " ").capitalized)
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                if device.captureCount > 0 {
                                    Text("\(device.captureCount) photos")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                Spacer()
            }
            .padding(.top, 40)
            .navigationTitle("Sync Connection").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showingSyncSheet = false } } }
        }
    }

    // MARK: - US Card QR Scan Sheet

    private var usCardQRSheet: some View {
        NavigationView {
            QRScannerCameraView(
                isScanning: .constant(true),
                torchOn: .constant(false),
                onCodeScanned: { code in
                    // Find matching subject by qr_code, roster_id, or student_id
                    if let match = subjects.first(where: {
                        $0.rosterId == code || $0.studentId == code ||
                        $0.id.uuidString.lowercased() == code.lowercased()
                    }) {
                        usCardSubject = match
                        showingUSCardQRScan = false
                        // Small delay to let the QR sheet dismiss before presenting doc scan
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            showingUSCardDocScan = true
                        }
                    } else {
                        scanError = "No matching US card found for code: \(code)"
                    }
                }
            )
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                if let error = scanError {
                    Text(error)
                        .font(.subheadline).fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color.red.cornerRadius(10))
                        .padding(.top, 60)
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { scanError = nil }
                        }
                }
            }
            .navigationTitle("Scan US Card QR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingUSCardQRScan = false; scanError = nil }
                }
            }
        }
    }

    // MARK: - US Card Document Scan Sheet

    private var usCardDocScanSheet: some View {
        Group {
            if scanProcessing {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Reading handwritten card...")
                        .font(.headline)
                    if let name = usCardSubject.map({ "\($0.firstName) \($0.lastName)".trimmingCharacters(in: .whitespaces) }),
                       !name.isEmpty, name != " " {
                        Text("Updating: \(name)")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DocumentScannerView(onScan: { images in
                    guard let image = images.first, let usSubject = usCardSubject else {
                        showingUSCardDocScan = false
                        return
                    }
                    scanProcessing = true
                    ClaudeRosterService.shared.extractPortraitCard(
                        image,
                        galleryId: galleryId,
                        organizationId: storedUserOrganizationID
                    ) { result in
                        scanProcessing = false
                        switch result {
                        case .success(let cardResult):
                            let extracted = cardResult.subject
                            // Update the US subject with extracted fields
                            var updated = usSubject
                            if !extracted.firstName.isEmpty { updated.firstName = extracted.firstName }
                            if !extracted.lastName.isEmpty { updated.lastName = extracted.lastName }
                            if !extracted.grade.isEmpty { updated.grade = extracted.grade }
                            if !extracted.teacher.isEmpty { updated.teacher = extracted.teacher }
                            if !extracted.studentId.isEmpty { updated.studentId = extracted.studentId }
                            updated.updatedAt = Date()

                            saveSubject(updated)
                            selectedSubjectId = updated.id
                            showingUSCardDocScan = false
                            usCardSubject = nil

                            if cardResult.usedOnDeviceOCR {
                                scanError = "Used on-device OCR (offline) — please verify the scanned info"
                            }
                        case .failure(let error):
                            scanError = "Card scan failed: \(error.localizedDescription)"
                            showingUSCardDocScan = false
                            usCardSubject = nil
                        }
                    }
                })
            }
        }
    }

    // MARK: - Add Subject Sheet

    private var addSubjectSheet: some View {
        AddSubjectSheet(galleryId: galleryId, organizationId: storedUserOrganizationID, subjects: subjects) { newSubject in
            Task {
                do {
                    try await powerSync.saveSubject(newSubject)
                    let sid = newSubject.id.uuidString.lowercased()
                    fpSync.broadcastSubjectCreated(rosterEntryId: sid, firstName: newSubject.firstName, lastName: newSubject.lastName, rosterId: newSubject.rosterId, grade: newSubject.grade, groupName: newSubject.sport.isEmpty ? newSubject.homeroom : newSubject.sport)
                    showingAddSubject = false
                } catch { print("Add subject failed: \(error)") }
            }
        }
    }
}

// MARK: - Subject Detail Panel

struct SubjectDetailPanel: View {
    let subject: FPSubject
    let thumbnails: [CaptureThumb]
    let photoCount: Int
    let galleryId: String
    let onSave: (FPSubject) -> Void
    let onSelect: () -> Void
    let onViewPhotos: (String, [CaptureThumb]) -> Void

    @State private var draft: FPSubject?

    private var editing: FPSubject { draft ?? subject }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header + select button
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(subject.firstName) \(subject.lastName)")
                            .font(.title3).fontWeight(.bold)
                        if photoCount > 0 {
                            Text("\(photoCount) photo\(photoCount == 1 ? "" : "s")")
                                .font(.caption).foregroundColor(.green)
                        }
                    }
                    Spacer()
                    Button(action: onSelect) {
                        Label("Select", systemImage: "camera")
                            .font(.subheadline).fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                }

                // Thumbnail grid
                if !thumbnails.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PHOTOS")
                            .font(.caption).fontWeight(.bold).foregroundColor(.secondary)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 6)], spacing: 6) {
                            ForEach(thumbnails) { thumb in
                                Image(uiImage: thumb.image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 70, height: 70)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .onTapGesture {
                                        onViewPhotos("\(subject.firstName) \(subject.lastName)", thumbnails)
                                    }
                            }
                        }
                    }
                }

                Divider()

                // Editable fields
                Group {
                    fieldRow("First Name", value: binding(\.firstName))
                    fieldRow("Last Name", value: binding(\.lastName))
                    fieldRow("Grade", value: binding(\.grade))
                    fieldRow("Teacher", value: binding(\.teacher))
                    fieldRow("Homeroom", value: binding(\.homeroom))
                    fieldRow("Student ID", value: binding(\.studentId))
                    fieldRow("Roster ID", value: binding(\.rosterId))
                }

                Divider()

                Group {
                    fieldRow("Email", value: binding(\.email))
                    fieldRow("Phone", value: binding(\.phone))
                    fieldRow("Notes", value: binding(\.notes))
                }

                if !subject.jerseyNumber.isEmpty || !subject.sport.isEmpty {
                    Divider()
                    Group {
                        fieldRow("Jersey #", value: binding(\.jerseyNumber))
                        fieldRow("Sport", value: binding(\.sport))
                        fieldRow("Position", value: binding(\.position))
                    }
                }

                Divider()
                HStack(spacing: 20) {
                    Toggle("Absent", isOn: absentBinding).toggleStyle(.switch)
                    Toggle("Retake", isOn: retakeBinding).toggleStyle(.switch)
                }
                .font(.subheadline)

                Spacer(minLength: 40)
            }
            .padding(20)
        }
        .background(Color(.secondarySystemBackground))
        .onChange(of: subject.id) { _ in draft = nil }
    }

    private func fieldRow(_ label: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).fontWeight(.semibold).foregroundColor(.secondary).textCase(.uppercase)
            TextField(label, text: value)
                .textFieldStyle(.roundedBorder).font(.body)
                .onChange(of: value.wrappedValue) { _ in
                    if let d = draft { onSave(d) }
                }
        }
    }

    private func binding(_ keyPath: WritableKeyPath<FPSubject, String>) -> Binding<String> {
        Binding(
            get: { editing[keyPath: keyPath] },
            set: { newValue in
                if draft == nil { draft = subject }
                draft![keyPath: keyPath] = newValue
            }
        )
    }

    private var absentBinding: Binding<Bool> {
        Binding(get: { editing.isAbsent }, set: { v in
            if draft == nil { draft = subject }
            draft!.isAbsent = v; onSave(draft!)
        })
    }

    private var retakeBinding: Binding<Bool> {
        Binding(get: { editing.needsRetake }, set: { v in
            if draft == nil { draft = subject }
            draft!.needsRetake = v; onSave(draft!)
        })
    }
}

// MARK: - Add Subject Sheet

struct AddSubjectSheet: View {
    let galleryId: String
    let organizationId: String
    let subjects: [FPSubject]
    let onAdd: (FPSubject) -> Void

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var grade = ""
    @State private var teacher = ""
    @State private var homeroom = ""
    @State private var studentId = ""
    @State private var showingCardScan = false
    @State private var scanProcessing = false
    @State private var ocrWarning: String?
    @Environment(\.dismiss) private var dismiss

    private var showGrade: Bool { subjects.contains { !$0.grade.isEmpty } }
    private var showTeacher: Bool { subjects.contains { !$0.teacher.isEmpty } }
    private var showHomeroom: Bool { subjects.contains { !$0.homeroom.isEmpty } }
    private var showStudentId: Bool { subjects.contains { !$0.studentId.isEmpty } }

    var body: some View {
        NavigationView {
            Form {
                // Scan Card option
                Section {
                    if scanProcessing {
                        HStack {
                            ProgressView()
                            Text("Reading card...").foregroundColor(.secondary)
                        }
                    } else {
                        Button(action: { showingCardScan = true }) {
                            Label("Scan Handwritten Card", systemImage: "doc.viewfinder")
                        }
                    }
                }

                if let warning = ocrWarning {
                    Section {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                    }
                }

                Section("Name") {
                    TextField("First Name", text: $firstName)
                    TextField("Last Name", text: $lastName)
                }
                if showGrade || showTeacher || showHomeroom || showStudentId {
                    Section("Info") {
                        if showGrade { TextField("Grade", text: $grade) }
                        if showTeacher { TextField("Teacher", text: $teacher) }
                        if showHomeroom { TextField("Homeroom", text: $homeroom) }
                        if showStudentId { TextField("Student ID", text: $studentId) }
                    }
                }
            }
            .navigationTitle("Add Student").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let subject = FPSubject(galleryId: galleryId, organizationId: organizationId, firstName: firstName.trimmingCharacters(in: .whitespaces), lastName: lastName.trimmingCharacters(in: .whitespaces), grade: grade, teacher: teacher, homeroom: homeroom, studentId: studentId)
                        onAdd(subject)
                    }
                    .disabled(firstName.trimmingCharacters(in: .whitespaces).isEmpty || lastName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $showingCardScan) {
                DocumentScannerView(onScan: { images in
                    guard let image = images.first else { return }
                    scanProcessing = true
                    ClaudeRosterService.shared.extractPortraitCard(
                        image,
                        galleryId: galleryId,
                        organizationId: organizationId
                    ) { result in
                        scanProcessing = false
                        if case .success(let cardResult) = result {
                            let extracted = cardResult.subject
                            if !extracted.firstName.isEmpty { firstName = extracted.firstName }
                            if !extracted.lastName.isEmpty { lastName = extracted.lastName }
                            if !extracted.grade.isEmpty { grade = extracted.grade }
                            if !extracted.teacher.isEmpty { teacher = extracted.teacher }
                            if !extracted.studentId.isEmpty { studentId = extracted.studentId }
                            if cardResult.usedOnDeviceOCR {
                                ocrWarning = "Used on-device OCR (offline) — please verify"
                            }
                        }
                    }
                })
            }
        }
    }
}
