import SwiftUI

struct AllFeaturesView: View {
    @ObservedObject var viewModel: MainEmployeeViewModel
    @Binding var selectedFeatureID: String?
    @State private var localEditMode: EditMode = .inactive
    let userRole: String
    
    // Manager features
    let managerFeatures: [FeatureItem] = [
        FeatureItem(id: "timeOffApprovals", title: "Time Off Approvals", systemImage: "checkmark.circle.fill", description: "Approve or deny time off requests"),
        FeatureItem(id: "flagUser", title: "Flag User", systemImage: "flag.fill", description: "Flag a user in your organization"),
        FeatureItem(id: "unflagUser", title: "Unflag User", systemImage: "flag.slash.fill", description: "Unflag a previously flagged user"),
        FeatureItem(id: "managerMileage", title: "Manager Mileage", systemImage: "car.2.fill", description: "View mileage reports for all employees"),
        FeatureItem(id: "stats", title: "Statistics", systemImage: "chart.bar.fill", description: "View business analytics and statistics"),
        FeatureItem(id: "galleryCreator", title: "Gallery Creator", systemImage: "photo.on.rectangle.angled", description: "Create galleries in Captura and Google Sheets"),
        FeatureItem(id: "jobBoxTracker", title: "Job Box Tracker", systemImage: "cube.box.fill", description: "Track and manage job box status")
    ]
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        List {
            // Employee Features Section (re-orderable)
            Section(header: Text("Employee Features")) {
                ForEach(viewModel.employeeFeatures) { feature in
                    if localEditMode == .active {
                        // Simple row in edit mode
                        HStack {
                            Image(systemName: feature.systemImage)
                                .foregroundColor(.white)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(featureColorFor(feature.id)))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(feature.title)
                                    .font(.headline)
                                Text(feature.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.leading, 8)
                            
                            Spacer()
                            
                            Image(systemName: "line.3.horizontal")
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 4)
                    } else {
                        // Use Button for navigation
                        Button(action: {
                            selectedFeatureID = feature.id
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: feature.systemImage)
                                    .foregroundColor(.white)
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(featureColorFor(feature.id)))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feature.title)
                                        .font(.headline)
                                    Text(feature.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.leading, 8)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .contentShape(Rectangle())
                    }
                }
                .onMove(perform: localEditMode == .active ? viewModel.moveEmployeeFeatures : nil)
            }
            
            // Manager Features Section (fixed order) if user is a manager or admin
            if userRole == "manager" || userRole == "admin" {
                Section(header: Text("Management Features")) {
                    ForEach(managerFeatures) { feature in
                        Button(action: {
                            selectedFeatureID = feature.id
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: feature.systemImage)
                                    .foregroundColor(.white)
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(featureColorFor(feature.id)))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feature.title)
                                        .font(.headline)
                                    Text(feature.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.leading, 8)
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                                    .font(.caption)
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .navigationTitle("All Features")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if localEditMode == .active {
                    Button("Done") {
                        withAnimation { 
                            localEditMode = .inactive 
                        }
                        viewModel.saveEmployeeFeatureOrder()
                    }
                } else {
                    Button("Edit") {
                        withAnimation { 
                            localEditMode = .active 
                        }
                    }
                }
            }
        }
        .environment(\.editMode, $localEditMode)
    }
    
    private func featureColorFor(_ id: String) -> Color {
        switch id {
        case "timeTracking": return .cyan
        case "photoshootNotes": return .purple
        case "dailyJobReport": return .blue
        case "customDailyReports": return .mint
        case "myDailyJobReports": return .green
        case "mileageReports": return .orange
        case "schedule": return .red
        case "locationPhotos": return .pink
        case "sportsShoot": return .indigo
        case "yearbookChecklists": return .purple
        case "classGroups": return .brown
        case "chat": return .blue
        case "scan": return .orange
        case "timeOffRequests": return .teal
        case "flagUser": return .red
        case "unflagUser": return .green
        case "managerMileage": return .blue
        case "stats": return .indigo
        case "galleryCreator": return .green
        case "jobBoxTracker": return .teal
        default: return .gray
        }
    }
}