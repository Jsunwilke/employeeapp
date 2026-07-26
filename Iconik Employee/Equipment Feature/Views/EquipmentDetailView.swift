//
//  EquipmentDetailView.swift
//  Iconik Employee
//
//  One item, in the Ambient design language (AMB.3).
//
//  Ported from the AMB.2 lab mockup the operator approved on iPhone and iPad.
//
//  THE PHOTO IS NO LONGER THE HEADLINE.
//      The app opened with a 250pt photo above everything. You are almost always
//      holding the object; what you cannot see by looking at it is whether it is
//      free, who has it and when it is due. So that leads, and the photo becomes a
//      thumbnail you tap to enlarge.
//
//  THE THREE ACTIONS ARE CONDITIONAL, exactly as they were: you cannot check out
//  something somebody else is holding, and you cannot request something you already
//  have. The first cut of the mockup drew all three all the time, which is a
//  different screen — caught by the parity inventory, not by review.
//

import SwiftUI

struct EquipmentDetailView: View {
    let equipmentId: UUID

    @StateObject private var equipmentService = EquipmentService.shared

    @State private var equipment: EquipmentItem?
    @State private var assignmentHistory: [EquipmentAssignment] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var photoExpanded = false
    @State private var currentUserId: String?

    @State private var showCheckOut = false
    @State private var showDamageReport = false
    @State private var showRequestForm = false

