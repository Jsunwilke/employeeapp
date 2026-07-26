//  BottomTabBar.swift
//  Iconik Employee — the app's bottom navigation (AMB.4)
//
//  A FLOATING GLASS CAPSULE, converted 2026-07-25 from the opaque full-width slab
//  this had been since NAV.1. The design was approved on a device after four
//  rounds of operator feedback; the mockup it was ported from is
//  DesignLab/Mockups/TabBarMockup.swift and STAYS until the port is confirmed on
//  both devices, because a validation reference outlives the phase, not the port.
//
//  WHY THIS FILE WAS THE LAST THING IN THE APP TO BE CONVERTED, which is the part
//  worth remembering: it belonged to NO PHASE. The AMB arc's phase list is
//  organised by FEATURE, and this bar is nav-shell furniture that appears on every
//  screen, so it matched no entry. The card-drift gate could not catch it either —
//  it looks for hand-rolled CARDS and a full-width bar is not one. Two independent
//  mechanisms for finding unconverted surfaces, both blind to it. It surfaced only
//  because the operator looked at the app and asked why it had not changed.
//
//  THE SHAPE, ported from the operator's own KeepUp app (GlassSegmentedTabBar):
//    A capsule inset from the screen edges with a real shadow, not a bar welded to
//      the bottom. Real Liquid Glass on iOS 26, custom glass below it (the app's
//      floor is 16.6 and the fallback has to stand on its own — D4).
//    A SELECTION PILL THIS VIEW ANIMATES ITSELF. The load-bearing reason: a
//      material or a glassEffect CANNOT ANIMATE ITS POSITION, so a glass pill that
//      slides cannot be got from the system at all. It is hand-built — tint at
//      30%, a top-down white sheen for specular depth, a bright rim — and moved
//      with an explicit ease.
//    CELLS DIVIDE THE WIDTH. The system tab bar caps at five; this holds whatever
//      the customise screen allows. It also fixes a real bug: the old cells were a
//      fixed 50pt with minimum-length spacers, so at the six items that screen
//      permits the bar was 438pt wide against 393pt on an iPhone 16.
//    NEIGHBOURS PART around the selection, decaying with distance.
//
//  ADAPTED FOR THIS APP RATHER THAN COPIED:
//    THE PILL TAKES THE SELECTED FEATURE'S COLOUR. KeepUp has one amber; this app
//      has 27 distinct feature colours since AMB.2 and D11 makes a feature's
//      colour mean something, so the bar agrees with the tile you tapped.
//    AND THAT CLOSES A THREE-PHASE-OLD MISTAKE. The plan's D11 claimed re-cutting
//      the palette in AMB.2 changed this bar. It did not: FeatureTheme appeared in
//      this file exactly once, inside the CUSTOMISE screen. The bar itself coloured
//      from a fourth hardcoded map covering seven ids and defaulting the rest to
//      blue, so the tile you tapped and the item you landed on disagreed for nearly
//      every feature — Tasks was not in the map at all. That map is gone.
//    ONE BAR, NOT TWO (operator: "the ipad bar should be exactly like the iphone
//      except the scan button is a home button"). They used to differ in icon
//      sizes and carry a hairline notched around the iPad's circle. Now everything
//      is shared except what behaviour requires: which destination the centre
//      button goes to, its colour, the item cap the device allows, and a width cap
//      that keeps the iPad row phone-sized.
//
//  TUCK, the operator's idea, and it replaced hide-on-scroll. Swipe the bar right
//  and it slides off the edge leaving a handle; tap the handle or swipe it left to
//  bring it back. Navigation is never taken away by the app — it is put away by
//  the person, deliberately, and the way back is always visible. Hide-on-scroll was
//  built first and dropped on the operator's own reasoning: "navigation is more
//  important."
//
//  ON iPAD THE HANDLE IS THE ONLY WAY HOME. HomeToolbarButton is iPhone-only,
//  because on iPad Home IS this bar's centre button — so from any feature screen
//  the bar is the sole route back. The handle is therefore not a convenience and
//  must never be dismissible or hard to hit.

