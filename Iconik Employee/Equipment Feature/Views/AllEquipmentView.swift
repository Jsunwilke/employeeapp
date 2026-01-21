//
//  AllEquipmentView.swift
//  Iconik Employee
//
//  Equipment Management Feature - Browse All Equipment View
//

import SwiftUI

struct AllEquipmentView: View {
    @StateObject private var equipmentService = EquipmentService.shared
    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""
    @AppStorage("userRole") private var storedUserRole: String = ""

    @State private var searchText = ""
    @State private var selectedCategory: EquipmentCategory?
    @State private var selectedStatus: EquipmentStatus?
    @State private var showCreateEquipment = false
    @State private var selectedEquipmentId: UUID?
    @State private var showEquipmentDetail = false
    @State private var errorMessage: String?

    // Build equipment to kit color mapping
    private var equipmentKitColors: [UUID: String] {
        var mapping: [UUID: String] = [:]
        for kit in equipmentService.kitTemplates {
            if let color = kit.color {
                for equipmentId in kit.equipmentIds {
                    mapping[equipmentId] = color
                }
            }
        }
        return mapping
    }

    private var filteredEquipment: [EquipmentItem] {
        var items = equipmentService.equipment

        // Filter by search
        if !searchText.isEmpty {
            items = items.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                ($0.serial_number?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                ($0.description?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        // Filter by category
        if let category = selectedCategory {
            items = items.filter { $0.category_id == category.id }
        }

        // Filter by status
        if let status = selectedStatus {
            items = items.filter { $0.statusEnum == status }
        }

        return items
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            searchBar

            // Filter chips
            filterChips

            // Content
            if equipmentService.isLoading {
                loadingView
            } else if filteredEquipment.isEmpty {
                emptyView
            } else {
                equipmentList
            }
        }
        .background(Color(.systemGroupedBackground))
        .task {
            await loadData()
        }
        .refreshable {
            await loadData()
        }
        .sheet(isPresented: $showCreateEquipment) {
            NavigationStack {
                CreateEquipmentView()
            }
        }
        .navigationDestination(isPresented: $showEquipmentDetail) {
            if let equipmentId = selectedEquipmentId {
                EquipmentDetailView(equipmentId: equipmentId)
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if canCreateEquipment {
                    Button {
                        showCreateEquipment = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Views

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Search equipment...", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
        }
        .padding(10)
        .background(Color(.systemBackground))
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Category filters
                ForEach(equipmentService.categories) { category in
                    categoryFilterChip(for: category)
                }

                Divider()
                    .frame(height: 20)

                // Status filters
                ForEach(EquipmentStatus.allCases, id: \.self) { status in
                    statusFilterChip(for: status)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }

    private func categoryFilterChip(for category: EquipmentCategory) -> some View {
        EquipmentFilterChip(
            title: category.name,
            isSelected: selectedCategory?.id == category.id,
            color: nil
        ) {
            if selectedCategory?.id == category.id {
                selectedCategory = nil
            } else {
                selectedCategory = category
            }
        }
    }

    private func statusFilterChip(for status: EquipmentStatus) -> some View {
        EquipmentFilterChip(
            title: status.label,
            isSelected: selectedStatus == status,
            color: status.color
        ) {
            if selectedStatus == status {
                selectedStatus = nil
            } else {
                selectedStatus = status
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading equipment...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.gray)

            Text("No Equipment Found")
                .font(.headline)

            if !searchText.isEmpty || selectedCategory != nil || selectedStatus != nil {
                Text("Try adjusting your search or filters")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Button("Clear Filters") {
                    searchText = ""
                    selectedCategory = nil
                    selectedStatus = nil
                }
                .foregroundColor(.blue)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var equipmentList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredEquipment) { item in
                    EquipmentCard(
                        item: item,
                        kitColor: equipmentKitColors[item.id],
                        showAssignee: true
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedEquipmentId = item.id
                        showEquipmentDetail = true
                    }
                }
            }
            .padding()
        }
    }

    // MARK: - Computed Properties

    private var canCreateEquipment: Bool {
        guard !storedUserRole.isEmpty else { return false }
        return ["admin", "manager"].contains(storedUserRole.lowercased())
    }

    // MARK: - Data Loading

    private func loadData() async {
        print("🔧 AllEquipmentView: loadData called")
        print("🔧 AllEquipmentView: storedUserOrganizationID = '\(storedUserOrganizationID)'")

        guard !storedUserOrganizationID.isEmpty else {
            print("🔧 AllEquipmentView: EARLY RETURN - org ID is empty")
            errorMessage = "Organization not configured. Please contact your administrator."
            return
        }

        errorMessage = nil

        do {
            print("🔧 AllEquipmentView: Fetching data for orgId=\(storedUserOrganizationID)")

            try await equipmentService.loadAllEquipmentData(organizationId: storedUserOrganizationID)

            print("🔧 AllEquipmentView: Loaded \(equipmentService.equipment.count) equipment items")
        } catch {
            print("🔧 AllEquipmentView: Error loading equipment - \(error)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Filter Chip Component

private struct EquipmentFilterChip: View {
    let title: String
    let isSelected: Bool
    var color: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let color = color {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }
                Text(title)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(isSelected ? Color.blue.opacity(0.2) : Color(.systemBackground))
            .foregroundColor(isSelected ? .blue : .primary)
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
    }
}

// MARK: - Create Equipment View (Placeholder)

struct CreateEquipmentView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Create Equipment")
                .font(.title)

            Text("Equipment creation form will be implemented here")
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding()
        .navigationTitle("New Equipment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}

// MARK: - Preview

struct AllEquipmentView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            AllEquipmentView()
        }
    }
}
