//  TabBarMockup.swift
//  Iconik Employee — AMB.4's third mockup, second cut
//
//  ARC SCAFFOLDING. Deleted with the rest of the lab at AMB.12.
//
//  THE FIRST CUT WAS REJECTED, and the operator was right: "hate it, not really
//  any different". It swapped an opaque slab for a material and kept every other
//  decision the 2023 bar had made — same fixed-width cells, same underline, same
//  full-bleed rectangle. A restyle of a shape nobody had questioned.
//
//  THIS CUT IS PORTED FROM KeepUp's GlassSegmentedTabBar (the operator's own app,
//  ~/Desktop/KeepUP/KeepUp/App/GlassSegmentedTabBar.swift), read end to end
//  rather than described from memory. What it actually does:
//
//    A FLOATING CAPSULE, not a bar welded to the bottom edge. Inset 14pt from the
//      sides, 6pt off the bottom, with a real drop shadow under it. KeepUp's is
//      60pt tall; this one is 68 — see the centre-button note below for why.
//    REAL LIQUID GLASS on iOS 26 — .glassEffect(.clear, in: Capsule()), with a
//      separately adjustable frost layer behind it (see GlassCapsule).
//    A SELECTION PILL IT ANIMATES ITSELF, and the reason is the load-bearing
//      part: a material or a glassEffect CANNOT ANIMATE ITS POSITION, so a
//      glass pill that slides is impossible to get from the system. KeepUp
//      hand-builds the pill — accent fill at 30%, a top-down white sheen for
//      specular depth, a bright white rim — and slides it with an explicit ease.
//      They tried the native UISegmentedControl indicator first; it slides, but
//      its indicator is a flat solid fill with no glass, its timing is not
//      tunable, and its UIKit host composited OVER the SwiftUI pill at rest.
//    NEIGHBOURS MOVE. Icons either side of the selection nudge away from it by
//      7/distance, decaying outward, so the pill appears to part the row.
//    WIDTH DIVIDED BY COUNT. This is the operator's "holds more than the
//      official glass bar": the system TabView caps at five, this divides the
//      capsule by however many items there are.
//
//  WHAT IS ADAPTED FOR THIS APP RATHER THAN COPIED
//    THE PILL TAKES THE SELECTED FEATURE'S COLOUR, not one fixed accent. KeepUp
//      has a single amber; this app has 27 distinct feature colours since AMB.2,
//      and D11 makes a feature's colour mean something. So the pill changes hue
//      as it travels, and it agrees with the tile you tapped to get there.
//    SCAN AND iPAD HOME KEEP A DEDICATED CENTRE SLOT. NAV.1 made Scan permanent
//      and prominent on iPhone, and gave the iPad a big centre Home instead
//      (iPads have no NFC). Flattening either into an ordinary cell would lose a
//      deliberate navigation decision.
//
//      REVISED THREE TIMES against operator feedback, and the numbers here are
//      the current ones — the file's own history is in git, not in this comment.
//        1. The circle floated above the capsule's top edge while the cells
//           divided the whole width underneath, so items slid behind it.
//           -> vertically centred, with a RESERVED slot the cells step over.
//        2. On odd item counts the slot still sat half a cell right of centre,
//           which is what the LIVE bar does too. -> both sides now take an equal
//           half of the non-button width, so it is dead centre at every count.
//        3. Too small. -> glyph 52pt against 17pt for every other icon, in a 56pt
//           disc, inside a 76pt slot. The capsule grew 60 -> 68 to contain it with
//           6pt clear above and below, because it has to stay centred INSIDE the
//           glass.
//      One consequence, named rather than slipped in: today's Scan glyph is 60pt
//      on a 50pt circle — a deliberate overrun that worked because the button
//      stood proud of the bar. Centred inside the capsule an overrun would spill
//      past the glass, so the glyph nearly fills its disc instead of exceeding it.
//    DIVIDING BY COUNT ALSO FIXES A REAL BUG: today's cells are a fixed 50pt
//      with minimum-length spacers, so at the six items the customise screen
//      allows the bar is 438pt wide against 393pt on an iPhone 16.
//
//  THE DECISION THIS MOCKUP EXISTS TO SETTLE — see the "Reserves its space"
//  toggle. A floating bar means content scrolls UNDER it, which is what gives
//  glass something to refract and is the whole point of the look. It also means
//  the bar stops participating in layout, so every screen needs its own bottom
//  inset or its last row hides behind the capsule. This app has twenty-odd
//  screens and nine of them are unconverted. The toggle shows both, and the cost
//  of each is stated on screen.