import SwiftUI

// MARK: - Geometry

/// The bar's numbers, in one place because several of them are load-bearing and
/// the shell needs two of them to reserve the right amount of room.
enum TabBarMetrics {
    /// Taller than KeepUp's 60 so the centre button can be clearly the largest
    /// thing on the bar and still sit fully INSIDE the glass rather than breaking
    /// its edge.
    static let height: CGFloat = 68
    /// Reserved in the middle of the row for Scan (iPhone) or Home (iPad). A slot
    /// the cells step over, not an overlay they slide beneath.
    static let centreSlot: CGFloat = 76
    static let centreDisc: CGFloat = 56
    static let horizontalInset: CGFloat = 14
    static let bottomInset: CGFloat = 6
    /// Keeps the iPad row phone-sized instead of sprawling across a 13-inch
    /// screen. KeepUp's own number, and it lands in the same place: ten items on
    /// iPad give 45.6pt cells against 45.2pt for six on a 375pt iPhone.
    static let iPadMaxWidth: CGFloat = 560
    /// Settled by the operator on a slider at 50%. The base is the clearest glass
    /// each OS can give and this adds diffusion behind it.
    static let frost: Double = 0.5

    /// What a screen must leave clear at the bottom so its last row is not trapped
    /// under the capsule. Read by the shell.
    static var clearance: CGFloat { height + bottomInset + 10 }
}

extension View {
    /// Leaves room at the bottom for the floating bar, so a screen's last row can
    /// be scrolled clear of it while content still travels underneath.
    ///
    /// MUST BE APPLIED INSIDE THE SCREEN'S OWN `NavigationView`. The first version
    /// of this put the inset on the shell's content group, OUTSIDE the navigation
    /// containers, and it did nothing at all: the operator could not pull the "All
    /// Features" row far enough to clear the bar because nothing was inset and the
    /// over-scroll simply sprang back. A legacy `NavigationView` does not carry an
    /// externally applied safe-area inset down to the scroll view inside it.
    func tabBarClearance(_ active: Bool) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            if active {
                Color.clear.frame(height: TabBarMetrics.clearance)
            }
        }
    }

    /// For a SELF-NAV feature — one that builds its own navigation container, so the
    /// shell cannot reach inside it. Apply to the container's CONTENT, not to the
    /// feature view from outside; outside is the position that silently did nothing.
    ///
    /// Watches the shell itself rather than taking a flag, because these features are
    /// not handed one.
    func tabBarClearance() -> some View {
        modifier(SelfNavTabBarClearance())
    }
}

/// Reads the shell's own state so a self-nav feature does not have to be told.
private struct SelfNavTabBarClearance: ViewModifier {
    @ObservedObject private var tabBarManager = TabBarManager.shared

    func body(content: Content) -> some View {
        content.tabBarClearance(!tabBarManager.isFullScreenOverlayActive)
    }
}

// MARK: - The bar

struct BottomTabBar: View {
    @Binding var selectedTab: String
    @ObservedObject var tabBarManager: TabBarManager
    @ObservedObject var chatManager: ChatManager
    let timeTrackingService: TimeTrackingService

    @Namespace private var namespace
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Tucked away by hand. Deliberately NOT persisted: a tuck is a momentary "get
    /// out of my way", not a setting that outlives the screen it was made on.
    @State private var tucked = false
    /// Live finger travel, so the bar follows the drag rather than snapping at the end.
    @State private var dragX: CGFloat = 0

    /// Matches the predicate the rest of the app uses for its iPad layouts, and it
    /// is the DEVICE rather than the size class on purpose: an iPad in a narrow
    /// split view still has no NFC, so Scan still must not appear there.
    private var isIPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private var items: [TabBarItem] { tabBarManager.getQuickAccessItemsExcludingScan() }

    /// Scan on iPhone, Home on iPad — never both. iPads have no NFC, which is why
    /// `getScanItem()` returns nil there, so the centre slot goes to Home instead.
    private var centreID: String { isIPad ? "home" : "scan" }

