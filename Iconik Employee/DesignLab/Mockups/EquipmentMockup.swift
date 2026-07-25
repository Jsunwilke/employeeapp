//  EquipmentMockup.swift
//  Iconik Employee — AMB.3's mockup
//
//  ARC SCAFFOLDING. Deleted with the rest of the lab at AMB.12.
//
//  THIS IS THE D10 GATE FOR AMB.3, and under D12 it is a REDESIGN with a parity
//  constraint rather than a restyle. Every capability it must not lose is listed
//  in AMB_BATCH1_PARITY.md, read out of the source rather than off the screen.
//
//  THE ONE STRUCTURAL CHANGE: THE TAB BAR IS GONE.
//      Equipment ships as two tabs — My Kit(s), which is the default, and All
//      Equipment. But those are not two places, they are two questions, and only
//      one of them gets asked most days: what am I holding, and is any of it
//      late. Browsing the org's entire inventory is the rarer errand.
//
//      So the screen leads with YOUR GEAR and carries the inventory behind one
//      row. Nothing is lost — both destinations are one tap from the top, the
//      same as a segmented control — and the common case stops costing a tap.
//
//      What that buys, and it is the real point: a standing line at the top that
//      says how much you have out, how much is due back, and how much is LATE.
//      Today the only way to find out something is overdue is to read every kit
//      card in turn.
//
//  THE QR BUTTON STAYS A FAB.
//      It was tempting to fold it into the search field as a glyph. It is the
//      fastest route to any item in the building — scan the tape on the case —
//      and it gets pressed with a case in the other hand. A 56pt target beats a
//      tidy one. It is lifted here only to clear the lab's own switcher.
//
//  THE KIT DETAIL IS A PACKING LIST.
//      Categories open EXPANDED, in the app's own photography workflow order
//      (cameras, lenses, lighting, stands, bags, backdrops, power, storage,
//      audio, accessories). Collapsed-by-default means a six-item kit opens on
//      three headers and no equipment, which is the wrong answer to the only
//      question anyone opens a kit to ask.
//
//  CONTAINER NOTE: Equipment is a self-nav feature (isSelfNavFeature), so it
//  builds its own NavigationStack while the lab runs inside the shell's
//  NavigationView. Everything here pushes through .ambientPush(item:), which
//  works in both, so nothing approved can fail on the way out.

import SwiftUI

struct EquipmentMockup: View {

    /// The status filters. Categories come from the data — see `categories`.
    private enum StatusFilter: String, CaseIterable {
        case available = "Available"
        case checkedOut = "Checked Out"
        case needsRepair = "Needs Repair"
        case retired = "Retired"

        var status: LabEquipmentStatus {
            switch self {
            case .available: return .available
            case .checkedOut: return .checkedOut
            case .needsRepair: return .needsRepair
            case .retired: return .retired
            }
        }
    }

    @State private var wash: Double = 1
    @State private var query = ""
    @State private var browsing = false
    @State private var category: String?
    @State private var status: StatusFilter?
    @State private var pushedItem: LabEquipmentItem?
    @State private var pushedKit: LabKit?

    private var feature: Color { FeatureTheme.color(for: "equipment") }

