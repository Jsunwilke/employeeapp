import SwiftUI
import Firebase
import FirebaseAuth

struct CustomDailyReportsView: View {
    @StateObject private var templateService = TemplateService.shared
    @State private var selectedTemplate: ReportTemplate?
    @State private var searchText = ""
    
    @Environment(\.presentationMode) var presentationMode
    
    private var filteredTemplates: [ReportTemplate] {
        if searchText.isEmpty {
            return templateService.templates
        } else {
            return templateService.templates.filter { template in
                template.name.localizedCaseInsensitiveContains(searchText) ||
                template.description?.localizedCaseInsensitiveContains(searchText) == true ||
                template.shootType.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    private var templatesByCategory: [String: [ReportTemplate]] {
        Dictionary(grouping: filteredTemplates) { template in
            template.shootType.capitalized
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header with search
                headerSection
                
                if templateService.isLoading {
                    loadingView
                } else if !templateService.errorMessage.isEmpty {
                    errorView
                } else if templateService.templates.isEmpty {
                    emptyStateView
                } else {
                    templatesListView
                }
            }
            .navigationTitle("Custom Daily Reports")
            .navigationBarTitleDisplayMode(.large)
            .navigationBarItems(
                leading: Button("Close") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
        .onAppear {
            templateService.loadTemplatesAsync()
        }
        .sheet(item: $selectedTemplate) { template in
            TemplateFormView(template: template)
                .onAppear {
                    print("🔍 Sheet presented with template: \(template.name)")
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
                
                TextField("Search templates...", text: $searchText)
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
            
            // Summary info
            if !templateService.templates.isEmpty {
                HStack {
                    Text("\(filteredTemplates.count) template\(filteredTemplates.count == 1 ? "" : "s") available")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("\(templatesByCategory.count) categor\(templatesByCategory.count == 1 ? "y" : "ies")")
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
            
            Text("Loading templates...")
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
            
            Text("Unable to Load Templates")
                .font(.headline)
            
            Text(templateService.errorMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Try Again") {
                templateService.loadTemplatesAsync()
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
            
            Text("No Templates Available")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Contact your administrator to set up daily report templates for your organization.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var templatesListView: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                ForEach(templatesByCategory.keys.sorted(), id: \.self) { category in
                    templateCategorySection(category: category, templates: templatesByCategory[category] ?? [])
                }
            }
            .padding()
        }
    }
    
    // MARK: - Template Category Section
    
    private func templateCategorySection(category: String, templates: [ReportTemplate]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Category header
            HStack {
                Text(category)
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Text("\(templates.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(12)
            }
            
            // Templates grid
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 12) {
                ForEach(templates.sorted(by: { $0.isDefault && !$1.isDefault })) { template in
                    templateCard(template)
                }
            }
        }
    }
    
    // MARK: - Template Card
    
    private func templateCard(_ template: ReportTemplate) -> some View {
        Button(action: {
            print("🔍 Template card tapped: '\(template.name)'")
            print("🔍 Before setting - selectedTemplate: \(selectedTemplate?.name ?? "nil")")
            selectedTemplate = template
            print("🔍 After setting selectedTemplate: \(selectedTemplate?.name ?? "nil")")
            print("🔍 Sheet should now present automatically")
        }) {
            VStack(alignment: .leading, spacing: 12) {
                // Header with title and default badge
                HStack {
                    Text(template.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    
                    Spacer()
                    
                    if template.isDefault {
                        Text("DEFAULT")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                }
                
                // Description
                if let description = template.description, !description.isEmpty {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                } else {
                    Text("No description available")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .italic()
                }
                
                Spacer()
                
                // Footer with field count and version
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "list.bullet")
                            .font(.caption)
                        Text("\(template.fields.count) field\(template.fields.count == 1 ? "" : "s")")
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("v\(template.version)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Smart fields indicator
                let smartFieldsCount = template.fields.filter { $0.smartConfig != nil }.count
                if smartFieldsCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text("\(smartFieldsCount) smart field\(smartFieldsCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding(16)
            .frame(height: 160)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(template.isDefault ? Color.green.opacity(0.3) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview

struct CustomDailyReportsView_Previews: PreviewProvider {
    static var previews: some View {
        CustomDailyReportsView()
    }
}