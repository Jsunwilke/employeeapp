//  EquipmentMockup.swift
//  Iconik Employee — AMB.3's mockup
//
//  ARC SCAFFOLDING. Deleted with the rest of the lab at AMB.12.
//
//  THIS IS THE D10 GATE FOR AMB.3. The specimen sheet proposed Equipment's ROW;
//  a row is not a screen, and AMB.3 does not start until the screen below has
//  been approved on a device.
//
//  WHAT IS HERE, AND WHY BOTH TABS
//      Equipment opens on MY KITS, not on the equipment list — that is the real
//      default (EquipmentTabView.selectedTab = .myKits). Mocking only the list
//      would gate AMB.3 on a screen the photographer does not actually land on,
//      so both tabs are here, plus both detail screens they push to.
//
//  THE WASH  (D11)
//      Equipment's feature colour, #00A2C7, straight out of FeatureTheme — the
//      same colour as its home tile and its bottom-bar item, so the tile you tap
//      and the screen you land on agree. Starts at full strength because nobody
//      has judged the intensity for this screen yet; the slider is how it gets
//      judged. The dashboard settled at 90% for comparison.
//
//  TWO THINGS THAT ARE DELIBERATELY NOT LIKE THE REAL SCREEN, both disclosed in
//  the lab strip at the top so the operator is not judging a lie:
//
//      1. THE QR BUTTON IS LIFTED. It sits hard at the bottom-right corner in
//         the app; here it is raised to clear the lab's own mockup switcher,
//         which occupies that corner. Same size, same side, wrong height.
//
//      2. THE CONTAINER IS NOT THE ONE EQUIPMENT REALLY GETS. Equipment is a
//         self-nav feature (MainEmployeeView.isSelfNavFeature) — it builds its
//         own NavigationStack. The lab is inside the shell's NavigationView, per
//         the rule that a mockup never supplies its own container. Everything
//         here therefore pushes through .ambientPush(item:), which is the one
//         form that works in BOTH, so nothing approved here can fail on the way
//         out. AMB.3 still has to decide whether Equipment keeps its own stack.

import SwiftUI

struct EquipmentMockup: View {

    private enum Tab: String, CaseIterable {
        case myKits = "My Kit(s)"
        case allEquipment = "All Equipment"
    }

    /// The status filters across the top of the list. `all` is the resting state.
    private enum Filter: String, CaseIterable {
        case all = "All"
        case available = "Available"
        case checkedOut = "Checked Out"
        case needsRepair = "Needs Repair"
        case retired = "Retired"

        var status: LabEquipmentStatus? {
            switch self {
            case .all: return nil
            case .available: return .available
            case .checkedOut: return .checkedOut
            case .needsRepair: return .needsRepair
            case .retired: return .retired
            }
        }
    }

    @State private var tab: Tab = .myKits
    @State private var wash: Double = 1
    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var pushedItem: LabEquipmentItem?
    @State private var pushedKit: LabKit?

    private var feature: Color { FeatureTheme.color(for: "equipment") }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AmbientBackdrop(tint: feature, intensity: wash)

            VStack(spacing: 0) {
                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 10)

