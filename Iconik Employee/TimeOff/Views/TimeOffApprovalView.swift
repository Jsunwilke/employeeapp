import SwiftUI

struct TimeOffApprovalView: View {
    @StateObject private var timeOffService = TimeOffService.shared
    @State private var selectedTab = 0
    @State private var showingDenialDialog = false
    @State private var requestToDeny: TimeOffRequest? = nil
    @State private var denialReason = ""
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    private var pendingRequests: [TimeOffRequest] {
        return timeOffService.pendingRequests.sorted { $0.createdAt < $1.createdAt }
    }
    
    private var historyRequests: [TimeOffRequest] {
        return timeOffService.timeOffRequests
            .filter { $0.status != .pending }
            .sorted { $0.updatedAt > $1.updatedAt }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            tabSelector
            
            // Content based on selected tab
            TabView(selection: $selectedTab) {
                // Pending requests tab
                pendingRequestsView
                    .tag(0)
                
                // History tab
                historyRequestsView
                    .tag(1)
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        }
        .navigationTitle("Time Off Approvals")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            timeOffService.startListeningToRequests()
        }
        .onDisappear {
            timeOffService.stopListening()
        }
        .alert("Deny Request", isPresented: $showingDenialDialog) {
            TextField("Reason for denial", text: $denialReason)
            Button("Deny Request", role: .destructive) {
                if let request = requestToDeny {
                    denyRequest(request)
                }
            }
            Button("Cancel", role: .cancel) {
                denialReason = ""
                requestToDeny = nil
            }
        } message: {
            Text("Please provide a reason for denying this time off request.")
        }
        .alert("Time Off Management", isPresented: $showingAlert) {
            Button("OK") {}
        } message: {
            Text(alertMessage)
        }
    }
    
    // MARK: - Tab Selector
    
    private var tabSelector: some View {
        HStack(spacing: 0) {
            TabButton(
                title: "Pending",
                badge: pendingRequests.count,
                isSelected: selectedTab == 0
            ) {
                selectedTab = 0
            }
            
            TabButton(
                title: "History",
                badge: nil,
                isSelected: selectedTab == 1
            ) {
                selectedTab = 1
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
    
    // MARK: - Pending Requests View
    
    private var pendingRequestsView: some View {
        Group {
            if timeOffService.isLoading {
                loadingView
            } else if pendingRequests.isEmpty {
                emptyPendingView
            } else {
                List {
                    ForEach(pendingRequests) { request in
                        TimeOffRequestCard(
                            request: request,
                            showActions: false,
                            onApprove: {
                                approveRequest(request)
                            },
                            onDeny: {
                                requestToDeny = request
                                showingDenialDialog = true
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
        }
    }
    
    // MARK: - History View
    
    private var historyRequestsView: some View {
        Group {
            if timeOffService.isLoading {
                loadingView
            } else if historyRequests.isEmpty {
                emptyHistoryView
            } else {
                List {
                    ForEach(historyRequests) { request in
                        TimeOffRequestCard(request: request, showActions: false)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowSeparator(.hidden)
                    }
                }
                .listStyle(PlainListStyle())
                .refreshable {
                    timeOffService.refreshRequests()
                }
            }
        }
    }
    
    // MARK: - Empty States
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading requests...")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyPendingView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            VStack(spacing: 8) {
                Text("All Caught Up!")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("There are no pending time off requests to review.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyHistoryView: some View {
        VStack(spacing: 24) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            VStack(spacing: 8) {
                Text("No History")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("No time off requests have been processed yet.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Helper Methods
    
    private func approveRequest(_ request: TimeOffRequest) {
        timeOffService.approveTimeOffRequest(requestId: request.id) { success, error in
            DispatchQueue.main.async {
                if success {
                    alertMessage = "Request approved successfully"
                } else {
                    alertMessage = error ?? "Failed to approve request"
                }
                showingAlert = true
            }
        }
    }
    
    private func denyRequest(_ request: TimeOffRequest) {
        guard !denialReason.trimmingCharacters(in: .whitespaces).isEmpty else {
            alertMessage = "Please provide a reason for denial"
            showingAlert = true
            return
        }
        
        timeOffService.denyTimeOffRequest(requestId: request.id, denialReason: denialReason) { success, error in
            DispatchQueue.main.async {
                if success {
                    alertMessage = "Request denied successfully"
                } else {
                    alertMessage = error ?? "Failed to deny request"
                }
                showingAlert = true
                
                // Reset dialog state
                denialReason = ""
                requestToDeny = nil
            }
        }
    }
}

// MARK: - Tab Button

struct TabButton: View {
    let title: String
    let badge: Int?
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                
                if let badge = badge, badge > 0 {
                    Text("\(badge)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
            }
            .foregroundColor(isSelected ? .blue : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}