import SwiftUI

/// The two genuinely different bars this app ships. Not a reflow of each other:
/// iPhone has a permanent centre Scan and no Home; iPad has a centre Home and no
/// Scan at all.
enum TabBarMockupLayout: String, CaseIterable, Identifiable {
    case iPhone, iPad
    var id: String { rawValue }
}

struct TabBarMockup: View {
    private typealias Layout = TabBarMockupLayout

    @State private var layout: Layout =
        UIDevice.current.userInterfaceIdiom == .pad ? .iPad : .iPhone
    @State private var itemCount: Double = 5
    @State private var showLabels = true
    @State private var floats = true
    @State private var showToday = false
    @State private var selected = "chat"
    @State private var unread = 3
    @State private var clockedIn = true
    /// Starts near the middle so there is room to go either way. The fixed
    /// `.regular` the operator called too frosted sits at about 1.0.
    @State private var frost: Double = 0.45

    /// Real feature ids, so `FeatureTheme` returns the colour the converted bar
    /// would actually use — including the ones that fall through to blue today.
    private let catalogue: [LabTabItem] = [
        .init(id: "timeTracking", title: "Time", symbol: "clock.fill"),
        .init(id: "chat", title: "Chat", symbol: "bubble.left.and.bubble.right.fill"),
        .init(id: "schedule", title: "Schedule", symbol: "calendar"),
        .init(id: "photoshootNotes", title: "Notes", symbol: "note.text"),
        .init(id: "equipment", title: "Equipment", symbol: "camera.fill"),
        .init(id: "tasks", title: "Tasks", symbol: "checklist"),
        .init(id: "classGroups", title: "Groups", symbol: "person.3"),
        .init(id: "mileageReports", title: "Mileage", symbol: "car.fill"),
        .init(id: "timeOffRequests", title: "Time Off", symbol: "calendar.badge.plus"),
        .init(id: "sportsShoot", title: "Sports", symbol: "sportscourt"),
    ]

    private var items: [LabTabItem] { Array(catalogue.prefix(Int(itemCount))) }

    private var maxItems: Double { layout == .iPad ? 10 : 6 }