    /// Typing anywhere jumps straight into the inventory — you never have to
    /// find the browse row first.
    private var showingInventory: Bool {
        browsing || !query.isEmpty || category != nil || status != nil
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AmbientBackdrop(tint: feature, intensity: wash)

            VStack(spacing: 10) {
                searchField.padding(.horizontal, 16).padding(.top, 8)

                if showingInventory {
                    filterChips
                    inventory
                } else {
                    myGear
                }
            }

            qrButton
        }
        .ambientPush(item: $pushedKit) { EquipmentKitDetailMockup(kit: $0, feature: feature, wash: wash) }
        .ambientPush(item: $pushedItem) { EquipmentDetailMockup(item: $0, feature: feature, wash: wash) }
        .animation(AmbientMotion.gentle, value: showingInventory)
    }

    // MARK: - Lab chrome

    private var labStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(feature).frame(width: 12, height: 12)
                Text("Equipment wash").font(.footnote.weight(.semibold))
                Spacer()
                Text(wash == 0 ? "off" : "\(Int(wash * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: $wash, in: 0...1).tint(feature)
            Text("The two tabs are gone: this screen leads with your gear and the whole inventory is one row down (or just start typing). The scan button is lifted to clear the lab's switcher — in the app it sits in the corner.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .ambientCard(density: .compact, border: .dashed(Color.primary.opacity(0.25)), fillWidth: true)
    }

    // MARK: - Your gear  (what the default tab used to be)

    private var myGear: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AmbientDensity.compact.stackSpacing) {
                labStrip.padding(.bottom, 4)

                standingLine

                AmbientSectionTitle("Your kits", trailing: "\(DesignLabSampleData.myKits.count)")
                ForEach(DesignLabSampleData.myKits) { kit in
                    Button { pushedKit = kit } label: { LabKitRow(kit: kit) }
                        .buttonStyle(.plain)
                }

                AmbientSectionTitle("Also checked out to you",
                                    trailing: "\(DesignLabSampleData.otherAssignedEquipment.count)")
                    .padding(.top, 10)
                ForEach(DesignLabSampleData.otherAssignedEquipment) { item in
                    // In the app this row's tap handler is an EMPTY COMMENT — it
                    // looks tappable and does nothing. Wired here; that is a bug
                    // fix AMB.3 should ship, not a redesign.
                    Button { pushedItem = item } label: { LabEquipmentRow(item: item) }
                        .buttonStyle(.plain)
                }

                browseRow.padding(.top, 14)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 96)
        }
    }

    /// The line that does not exist today. Three numbers, and the late one is
    /// the only one allowed to shout.
    private var standingLine: some View {
        let gear = DesignLabSampleData.MyGear.self
        return HStack(spacing: 0) {
            standingStat("\(gear.itemCount)", "items out", tint: .primary)
            divider
            standingStat("\(gear.dueSoonCount)", "due back", tint: .secondary)
            divider
            standingStat("\(gear.overdueCount)", "overdue",
                         tint: gear.overdueCount > 0 ? .red : .secondary)
        }
        .ambientCard(density: .roomy,
                     state: gear.overdueCount > 0 ? .highlighted : .normal,
                     border: gear.overdueCount > 0
                        ? .strong(Color.red.opacity(0.45))
                        : .hairline(Color.primary.opacity(0.08)),
                     fillWidth: true)
    }

    private var divider: some View {
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
                .lineLimit(1).minimumScaleFactor(0.8)
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
                    Text("\(DesignLabSampleData.equipment.count) items · \(DesignLabSampleData.equipmentCategories.count) categories")
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

    // MARK: - Inventory  (what All Equipment used to be)

    private var inventory: some View {
        Group {
            if filtered.isEmpty {
                ScrollView {
                    VStack(spacing: 14) {
                        AmbientEmptyState(
                            title: "No equipment found",
                            message: "Try adjusting your search or filters.",
                            systemImage: "shippingbox")
                        // The app shows Clear Filters only when something is
                        // actually filtered. Same rule here.
                        if isFiltered {
                            Button { clearFilters() } label: {
                                Text("Clear filters")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 20).padding(.vertical, 11)
                                    .background(Capsule().fill(feature))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 96)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
                        ForEach(filtered) { item in
                            Button { pushedItem = item } label: { LabEquipmentRow(item: item) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 2)
                    .padding(.bottom, 96)
                }
            }
        }
    }

    private var isFiltered: Bool { !query.isEmpty || category != nil || status != nil }

    private func clearFilters() {
        withAnimation(AmbientMotion.snappy) {
            query = ""; category = nil; status = nil
        }
    }

    /// Search matches name, category, serial AND description — the app searches
    /// name, serial and description, and dropping category would have made the
    /// category chips the only way to find one.
    private var filtered: [LabEquipmentItem] {
        DesignLabSampleData.equipment.filter { item in
            if let status, item.status != status.status { return false }
            if let category, item.category != category { return false }
            guard !query.isEmpty else { return true }
            let needle = query.lowercased()
            return item.name.lowercased().contains(needle)
                || (item.category?.lowercased().contains(needle) ?? false)
                || (item.serial?.lowercased().contains(needle) ?? false)
                || (item.detail?.lowercased().contains(needle) ?? false)
        }
    }

    /// Categories AND statuses, in one scroller with a divider between them —
    /// the app's arrangement, and the first cut of this mockup dropped the
    /// category half entirely.
    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DesignLabSampleData.equipmentCategories, id: \.self) { name in
                    chip(name, selected: category == name, dot: nil) {
                        category = category == name ? nil : name
                    }
                }

                Rectangle().fill(Color.primary.opacity(0.12))
                    .frame(width: 1, height: 20)
                    .padding(.horizontal, 2)

                ForEach(StatusFilter.allCases, id: \.self) { option in
                    chip(option.rawValue, selected: status == option,
                         dot: option.status.color) {
                        status = status == option ? nil : option
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
            .padding(.horizontal, 12).padding(.vertical, 7)
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
            TextField("Search all \(DesignLabSampleData.equipment.count) items", text: $query)
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
        Image(systemName: "qrcode.viewfinder")
            .font(.title2)
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(Circle().fill(feature))
            .shadow(color: feature.opacity(0.45), radius: 10, y: 5)
            .padding(.trailing, 20)
            // 92 rather than 20: the lab's switcher owns this corner.
            .padding(.bottom, 92)
    }
}

// MARK: - Kit row

/// Everything `KitCard` renders: tape stripe, box icon with its colour dot,
/// name, description, item count, and exactly one of overdue / permanent /
/// return date.
struct LabKitRow: View {
    let kit: LabKit
    var density: AmbientDensity = .compact

    var body: some View {
        HStack(spacing: 10) {
            icon

            VStack(alignment: .leading, spacing: density.contentSpacing) {
                Text(kit.name).font(density.titleFont).lineLimit(1)
                if let detail = kit.detail {
                    Text(detail)
                        .font(density.subtitleFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    AmbientBadge(text: "\(kit.itemCount) items",
                                 systemImage: "cube.box.fill", tint: .secondary)
                    LabKitDueBadge(due: kit.due)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold)).foregroundStyle(.tertiary)
        }
        .ambientCard(density: density, border: .hairline(borderTint))
        .labKitEdge(kit.colorHex, density: density)
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
                    .font(.system(size: 16)).foregroundStyle(.secondary)
            }
            .overlay(alignment: .topLeading) {
                LabKitDot(kit: kit, size: 12).offset(x: -3, y: -3)
            }
    }
}

/// Exactly one of the three, which is the rule in KitCard and KitDetailView.
struct LabKitDueBadge: View {
    let due: LabKitDue
    var spelledOut = false

    var body: some View {
        switch due {
        case .permanent:
            AmbientBadge(text: "Permanent", systemImage: "infinity", tint: .blue)
        case .on(let date):
            AmbientBadge(text: "Due \(date)", systemImage: "calendar", tint: .secondary)
        case .overdue(let days):
            AmbientBadge(text: spelledOut ? "\(days) days overdue" : "\(days)d overdue",
                         systemImage: "exclamationmark.triangle.fill", tint: .red)
        }
    }
}

// MARK: - Kit colour, including rainbow

/// The kit tape colour, as a FLUSH EDGE BAND on the card.
///
/// The first cut drew this as a 3pt Capsule inset 1pt from the leading edge and
/// inset vertically by the card's own padding — which makes it a floating
/// rounded pill sitting inside the card rather than an edge, and it read as a
/// stray mark. The app does not do that: `KitColorBorder` is a plain Rectangle
/// first in an HStack(spacing: 0), so it runs the FULL height of the card,
/// flush to the leading edge, with the container's corner radius clipping its
/// ends. That is why it reads as binding tape there and as litter here.
///
/// So: full height, flush, square ends, and the card clipped to its own radius
/// so the band follows the corner. Full saturation is deliberate — this colour
/// is matching real tape wrapped on a real case, so it has to be recognisable
/// rather than tasteful.
///
/// Rainbow is a real tape colour (`KitTemplate.isRainbow`, special-cased in
/// three views), so a band drawn as a flat `Color(hex:)` would render garbage.
/// The gradient mirrors KitColorBorder's without its endless animation: a
/// colour spinning forever on every row of a list is a battery cost and a
/// distraction, and this is the right place to find out whether it is missed.
struct LabKitEdge: ViewModifier {
    /// A hex string, or the literal "rainbow", or nil for an item in no kit.
    let hex: String?
    let density: AmbientDensity

    private var isRainbow: Bool { hex?.lowercased() == "rainbow" }

    /// Branches on a value fixed at the call site — a row's kit does not change
    /// under it — so the `_ConditionalContent` identity switch cannot fire
    /// mid-animation. Same reasoning as `AmbientGlow`.
    func body(content: Content) -> some View {
        if let hex {
            content
                .overlay(alignment: .leading) {
                    Group {
                        if isRainbow {
                            Rectangle().fill(LabKitEdge.rainbow)
                        } else {
                            Rectangle().fill(Color(hex: hex))
                        }
                    }
                    .frame(width: 4)
                }
                // Clipping the CARD, not the band: this is what makes the band
                // follow the corner curve instead of overhanging it.
                .clipShape(RoundedRectangle(cornerRadius: density.cornerRadius,
                                            style: .continuous))
        } else {
            content
        }
    }

    static let rainbow = LinearGradient(
        colors: [.red, .orange, .yellow, .green, .blue, .purple],
        startPoint: .top, endPoint: .bottom)
}

extension View {
    /// Bind a card with a kit's tape colour. No-op when the thing is in no kit.
    func labKitEdge(_ hex: String?, density: AmbientDensity) -> some View {
        modifier(LabKitEdge(hex: hex, density: density))
    }
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

// MARK: - Kit detail — a packing list

struct EquipmentKitDetailMockup: View {
    let kit: LabKit
    let feature: Color
    let wash: Double

    /// Starts EMPTY, meaning nothing is collapsed. The app starts with
    /// everything collapsed, so a six-item kit opens on three headers.
    @State private var collapsed: Set<String> = []
    @State private var pushedItem: LabEquipmentItem?

    /// The app's own photography workflow order, carried over verbatim from
    /// KitDetailView.categorySortOrder. Cameras first, accessories last,
    /// Uncategorized dead last. Sorting these alphabetically would look
    /// identical in a screenshot and be wrong every time anyone packs a case.
    private static let workflowOrder: [String] = [
        "camera", "bodies", "lens", "light", "flash", "strobe",
        "stand", "tripod", "monopod", "bag", "case", "backdrop", "background",
        "battery", "power", "memory", "card", "storage", "audio", "mic", "accessori",
    ]

    private static func priority(_ name: String) -> Int {
        let lower = name.lowercased()
        for (index, keyword) in workflowOrder.enumerated() where lower.contains(keyword) {
            return index
        }
        if name == "Uncategorised" || name == "Uncategorized" { return 999 }
        return 998
    }

    private var groups: [(category: String, items: [LabEquipmentItem])] {
        Dictionary(grouping: kit.items) { $0.category ?? "Uncategorised" }
            .map { (category: $0.key, items: $0.value) }
            .sorted { Self.priority($0.category) < Self.priority($1.category) }
    }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: feature, intensity: wash)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header

                    AmbientSectionTitle("In this kit", trailing: "\(kit.itemCount)")
                    VStack(spacing: AmbientDensity.compact.stackSpacing) {
                        ForEach(groups, id: \.category) { group in
                            categorySection(group)
                        }
                    }

                    checkInButton.padding(.top, 6)

                    Text("Grouped in the order a case gets packed — cameras, lenses, lighting, stands, bags — which is the app's own sort and not alphabetical. Categories open expanded here; in the app they all start closed.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
        }
        .navigationTitle(kit.name)
        .navigationBarTitleDisplayMode(.inline)
        .ambientPush(item: $pushedItem) { EquipmentDetailMockup(item: $0, feature: feature, wash: wash) }
    }

    /// Compact rather than the app's centred 80pt hero: same content, far less
    /// of the fold spent before the first item you came here to look at.
    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 52, height: 52)
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 22)).foregroundStyle(.secondary)
                LabKitDot(kit: kit, size: 16).offset(x: 20, y: -20)
            }

            VStack(alignment: .leading, spacing: 4) {
                if let detail = kit.detail {
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    AmbientBadge(text: "\(kit.itemCount) items",
                                 systemImage: "cube.box.fill", tint: .secondary)
                    LabKitDueBadge(due: kit.due, spelledOut: true)
                }
                // The tape-colour reference line, kept: it is how you find the
                // case on a shelf.
                HStack(spacing: 6) {
                    LabKitDot(kit: kit, size: 12)
                    Text(kit.isRainbow ? "Rainbow tape" : "Tape colour")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .ambientCard(density: .roomy, state: .highlighted,
                     border: .hairline(feature.opacity(0.3)),
                     glow: feature, fillWidth: true)
    }

    private func categorySection(_ group: (category: String, items: [LabEquipmentItem])) -> some View {
        let isOpen = !collapsed.contains(group.category)
        return VStack(spacing: AmbientDensity.compact.stackSpacing) {
            Button {
                withAnimation(AmbientMotion.snappy) {
                    if isOpen { collapsed.insert(group.category) }
                    else { collapsed.remove(group.category) }
                }
                AmbientHaptics.selection()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: Self.icon(for: group.category))
                        .font(.footnote).foregroundStyle(.secondary).frame(width: 20)
                    Text(group.category).font(.footnote.weight(.semibold))
                    Text("\(group.items.count)")
                        .font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.bold)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                ForEach(group.items) { item in
                    Button { pushedItem = item } label: { LabEquipmentRow(item: item) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    /// Carried over from KitDetailView.categoryIcon.
    private static func icon(for category: String) -> String {
        let name = category.lowercased()
        if name.contains("camera") || name.contains("bodies") { return "camera.fill" }
        if name.contains("lens") { return "camera.aperture" }
        if name.contains("light") { return "light.max" }
        if name.contains("bag") || name.contains("case") || name.contains("transport") { return "bag.fill" }
        if name.contains("accessori") { return "gearshape.fill" }
        if name.contains("tripod") || name.contains("stand") || name.contains("support") { return "camera.on.rectangle.fill" }
        if name.contains("battery") || name.contains("power") { return "battery.100" }
        if name.contains("memory") || name.contains("card") || name.contains("media") { return "sdcard.fill" }
        if name.contains("audio") || name.contains("mic") { return "mic.fill" }
        if name.contains("backdrop") || name.contains("background") { return "rectangle.portrait.fill" }
        return "cube.box.fill"
    }

    private var checkInButton: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.to.line").font(.footnote.weight(.semibold))
                Text("Check in kit").font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 13)
            .background(Capsule().fill(feature))

            Text("Returns all \(kit.itemCount) items in this kit")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Item detail

/// Reordered against the app, which opens with a 250pt photo. You are usually
/// holding the object; what you cannot see by looking at it is whether it is
/// free, who has it, and when it is due. So that leads, and the photo becomes a
/// thumbnail beside it.
struct EquipmentDetailMockup: View {
    let item: LabEquipmentItem
    let feature: Color
    let wash: Double

    @State private var photoExpanded = false

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: feature, intensity: wash)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    headline
                    if let assignee = item.assignee { assignment(assignee) }
                    actions
                    specs
                    history
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headline: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(AmbientMotion.gentle) { photoExpanded.toggle() }
            } label: {
                photo
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.name)
                    .font(.system(size: 17, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    AmbientBadge(text: item.status.rawValue,
                                 systemImage: item.status.symbol, tint: item.status.color)
                    AmbientBadge(text: item.condition.rawValue, tint: item.condition.color)
                }
                if let kitName = item.kitName {
                    Label("In \(kitName)", systemImage: "shippingbox.fill")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .ambientCard(density: .roomy, state: .highlighted,
                     border: .hairline(item.status.color.opacity(0.35)),
                     glow: item.status.color, fillWidth: true)
    }

    private var photo: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primary.opacity(0.06))
            .frame(width: photoExpanded ? 150 : 68,
                   height: photoExpanded ? 150 : 68)
            .overlay {
                VStack(spacing: 4) {
                    Image(systemName: item.hasPhoto ? "camera.fill" : "circle.dashed")
                        .font(.system(size: photoExpanded ? 34 : 22, weight: .light))
                        .foregroundStyle(.tertiary)
                    if photoExpanded && !item.hasPhoto {
                        Text("No photo").font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
    }

    private func assignment(_ assignee: String) -> some View {
        HStack(spacing: 12) {
            AmbientAvatar(name: assignee, size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("Checked out to \(assignee)")
                    .font(.subheadline.weight(.semibold))
                Text(item.overdue ? "Was due \(item.dueLabel ?? "—")"
                                  : "Due back \(item.dueLabel ?? "Aug 2")")
                    .font(.caption)
                    .foregroundStyle(item.overdue ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
                if item.overdue {
                    Text("Left in the studio after the Riverside job")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .ambientCard(density: .roomy,
                     border: item.overdue ? .strong(Color.red.opacity(0.5))
                                          : .hairline(Color.primary.opacity(0.08)),
                     fillWidth: true)
    }

    /// CONDITIONAL, exactly as EquipmentDetailView has them. The first cut of
    /// this mockup drew all three all the time, which is a different screen:
    /// you cannot check out something somebody else is holding.
    private var actions: some View {
        VStack(spacing: 10) {
            if item.status == .available {
                action("Check out", systemImage: "arrow.up.to.line",
                       tint: feature, solid: true)
            }
            if item.status == .checkedOut && !item.mine {
                action("Request this", systemImage: "hand.raised.fill",
                       tint: feature, solid: false)
            }
            action("Report damage", systemImage: "exclamationmark.triangle.fill",
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
        .frame(maxWidth: .infinity).padding(.vertical, 13)
        .background {
            if solid { Capsule().fill(tint) } else { Capsule().fill(tint.opacity(0.14)) }
        }
    }

    /// Every field EquipmentDetailView renders, and it renders each only when
    /// present — so this list is short for a sparse item and long for a
    /// well-catalogued one.
    private var specs: some View {
        VStack(alignment: .leading, spacing: 0) {
            AmbientSectionTitle("Details").padding(.bottom, 8)
            spec("Category", item.category, "folder")
            spec("Serial number", item.serial, "number")
            spec("Description", item.detail, "text.alignleft")
            spec("Notes", item.notes, "note.text")
            spec("Purchase price", item.purchasePrice.map { String(format: "$%.2f", $0) },
                 "dollarsign.circle")
            spec("Purchased", item.purchaseDate, "calendar")
        }
        .ambientCard(density: .roomy, fillWidth: true)
    }

    @ViewBuilder
    private func spec(_ label: String, _ value: String?, _ symbol: String) -> some View {
        if let value {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol).font(.footnote)
                    .foregroundStyle(.secondary).frame(width: 18)
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

    private var history: some View {
        VStack(alignment: .leading, spacing: AmbientDensity.compact.stackSpacing) {
            AmbientSectionTitle("Assignment history")
            ForEach(DesignLabSampleData.crew.prefix(3)) { person in
                HStack(spacing: 10) {
                    AmbientAvatar(name: person.name, size: 26)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.name).font(.footnote.weight(.medium))
                        Text("Jun 14 – Jun 28").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Text("Returned").font(.caption2).foregroundStyle(.secondary)
                }
                .ambientCard(density: .compact, state: .receded, fillWidth: true)
            }
        }
    }
}
