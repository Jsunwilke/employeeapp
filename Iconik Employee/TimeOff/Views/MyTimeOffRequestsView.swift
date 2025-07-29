import SwiftUI

struct MyTimeOffRequestsView: View {
    @StateObject private var timeOffService = TimeOffService.shared
    @State private var selectedStatus: TimeOffStatus? = nil
    @State private var showingNewRequest = false
    @State private var editingRequest: TimeOffRequest? = nil
    @State private var showingCancelAlert = false
    @State private var requestToCancel: TimeOffRequest? = nil
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    private var filteredRequests: [TimeOffRequest] {
        if let status = selectedStatus {
            return timeOffService.getMyRequests(status: status)
        }
        return timeOffService.myRequests
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with filter
            headerSection
            
            // Content
            if timeOffService.isLoading {
                loadingView
            } else if filteredRequests.isEmpty {
                emptyStateView
            } else {
                requestsList
            }
        }
        .navigationTitle("My Time Off")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            timeOffService.startListeningToRequests()
        }
        .onDisappear {
            timeOffService.stopListening()
        }
        .sheet(isPresented: $showingNewRequest) {
            TimeOffRequestView(timeOffService: timeOffService)
        }
        .sheet(item: $editingRequest) { request in
            TimeOffRequestView(timeOffService: timeOffService, editingRequest: request)
        }
        .alert("Cancel Request", isPresented: $showingCancelAlert) {
            Button("Cancel Request", role: .destructive) {
                if let request = requestToCancel {
                    cancelRequest(request)
                }
            }
            Button("Keep Request", role: .cancel) {}
        } message: {
            Text("Are you sure you want to cancel this time off request? This action cannot be undone.")
        }
        .alert("Time Off", isPresented: $showingAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            // New Request Button
            Button(action: {
                showingNewRequest = true
            }) {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                    Text("New Time Off Request")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.blue)
                .cornerRadius(10)
            }
            .padding(.horizontal)
            
            // Status Filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    FilterButton(
                        title: "All",
                        isSelected: selectedStatus == nil,
                        count: timeOffService.myRequests.count
                    ) {
                        selectedStatus = nil
                    }
                    
                    ForEach(TimeOffStatus.filterOptions, id: \.self) { status in
                        FilterButton(
                            title: status.displayName,
                            isSelected: selectedStatus == status,
                            count: timeOffService.getMyRequests(status: status).count,
                            color: Color(status.colorName)
                        ) {
                            selectedStatus = status
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
        .background(Color(.systemGray6))
    }
    
    // MARK: - Content Views
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading your requests...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            VStack(spacing: 8) {
                Text(selectedStatus == nil ? "No Time Off Requests" : "No \(selectedStatus?.displayName ?? "") Requests")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(selectedStatus == nil ? 
                     "You haven't submitted any time off requests yet." :
                     "You don't have any \(selectedStatus?.displayName.lowercased() ?? "") requests.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            if selectedStatus == nil {
                Button(action: {
                    showingNewRequest = true
                }) {
                    Text("Create First Request")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var requestsList: some View {
        List {
            ForEach(filteredRequests) { request in
                TimeOffRequestCard(
                    request: request,
                    showActions: true,
                    onEdit: {
                        editingRequest = request
                    },
                    onCancel: {
                        requestToCancel = request
                        showingCancelAlert = true
                    }
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(PlainListStyle())
        .refreshable {
            timeOffService.refreshRequests()
        }
    }
    
    // MARK: - Helper Methods
    
    private func cancelRequest(_ request: TimeOffRequest) {
        timeOffService.cancelTimeOffRequest(requestId: request.id) { success, error in
            DispatchQueue.main.async {
                if success {
                    alertMessage = "Request cancelled successfully"
                } else {
                    alertMessage = error ?? "Failed to cancel request"
                }
                showingAlert = true
            }
        }
    }
}

// MARK: - Filter Button

struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let count: Int
    let color: Color
    let action: () -> Void
    
    init(title: String, isSelected: Bool, count: Int, color: Color = .blue, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.count = count
        self.color = color
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                if count > 0 {
                    Text("\(count)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(isSelected ? color : .white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isSelected ? .white : color)
                        .clipShape(Capsule())
                }
            }
            .foregroundColor(isSelected ? .white : color)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? color : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(color, lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Time Off Request Card

struct TimeOffRequestCard: View {
    let request: TimeOffRequest
    let showActions: Bool
    let onEdit: (() -> Void)?
    let onCancel: (() -> Void)?
    let onApprove: (() -> Void)?
    let onDeny: (() -> Void)?
    let onReview: (() -> Void)?
    
    init(
        request: TimeOffRequest,
        showActions: Bool = false,
        onEdit: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onApprove: (() -> Void)? = nil,
        onDeny: (() -> Void)? = nil,
        onReview: (() -> Void)? = nil
    ) {
        self.request = request
        self.showActions = showActions
        self.onEdit = onEdit
        self.onCancel = onCancel
        self.onApprove = onApprove
        self.onDeny = onDeny
        self.onReview = onReview
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Header with status
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(request.formattedDateRange)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(request.formattedDuration)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 6) {
                    Image(systemName: request.status.systemImageName)
                        .font(.caption)
                    Text(request.status.displayName)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(request.status.colorName))
                .clipShape(Capsule())
            }
            
            // Reason and notes
            HStack {
                Image(systemName: request.reason.systemImageName)
                    .foregroundColor(Color(request.reason.colorName))
                Text(request.reason.displayName)
                    .fontWeight(.medium)
                Spacer()
            }
            
            if !request.notes.isEmpty {
                HStack {
                    Text("Notes:")
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    Text(request.notes)
                        .foregroundColor(.primary)
                    Spacer()
                }
                .font(.caption)
            }
            
            // Approval/Denial details
            if request.status == .approved, let approverName = request.approverName, let approvedAt = request.approvedAt {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Approved by \(approverName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatDate(approvedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if request.status == .underReview, let reviewerName = request.reviewerName, let reviewedAt = request.reviewedAt {
                HStack {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .foregroundColor(.blue)
                    Text("In review by \(reviewerName)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatDate(reviewedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if request.status == .denied, let denierName = request.denierName, let deniedAt = request.deniedAt {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text("Denied by \(denierName)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(formatDate(deniedAt))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if let denialReason = request.denialReason {
                        Text("Reason: \(denialReason)")
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.leading, 20)
                    }
                }
            }
            
            // Actions
            if showActions && (request.canBeEdited || request.canBeCancelled) {
                HStack(spacing: 12) {
                    if request.canBeEdited, let onEdit = onEdit {
                        Button("Edit") {
                            onEdit()
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    
                    if request.canBeCancelled, let onCancel = onCancel {
                        Button("Cancel") {
                            onCancel()
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.red)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    
                    Spacer()
                }
            }
            
            // Manager actions
            if let onApprove = onApprove, let onDeny = onDeny, (request.status == .pending || request.status == .underReview) {
                HStack(spacing: 12) {
                    if request.status == .pending, let onReview = onReview {
                        Button("Put in Review") {
                            onReview()
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .clipShape(Capsule())
                    }
                    
                    Button("Approve") {
                        onApprove()
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.green)
                    .clipShape(Capsule())
                    
                    Button("Deny") {
                        onDeny()
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.red)
                    .clipShape(Capsule())
                    
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}