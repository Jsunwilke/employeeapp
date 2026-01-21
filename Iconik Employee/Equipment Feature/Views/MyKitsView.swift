//
//  MyKitsView.swift
//  Iconik Employee
//
//  Equipment Management Feature - My Kits View (Default View)
//

import SwiftUI

struct MyKitsView: View {
    @StateObject private var equipmentService = EquipmentService.shared
    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""

    @State private var userKitAssignments: [UserKitAssignment] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedKitAssignment: UserKitAssignment?
    @State private var showKitDetail = false

    var body: some View {
        Group {
            if isLoading {
                loadingView
            } else if userKitAssignments.isEmpty {
                emptyStateView
            } else {
                contentView
            }
        }
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .navigationDestination(isPresented: $showKitDetail) {
            if let kitAssignment = selectedKitAssignment {
                KitDetailView(kitAssignment: kitAssignment)
            }
        }
    }

    // MARK: - Views

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading your equipment...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "shippingbox")
                .font(.system(size: 60))
                .foregroundColor(.gray)

            Text("No Equipment Assigned")
                .font(.title2)
                .fontWeight(.semibold)

            Text("You don't have any equipment checked out.\nBrowse available equipment or contact your manager.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                // Switch to All Equipment tab
                NotificationCenter.default.post(
                    name: Notification.Name("SwitchToAllEquipment"),
                    object: nil
                )
            } label: {
                Text("Browse Equipment")
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contentView: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                // Kits section
                let kits = userKitAssignments.filter { $0.kitTemplate != nil }
                if !kits.isEmpty {
                    Section {
                        ForEach(kits) { kitAssignment in
                            KitCard(kitAssignment: kitAssignment)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedKitAssignment = kitAssignment
                                    showKitDetail = true
                                }
                        }
                    } header: {
                        sectionHeader("My Kits", count: kits.count)
                    }
                }

                // Other Equipment section (items not in any kit)
                let otherEquipment = userKitAssignments.filter { $0.kitTemplate == nil }
                if !otherEquipment.isEmpty {
                    Section {
                        ForEach(otherEquipment) { assignment in
                            // Show individual items
                            ForEach(assignment.items) { item in
                                EquipmentCard(item: item)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        // Navigate to equipment detail
                                    }
                            }
                        }
                    } header: {
                        let itemCount = otherEquipment.reduce(0) { $0 + $1.items.count }
                        sectionHeader("Other Equipment", count: itemCount)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)

            Text("(\(count))")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.top, 8)
    }

    // MARK: - Data Loading

    private func loadData() async {
        print("🔧 MyKitsView: loadData called")
        print("🔧 MyKitsView: storedUserOrganizationID = '\(storedUserOrganizationID)'")
        print("🔧 MyKitsView: userId = '\(UserManager.shared.getCurrentUserIDUnified() ?? "nil")'")

        guard let userId = UserManager.shared.getCurrentUserIDUnified() else {
            print("🔧 MyKitsView: EARLY RETURN - missing userId")
            errorMessage = "Unable to get your user ID. Please sign out and sign back in."
            return
        }

        guard !storedUserOrganizationID.isEmpty else {
            print("🔧 MyKitsView: EARLY RETURN - org ID is empty")
            errorMessage = "Organization not configured. Please contact your administrator."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let userIdUUID = UUID(uuidString: userId.lowercased()) ?? UUID()

            print("🔧 MyKitsView: Fetching data for userId=\(userIdUUID), orgId=\(storedUserOrganizationID)")

            userKitAssignments = try await equipmentService.loadMyKitsData(
                userId: userIdUUID,
                organizationId: storedUserOrganizationID
            )

            print("🔧 MyKitsView: Loaded \(userKitAssignments.count) kit assignments")
        } catch {
            print("🔧 MyKitsView: Error loading data - \(error)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - Preview

struct MyKitsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            MyKitsView()
        }
    }
}