    var body: some View {
        ZStack {
            AmbientBackdrop(tint: AmbientStyle.brand, intensity: 0.9)

            // Content BEHIND the bar. It exists so the glass has something real to
            // refract — judging a glass bar over a flat page tells you nothing,
            // which is part of why the first cut read as "not really different".
            ScrollView {
                VStack(spacing: 12) {
                    controls
                    ForEach(0..<8, id: \.self) { index in
                        filler(index)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                // Room for the floating capsule, so the last card can clear it.
                .padding(.bottom, floats ? 96 : 20)
            }

            VStack(spacing: 10) {
                Spacer()
                if showToday {
                    VStack(spacing: 4) {
                        Text("TODAY")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.secondary)
                        LegacyTabBarPreview(items: items, layout: layout,
                                            selected: $selected, showLabels: showLabels,
                                            unread: unread, clockedIn: clockedIn)
                    }
                }
                GlassTabBarPreview(items: items, layout: layout, selected: $selected,
                                   showLabels: showLabels, unread: unread,
                                   clockedIn: clockedIn, frost: frost)
            }
            // A bar that reserves its space sits flush; a floating one is inset.
            .padding(.bottom, floats ? 6 : 0)
        }
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            frostControl
            Divider().opacity(0.4)

            Picker("Layout", selection: $layout) {
                ForEach(Layout.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: layout) { _ in
                if itemCount > maxItems { itemCount = maxItems }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Items")
                        .font(.footnote.weight(.semibold))
                    Spacer()
                    Text("\(Int(itemCount)) of \(Int(maxItems))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $itemCount, in: 2...maxItems, step: 1)
                    .tint(AmbientStyle.brand)
                Text("Drag it to the maximum. The cells divide the capsule, so it never runs off the edge — today's bar is fixed 50pt cells and is 438pt wide at six items, against 393pt on an iPhone 16. This is also what \"holds more than the official glass bar\" means: the system tab bar stops at five.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().opacity(0.4)

            Toggle("Floats over the content", isOn: $floats)
                .font(.footnote.weight(.semibold))
                .tint(AmbientStyle.brand)
            Text(floats
                 ? "Content scrolls UNDER the glass, which is what makes it read as glass. THE COST: the bar stops participating in layout, so every screen needs its own bottom inset — about twenty screens here, nine of them not yet converted. Scroll this page and watch the cards pass beneath it."
                 : "The bar reserves its own space, exactly as it does today, so no other screen has to change. THE COST: nothing ever passes behind the glass, so it has little to refract and reads closer to a tinted panel.")
                .font(.caption2)
                .foregroundStyle(floats ? .orange : .secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider().opacity(0.4)

            Toggle("Show labels", isOn: $showLabels)
                .font(.footnote.weight(.semibold))
                .tint(AmbientStyle.brand)
            Toggle("Show today's bar above it", isOn: $showToday)
                .font(.footnote.weight(.semibold))
                .tint(AmbientStyle.brand)
            Toggle("Clocked in", isOn: $clockedIn)
                .font(.footnote.weight(.semibold))
                .tint(AmbientStyle.brand)
            Stepper("Unread: \(unread)", value: $unread, in: 0...120)
                .font(.footnote.weight(.semibold))

            Text(glassNote)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Note: the app's REAL bar is still at the very bottom of the screen, below the proposal — it is on every screen, including this one. The lowest bar you can see is the live one; the capsule above it is the proposal.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .ambientCard(density: .compact, fillWidth: true)
    }

    /// The one control that exists to be reported back rather than admired.
    private var frostControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "circle.lefthalf.filled")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AmbientStyle.brand)
                Text("Frost")
                    .font(.footnote.weight(.semibold))
                Spacer()
                Text("\(Int(frost * 100))%")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AmbientStyle.brand)
            }
            Slider(value: $frost, in: 0...1)
                .tint(AmbientStyle.brand)

            HStack(spacing: 0) {
                Text("0% bare glass")
                Spacer()
                Text("100% fully frosted")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            Text("Scroll the page while you drag it — frost only shows its worth against something moving underneath. TELL ME THE NUMBER and I will bake it in as a constant; the slider does not ship. For reference, the version you called too frosted was about 100%.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var glassNote: String {
        if #available(iOS 26.0, *) {
            return "This device is on iOS 26, so the capsule is REAL Liquid Glass (.glassEffect). The sliding pill is hand-built either way — a material cannot animate its position, which is why KeepUp draws its own."
        } else {
            return "This device is below iOS 26, so you are seeing the custom-glass fallback: material, a white sheen and a bright rim. The app's floor is iOS 16.6, so this path has to look right on its own — the real Liquid Glass only appears on 26."
        }
    }

    private func filler(_ index: Int) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(FeatureTheme.color(for: catalogue[index % catalogue.count].id).gradient)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text("Something on the screen behind the bar")
                    .font(.system(size: 14, weight: .semibold))
                Text("Scroll so this row passes under the capsule")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .ambientCard(density: .compact, fillWidth: true)
    }
}

// MARK: - Item

struct LabTabItem: Identifiable, Hashable {
    let id: String
    let title: String
    let symbol: String
}

// MARK: - The proposal

/// The floating glass bar, ported from KeepUp's `GlassSegmentedTabBar`.
///
/// Structure is theirs: a capsule of real glass on iOS 26, cells that divide the
/// width, and a pill this view positions and animates itself because the system
/// cannot animate a material's position. The pill's colour is this app's addition
/// — it takes the selected feature's colour so the bar agrees with the tile.
private struct GlassTabBarPreview: View {
    let items: [LabTabItem]
    let layout: TabBarMockupLayout
    @Binding var selected: String
    let showLabels: Bool
    let unread: Int
    let clockedIn: Bool
    let frost: Double

    /// iPad caps the row rather than sprawling across a 13-inch screen — KeepUp
    /// does the same at 560 for six items; this allows up to ten.
    private var maxWidth: CGFloat { layout == .iPad ? 720 : .infinity }

