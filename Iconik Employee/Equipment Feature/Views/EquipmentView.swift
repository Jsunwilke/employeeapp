//
//  EquipmentView.swift
//  Iconik Employee
//
//  Equipment in the Ambient design language — the one screen (AMB.3).
//
//  Replaces EquipmentTabView + MyKitsView + AllEquipmentView, all three deleted in
//  the same commit. Ported from the AMB.2 lab mockup the operator approved on
//  iPhone and iPad (DesignLab/Mockups/EquipmentMockup.swift).
//
//  THE ONE STRUCTURAL CHANGE: THE TAB BAR IS GONE.
//      Equipment shipped as two tabs — My Kit(s), the default, and All Equipment.
//      Those are not two places, they are two questions, and only one of them gets
//      asked most days: what am I holding, and is any of it late. Browsing the
//      org's whole inventory is the rarer errand.
//
//      So the screen leads with YOUR GEAR and carries the inventory behind one row.
//      Nothing is lost — both destinations are one tap from the top, the same as a
//      segmented control — and the common case stops costing a tap. Typing anywhere
//      jumps straight into the inventory, so you never have to find the row first.
//
//      What that buys, and it is the real point: a standing line at the top saying
//      how much you have out, how much is due back, and how much is LATE. Today the
//      only way to find out something is overdue is to read every kit card in turn.
//
//  THE QR BUTTON STAYS A FAB.
//      It was tempting to fold it into the search field as a glyph. It is the
//      fastest route to any item in the building — scan the tape on the case — and
//      it gets pressed with a case in the other hand. A 56pt target beats a tidy one.
//
//  Capability inventory for this surface: AMB_BATCH1_PARITY.md.
//

import SwiftUI

/// A pushable reference to an equipment item, for a screen whose only push target
/// IS an item — the kit detail. The detail screen loads its own item by id, so an id
/// is the whole of what a row tap needs to carry.
struct EquipmentReference: Identifiable {
    let id: UUID
}

/// Everywhere this screen can push to, as ONE value.
///
/// It would read more naturally as two `@State` optionals with an `.ambientPush`
/// each, and that is how the lab mockup was written. But `ambientPush` is built on
/// `NavigationLink(isActive:)` — the only push API that works both inside the
/// shell's `NavigationView` and inside a real `NavigationStack` — and stacking two
/// of those on one view means two simultaneously-live links competing for one
/// stack. Equipment is the first Ambient surface to run inside an actual
/// NavigationStack, so it is the first place that combination would be exercised,
/// and a push that silently does nothing is precisely the defect AMB.1 shipped.
/// One link cannot have that problem.
enum EquipmentDestination: Identifiable {
    case kit(UserKitAssignment)
    case item(UUID)

    var id: String {
        switch self {
        case .kit(let kit): return "kit-\(kit.id.uuidString)"
        case .item(let id): return "item-\(id.uuidString)"
        }
    }
}

struct EquipmentView: View {
    @StateObject private var equipmentService = EquipmentService.shared
    @AppStorage("userOrganizationID") private var storedUserOrganizationID: String = ""

    @State private var myGear: [UserKitAssignment] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var query = ""
    @State private var browsing = false
    @State private var selectedCategory: EquipmentCategory?
    @State private var selectedStatus: EquipmentStatus?

    @State private var destination: EquipmentDestination?

    @State private var showQRScanner = false
    @State private var showAdminKits = false
    @State private var showCreateEquipment = false

    private var feature: Color { FeatureTheme.color(for: "equipment") }

    /// Typing anywhere, or picking any filter, is a request for the inventory.
    private var showingInventory: Bool {
        browsing || !query.isEmpty || selectedCategory != nil || selectedStatus != nil
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                AmbientBackdrop(tint: feature)

                VStack(spacing: 10) {
                    searchField
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    if showingInventory {
                        filterChips
                        inventory
                    } else {
                        myGearList
                    }
                }

                qrButton
            }
            // Room for the app's floating bar. Applied HERE, inside this screen's
            // own NavigationStack, because the shell cannot reach into a self-nav
            // feature — the QR button sat directly under the capsule until it was.
            .tabBarClearance()
            .navigationTitle("Equipment")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HomeToolbarButton()
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        // Creating equipment belongs with the inventory, which is
                        // where it lived when the inventory was its own tab.
                        if showingInventory && canEditEquipment {
                            Button {
                                showCreateEquipment = true
                            } label: {
                                Image(systemName: "plus")
                            }
                        }

