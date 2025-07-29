import SwiftUI

struct TimeOffDetailView: View {
    let timeOffEntry: TimeOffCalendarEntry
    let onCancel: (() -> Void)?
    let onDelete: (() -> Void)?
    
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var timeOffService = TimeOffService.shared
    
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingConfirmation = false
    @State private var confirmationAction: (() -> Void)?
    @State private var confirmationTitle = ""
    @State private var confirmationMessage = ""
    @State private var confirmationButtonText = ""
    
    init(
        timeOffEntry: TimeOffCalendarEntry,
        onCancel: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        print("🟡 TimeOffDetailView initialized for entry: \(timeOffEntry.id)")
        self.timeOffEntry = timeOffEntry
        self.onCancel = onCancel
        self.onDelete = onDelete
    }
    
    private var canModifyRequest: Bool {
        let currentUserId = UserDefaults.standard.string(forKey: "userID") ?? ""
        let userRole = UserDefaults.standard.string(forKey: "userRole") ?? ""
        let isOwnRequest = timeOffEntry.photographerId == currentUserId
        let isAdmin = ["admin", "manager", "owner"].contains(userRole)
        return isOwnRequest || isAdmin
    }
    
    private var statusColor: Color {
        switch timeOffEntry.status {
        case .pending:
            return .orange
        case .underReview:
            return .blue
        case .approved:
            return .green
        case .denied:
            return .red
        case .cancelled:
            return .gray
        }
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header with status
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: timeOffEntry.reason.systemImageName)
                                .font(.title)
                                .foregroundColor(statusColor)
                            
                            Text("Time Off Request")
                                .font(.title2)
                                .fontWeight(.semibold)
                        }
                        
                        // Status badge
                        HStack(spacing: 8) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 12, height: 12)
                            Text(timeOffEntry.status.rawValue.capitalized)
                                .font(.headline)
                                .fontWeight(.medium)
                                .foregroundColor(statusColor)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(statusColor.opacity(0.1))
                        .cornerRadius(20)
                    }
                    .padding(.top)
                    
                    // Details section
                    VStack(spacing: 16) {
                        DetailRow(
                            icon: "calendar",
                            title: "Date",
                            value: formatDate(timeOffEntry.date)
                        )
                        
                        if timeOffEntry.isPartialDay {
                            DetailRow(
                                icon: "clock",
                                title: "Time Range",
                                value: "\(formatTime(timeOffEntry.startTime)) - \(formatTime(timeOffEntry.endTime))"
                            )
                        } else {
                            DetailRow(
                                icon: "sun.max",
                                title: "Duration",
                                value: "Full Day"
                            )
                        }
                        
                        DetailRow(
                            icon: "person",
                            title: "Photographer",
                            value: timeOffEntry.photographerName
                        )
                        
                        DetailRow(
                            icon: "tag",
                            title: "Reason",
                            value: timeOffEntry.reason.displayName
                        )
                        
                        if !timeOffEntry.notes.isEmpty {
                            DetailRow(
                                icon: "text.bubble",
                                title: "Notes",
                                value: timeOffEntry.notes
                            )
                        }
                        
                        // Type indicator
                        HStack {
                            Image(systemName: timeOffEntry.isPartialDay ? "clock.badge.checkmark" : "calendar.badge.clock")
                                .foregroundColor(.secondary)
                            Text(timeOffEntry.isPartialDay ? "Partial Day Request" : "Full Day Request")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.top, 8)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // Action buttons
                    if canModifyRequest {
                        VStack(spacing: 12) {
                            if timeOffEntry.status == .pending {
                                Button(action: {
                                    showCancelConfirmation()
                                }) {
                                    HStack {
                                        Image(systemName: "xmark.circle")
                                        Text("Cancel Request")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.orange)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                }
                            } else if timeOffEntry.status == .approved {
                                Button(action: {
                                    showDeleteConfirmation()
                                }) {
                                    HStack {
                                        Image(systemName: "trash")
                                        Text("Delete Time Off")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.red)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
            .onAppear {
                print("🟡 TimeOffDetailView appeared for entry: \(timeOffEntry.id)")
            }
        }
        .alert(isPresented: $showingAlert) {
            Alert(
                title: Text("Time Off Request"),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .alert(isPresented: $showingConfirmation) {
            Alert(
                title: Text(confirmationTitle),
                message: Text(confirmationMessage),
                primaryButton: .destructive(Text(confirmationButtonText)) {
                    confirmationAction?()
                },
                secondaryButton: .cancel()
            )
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }
    
    private func formatTime(_ timeString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        
        if let time = formatter.date(from: timeString) {
            formatter.timeStyle = .short
            return formatter.string(from: time)
        }
        
        return timeString
    }
    
    private func showCancelConfirmation() {
        confirmationTitle = "Cancel Time Off Request"
        confirmationMessage = "Are you sure you want to cancel this time off request? This action cannot be undone."
        confirmationButtonText = "Cancel Request"
        confirmationAction = cancelRequest
        showingConfirmation = true
    }
    
    private func showDeleteConfirmation() {
        confirmationTitle = "Delete Time Off"
        confirmationMessage = "Are you sure you want to delete this approved time off? This action cannot be undone."
        confirmationButtonText = "Delete"
        confirmationAction = deleteRequest
        showingConfirmation = true
    }
    
    private func cancelRequest() {
        timeOffService.cancelTimeOffRequest(requestId: timeOffEntry.requestId) { success, error in
            DispatchQueue.main.async {
                if success {
                    alertMessage = "Time off request cancelled successfully"
                    onCancel?()
                    presentationMode.wrappedValue.dismiss()
                } else {
                    alertMessage = error ?? "Failed to cancel request"
                    showingAlert = true
                }
            }
        }
    }
    
    private func deleteRequest() {
        timeOffService.cancelTimeOffRequest(requestId: timeOffEntry.requestId) { success, error in
            DispatchQueue.main.async {
                if success {
                    alertMessage = "Time off deleted successfully"
                    onDelete?()
                    presentationMode.wrappedValue.dismiss()
                } else {
                    alertMessage = error ?? "Failed to delete time off"
                    showingAlert = true
                }
            }
        }
    }
}

// MARK: - Detail Row Component

struct DetailRow: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.body)
            }
            
            Spacer()
        }
    }
}

// MARK: - Preview

struct TimeOffDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleEntry = TimeOffCalendarEntry(
            id: "sample",
            requestId: "request-123",
            title: "Time Off: Vacation",
            date: Date(),
            startTime: "09:00",
            endTime: "17:00",
            photographerId: "user-123",
            photographerName: "John Doe",
            status: .pending,
            isPartialDay: false,
            reason: .vacation,
            notes: "Family vacation to the beach"
        )
        
        TimeOffDetailView(timeOffEntry: sampleEntry)
    }
}