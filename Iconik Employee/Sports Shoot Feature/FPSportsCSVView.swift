//
//  FPSportsCSVView.swift
//  Iconik Employee
//
//  CSV import/export for FP Sports subjects.
//  Parallel to CSVImportExportView but uses FPSubject + PowerSync subjects table.
//

import SwiftUI
import UniformTypeIdentifiers

struct FPSportsCSVView: View {
    let galleryId: String
    let organizationId: String
    let onComplete: (Bool) -> Void

    private let powerSync = PowerSyncManager.shared
    @Environment(\.presentationMode) var presentationMode

    @State private var isImporting = false
    @State private var isExporting = false
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var importedSubjects: [FPSubject] = []
    @State private var currentSubjects: [FPSubject] = []
    @State private var isLoading = true

    @State private var showPhotoImport = false
    @State private var showMultiPhotoImport = false

    var body: some View {
        NavigationView {
            VStack {
                if isLoading {
                    ProgressView("Loading...")
                } else {
                    Form {
                        Section(header: Text("Import/Export")) {
                            Button(action: { showMultiPhotoImport = true }) {
                                Label("Import Paper Rosters", systemImage: "doc.viewfinder").foregroundColor(.blue)
                            }
                            Button(action: { showPhotoImport = true }) {
                                Label("Import from Photo", systemImage: "camera").foregroundColor(.blue)
                            }
                            Button(action: { isImporting = true }) {
                                Label("Import CSV", systemImage: "square.and.arrow.down")
                            }
                            Button(action: { exportCSV() }) {
                                Label("Export CSV", systemImage: "square.and.arrow.up")
                            }
                        }

                        Section(header: Text("Field Mapping")) {
                            Text("Name → Last Name").font(.subheadline)
                            Text("Roster ID → Roster ID").font(.subheadline)
                            Text("Sport/Team → Sport").font(.subheadline)
                            Text("Special → Teacher/Grade").font(.subheadline)
                            Text("Images use semicolon separator (;)")
                                .font(.subheadline).foregroundColor(.secondary).padding(.top, 4)
                        }

                        if !importedSubjects.isEmpty {
                            Section(header: Text("Preview")) {
                                ForEach(importedSubjects.prefix(5)) { subject in
                                    VStack(alignment: .leading) {
                                        Text("\(subject.lastName) — ID \(subject.rosterId)").font(.headline)
                                        if !subject.sport.isEmpty {
                                            Text("Sport: \(subject.sport)").font(.caption)
                                        }
                                        if !subject.teacher.isEmpty {
                                            Text("Special: \(subject.teacher)").font(.caption)
                                        }
                                    }
                                }
                                if importedSubjects.count > 5 {
                                    Text("... and \(importedSubjects.count - 5) more")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                                Button(action: { saveImported() }) {
                                    Label("Save Imported Roster", systemImage: "checkmark.circle").foregroundColor(.green)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Import/Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { onComplete(false); presentationMode.wrappedValue.dismiss() }
                }
            }
            .sheet(isPresented: $isImporting) {
                DocumentPicker(onDocumentPicked: { url in importCSV(from: url) })
            }
            .sheet(isPresented: $showPhotoImport) {
                FPSportsPhotoImporter(galleryId: galleryId, organizationId: organizationId) { success in
                    if success { loadSubjects(); onComplete(true) }
                    showPhotoImport = false
                }
            }
            .sheet(isPresented: $showMultiPhotoImport) {
                FPSportsMultiPhotoImporter(galleryId: galleryId, organizationId: organizationId) { success in
                    if success { loadSubjects(); onComplete(true) }
                    showMultiPhotoImport = false
                }
            }
            .onAppear { loadSubjects() }
            .alert(isPresented: $showAlert) {
                Alert(title: Text(alertTitle), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
        }
    }

    private func loadSubjects() {
        isLoading = true
        Task {
            do {
                let subjects = try await powerSync.getSubjects(forGalleryId: galleryId)
                await MainActor.run { currentSubjects = subjects; isLoading = false }
            } catch {
                await MainActor.run {
                    isLoading = false
                    alertTitle = "Error"
                    alertMessage = "Failed to load subjects: \(error.localizedDescription)"
                    showAlert = true
                }
            }
        }
    }

    private func importCSV(from url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let csvData = try String(contentsOf: url)
            importedSubjects = parseCSV(csvString: csvData)
            if importedSubjects.isEmpty {
                alertTitle = "Import Error"
                alertMessage = "No valid entries found."
            } else {
                alertTitle = "Import Success"
                alertMessage = "Imported \(importedSubjects.count) entries. Review and save."
            }
            showAlert = true
        } catch {
            alertTitle = "Import Error"
            alertMessage = "Failed to read CSV: \(error.localizedDescription)"
            showAlert = true
        }
    }

    private func parseCSV(csvString: String) -> [FPSubject] {
        var subjects: [FPSubject] = []
        let lines = csvString.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count > 1 else { return subjects }

        let header = parseCSVLine(lines[0])
        let h = header.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

        let nameIdx = h.firstIndex(of: "name") ?? h.firstIndex(of: "last_name") ?? h.firstIndex(of: "lastname")
        let rosterIdIdx = h.firstIndex(of: "roster id") ?? h.firstIndex(of: "rosterid") ?? h.firstIndex(of: "roster_id") ?? h.firstIndex(of: "subject id") ?? h.firstIndex(of: "subjectid")
        let specialIdx = h.firstIndex(of: "special") ?? h.firstIndex(of: "teacher")
        let sportIdx = h.firstIndex(of: "sport/team") ?? h.firstIndex(of: "sport") ?? h.firstIndex(of: "team") ?? h.firstIndex(of: "group")
        let emailIdx = h.firstIndex(of: "email")
        let phoneIdx = h.firstIndex(of: "phone")
        let imagesIdx = h.firstIndex(of: "images") ?? h.firstIndex(of: "image_numbers")
        let gradeIdx = h.firstIndex(of: "grade")
        let jerseyIdx = h.firstIndex(of: "jersey") ?? h.firstIndex(of: "jersey_number") ?? h.firstIndex(of: "jersey number")

        for i in 1..<lines.count {
            let f = parseCSVLine(lines[i])
            guard !f.isEmpty else { continue }
            let subject = FPSubject(
                galleryId: galleryId,
                organizationId: organizationId,
                firstName: "",
                lastName: nameIdx != nil && f.count > nameIdx! ? f[nameIdx!] : "",
                grade: gradeIdx != nil && f.count > gradeIdx! ? f[gradeIdx!] : "",
                teacher: specialIdx != nil && f.count > specialIdx! ? f[specialIdx!] : "",
                homeroom: "",
                studentId: "",
                rosterId: rosterIdIdx != nil && f.count > rosterIdIdx! ? f[rosterIdIdx!] : "",
                jerseyNumber: jerseyIdx != nil && f.count > jerseyIdx! ? f[jerseyIdx!] : "",
                sport: (sportIdx != nil && f.count > sportIdx! ? f[sportIdx!] : "").uppercased(),
                position: "",
                email: emailIdx != nil && f.count > emailIdx! ? f[emailIdx!] : "",
                phone: phoneIdx != nil && f.count > phoneIdx! ? f[phoneIdx!] : "",
                imageNumbers: imagesIdx != nil && f.count > imagesIdx! ? f[imagesIdx!] : ""
            )
            subjects.append(subject)
        }
        return subjects
    }

    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for char in line {
            if char == "\"" { inQuotes.toggle() }
            else if char == "," && !inQuotes { fields.append(current.trimmingCharacters(in: .whitespaces)); current = "" }
            else { current.append(char) }
        }
        fields.append(current.trimmingCharacters(in: .whitespaces))
        return fields
    }

    private func saveImported() {
        guard !importedSubjects.isEmpty else { return }
        isLoading = true
        Task {
            var saved = 0
            for subject in importedSubjects {
                do {
                    try await powerSync.saveSubject(subject)
                    saved += 1
                } catch {
                    print("FPSportsCSVView: Failed to save subject: \(error)")
                }
            }
            await MainActor.run {
                isLoading = false
                alertTitle = "Import Complete"
                alertMessage = "Saved \(saved) of \(importedSubjects.count) entries."
                showAlert = true
                importedSubjects = []
                loadSubjects()
                onComplete(true)
            }
        }
    }

    private func exportCSV() {
        guard !currentSubjects.isEmpty else {
            alertTitle = "Export Error"; alertMessage = "No subjects to export."; showAlert = true; return
        }
        var csv = "Name,Roster ID,Special,Sport/Team,Grade,Jersey,Email,Phone,Images\n"
        for s in currentSubjects {
            csv += "\(esc(s.lastName)),\(esc(s.rosterId)),\(esc(s.teacher)),\(esc(s.sport)),\(esc(s.grade)),\(esc(s.jerseyNumber)),\(esc(s.email)),\(esc(s.phone)),\(esc(s.imageNumbers))\n"
        }
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("Roster_\(Date().timeIntervalSince1970).csv")
        do {
            try csv.write(to: fileURL, atomically: true, encoding: .utf8)
            let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                rootVC.present(activityVC, animated: true)
            }
        } catch {
            alertTitle = "Export Error"; alertMessage = "Failed: \(error.localizedDescription)"; showAlert = true
        }
    }

    private func esc(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") {
            return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return field
    }
}