                        if canEditEquipment {
                            Button {
                                showAdminKits = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                        }
                    }
                }
            }
            .task {
                await load()
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
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
            .sheet(isPresented: $showCreateEquipment) {
                NavigationStack {
                    CreateEquipmentView()
                }
            }
            .ambientPush(item: $destination) { destination in
                switch destination {
                case .kit(let kit):
                    EquipmentKitDetailView(kitAssignment: kit)
                case .item(let equipmentId):
                    EquipmentDetailView(equipmentId: equipmentId)
                }
            }
            .animation(AmbientMotion.gentle, value: showingInventory)
        }
    }

    // MARK: - Your gear

    @ViewBuilder
    private var myGearList: some View {
        if isLoading && myGear.isEmpty {
            loadingView
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AmbientDensity.compact.stackSpacing) {
                    if myGear.isEmpty {
                        AmbientEmptyState(
                            title: "No equipment assigned",
                            message: "You don't have any equipment checked out. Browse the inventory below, or contact your manager.",
                            systemImage: "shippingbox")
                    } else {
                        standingLine

                        if assignedKits.isEmpty && looseItems.isEmpty {
                            unmatchedGearNote
                        }

                        if !assignedKits.isEmpty {
                            AmbientSectionTitle("Your kits", trailing: "\(assignedKits.count)")
                            ForEach(assignedKits) { kit in
                                Button { destination = .kit(kit) } label: { EquipmentKitRow(kit: kit) }
                                    .buttonStyle(.plain)
                            }
                        }

                        if !looseItems.isEmpty {
                            AmbientSectionTitle("Also checked out to you",
                                                trailing: "\(looseItems.count)")
                                .padding(.top, assignedKits.isEmpty ? 0 : 10)
                            ForEach(looseItems, id: \.item.id) { entry in
                                // In the app this row's tap handler was an EMPTY
                                // COMMENT — it looked tappable and did nothing.
                                // Wired here; a bug fix AMB.3 ships, not a redesign.
                                Button {
                                    destination = .item(entry.item.id)
                                } label: {
                                    EquipmentRow(item: entry.item,
                                                 kitColorHex: nil,
                                                 assignee: assigneeForOwnItem(entry.assignment))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    browseRow.padding(.top, myGear.isEmpty ? 0 : 14)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 96)
            }
            .refreshable { await load() }
        }
    }

    /// The line that does not exist today. Three numbers, and the late one is the
    /// only one allowed to shout.
    private var standingLine: some View {
        HStack(spacing: 0) {
            standingStat("\(assignedItemCount)", "items out", tint: .primary)
            standingDivider
            standingStat("\(dueBackCount)", "due back", tint: .secondary)
            standingDivider
            standingStat("\(overdueCount)", "overdue",
                         tint: overdueCount > 0 ? .red : .secondary)
        }
        .ambientCard(density: .roomy,
                     state: overdueCount > 0 ? .highlighted : .normal,
                     border: overdueCount > 0
                        ? .strong(Color.red.opacity(0.45))
                        : .hairline(Color.primary.opacity(0.08)),
                     fillWidth: true)
    }

    /// Shown when you have assignments but not one of them resolved to an
    /// equipment record, so the standing line has numbers and there is nothing to
    /// list under it.
    ///
    /// The two halves of this screen come from different queries: the counts are
    /// assignments, the rows are equipment. `groupAssignmentsByKit` drops an
    /// assignment's item silently when it is not in the fetched inventory — which
    /// happens if the equipment row was deleted, or belongs to another org — so the
    /// count survives and the row does not. Without this, that state renders as
    /// three numbers above blank space with no explanation, which reads as a broken
    /// screen rather than as missing data. Same lesson as PUB.1's O5: a failed
    /// match must not be indistinguishable from having nothing.
    private var unmatchedGearNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Equipment records missing", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text("\(assignedItemCount) item\(assignedItemCount == 1 ? " is" : "s are") checked out to you, but none of them could be matched to an item in the inventory. They may have been removed. Pull down to refresh, or contact your administrator.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .ambientCard(density: .roomy,
                     border: .hairline(Color.orange.opacity(0.45)),
                     fillWidth: true)
    }

    private var standingDivider: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1, height: 30)
    }

    private func standingStat(_ value: String, _ label: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private var browseRow: some View {
        Button {
            withAnimation(AmbientMotion.gentle) { browsing = true }
            AmbientHaptics.impact(.light)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(feature)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Browse all equipment").font(.subheadline.weight(.semibold))
                    Text("\(equipmentService.equipment.count) items · \(equipmentService.categories.count) categories")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold)).foregroundStyle(.tertiary)
            }
            .ambientCard(density: .roomy, fillWidth: true)
        }
        .buttonStyle(.plain)
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Loading your equipment...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Inventory

    @ViewBuilder
    private var inventory: some View {
        // This view's own `isLoading`, not the service's — still, now for a plainer
        // reason than when it was written. The service's flag used to stick true
        // forever after a failed load (it rethrew before resetting it); that is
        // fixed with a `defer`. But this screen loads TWO things, the inventory and
        // your assignments, and only the first of them is what the service's flag
        // describes. One flag covering the whole load is the honest one.
        if isLoading && equipmentService.equipment.isEmpty {
            VStack(spacing: 16) {
                ProgressView()
                Text("Loading equipment...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredEquipment.isEmpty {
            ScrollView {
                VStack(spacing: 14) {
                    AmbientEmptyState(
                        title: "No equipment found",
                        message: "Try adjusting your search or filters.",
                        systemImage: "shippingbox")

                    // The app showed Clear Filters only when something was
                    // actually filtered. Same rule here.
                    if isFiltered {
                        Button { clearFilters() } label: {
                            Text("Clear filters")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 11)
                                .background(Capsule().fill(feature))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 96)
            }
            .refreshable { await load() }
        } else {
            ScrollView {
                LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
                    ForEach(filteredEquipment) { item in
                        Button {
                            destination = .item(item.id)
                        } label: {
                            EquipmentRow(item: item,
                                         kitColorHex: equipmentKitColors[item.id],
                                         assignee: assigneeForInventoryItem(item))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 96)
            }
            .refreshable { await load() }
        }
    }

    /// Categories AND statuses, in one scroller with a divider between them — the
    /// app's arrangement. The first cut of the mockup dropped the category half
    /// entirely, which the parity inventory caught.
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(equipmentService.categories) { category in
                    chip(category.name,
                         selected: selectedCategory?.id == category.id,
                         dot: nil) {
                        selectedCategory = selectedCategory?.id == category.id ? nil : category
                    }
                }

                if !equipmentService.categories.isEmpty {
                    Rectangle().fill(Color.primary.opacity(0.12))
                        .frame(width: 1, height: 20)
                        .padding(.horizontal, 2)
                }

                ForEach(EquipmentStatus.allCases, id: \.self) { status in
                    chip(status.label,
                         selected: selectedStatus == status,
                         dot: status.color) {
                        selectedStatus = selectedStatus == status ? nil : status
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(_ title: String, selected: Bool, dot: Color?,
                      action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(AmbientMotion.snappy) { action() }
            AmbientHaptics.selection()
        } label: {
            HStack(spacing: 5) {
                if let dot { Circle().fill(dot).frame(width: 6, height: 6) }
                Text(title).font(.caption.weight(.semibold))
            }
            .foregroundStyle(selected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                if selected { Capsule().fill(feature) }
                else { Capsule().fill(.ultraThinMaterial) }
            }
            .overlay(Capsule().strokeBorder(Color.primary.opacity(selected ? 0 : 0.1)))
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("Search all \(equipmentService.equipment.count) items", text: $query)
                .font(.subheadline)
                .autocorrectionDisabled()
            if showingInventory {
                Button {
                    clearFilters()
                    withAnimation(AmbientMotion.gentle) { browsing = false }
                } label: {
                    Text("Done").font(.caption.weight(.bold)).foregroundStyle(feature)
                }
                .buttonStyle(.plain)
            }
        }
        .ambientCard(density: .compact, fillWidth: true)
    }

    private var qrButton: some View {
        Button {
            showQRScanner = true
        } label: {
            Image(systemName: "qrcode.viewfinder")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(feature))
                .shadow(color: feature.opacity(0.45), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .padding(.bottom, 20)
    }

    // MARK: - Derived data

    private var assignedKits: [UserKitAssignment] {
        myGear.filter { $0.kitTemplate != nil }
    }

    /// Items assigned to you outside any kit, paired with the assignment that put
    /// them there so a row can say when they are due.
    private var looseItems: [(item: EquipmentItem, assignment: EquipmentAssignment?)] {
        myGear.filter { $0.kitTemplate == nil }.flatMap { group in
            group.items.map { item in
                (item: item,
                 assignment: group.assignments.first { $0.equipment_id == item.id })
            }
        }
    }

    private var allAssignments: [EquipmentAssignment] {
        myGear.flatMap(\.assignments)
    }

    private var assignedItemCount: Int { allAssignments.count }

    private var overdueCount: Int { allAssignments.filter(\.isOverdue).count }

    /// Has a return date still ahead of it. Permanent assignments are not "due back".
    private var dueBackCount: Int {
        allAssignments.filter { $0.expected_return_date != nil && !$0.isOverdue }.count
    }

    private var isFiltered: Bool {
        !query.isEmpty || selectedCategory != nil || selectedStatus != nil
    }

    private var filteredEquipment: [EquipmentItem] {
        equipmentService.equipment.filter { item in
            if let selectedStatus, item.statusEnum != selectedStatus { return false }
            if let selectedCategory, item.category_id != selectedCategory.id { return false }
            guard !query.isEmpty else { return true }
            return item.name.localizedCaseInsensitiveContains(query)
                || (item.category?.name.localizedCaseInsensitiveContains(query) ?? false)
                || (item.serial_number?.localizedCaseInsensitiveContains(query) ?? false)
                || (item.description?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    /// Equipment id -> the tape colour of the kit it belongs to.
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

    private func assigneeForOwnItem(_ assignment: EquipmentAssignment?) -> EquipmentRowAssignee {
        guard let assignment else { return EquipmentRowAssignee(label: "You") }
        return EquipmentRowAssignee(
            label: "You",
            dueLabel: assignment.expected_return_date.map { Formatters.monthDay.string(from: $0) },
            overdue: assignment.isOverdue)
    }

    /// The inventory list has no assignment join, so it can say that something is
    /// out but not who has it — exactly what `EquipmentCard` said. Naming the holder
    /// here would need a new query, and AMB.3 does not change the data layer.
    private func assigneeForInventoryItem(_ item: EquipmentItem) -> EquipmentRowAssignee? {
        item.statusEnum == .checkedOut
            ? EquipmentRowAssignee(label: "Currently checked out")
            : nil
    }

    private var canEditEquipment: Bool {
        // Phase 7 RBAC — equipment edit covers kit templates and creating items.
        Permissions.has("equipment", level: .edit)
    }

    // MARK: - Actions

    private func clearFilters() {
        withAnimation(AmbientMotion.snappy) {
            query = ""
            selectedCategory = nil
            selectedStatus = nil
        }
    }

    /// QR payload is "EQ-{uuid}".
    private func handleScannedCode(_ code: String) {
        showQRScanner = false

        let idString = code.hasPrefix("EQ-") ? String(code.dropFirst(3)) : code
        if let uuid = UUID(uuidString: idString) {
            destination = .item(uuid)
        }
    }

    // MARK: - Data loading

    private func load() async {
        guard let userId = UserManager.shared.getCurrentUserIDUnified() else {
            errorMessage = "Unable to get your user ID. Please sign out and sign back in."
            return
        }

        // The old view fell back to a fresh random UUID here, which silently
        // queried for a user that cannot exist and reported "no equipment" instead
        // of a problem. A malformed id is an error, not an empty kit bag.
        guard let userUUID = UUID(uuidString: userId.lowercased()) else {
            errorMessage = "Your user ID is not in the expected format. Please sign out and sign back in."
            return
        }

        guard !storedUserOrganizationID.isEmpty else {
            errorMessage = "Organization not configured. Please contact your administrator."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            // One load for the whole screen: this populates the service's
            // equipment, categories and kit templates, which the inventory, the
            // browse row's counts and the kit-colour mapping all read.
            try await equipmentService.loadAllEquipmentData(
                organizationId: storedUserOrganizationID)

            let assignments = try await equipmentService.getUserAssignments(
                userId: userUUID,
                organizationId: storedUserOrganizationID)

            myGear = equipmentService.groupAssignmentsByKit(
                assignments: assignments,
                equipmentItems: equipmentService.equipment,
                kitTemplates: equipmentService.kitTemplates)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
