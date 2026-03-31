//
//  PoserStationView.swift
//  Iconik Employee
//
//  iPad poser station for spring/underclass portrait shoots.
//  Shows subject queue, handles check-in, syncs bi-directionally
//  with Surface Pro camera station via WebSocket.
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

    // UI state
    @State private var showFullRoster = false
    @State private var searchText = ""
    @State private var activeSubjectId: String?
    @State private var photoCountMap: [String: Int] = [:]
    @State private var thumbnailMap: [String: String] = [:]

    // Sync connection
    @State private var showingSyncSheet = false

    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""

    // MARK: - Computed

    var galleryId: String {
        gallery.galleryId ?? gallery.id.uuidString.lowercased()
    }

    var queue: [FPSubject] {
        subjects
            .filter { $0.checkedInAt != nil && !$0.isPhotographed }
            .sorted { ($0.checkedInAt ?? "") < ($1.checkedInAt ?? "") }
    }

    var photographed: [FPSubject] {
        subjects.filter { $0.isPhotographed || (photoCountMap[$0.id.uuidString.lowercased()] ?? 0) > 0 }
    }

    var rosterSubjects: [FPSubject] {
        let q = searchText.lowercased()
        let list = subjects.sorted { $0.lastName < $1.lastName }
        if q.isEmpty { return list }
        return list.filter {
            $0.firstName.lowercased().contains(q) ||
            $0.lastName.lowercased().contains(q) ||
            $0.grade.lowercased().contains(q) ||
            $0.teacher.lowercased().contains(q)
        }
    }

    var shotCount: Int { photographed.count }
    var totalCount: Int { subjects.count }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerBar

            // Content
            if isLoading {
                ProgressView("Loading subjects...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if showFullRoster {
                fullRosterLayout
            } else {
                queueOnlyLayout
            }
        }
        .navigationTitle("")
        .navigationBarHidden(true)
        .task {
            await loadSubjects()
            startWatching()
            setupSyncCallbacks()
        }
        .onDisappear {
            subjectWatchTask?.cancel()
        }
        .sheet(isPresented: $showingSyncSheet) {
            syncConnectionSheet
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(gallery.schoolName)
                    .font(.headline)
                    .fontWeight(.bold)

                Text("\(shotCount) of \(totalCount) photographed")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Toggle roster/queue
            Button(action: { showFullRoster.toggle() }) {
                Label(showFullRoster ? "Queue" : "Roster", systemImage: showFullRoster ? "list.number" : "person.3")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .buttonStyle(.bordered)
            .tint(.blue)

            // Sync connection
            Button(action: { showingSyncSheet = true }) {
                Image(systemName: fpSync.isConnected ? "wifi" : "wifi.slash")
                    .font(.title3)
                    .foregroundColor(fpSync.isConnected ? .green : .secondary)
            }
            .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(Color(.separator)),
            alignment: .bottom
        )
    }

    // MARK: - Queue Only Layout

    private var queueOnlyLayout: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                if queue.isEmpty {
                    emptyQueueView
                } else {
                    ForEach(queue) { subject in
                        subjectRow(subject, isActive: activeSubjectId == subject.id.uuidString.lowercased())
                            .onTapGesture {
                                selectSubject(subject)
                            }
                    }
                }

                if !photographed.isEmpty {
                    Section {
                        ForEach(photographed) { subject in
                            subjectRow(subject, isActive: false)
                                .opacity(0.45)
                        }
                    } header: {
                        Text("Photographed")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 20)
                            .padding(.horizontal, 4)
                    }
                }
            }
            .padding(16)
        }
    }

    // MARK: - Full Roster Layout

    private var fullRosterLayout: some View {
        HStack(spacing: 0) {
            // Left: Full roster
            VStack(spacing: 0) {
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                // Roster list
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(rosterSubjects) { subject in
                            let isCheckedIn = subject.checkedInAt != nil
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(subject.firstName) \(subject.lastName)")
                                        .font(.body)
                                        .fontWeight(.medium)
                                    let rosterInfo = subjectInfo(subject)
                                    if !rosterInfo.isEmpty {
                                        Text(rosterInfo)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                if isCheckedIn {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                } else {
                                    Button("Check In") {
                                        checkIn(subject)
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(.blue)
                                    .controlSize(.small)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(isCheckedIn ? Color.green.opacity(0.06) : Color.clear)
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color(.systemBackground))

            // Divider
            Rectangle()
                .fill(Color(.separator))
                .frame(width: 1)

            // Right: Queue
            VStack(spacing: 0) {
                Text("Queue")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6))

                ScrollView {
                    LazyVStack(spacing: 6) {
                        if queue.isEmpty {
                            Text("No students checked in")
                                .foregroundColor(.secondary)
                                .padding(40)
                        } else {
                            ForEach(queue) { subject in
                                subjectRow(subject, isActive: activeSubjectId == subject.id.uuidString.lowercased())
                                    .onTapGesture {
                                        selectSubject(subject)
                                    }
                            }
                        }
                    }
                    .padding(12)
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color(.secondarySystemBackground))
        }
    }

    // MARK: - Subject Row

    private func subjectRow(_ subject: FPSubject, isActive: Bool) -> some View {
        let sid = subject.id.uuidString.lowercased()
        let count = photoCountMap[sid] ?? 0

        return HStack(spacing: 12) {
            // Thumbnail or initials
            if let thumbUrl = thumbnailMap[sid], let url = URL(string: thumbUrl) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    initialsView(subject)
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
            } else {
                initialsView(subject)
            }

            // Name + info
            VStack(alignment: .leading, spacing: 2) {
                Text("\(subject.firstName) \(subject.lastName)")
                    .font(.system(size: 18, weight: .semibold))

                let info = subjectInfo(subject)
                if !info.isEmpty {
                    Text(info)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Photo count
            if count > 0 {
                Text("+\(count)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(99)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isActive ? Color.green.opacity(0.12) : Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isActive ? Color.green.opacity(0.4) : Color.clear, lineWidth: 2)
        )
    }

    private func initialsView(_ subject: FPSubject) -> some View {
        let initials = "\(subject.firstName.prefix(1))\(subject.lastName.prefix(1))"
        return Text(initials)
            .font(.system(size: 14, weight: .bold))
            .foregroundColor(.secondary)
            .frame(width: 44, height: 44)
            .background(Color.gray.opacity(0.2))
            .clipShape(Circle())
    }

    private func subjectInfo(_ subject: FPSubject) -> String {
        if !subject.homeroom.isEmpty {
            return subject.homeroom
        }
        var parts: [String] = []
        if !subject.grade.isEmpty { parts.append(subject.grade) }
        if !subject.teacher.isEmpty { parts.append(subject.teacher) }
        return parts.joined(separator: " \u{00B7} ")
    }

    private var emptyQueueView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("No students in queue")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Switch to Roster view to check students in, or use the kiosk on the Surface Pro.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .padding(60)
    }

    // MARK: - Sync Connection Sheet

    private var syncConnectionSheet: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: fpSync.isConnected ? "wifi" : "wifi.slash")
                    .font(.system(size: 48))
                    .foregroundColor(fpSync.isConnected ? .green : .secondary)

                Text(fpSync.isConnected ? "Connected to Surface Pro" : "Not Connected")
                    .font(.headline)

                if !fpSync.isConnected {
                    Text("Make sure the Surface Pro has networking started and both devices are on the same WiFi network.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)

                    Button("Connect") {
                        fpSync.startDiscovery(galleryId: galleryId, authToken: nil)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Disconnect") {
                        fpSync.disconnect()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }

                Spacer()
            }
            .padding(.top, 40)
            .navigationTitle("Sync Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showingSyncSheet = false }
                }
            }
        }
    }

    // MARK: - Actions

    private func selectSubject(_ subject: FPSubject) {
        let sid = subject.id.uuidString.lowercased()
        activeSubjectId = sid

        // Tell camera station to select this subject
        fpSync.selectSubject(
            subjectId: sid,
            rosterEntryId: nil,
            subjectName: "\(subject.firstName) \(subject.lastName)"
        )
    }

    private func checkIn(_ subject: FPSubject) {
        var updated = subject
        updated.checkedInAt = ISO8601DateFormatter().string(from: Date())

        Task {
            do {
                try await powerSync.saveSubject(updated)
                // Broadcast to other stations
                let sid = subject.id.uuidString.lowercased()
                let name = "\(subject.firstName) \(subject.lastName)"
                fpSync.broadcastCheckIn(galleryId: galleryId, subjectId: sid, subjectName: name)
            } catch {
                print("Check-in failed: \(error)")
            }
        }
    }

    // MARK: - Data Loading

    private func loadSubjects() async {
        isLoading = true
        do {
            subjects = try await powerSync.getSubjects(forGalleryId: galleryId)
        } catch {
            print("Failed to load subjects: \(error)")
        }
        isLoading = false
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
                if !Task.isCancelled {
                    print("Subject watch error: \(error)")
                }
            }
        }
    }

    // MARK: - Sync Callbacks

    private func setupSyncCallbacks() {
        fpSync.onActiveSubjectChanged = { (subjectId: String) in
            DispatchQueue.main.async {
                activeSubjectId = subjectId
            }
        }

        fpSync.onSubjectPhotographed = { (subjectId: String, _: String?, _: Int?) in
            DispatchQueue.main.async {
                let count = photoCountMap[subjectId] ?? 0
                photoCountMap[subjectId] = count + 1
            }
        }

        fpSync.onCaptureCompleted = { (event: FPCaptureEvent) in
            DispatchQueue.main.async {
                let sid = event.subjectId
                let count = photoCountMap[sid] ?? 0
                photoCountMap[sid] = count + 1
            }
        }
    }
}