    private var feature: Color { FeatureTheme.color(for: "equipment") }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: feature)

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let equipment {
                content(for: equipment)
            } else {
                notFoundView
            }
        }
        .task {
            await loadData()
        }
        .navigationTitle(equipment?.name ?? "Equipment")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCheckOut) {
            if let equipment {
                NavigationStack {
                    EquipmentCheckOutView(equipment: equipment)
                }
            }
        }
        .sheet(isPresented: $showDamageReport) {
            if let equipment {
                NavigationStack {
                    DamageReportView(equipment: equipment, assignmentId: currentAssignment?.id)
                }
            }
        }
        .sheet(isPresented: $showRequestForm) {
            if let equipment {
                NavigationStack {
                    EquipmentRequestView(equipment: equipment, currentAssignment: currentAssignment)
                }
            }
        }
    }

    // MARK: - Content

    private func content(for equipment: EquipmentItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headline(for: equipment)

                if equipment.statusEnum == .checkedOut, let assignment = currentAssignment {
                    assignmentCard(assignment)
                }

                actions(for: equipment)

                if hasSpecs(equipment) {
                    specs(for: equipment)
                }

                if !assignmentHistory.isEmpty {
                    history
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }

    private var notFoundView: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.orange)
            Text("Equipment Not Found").font(.headline)
            if let errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .padding(.vertical, 44)
    }

    // MARK: - Headline

    private func headline(for equipment: EquipmentItem) -> some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(AmbientMotion.gentle) { photoExpanded.toggle() }
            } label: {
                photo(for: equipment)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text(equipment.name)
                    .font(.system(size: 17, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    AmbientBadge(text: equipment.statusEnum.label,
                                 systemImage: equipment.statusEnum.systemImage,
                                 tint: equipment.statusEnum.color)
                    AmbientBadge(text: equipment.conditionEnum.label,
                                 tint: equipment.conditionEnum.color)
                }

                if let kitName = kitMembership(for: equipment) {
                    Label("In \(kitName)", systemImage: "shippingbox.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .ambientCard(density: .roomy, state: .highlighted,
                     border: .hairline(equipment.statusEnum.color.opacity(0.35)),
                     glow: equipment.statusEnum.color, fillWidth: true)
    }

    private var photoSide: CGFloat { photoExpanded ? 150 : 68 }

    @ViewBuilder
    private func photo(for equipment: EquipmentItem) -> some View {
        if let photoPath = equipment.photo_url, !photoPath.isEmpty {
            SupabaseImageView(
                storageURL: photoPath,
                bucket: "equipment-photos",
                width: photoSide,
                height: photoSide,
                contentMode: .fill,
                cornerRadius: 12
            )
        } else {
            // ambient-allow: the "no photo" placeholder, not a card.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .frame(width: photoSide, height: photoSide)
                .overlay {
                    VStack(spacing: 4) {
                        Image(systemName: "circle.dashed")
                            .font(.system(size: photoExpanded ? 34 : 22, weight: .light))
                            .foregroundStyle(.tertiary)
                        if photoExpanded {
                            Text("No photo").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
        }
    }

    // MARK: - Current assignment

    private func assignmentCard(_ assignment: EquipmentAssignment) -> some View {
        HStack(spacing: 12) {
            if let name = holderName(assignment) {
                AmbientAvatar(name: name, size: 38)
            } else {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(holderLine(assignment))
                    .font(.subheadline.weight(.semibold))

                if assignment.isPermanent {
                    Text("Permanent assignment")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let returnDate = assignment.expected_return_date {
                    Text(assignment.isOverdue
                         ? "Was due \(Formatters.mediumDate.string(from: returnDate))"
                         : "Due back \(Formatters.mediumDate.string(from: returnDate))")
                        .font(.caption)
                        .foregroundStyle(assignment.isOverdue
                                         ? AnyShapeStyle(Color.red)
                                         : AnyShapeStyle(.secondary))
                }

                if let notes = assignment.checkin_notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .ambientCard(density: .roomy,
                     border: assignment.isOverdue
                        ? .strong(Color.red.opacity(0.5))
                        : .hairline(Color.primary.opacity(0.08)),
                     fillWidth: true)
    }

    // MARK: - Actions

    private func actions(for equipment: EquipmentItem) -> some View {
        VStack(spacing: 10) {
            if equipment.statusEnum == .available {
                actionButton("Check Out", systemImage: "arrow.up.to.line",
                             tint: feature, solid: true) {
                    showCheckOut = true
                }
            }

            if equipment.statusEnum == .checkedOut && !isAssignedToCurrentUser {
                actionButton("Request Equipment", systemImage: "hand.raised.fill",
                             tint: feature, solid: false) {
                    showRequestForm = true
                }
            }

            actionButton("Report Damage", systemImage: "exclamationmark.triangle.fill",
                         tint: .orange, solid: false) {
                showDamageReport = true
            }
        }
    }

    private func actionButton(_ title: String, systemImage: String, tint: Color,
                              solid: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage).font(.footnote.weight(.semibold))
                Text(title).font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(solid ? AnyShapeStyle(.white) : AnyShapeStyle(tint))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background {
                if solid { Capsule().fill(tint) } else { Capsule().fill(tint.opacity(0.14)) }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Specs

    /// True when the Details card has at least one row to draw.
    ///
    /// The card is skipped entirely otherwise. The app's equivalent section always
    /// had content because the status and condition badges lived inside it; those
    /// moved up into the headline here, so on a sparse item — a name and nothing
    /// else, which is what an item created from a QR scan looks like — the card
    /// would have rendered empty but for its own "DETAILS" heading.
    private func hasSpecs(_ equipment: EquipmentItem) -> Bool {
        func present(_ value: String?) -> Bool {
            guard let value else { return false }
            return !value.isEmpty
        }
        return present(equipment.category?.name)
            || present(equipment.serial_number)
            || present(equipment.description)
            || present(equipment.notes)
            || equipment.purchase_price != nil
            || equipment.purchase_date != nil
    }

    /// Every field the app rendered, and each only when present — so this list is
    /// short for a sparse item and long for a well-catalogued one.
    private func specs(for equipment: EquipmentItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            AmbientSectionTitle("Details").padding(.bottom, 8)
            spec("Category", equipment.category?.name, "folder")
            spec("Serial number", equipment.serial_number, "number")
            spec("Description", equipment.description, "text.alignleft")
            spec("Notes", equipment.notes, "note.text")
            spec("Purchase price", equipment.purchase_price.map { String(format: "$%.2f", $0) },
                 "dollarsign.circle")
            spec("Purchased", equipment.purchase_date.map { Formatters.mediumDate.string(from: $0) },
                 "calendar")
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    @ViewBuilder
    private func spec(_ label: String, _ value: String?, _ symbol: String) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(label).font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 12)
                Text(value)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - History

    private var history: some View {
        VStack(alignment: .leading, spacing: AmbientDensity.compact.stackSpacing) {
            AmbientSectionTitle("Assignment history")

            ForEach(assignmentHistory) { assignment in
                historyRow(assignment)
            }
        }
    }

    private func historyRow(_ assignment: EquipmentAssignment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if let name = holderName(assignment) {
                AmbientAvatar(name: name, size: 26)
            } else {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(holderName(assignment) ?? (isMine(assignment) ? "You" : "Checked out"))
                    .font(.footnote.weight(.medium))

                Text(historyDates(assignment))
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let notes = assignment.checkin_notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if let raw = assignment.condition_at_checkin,
                   let condition = EquipmentCondition(rawValue: raw) {
                    HStack(spacing: 4) {
                        Text("Returned in").font(.caption2).foregroundStyle(.secondary)
                        AmbientBadge(text: condition.label, tint: condition.color)
                    }
                    .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)

            if assignment.isActive {
                AmbientBadge(text: "Current", tint: feature)
            } else if assignment.checked_in_at != nil {
                Text("Returned").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .ambientCard(density: .compact,
                     state: assignment.isActive ? .normal : .receded,
                     fillWidth: true)
    }

    /// Dated with the YEAR, unlike the mockup's "Jun 14 – Jun 28".
    ///
    /// The mockup's sample history all sat inside one month, which hid the problem:
    /// this is the one screen where "when did I last have this" is asked across
    /// years, and a bare month and day cannot answer it. The app's own row carried a
    /// full short date for the same reason.
    private func historyDates(_ assignment: EquipmentAssignment) -> String {
        let out = Formatters.mediumDate.string(from: assignment.checked_out_at)
        if let checkedIn = assignment.checked_in_at {
            return "\(out) – \(Formatters.mediumDate.string(from: checkedIn))"
        }
        if let expected = assignment.expected_return_date {
            return "\(out) – due \(Formatters.mediumDate.string(from: expected))"
        }
        return "\(out) – permanent"
    }

    // MARK: - Derived

    /// The active assignment, from the item's history.
    private var currentAssignment: EquipmentAssignment? {
        assignmentHistory.first { $0.isActive }
    }

    private var isAssignedToCurrentUser: Bool {
        guard let assignment = currentAssignment else { return false }
        return isMine(assignment)
    }

    /// Read once in `loadData` rather than per row: `isMine` is called for every
    /// entry in the history, and each call was hitting `UserManager` again.
    /// Lowercased at the source — Supabase stores lowercase and Swift generates
    /// uppercase, and string comparison is not case-insensitive.
    private func isMine(_ assignment: EquipmentAssignment) -> Bool {
        guard let currentUserId else { return false }
        return assignment.assigned_to.uuidString.lowercased() == currentUserId
    }

    /// `getEquipmentHistory` cannot join the users table — there is no FK between
    /// equipment_assignments and users — so `assignedToUser` is nil in practice.
    /// The app rendered nothing at all in that case; here the row still says what it
    /// knows, and says "you" when the holder is you. Naming other people would need a
    /// second query, which is a data-layer change AMB.3 does not make.
    private func holderName(_ assignment: EquipmentAssignment) -> String? {
        assignment.assignedToUser?.displayName
    }

    private func holderLine(_ assignment: EquipmentAssignment) -> String {
        if let name = holderName(assignment) { return "Checked out to \(name)" }
        return isMine(assignment) ? "Checked out to you" : "Checked out"
    }

    private func kitMembership(for equipment: EquipmentItem) -> String? {
        equipmentService.kitTemplates.first { $0.equipmentIds.contains(equipment.id) }?.name
    }

    // MARK: - Data loading

    private func loadData() async {
        isLoading = true
        errorMessage = nil
        currentUserId = UserManager.shared.getCurrentUserIDUnified()?.lowercased()

        do {
            equipment = try await equipmentService.getEquipmentItem(id: equipmentId)
            assignmentHistory = try await equipmentService.getEquipmentHistory(equipmentId: equipmentId)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