                switch tab {
                case .myKits: myKits
                case .allEquipment: allEquipment
                }
            }

            qrButton
        }
        .ambientPush(item: $pushedKit) { EquipmentKitDetailMockup(kit: $0, feature: feature, wash: wash) }
        .ambientPush(item: $pushedItem) { EquipmentDetailMockup(item: $0, feature: feature, wash: wash) }
    }

    // MARK: - Lab chrome

    /// Dashed, because the design system's dashed edge means "not the same KIND
    /// of thing as the cards around it" — which is exactly what lab chrome is.
    private var labStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(feature).frame(width: 12, height: 12)
                Text("Equipment wash")
                    .font(.footnote.weight(.semibold))
                Spacer()
                Text(wash == 0 ? "off" : "\(Int(wash * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $wash, in: 0...1).tint(feature)
            Text("Full strength to start — nobody has judged this screen's intensity yet. Home settled at 90%. Two things here are not like the app: the scan button is lifted to clear the lab's own switcher, and this strip does not exist.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .ambientCard(density: .compact, border: .dashed(Color.primary.opacity(0.25)), fillWidth: true)
    }

    // MARK: - My Kits  (the default tab)

    private var myKits: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AmbientDensity.compact.stackSpacing) {
                labStrip
                    .padding(.bottom, 4)

                AmbientSectionTitle("My kits", trailing: "\(DesignLabSampleData.myKits.count)")
                ForEach(DesignLabSampleData.myKits) { kit in
                    Button { pushedKit = kit } label: { LabKitRow(kit: kit) }
                        .buttonStyle(.plain)
                }

                AmbientSectionTitle("Other equipment",
                                    trailing: "\(DesignLabSampleData.otherAssignedEquipment.count)")
                    .padding(.top, 10)
                ForEach(DesignLabSampleData.otherAssignedEquipment) { item in
                    Button { pushedItem = item } label: { LabEquipmentRow(item: item) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 96)
        }
    }

    // MARK: - All Equipment

    private var allEquipment: some View {
        VStack(spacing: 10) {
            searchField
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Filter.allCases, id: \.self) { option in
                        filterChip(option)
                    }
                }
                .padding(.horizontal, 16)
            }

            if filtered.isEmpty {
                ScrollView {
                    VStack(spacing: 14) {
                        labStrip
                        AmbientEmptyState(
                            title: "No equipment found",
                            message: "Try adjusting your search or filters.",
                            systemImage: "shippingbox")
                        Button {
                            query = ""
                            filter = .all
                        } label: {
                            Text("Clear filters")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20).padding(.vertical, 11)
                                .background(Capsule().fill(feature))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 96)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
                        labStrip
                            .padding(.bottom, 4)
                        ForEach(filtered) { item in
                            Button { pushedItem = item } label: { LabEquipmentRow(item: item) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 96)
                }
            }
        }
    }

    /// Live, so the empty state is reached by actually typing rather than by a
    /// toggle that pretends. Equipment filters client-side over the whole array
    /// in the app too — there is no pagination anywhere in the feature.
    private var filtered: [LabEquipmentItem] {
        DesignLabSampleData.equipment.filter { item in
            let matchesStatus = filter.status.map { $0 == item.status } ?? true
            guard matchesStatus else { return false }
            guard !query.isEmpty else { return true }
            let needle = query.lowercased()
            return item.name.lowercased().contains(needle)
                || (item.category?.lowercased().contains(needle) ?? false)
                || (item.serial?.lowercased().contains(needle) ?? false)
        }
    }

    /// The card primitive doing duty as a text field container — one of the
    /// things AMB.2 wanted to know: whether `.ambientCard` covers the furniture
    /// as well as the content. It does.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("Search equipment", text: $query)
                .font(.subheadline)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .ambientCard(density: .compact, fillWidth: true)
    }

    private func filterChip(_ option: Filter) -> some View {
        let selected = option == filter
        return Button {
            withAnimation(AmbientMotion.snappy) { filter = option }
            AmbientHaptics.selection()
        } label: {
            HStack(spacing: 5) {
                if let status = option.status {
                    Circle().fill(status.color).frame(width: 6, height: 6)
                }
                Text(option.rawValue)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(selected ? .white : .primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                if selected {
                    Capsule().fill(feature)
                } else {
                    Capsule().fill(.ultraThinMaterial)
                }
            }
            .overlay(Capsule().strokeBorder(Color.primary.opacity(selected ? 0 : 0.1)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - The scan button

    private var qrButton: some View {
        Image(systemName: "qrcode.viewfinder")
            .font(.title2)
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(Circle().fill(feature))
            .shadow(color: feature.opacity(0.45), radius: 10, y: 5)
            .padding(.trailing, 20)
            // 92 rather than 20: the lab's mockup switcher owns this corner.
            .padding(.bottom, 92)
    }
}

// MARK: - Kit row

/// My Kits' row, rebuilt from Ambient primitives. Drawn from what `KitCard`
/// renders today: the tape-colour stripe, the box icon with its colour dot, the
/// name, an optional description, the item count, and exactly one of overdue /
/// permanent / a return date.
struct LabKitRow: View {
    let kit: LabKit
    var density: AmbientDensity = .compact

    var body: some View {
        HStack(spacing: 10) {
            icon

            VStack(alignment: .leading, spacing: density.contentSpacing) {
                Text(kit.name)
                    .font(density.titleFont)
                    .lineLimit(1)
                if let detail = kit.detail {
                    Text(detail)
                        .font(density.subtitleFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    AmbientBadge(text: "\(kit.itemCount) items",
                                 systemImage: "cube.box.fill", tint: .secondary)
                    dueBadge
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(.tertiary)
        }
        .ambientCard(density: density, border: .hairline(borderTint))
        .overlay(alignment: .leading) { LabKitStripe(kit: kit, density: density) }
    }

    private var borderTint: Color {
        if case .overdue = kit.due { return .red.opacity(0.5) }
        return Color.primary.opacity(0.08)
    }

    private var icon: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.primary.opacity(0.06))
            .frame(width: 40, height: 40)
            .overlay {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .overlay(alignment: .topLeading) {
                LabKitDot(kit: kit, size: 12).offset(x: -3, y: -3)
            }
    }

    @ViewBuilder
    private var dueBadge: some View {
        switch kit.due {
        case .permanent:
            AmbientBadge(text: "Permanent", systemImage: "infinity", tint: .blue)
        case .on(let date):
            AmbientBadge(text: "Due \(date)", systemImage: "calendar", tint: .secondary)
        case .overdue(let days):
            AmbientBadge(text: "\(days)d overdue",
                         systemImage: "exclamationmark.triangle.fill", tint: .red)
        }
    }
}

// MARK: - Kit colour, including rainbow

/// The tape colour as a stripe down the leading edge.
///
/// Rainbow is a real kit tape colour — the model has `isRainbow` and three views
/// special-case it — so a stripe drawn as a flat `Color(hex:)` would render it
/// as garbage. Mirrors `KitColorBorder`'s gradient, minus the endless animation:
/// a colour that spins forever on every row of a list is a battery cost and a
/// distraction, and this is the right place to find out whether it is missed.
struct LabKitStripe: View {
    let kit: LabKit
    var density: AmbientDensity = .compact

    var body: some View {
        Group {
            if kit.isRainbow {
                Capsule().fill(LabKitStripe.rainbow)
            } else if let hex = kit.colorHex {
                Capsule().fill(Color(hex: hex))
            }
        }
        .frame(width: 3)
        .padding(.vertical, density.verticalPadding)
        .padding(.leading, 1)
    }

    static let rainbow = LinearGradient(
        colors: [.red, .orange, .yellow, .green, .blue, .purple],
        startPoint: .top, endPoint: .bottom)
}

struct LabKitDot: View {
    let kit: LabKit
    var size: CGFloat = 12

    var body: some View {
        Group {
            if kit.isRainbow {
                Circle().fill(AngularGradient(
                    colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                    center: .center))
            } else if let hex = kit.colorHex {
                Circle().fill(Color(hex: hex))
            }
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
    }
}

// MARK: - Kit detail

/// Drawn from `KitDetailView`: the big icon with its colour dot, the name, the
/// description, the item count and return badge, the tape-colour reference line,
/// then the items GROUPED BY CATEGORY and starting COLLAPSED — which is the part
/// of this screen worth arguing about, because a kit of six items opens showing
/// nothing but three category headers.
struct EquipmentKitDetailMockup: View {
    let kit: LabKit
    let feature: Color
    let wash: Double

    @State private var expanded: Set<String> = []
    @State private var pushedItem: LabEquipmentItem?

    private var groups: [(category: String, items: [LabEquipmentItem])] {
        Dictionary(grouping: kit.items) { $0.category ?? "Uncategorised" }
            .map { (category: $0.key, items: $0.value) }
            .sorted { $0.category < $1.category }
    }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: feature, intensity: wash)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    AmbientSectionTitle("Equipment in kit", trailing: "\(kit.itemCount)")
                    VStack(spacing: AmbientDensity.compact.stackSpacing) {
                        ForEach(groups, id: \.category) { group in
                            categorySection(group)
                        }
                    }

                    Text("Categories open collapsed in the app, so a six-item kit lands on three headers and no equipment. Worth deciding here: open the first, open all, or leave it.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle(kit.name)
        .navigationBarTitleDisplayMode(.inline)
        .ambientPush(item: $pushedItem) { EquipmentDetailMockup(item: $0, feature: feature, wash: wash) }
    }

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.primary.opacity(0.06)).frame(width: 80, height: 80)
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                LabKitDot(kit: kit, size: 24).offset(x: 28, y: -28)
            }

            Text(kit.name).font(.title3.weight(.bold))

            if let detail = kit.detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 8) {
                AmbientBadge(text: "\(kit.itemCount) items",
                             systemImage: "cube.box.fill", tint: .secondary)
                dueBadge
            }

            HStack(spacing: 8) {
                LabKitDot(kit: kit, size: 16)
                Text("Tape colour, for finding it on a shelf")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        }
        .ambientCard(density: .hero, state: .highlighted,
                     border: .hairline(feature.opacity(0.3)),
                     glow: feature, fillWidth: true, contentAlignment: .center)
    }

    @ViewBuilder
    private var dueBadge: some View {
        switch kit.due {
        case .permanent:
            AmbientBadge(text: "Permanent", systemImage: "infinity", tint: .blue)
        case .on(let date):
            AmbientBadge(text: "Due \(date)", systemImage: "calendar", tint: .secondary)
        case .overdue(let days):
            AmbientBadge(text: "\(days) days overdue",
                         systemImage: "exclamationmark.triangle.fill", tint: .red)
        }
    }

    private func categorySection(_ group: (category: String, items: [LabEquipmentItem])) -> some View {
        VStack(spacing: AmbientDensity.compact.stackSpacing) {
            Button {
                withAnimation(AmbientMotion.snappy) {
                    if expanded.contains(group.category) {
                        expanded.remove(group.category)
                    } else {
                        expanded.insert(group.category)
                    }
                }
                AmbientHaptics.selection()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: expanded.contains(group.category)
                          ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    Text(group.category).font(AmbientDensity.compact.titleFont)
                    Spacer(minLength: 0)
                    Text("\(group.items.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .ambientCard(density: .compact, fillWidth: true)
            }
            .buttonStyle(.plain)

            if expanded.contains(group.category) {
                ForEach(group.items) { item in
                    Button { pushedItem = item } label: {
                        LabEquipmentRow(item: item)
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 14)
                }
            }
        }
    }
}

// MARK: - Equipment detail

/// Drawn from `EquipmentDetailView`: a 250pt photo, a card of icon-label-value
/// rows, the current assignment when checked out, three actions, and the
/// assignment history.
struct EquipmentDetailMockup: View {
    let item: LabEquipmentItem
    let feature: Color
    let wash: Double

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: feature, intensity: wash)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    photo
                    infoCard
                    if let assignee = item.assignee { assignmentCard(assignee) }
                    actions
                    history
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var photo: some View {
        RoundedRectangle(cornerRadius: AmbientDensity.hero.cornerRadius, style: .continuous)
            .fill(Color.primary.opacity(0.06))
            .frame(height: 250)
            .overlay {
                Image(systemName: item.hasPhoto ? "camera.fill" : "circle.dashed")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(.tertiary)
            }
            .overlay(alignment: .topTrailing) {
                AmbientBadge(text: item.status.rawValue,
                             systemImage: item.status.symbol,
                             tint: item.status.color)
                    .padding(12)
            }
            .overlay(alignment: .bottomLeading) {
                if item.kitColor != nil {
                    AmbientBadge(text: "In a kit", systemImage: "shippingbox.fill", tint: .teal)
                        .padding(12)
                }
            }
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            infoRow("Category", item.category ?? "—", "square.grid.2x2")
            Divider().opacity(0.4)
            infoRow("Condition", item.condition.rawValue, "checkmark.seal",
                    tint: item.condition.color)
            Divider().opacity(0.4)
            infoRow("Serial", item.serial ?? "—", "number")
            Divider().opacity(0.4)
            infoRow("Status", item.status.rawValue, item.status.symbol,
                    tint: item.status.color)
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    private func infoRow(_ label: String, _ value: String,
                         _ symbol: String, tint: Color = .secondary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(tint)
                .frame(width: 20)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 9)
    }

    private func assignmentCard(_ assignee: String) -> some View {
        HStack(spacing: 12) {
            AmbientAvatar(name: assignee, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text("Checked out to")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(assignee).font(.subheadline.weight(.semibold))
                Text("Since Jul 21 · due back Aug 2")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .ambientCard(density: .roomy, state: .highlighted,
                     border: .strong(item.status.color.opacity(0.5)), fillWidth: true)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            action("Check Out", systemImage: "arrow.up.right.square.fill",
                   tint: feature, solid: true)
            action("Request Equipment", systemImage: "hand.raised.fill",
                   tint: feature, solid: false)
            action("Report Damage", systemImage: "exclamationmark.triangle.fill",
                   tint: .orange, solid: false)
        }
    }

    private func action(_ title: String, systemImage: String,
                        tint: Color, solid: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).font(.footnote.weight(.semibold))
            Text(title).font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(solid ? AnyShapeStyle(.white) : AnyShapeStyle(tint))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
        .background {
            if solid {
                Capsule().fill(tint)
            } else {
                Capsule().fill(tint.opacity(0.14))
            }
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            AmbientSectionTitle("Assignment history")
            ForEach(DesignLabSampleData.crew.prefix(3)) { person in
                HStack(spacing: 10) {
                    AmbientAvatar(name: person.name, size: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.name).font(.footnote.weight(.medium))
                        Text("Jun 14 – Jun 28")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text("Returned")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .ambientCard(density: .compact, state: .receded, fillWidth: true)
            }
        }
    }
}