    private var centreSymbol: String {
        // Both are the `.circle.fill` variant so the two bars' centre buttons read
        // identically. Scan's symbol is a filled circle that fills its disc at
        // 52pt; a plain `house.fill` at that size is a wide, short glyph that would
        // either clip the disc or float inside it.
        isIPad ? "house.circle.fill" : "wave.3.right.circle.fill"
    }

    /// Home takes the company blue because it is the CONTAINER rather than a
    /// feature — the same reasoning that gives the home dashboard its wash (D11).
    /// Scan is a feature and takes its palette colour like any other.
    private var centreTint: Color {
        isIPad ? AmbientStyle.brand : FeatureTheme.color(for: "scan")
    }

    private var accent: Color {
        selectedTab == centreID ? centreTint : FeatureTheme.color(for: selectedTab)
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            capsule
                .offset(x: tucked ? tuckedTravel : dragX)
                .gesture(tuckDrag)

            if tucked { handle }
        }
        .padding(.horizontal, TabBarMetrics.horizontalInset)
        .padding(.bottom, TabBarMetrics.bottomInset)
        // Any navigation brings it back. HomeToolbarButton works by setting
        // selectedTab, so this covers the top-left Home button and equally a
        // dashboard widget's "View all" or anything else that navigates.
        .onChange(of: selectedTab) { _ in
            if tucked {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { tucked = false }
            }
        }
    }

    // MARK: capsule

    private var capsule: some View {
        GeometryReader { geo in
            let count = max(items.count, 1)
            let selectedIndex = items.firstIndex { $0.id == selectedTab }

            // THE CENTRE BUTTON IS DEAD CENTRE AT EVERY ITEM COUNT. Splitting the
            // row with the extra item on the left — which is what this bar used to
            // do — leaves the slot half a cell right of the middle on any odd
            // count, about 30pt out at five items. So both sides take an EQUAL half
            // of the remaining width, sized for whichever side holds more, and the
            // lighter side centres its cells inside its half.
            let perSide = max((count + 1) / 2, count / 2)
            let cellWidth = max((geo.size.width - TabBarMetrics.centreSlot) / CGFloat(perSide * 2), 1)
            let halfWidth = cellWidth * CGFloat(perSide)
            let leftCount = (count + 1) / 2
            let rightCount = count - leftCount
            let leftInset = halfWidth - cellWidth * CGFloat(leftCount)
            let rightInset = (halfWidth - cellWidth * CGFloat(rightCount)) / 2

            // One array of origins, used by the cells AND the pill, so the
            // highlight can never land off the cell it is meant to mark.
            let origins = (0..<count).map { index -> CGFloat in
                index < leftCount
                    ? leftInset + cellWidth * CGFloat(index)
                    : halfWidth + TabBarMetrics.centreSlot + rightInset
                      + cellWidth * CGFloat(index - leftCount)
            }

            let pillWidth = cellWidth + 8
            let idealPillX = (selectedIndex.map { origins[$0] } ?? 0) - 4
            let pillX = min(max(idealPillX, 0), max(geo.size.width - pillWidth, 0))
            let pillShift = pillX - idealPillX

            ZStack(alignment: .leading) {
                pill(width: pillWidth, height: geo.size.height - 10)
                    .offset(x: pillX)
                    // Hidden rather than removed, so it slides back from where it
                    // left. TWO cases hide it: the centre button owns the
                    // selection, or THE CURRENT SCREEN IS NOT IN THE BAR — which is
                    // the common case, not an edge. The app has 27 features and the
                    // bar holds at most six, so any of the other twenty-one, plus
                    // Home itself on iPhone, leaves nothing here selected.
                    .opacity(selectedIndex == nil ? 0 : 1)

                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    cell(item, pillShift: pillShift)
                        .frame(width: cellWidth, height: geo.size.height)
                        .offset(x: origins[index])
                }

                centreButton
                    .frame(width: TabBarMetrics.centreSlot, height: geo.size.height)
                    .offset(x: halfWidth)
            }
        }
        .frame(height: TabBarMetrics.height)
        .frame(maxWidth: isIPad ? TabBarMetrics.iPadMaxWidth : .infinity)
        .frame(maxWidth: .infinity)
        .modifier(GlassCapsule(frost: TabBarMetrics.frost))
        // What makes it read as floating rather than painted on.
        .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 5)
        // Several labels cannot render at the largest accessibility sizes; the
        // bar's own text is bounded so navigation stays usable while screen
        // content remains fully scalable.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    /// Hand-built, NOT a material — a material cannot animate its position, and
    /// without the slide this is just a highlight.
    private func pill(width: CGFloat, height: CGFloat) -> some View {
        Capsule()
            .fill(accent.opacity(0.30))
            .overlay(
                Capsule().fill(
                    .linearGradient(colors: [.white.opacity(0.5), .white.opacity(0.0)],
                                    startPoint: .top, endPoint: .bottom)
                )
            )
            .overlay(Capsule().strokeBorder(.white.opacity(0.55), lineWidth: 1))
            .frame(width: width, height: height)
    }

    private func cell(_ rawItem: TabBarItem, pillShift: CGFloat) -> some View {
        let item = updatedItem(rawItem)
        let isSelected = selectedTab == item.id
        return Button {
            select(item.id, haptic: .light)
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .frame(height: 18)
                    badge(for: item)
                }
                if tabBarManager.configuration.showLabels {
                    Text(item.title)
                        .font(.system(size: 9, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            .foregroundStyle(isSelected ? FeatureTheme.color(for: item.id) : Color.secondary)
            // The selected icon rides the clamped pill so it stays centred in it;
            // the others part around the selection, strongest alongside it and
            // decaying outward. Visual only — the tappable cell does not move.
            .offset(x: isSelected ? pillShift : pushOffset(for: item))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityHint(item.description)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private func badge(for item: TabBarItem) -> some View {
        if let badgeValue = item.badgeValue {
            Text(badgeValue)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 5).padding(.vertical, 1.5)
                .background(Capsule().fill(Color.red))
                .offset(x: 13, y: -7)
                .transition(.scale.combined(with: .opacity))
        } else if item.showDot {
            // Green means clocked in; red is anything else that wants attention.
            Circle()
                .fill(item.badgeType == .active ? Color.green : Color.red)
                .frame(width: 7, height: 7)
                .overlay(Circle().strokeBorder(.white.opacity(0.7), lineWidth: 0.5))
                .offset(x: 10, y: -5)
                .transition(.scale.combined(with: .opacity))
        }
    }

    private var centreButton: some View {
        let isSelected = selectedTab == centreID
        return Button {
            select(centreID, haptic: .medium)
        } label: {
            ZStack {
                Circle()
                    .fill(isSelected ? AnyShapeStyle(centreTint.gradient)
                                     : AnyShapeStyle(centreTint.opacity(0.16)))
                    .overlay(Circle().strokeBorder(.white.opacity(isSelected ? 0.55 : 0.3),
                                                   lineWidth: 1))
                    .frame(width: TabBarMetrics.centreDisc, height: TabBarMetrics.centreDisc)
                Image(systemName: centreSymbol)
                    // Deliberately the largest thing on the bar: 52pt against 17pt
                    // for every other icon. It nearly fills its disc, the same read
                    // as the old 60pt-glyph-on-a-50pt-circle, without overrunning —
                    // centred inside the capsule an overrun would spill past the glass.
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : centreTint)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isIPad ? "Home" : "Scan")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Nudge away from the selection, strongest for the immediate neighbours and
    /// decaying with distance.
    private func pushOffset(for item: TabBarItem) -> CGFloat {
        guard let selectedIndex = items.firstIndex(where: { $0.id == selectedTab }),
              let itemIndex = items.firstIndex(where: { $0.id == item.id }) else { return 0 }
        let distance = itemIndex - selectedIndex
        guard distance != 0 else { return 0 }
        return (distance > 0 ? 1 : -1) * 7 / CGFloat(abs(distance))
    }

    private func select(_ id: String, haptic: UIImpactFeedbackGenerator.FeedbackStyle) {
        withAnimation(.easeInOut(duration: 0.4)) { selectedTab = id }
        AmbientHaptics.impact(haptic)
    }

    // MARK: tuck

    /// Far enough to clear the widest screen this app runs on.
    private var tuckedTravel: CGFloat { 1400 }

    /// Right to tuck, and only while shown, so the gesture can never fight a
    /// scroll view or drag the bar off the wrong edge.
    private var tuckDrag: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !tucked else { return }
                dragX = max(0, value.translation.width)
            }
            .onEnded { value in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    // A third of the way, or a decisive flick, commits it.
                    if !tucked,
                       value.translation.width > 90 || value.predictedEndTranslation.width > 180 {
                        tucked = true
                    }
                    dragX = 0
                }
                AmbientHaptics.impact(.light)
            }
    }

    /// The way back. On iPad this is the ONLY route home from a feature screen, so
    /// it is never dismissible and never smaller than a comfortable target.
    private var handle: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { tucked = false }
            AmbientHaptics.impact(.light)
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(AmbientStyle.brand)
                .frame(width: 26, height: 54)
                .background(
                    // Rounded on the inside only, flat against the screen edge, so
                    // it reads as something tucked BEHIND the edge rather than a
                    // button floating near it.
                    handleShape.fill(.regularMaterial)
                )
                .overlay(handleShape.strokeBorder(.white.opacity(0.35), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.18), radius: 8, x: -2, y: 3)
                // Extends the tappable area past the visible sliver, because the
                // visible part is deliberately small and this is load-bearing
                // navigation on iPad.
                .contentShape(Rectangle().inset(by: -10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show navigation bar")
        .gesture(
            DragGesture(minimumDistance: 10).onEnded { value in
                if value.translation.width < -30 {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { tucked = false }
                    AmbientHaptics.impact(.light)
                }
            }
        )
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private var handleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 27, bottomLeadingRadius: 27,
                               bottomTrailingRadius: 0, topTrailingRadius: 0,
                               style: .continuous)
    }

    // MARK: badges

    /// Live badge values. Unchanged from before the conversion: chat carries its
    /// unread count, time tracking carries a dot while clocked in.
    private func updatedItem(_ item: TabBarItem) -> TabBarItem {
        var updated = item
        switch item.id {
        case "chat":
            updated.badgeType = chatManager.totalUnreadCount > 0
                ? .count(chatManager.totalUnreadCount) : .none
        case "timeTracking":
            updated.badgeType = timeTrackingService.isClockIn ? .active : .none
        default:
            break
        }
        return updated
    }
}

