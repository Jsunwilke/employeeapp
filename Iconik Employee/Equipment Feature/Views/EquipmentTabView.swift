//
//  EquipmentTabView.swift
//  Iconik Employee
//
//  Equipment Management Feature - Main Tab Container View
//

import SwiftUI

struct EquipmentTabView: View {
    @StateObject private var equipmentService = EquipmentService.shared
    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""
    @AppStorage("userRole") private var storedUserRole: String = ""

    @State private var selectedTab: EquipmentViewTab = .myKits
    @State private var showQRScanner = false
    @State private var showAdminKits = false
    @State private var scannedEquipmentId: UUID?
    @State private var showScannedEquipment = false

    enum EquipmentViewTab: String, CaseIterable {
        case myKits = "My Kit(s)"
        case allEquipment = "All Equipment"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    // Segmented control
                    Picker("View", selection: $selectedTab) {
                        ForEach(EquipmentViewTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    // Content based on selected tab
                    switch selectedTab {
                    case .myKits:
                        MyKitsView()
                    case .allEquipment:
                        AllEquipmentView()
                    }
                }

                // QR Scan FAB
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            showQRScanner = true
                        } label: {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 56, height: 56)
                                .background(Color.blue)
                                .clipShape(Circle())
                                .shadow(color: Color.blue.opacity(0.4), radius: 8, x: 0, y: 4)
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Equipment")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if canManageKits {
                        Button {
                            showAdminKits = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
            .sheet(isPresented: $showQRScanner) {
                QRScannerView { code in
                    handleScannedCode(code)
                }
            }
            .sheet(isPresented: $showAdminKits) {
                NavigationStack {
                    AdminKitTemplatesView()
                }
            }
            .navigationDestination(isPresented: $showScannedEquipment) {
                if let equipmentId = scannedEquipmentId {
                    EquipmentDetailView(equipmentId: equipmentId)
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var canManageKits: Bool {
        // Phase 7 RBAC — equipment edit covers kit template management
        Permissions.has("equipment", level: .edit)
    }

    // MARK: - Methods

    private func handleScannedCode(_ code: String) {
        showQRScanner = false

        // QR code format: "EQ-{UUID}"
        let equipmentIdString = code.hasPrefix("EQ-") ? String(code.dropFirst(3)) : code

        if let uuid = UUID(uuidString: equipmentIdString) {
            scannedEquipmentId = uuid
            showScannedEquipment = true
        }
    }
}

// MARK: - Preview

struct EquipmentTabView_Previews: PreviewProvider {
    static var previews: some View {
        EquipmentTabView()
    }
}