    /// The centre button that straddles the capsule: Scan on iPhone, Home on
    /// iPad. Never both — iPads have no NFC, so Scan does not exist there.
    private var centreID: String { layout == .iPad ? "home" : "scan" }
    private var centreSymbol: String { layout == .iPad ? "house.fill" : "wave.3.right.circle.fill" }

    /// Home is the container, not a feature, so it takes the brand colour; Scan
    /// takes its palette colour like any other feature.
    private var centreTint: Color {
        layout == .iPad ? AmbientStyle.brand : FeatureTheme.color(for: "scan")
    }

    private var accent: Color {
        selected == centreID ? centreTint : FeatureTheme.color(for: selected)
    }

    var body: some View {
        capsuleBar
        .frame(maxWidth: maxWidth)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 14)
        // The shadow is what makes it read as floating rather than painted on.
        .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 5)
        // Six labels cannot render at the largest accessibility sizes; KeepUp
        // bounds its bar's own text for the same reason while leaving content
        // fully scalable.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// Width reserved in the middle of the row for Scan (iPhone) or Home (iPad).
    ///
    /// It is a RESERVED SLOT, not an overlay. The first cut floated the circle
    /// above the capsule's top edge and let the cells divide the whole width
    /// underneath, so items slid behind it. Operator: centre it vertically, and
    /// keep the other icons out from under it.
    private var centreSlot: CGFloat { 76 }

    /// Taller than KeepUp's 60, and the reason is a constraint rather than a
    /// preference: the operator asked for Scan at least 30% bigger AND vertically
    /// centred in the bar, so the glass has to grow to contain it. 68 fits a 56pt
    /// disc with 6pt clear above and below.
    private var barHeight: CGFloat { 68 }