// MARK: - Glass

/// Real Liquid Glass on iOS 26; custom glass below it, because the app's floor is
/// iOS 16.6 and the fallback has to stand on its own rather than be a degraded
/// afterthought (D4).
///
/// `frost` sits behind the glass so what shows THROUGH the bar is diffused rather
/// than the bar being painted over. Settled at 50% by the operator on a slider in
/// the mockup, after a fixed `.regular` read as too heavy over the ambient wash.
private struct GlassCapsule: ViewModifier {
    let frost: Double

    func body(content: Content) -> some View {
        content
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

// MARK: - Tab Bar Configuration View
struct TabBarConfigurationView: View {
    @ObservedObject var tabBarManager: TabBarManager
    @ObservedObject var mainViewModel: MainEmployeeViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var availableFeatures: [FeatureItem] = []
    @State private var selectedFeatures: [TabBarItem] = []
    @State private var editMode: EditMode = .active
    
    var body: some View {
        VStack(spacing: 0) {
                // Header with instructions and count
                VStack(spacing: 8) {
                    let isIPad = UIDevice.current.userInterfaceIdiom == .pad
                    let maxItems = tabBarManager.getMaxItemsForDevice()
                    
                    Text("Select up to \(maxItems) features for quick access")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if !isIPad {
                        Text("Scan is always included")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .italic()
                    }
                    
                    Text("\(selectedFeatures.count) of \(maxItems) selected")
                        .font(.caption)
                        .foregroundColor(selectedFeatures.count >= maxItems ? .red : .secondary)
                        .fontWeight(selectedFeatures.count >= maxItems ? .semibold : .regular)
                }
                .padding()
                
                // Single combined list
                List {
                    // Selected features (reorderable)
                    ForEach(selectedFeatures) { item in
                        HStack {
                            Image(systemName: item.systemImage)
                                .foregroundColor(.white)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(featureColorFor(item.id)))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.headline)
                                Text(item.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.leading, 8)
                            
                            Spacer()
                            
                            // Show minus button
                            Button(action: {
                                removeFeature(item)
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.title2)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .padding(.vertical, 4)
                    }
                    .onMove(perform: moveSelectedFeatures)
                    
                    // Available features (not selected)
                    ForEach(availableFeatures) { feature in
                        if !selectedFeatures.contains(where: { $0.id == feature.id }) {
                            HStack {
                                Image(systemName: feature.systemImage)
                                    .foregroundColor(.white)
                                    .frame(width: 30, height: 30)
                                    .background(Circle().fill(featureColorFor(feature.id)))
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feature.title)
                                        .font(.headline)
                                    Text(feature.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.leading, 8)
                                
                                Spacer()
                                
                                let maxItems = tabBarManager.getMaxItemsForDevice()
                                Button(action: {
                                    addFeature(feature)
                                }) {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(selectedFeatures.count >= maxItems ? .gray : .green)
                                        .font(.title2)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(selectedFeatures.count >= maxItems)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
                .environment(\.editMode, $editMode)
        }
        .navigationTitle("Customize Tab Bar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
        .onAppear {
            loadFeatures()
        }
    }
    
    private func loadFeatures() {
        // Combine all features but exclude scan since it's always present
        availableFeatures = (mainViewModel.defaultEmployeeFeatures + [
            FeatureItem(id: "chat", title: "Chat", systemImage: "bubble.left.and.bubble.right.fill", description: "Message your team"),
            FeatureItem(id: "timeOffRequests", title: "Time Off", systemImage: "calendar.badge.plus", description: "Request time off")
        ]).filter { $0.id != "scan" } // Exclude scan from available features
        
        // Load current configuration excluding scan
        selectedFeatures = tabBarManager.getQuickAccessItemsExcludingScan()
    }
    
    private func addFeature(_ feature: FeatureItem) {
        let maxItems = tabBarManager.getMaxItemsForDevice()
        guard selectedFeatures.count < maxItems else { return }
        
        let tabItem = TabBarItem(
            from: feature,
            order: selectedFeatures.count,
            isQuickAccess: true
        )
        selectedFeatures.append(tabItem)
        saveConfiguration() // Save immediately
    }
    
    private func removeFeature(_ item: TabBarItem) {
        selectedFeatures.removeAll { $0.id == item.id }
        
        // Update order
        selectedFeatures = selectedFeatures.enumerated().map { index, item in
            TabBarItem(
                id: item.id,
                title: item.title,
                systemImage: item.systemImage,
                description: item.description,
                order: index,
                isQuickAccess: true
            )
        }
        saveConfiguration() // Save immediately
    }
    
    private func moveSelectedFeatures(from source: IndexSet, to destination: Int) {
        selectedFeatures.move(fromOffsets: source, toOffset: destination)
        
        // Update order by creating new items
        selectedFeatures = selectedFeatures.enumerated().map { index, item in
            TabBarItem(
                id: item.id,
                title: item.title,
                systemImage: item.systemImage,
                description: item.description,
                order: index,
                isQuickAccess: true
            )
        }
        saveConfiguration() // Save immediately
    }
    
    
    private func saveConfiguration() {
        // Update all items' quick access status
        let allItems = availableFeatures.map { feature in
            TabBarItem(
                from: feature,
                order: selectedFeatures.firstIndex(where: { $0.id == feature.id }) ?? 999,
                isQuickAccess: selectedFeatures.contains(where: { $0.id == feature.id })
            )
        }
        
        tabBarManager.updateTabBarItems(allItems)
    }
    
    private func featureColorFor(_ id: String) -> Color {
        FeatureTheme.color(for: id)  // single source of truth — see DesignTokens.swift
    }
}