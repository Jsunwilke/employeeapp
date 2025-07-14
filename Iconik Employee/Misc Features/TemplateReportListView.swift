import SwiftUI
import Firebase
import FirebaseAuth
import FirebaseFirestore

struct TemplateReportListView: View {
    @StateObject private var templateService = TemplateService.shared
    @State private var reports: [DailyJobReport] = []
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var selectedReport: DailyJobReport?
    @State private var showingReportDetail = false
    @State private var searchText = ""
    @State private var selectedFilterType: String = "All"
    
    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""
    
    private let filterTypes = ["All", "This Week", "This Month", "Last 30 Days"]
    
    private var filteredReports: [DailyJobReport] {
        let dateFiltered = filterReportsByDate()
        
        if searchText.isEmpty {
            return dateFiltered
        } else {
            return dateFiltered.filter { report in
                report.photographer.localizedCaseInsensitiveContains(searchText) ||
                report.templateName?.localizedCaseInsensitiveContains(searchText) == true ||
                report.date.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    private var groupedReports: [String: [DailyJobReport]] {
        Dictionary(grouping: filteredReports) { report in
            // Group by template name or "Legacy Reports" for non-template reports
            if let templateName = report.templateName {
                return templateName
            } else {
                return "Legacy Reports"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with search and filter
            headerSection
            
            if isLoading {
                loadingView
            } else if !errorMessage.isEmpty {
                errorView
            } else if reports.isEmpty {
                emptyStateView
            } else {
                reportsListView
            }
        }
        .navigationTitle("Template Reports")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            loadReports()
        }
        .sheet(isPresented: $showingReportDetail) {
            if let report = selectedReport {
                ReportDetailView(report: report)
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search reports...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            .padding(.horizontal)
            
            // Filter picker
            Picker("Filter", selection: $selectedFilterType) {
                ForEach(filterTypes, id: \.self) { type in
                    Text(type).tag(type)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            
            // Summary info
            if !reports.isEmpty {
                HStack {
                    Text("\(filteredReports.count) report\(filteredReports.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    let templateCount = filteredReports.filter { $0.reportType == "template" }.count
                    let legacyCount = filteredReports.filter { $0.reportType != "template" }.count
                    
                    Text("\(templateCount) template, \(legacyCount) legacy")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
        .background(Color(.systemBackground))
    }
    
    // MARK: - Content Views
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text("Loading reports...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            Text("Unable to Load Reports")
                .font(.headline)
            
            Text(errorMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Try Again") {
                loadReports()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("No Reports Found")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("You haven't created any template-based reports yet. Create your first report using the Custom Daily Reports feature.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var reportsListView: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                ForEach(groupedReports.keys.sorted(), id: \.self) { groupName in
                    if let groupReports = groupedReports[groupName] {
                        reportGroupSection(groupName: groupName, reports: groupReports)
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Report Group Section
    
    private func reportGroupSection(groupName: String, reports: [DailyJobReport]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Group header
            HStack {
                if groupName == "Legacy Reports" {
                    Image(systemName: "doc.text")
                        .foregroundColor(.gray)
                } else {
                    Image(systemName: "doc.text.below.ecg")
                        .foregroundColor(.blue)
                }
                
                Text(groupName)
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(reports.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(12)
            }
            
            // Reports list
            VStack(spacing: 8) {
                ForEach(reports.sorted(by: { $0.createdAt.seconds > $1.createdAt.seconds })) { report in
                    reportCard(report)
                }
            }
        }
    }
    
    // MARK: - Report Card
    
    private func reportCard(_ report: DailyJobReport) -> some View {
        Button(action: {
            selectedReport = report
            showingReportDetail = true
        }) {
            VStack(alignment: .leading, spacing: 12) {
                // Header with date and type
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formatDate(report.date))
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("By \(report.photographer)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if report.reportType == "template" {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("TEMPLATE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                            
                            if let version = report.templateVersion {
                                Text("v\(version)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text("LEGACY")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                }
                
                // Smart fields indicator for template reports
                if let smartFields = report.smartFieldsUsed, !smartFields.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text("\(smartFields.count) smart field\(smartFields.count == 1 ? "" : "s") used")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                
                // Data preview
                let dataCount = report.formData.count
                if dataCount > 0 {
                    HStack {
                        Image(systemName: "list.bullet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(dataCount) field\(dataCount == 1 ? "" : "s") completed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(formatRelativeDate(report.createdAt))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(report.reportType == "template" ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Helper Functions
    
    private func loadReports() {
        guard !storedUserOrganizationID.isEmpty else {
            errorMessage = "No organization ID found"
            return
        }
        
        guard let currentUser = Auth.auth().currentUser else {
            errorMessage = "User not signed in"
            return
        }
        
        isLoading = true
        errorMessage = ""
        
        let db = Firestore.firestore()
        
        db.collection("dailyJobReports")
            .whereField("organizationID", isEqualTo: storedUserOrganizationID)
            .whereField("userId", isEqualTo: currentUser.uid)
            .order(by: "createdAt", descending: true)
            .limit(to: 100) // Limit to last 100 reports for performance
            .getDocuments { snapshot, error in
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    if let error = error {
                        self.errorMessage = error.localizedDescription
                        return
                    }
                    
                    guard let documents = snapshot?.documents else {
                        self.reports = []
                        return
                    }
                    
                    self.reports = documents.compactMap { doc in
                        try? doc.data(as: DailyJobReport.self)
                    }
                }
            }
    }
    
    private func filterReportsByDate() -> [DailyJobReport] {
        let calendar = Calendar.current
        let now = Date()
        
        switch selectedFilterType {
        case "This Week":
            let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            return reports.filter { report in
                let reportDate = report.createdAt.dateValue()
                return reportDate >= startOfWeek
            }
            
        case "This Month":
            let startOfMonth = calendar.dateInterval(of: .month, for: now)?.start ?? now
            return reports.filter { report in
                let reportDate = report.createdAt.dateValue()
                return reportDate >= startOfMonth
            }
            
        case "Last 30 Days":
            let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: now) ?? now
            return reports.filter { report in
                let reportDate = report.createdAt.dateValue()
                return reportDate >= thirtyDaysAgo
            }
            
        default: // "All"
            return reports
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        if let date = ISO8601DateFormatter().date(from: dateString) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            return formatter.string(from: date)
        }
        return dateString
    }
    
    private func formatRelativeDate(_ timestamp: Timestamp) -> String {
        let date = timestamp.dateValue()
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Report Detail View

struct ReportDetailView: View {
    let report: DailyJobReport
    
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header info
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(formatDate(report.date))
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            Spacer()
                            
                            if report.reportType == "template" {
                                Text("TEMPLATE")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(8)
                            }
                        }
                        
                        Text("Photographer: \(report.photographer)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        if let templateName = report.templateName {
                            HStack {
                                Text("Template: \(templateName)")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                if let version = report.templateVersion {
                                    Text("v\(version)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Form data
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Report Data")
                            .font(.headline)
                        
                        ForEach(Array(report.formData.keys.sorted()), id: \.self) { key in
                            if let value = report.formData[key] {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(key.capitalized.replacingOccurrences(of: "_", with: " "))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    
                                    Text(formatFieldValue(value.value))
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .padding(.leading, 8)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    
                    // Smart fields info
                    if let smartFields = report.smartFieldsUsed, !smartFields.isEmpty {
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Smart Fields Used")
                                .font(.headline)
                            
                            ForEach(smartFields, id: \.self) { fieldId in
                                HStack {
                                    Image(systemName: "sparkles")
                                        .foregroundColor(.blue)
                                        .font(.caption)
                                    
                                    Text(fieldId.capitalized.replacingOccurrences(of: "_", with: " "))
                                        .font(.subheadline)
                                }
                            }
                        }
                    }
                    
                    Spacer(minLength: 20)
                }
                .padding()
            }
            .navigationTitle("Report Details")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
    
    private func formatDate(_ dateString: String) -> String {
        if let date = ISO8601DateFormatter().date(from: dateString) {
            let formatter = DateFormatter()
            formatter.dateStyle = .full
            return formatter.string(from: date)
        }
        return dateString
    }
    
    private func formatFieldValue(_ value: Any) -> String {
        if let stringValue = value as? String {
            return stringValue
        } else if let numberValue = value as? NSNumber {
            return numberValue.stringValue
        } else if let boolValue = value as? Bool {
            return boolValue ? "Yes" : "No"
        } else if let arrayValue = value as? [Any] {
            return arrayValue.map { "\($0)" }.joined(separator: ", ")
        } else {
            return "\(value)"
        }
    }
}

// MARK: - Preview

struct TemplateReportListView_Previews: PreviewProvider {
    static var previews: some View {
        TemplateReportListView()
    }
}