    private var capsuleBar: some View {
        GeometryReader { geo in
            let count = max(items.count, 1)
            let selectedIndex = items.firstIndex(where: { $0.id == selected })

            // THE CENTRE BUTTON IS DEAD CENTRE, ALWAYS — operator, 2026-07-25.
            //
            // The obvious split (extra item on the left for odd counts, which is
            // what the live bar does) leaves the slot off-centre by half a cell:
            // at five items on an iPhone that is about 30pt right of the middle.
            // So instead BOTH SIDES GET AN EQUAL HALF of the remaining width,
            // sized for whichever side holds more items, and the lighter side
            // centres its cells inside its half. Cells stay a uniform width and
            // the button never moves.
            let perSide = max((count + 1) / 2, count / 2)
            let cellWidth = max((geo.size.width - centreSlot) / CGFloat(perSide * 2), 1)
            let halfWidth = cellWidth * CGFloat(perSide)
            let leftCount = (count + 1) / 2
            let rightCount = count - leftCount
            // The lighter side is inset so its group stays centred in its half.
            let leftInset = halfWidth - cellWidth * CGFloat(leftCount)
            let rightInset = (halfWidth - cellWidth * CGFloat(rightCount)) / 2

            // Each cell's leading edge. Precomputed rather than a local function,
            // which a ViewBuilder closure forbids.
            let cellOrigins = (0..<count).map { index -> CGFloat in
                index < leftCount
                    ? leftInset + cellWidth * CGFloat(index)
                    : halfWidth + centreSlot + rightInset
                      + cellWidth * CGFloat(index - leftCount)
            }

            // Wider than a cell so a long label fits, then clamped so it can never
            // slide past the capsule's rounded ends.
            let pillWidth = cellWidth + 8
            let idealPillX = (selectedIndex.map { cellOrigins[$0] } ?? 0) - 4
            let pillX = min(max(idealPillX, 0), max(geo.size.width - pillWidth, 0))
            // How far the clamp moved it. The selected icon shifts by the same
            // amount so it stays centred IN the pill on the end cells.
            let pillShift = pillX - idealPillX
            let onCentre = selected == centreID

            ZStack(alignment: .leading) {
                // Hand-built glass pill. NOT a material: a material cannot animate
                // its position, and without the slide this is just a highlight.
                Capsule()
                    .fill(accent.opacity(0.30))
                    .overlay(
                        Capsule().fill(
                            .linearGradient(colors: [.white.opacity(0.5), .white.opacity(0.0)],
                                            startPoint: .top, endPoint: .bottom)
                        )
                    )
                    .overlay(Capsule().strokeBorder(.white.opacity(0.55), lineWidth: 1))
                    .frame(width: pillWidth, height: geo.size.height - 10)
                    .offset(x: pillX)
                    // Hidden, not removed, while the centre button owns the
                    // selection — so it slides back from where it left rather
                    // than reappearing at cell zero.
                    .opacity(onCentre ? 0 : 1)

                // Everything is placed from `cellOrigins`, the same numbers the
                // pill uses, so the highlight can never land off its cell. Laying
                // this out with nested stacks and spacers is what let the two
                // halves drift apart in the previous cut.
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    cell(item, pillShift: pillShift, isSelected: item.id == selected)
                        .frame(width: cellWidth, height: geo.size.height)
                        .offset(x: cellOrigins[index])
                }

                // Its slot begins where the left half ends, so its centre is
                // halfWidth + centreSlot/2 — exactly the bar's midpoint.
                centreButton
                    .frame(width: centreSlot, height: geo.size.height)
                    .offset(x: halfWidth)
            }
        }
        .frame(height: barHeight)
        .modifier(GlassCapsule(frost: frost))
    }

    private func cell(_ item: LabTabItem, pillShift: CGFloat, isSelected: Bool) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.4)) { selected = item.id }
            AmbientHaptics.impact(.light)
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(height: 18)
                    badge(for: item)
                }
                if showLabels {
                    Text(item.title)
                        .font(.system(size: 9, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            .foregroundStyle(isSelected ? FeatureTheme.color(for: item.id) : Color.secondary)
            // The selected icon rides the clamped pill; the others part around it,
            // strongest next to the selection and decaying outward. Visual only —
            // the tappable cell does not move.
            .offset(x: isSelected ? pillShift : pushOffset(for: item))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func badge(for item: LabTabItem) -> some View {
        if item.id == "chat", unread > 0 {
            Text(unread > 99 ? "99+" : "\(unread)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5).padding(.vertical, 1.5)
                .background(Capsule().fill(Color.red))
                .offset(x: 13, y: -7)
        } else if item.id == "timeTracking", clockedIn {
            Circle().fill(Color.green)
                .frame(width: 7, height: 7)
                .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 0.5))
                .offset(x: 10, y: -5)
        }
    }

    /// Nudge away from the selection, strongest for the immediate neighbours and
    /// decaying with distance. Ported verbatim.
    private func pushOffset(for item: LabTabItem) -> CGFloat {
        guard let selectedIndex = items.firstIndex(where: { $0.id == selected }),
              let itemIndex = items.firstIndex(of: item) else { return 0 }
        let distance = itemIndex - selectedIndex
        guard distance != 0 else { return 0 }
        return (distance > 0 ? 1 : -1) * 7 / CGFloat(abs(distance))
    }

    private var centreButton: some View {
        let isSelected = selected == centreID
        return Button {
            withAnimation(.easeInOut(duration: 0.4)) { selected = centreID }
            AmbientHaptics.impact(.medium)
        } label: {
            ZStack {
                Circle()
                    .fill(isSelected ? AnyShapeStyle(centreTint.gradient)
                                     : AnyShapeStyle(centreTint.opacity(0.16)))
                    .overlay(Circle().strokeBorder(.white.opacity(isSelected ? 0.55 : 0.3),
                                                   lineWidth: 1))
                    // 56 inside a 68pt bar leaves 6pt above and below, so it is
                    // genuinely centred rather than clipped by the capsule.
                    .frame(width: 56, height: 56)
                Image(systemName: centreSymbol)
                    // DELIBERATELY THE LARGEST THING ON THE BAR, and then grown
                    // another 30% on top of that (operator, 2026-07-25). 40 -> 52
                    // against 17pt for every other icon, so it is now three times
                    // their size and nearly fills its disc — the same read as the
                    // live bar's 60pt glyph on a 50pt circle, without overrunning
                    // it, since centred inside the capsule an overrun would spill
                    // past the glass.
                    .font(.system(size: layout == .iPad ? 40 : 52, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : centreTint)
            }
            // Centred in its slot, vertically and horizontally.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(layout == .iPad ? "Home" : "Scan")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Real Liquid Glass on iOS 26; a custom-glass capsule below it, because this
/// app's floor is iOS 16.6 and the fallback has to stand on its own rather than
/// being a degraded afterthought (AMB plan, D4).
/// Real Liquid Glass on iOS 26; a custom-glass capsule below it, because this
/// app's floor is iOS 16.6 and the fallback has to stand on its own rather than
/// being a degraded afterthought (AMB plan, D4).
///
/// FROST IS A DIAL, not a variant, so the operator can settle it by eye and hand
/// back a number (their request, 2026-07-25 — the previous fixed `.regular` was
/// too much). The base is always the CLEAREST glass available, and `frost` adds a
/// diffusing layer behind it: 0 is bare glass, 1 is fully frosted. Continuous and
/// monotonic, and it behaves the same on both OS paths so tuning on either device
/// transfers to the other.
///
/// Once a value is chosen this collapses to a constant — a slider is not shipping
/// in the real bar.
private struct GlassCapsule: ViewModifier {
    let frost: Double

    func body(content: Content) -> some View {
        content
            // Behind the glass, so what shows THROUGH the bar is diffused rather
            // than the bar being painted over.
            .background(Capsule().fill(.regularMaterial).opacity(frost))
            .modifier(BaseGlass())
            .overlay(
                Capsule().fill(
                    .linearGradient(colors: [.white.opacity(0.28), .white.opacity(0.0)],
                                    startPoint: .top, endPoint: .bottom)
                )
                .allowsHitTesting(false)
            )
            .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 0.8))
    }
}

/// The clearest glass each OS can give. KeepUp uses `.clear` for the same reason:
/// it is the honest base, and anything frostier is a decision on top of it.
private struct BaseGlass: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.clear, in: Capsule())
        } else {
            content.background(.ultraThinMaterial, in: Capsule())
        }
    }
}

// MARK: - Today, for comparison

/// Today's bar, reproduced faithfully — opaque slab, fixed 50pt cells, the
/// hardcoded colour map with its fall-through to blue, and the underline. Drawn
/// so the before/after is honest rather than flattering.
private struct LegacyTabBarPreview: View {
    let items: [LabTabItem]
    let layout: TabBarMockupLayout
    @Binding var selected: String
    let showLabels: Bool
    let unread: Int
    let clockedIn: Bool

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                cell(item)
                    // Fixed width — the thing that makes it overflow at six.
                    .frame(width: layout == .iPad ? 60 : 50)
            }
        }
        .padding(.top, 7)
        .padding(.horizontal, 4)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        // ambient-allow: the BEFORE half of a before/after. Deliberately the live
        // bar's opaque slab and upward shadow, so the comparison is truthful.
        .background(Color(.systemBackground).shadow(color: .black.opacity(0.1),
                                                    radius: 10, x: 0, y: -5))
        .overlay(alignment: .top) {
            Rectangle().fill(Color(.separator)).frame(height: 0.5)
        }
    }

    /// TabBarButton.accentColor, verbatim — seven ids and blue for everything else.
    private func legacyTint(_ id: String) -> Color {
        switch id {
        case "timeTracking": return .cyan
        case "chat": return .blue
        case "scan": return .orange
        case "photoshootNotes": return .purple
        case "dailyJobReport": return .green
        case "sportsShoot": return .indigo
        case "equipment": return .cyan
        default: return .blue
        }
    }

    private func cell(_ item: LabTabItem) -> some View {
        let isSelected = selected == item.id
        let accent = legacyTint(item.id)
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { selected = item.id }
        } label: {
            VStack(spacing: 2) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 24))
                        .scaleEffect(isSelected ? 1.1 : 1)
                    if item.id == "chat", unread > 0 {
                        Text(unread > 99 ? "99+" : "\(unread)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.red))
                            .offset(x: 12, y: -8)
                    } else if item.id == "timeTracking", clockedIn {
                        Circle().fill(Color.green).frame(width: 8, height: 8)
                            .offset(x: 10, y: -6)
                    }
                }
                .frame(width: 44, height: 32)
                .foregroundStyle(isSelected ? accent : Color.gray)

                if showLabels {
                    Text(item.title)
                        .font(.system(size: 10))
                        .foregroundStyle(isSelected ? accent : Color.gray)
                        .lineLimit(1).minimumScaleFactor(0.8)
                }
                if isSelected {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(accent)
                        .frame(width: 20, height: 3)
                        .matchedGeometryEffect(id: "legacyTabSelection", in: namespace)
                } else {
                    Color.clear.frame(width: 20, height: 3)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
