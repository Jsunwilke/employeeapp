//  RoutePlannerView.swift
//  Iconik Employee — the Route Planner, converted to Ambient in AMB.9
//
//  Draws with `RoutePlannerKit.swift`, which the design lab's mockup also draws
//  with — so this screen and the approved design cannot diverge. The old screen's
//  hand-rolled search bar, inset-grouped `List`, segmented pickers, text-list
//  preview and `SchoolRowView` are GONE from this file, not left beside the new
//  ones.
//
//  WHAT CHANGED BEYOND THE PAINT, each approved by the operator on 2026-07-29 and
//  each a defect the parity inventory named (AMB_BATCH3_PARITY.md §3):
//
//    1. THE TWO-MODES-ONE-BOOLEAN SWAP IS DEAD. `showingRoutePreview` swapped two
//       full-screen modes inside one screen, so the preview drew the system
//       "Route Planner" bar PLUS a hand-rolled "Optimized Route" header — two
//       stacked title rows. The preview is now a PUSHED screen through one
//       `.ambientPush(item:)`, and it applies its own `.tabBarClearance()`
//       because a container's root inset is not inherited by what it pushes.
//
//    2. A SCHOOL WITH NO MAP PIN SAYS SO AND CANNOT BE PICKED. It used to be
//       tickable, counted in "3 selected", and then dropped by the optimizer's
//       `validSchools` filter with no notice anywhere. The selected count now
//       counts only routable schools.
//
//    3. THE OPTIMIZE BUTTON NO LONGER VANISHES. The whole bottom bar rendered
//       only at two or more selections — below two there was no button and no
//       explanation.
//
//    4. A FAILED OPTIMIZATION IS NOT PRESENTED AS A ROUTE. No `optimizedOrder`
//       used to mean the service handed back the user's own list with zero miles
//       and the view's `> 0` gate hid the totals. The service now throws with the
//       server's real message and this screen shows it; the preview is not pushed.
//
//    5. SKIPPED SCHOOLS ARE LISTED. `skippedShipments` was decoded, counted and
//       printed to the console only.
//
//    6. THE PREVIEW IS A SNAPSHOT. Its start/end labels used to read live
//       `@State` that `checkAddressAvailability()` could mutate from a realtime
//       organisation-coordinate update while the preview was on screen — so the
//       displayed start could silently become something the route was not
//       computed for. Everything the preview draws is captured at optimize time.
//
//  WHAT IS DELIBERATELY UNCHANGED, and named so the omissions are not silent:
//  the fixed 2-second GPS `Task.sleep` (a location strategy, not a design
//  question), the Edge Function's 10,000:1 distance:time cost model and its
//  per-request OAuth exchange, `SchoolService.getSchools` not filtering
//  `is_active`, and location permission still being surfaced only as a message
//  after the timeout. All four are data-layer or server work.

import SwiftUI
import CoreLocation

struct RoutePlannerView: View {
    @StateObject private var locationManager = RouteLocationManager()
    @ObservedObject private var organizationService = OrganizationService.shared

    @State private var schools: [School] = []
    /// The ids of the schools that HAVE a map pin, resolved once when the list lands.
    ///
    /// `School.parsedCoordinates` is not a stored property — it trims quotes, splits
    /// the string and parses two `Double`s on every access
    /// (`SessionFormModels.swift:64`). The selected count, every row's routable badge
    /// and the optimize gate all asked it, so a body pass re-parsed the coordinates of
    /// every school in the organisation several times over. The answer cannot change
    /// without the list changing, so it is computed where the list changes.
    @State private var routableSchoolIDs: Set<String> = []
    @State private var selectedSchools: Set<String> = []
    @State private var isLoading = false
    @State private var isOptimizing = false
    /// A school-load failure. Kept as the alert it has always been.
    @State private var errorMessage: String?
    /// An optimization failure, drawn INLINE beside the button that caused it —
    /// the message belongs next to the control, not behind an OK.
    @State private var optimizeFailure: String?
    @State private var searchText = ""

    @State private var selectedStartingPoint: StartingPointType = .currentLocation
    @State private var addEndPoint = false
    @State private var selectedEndPoint: EndPointType = .home

    @State private var hasHomeAddress = false
    @State private var hasWorkAddress = false

    /// One enum, one `.ambientPush` — the AMB.3 rule. It carries the whole
    /// preview, so nothing the preview draws can change under it.
    @State private var destination: RoutePlannerDestination?

    private enum RoutePlannerDestination: Identifiable {
        case preview(RoutePreviewModel)

        var id: String { "preview" }
    }

    private var tint: Color { RoutePlannerStyle.tint }

    // MARK: - Derived state

    /// Name and address only, which is what the live filter searches. Widening it
    /// to city/state/zip/district is a behaviour change, not a restyle.
    private var filteredSchools: [School] {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return schools }
        return schools.filter { school in
            school.name.localizedCaseInsensitiveContains(trimmed)
            || (school.address?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    /// ONLY ROUTABLE SCHOOLS COUNT. The old screen counted everything it let you
    /// tick, which is how "3 selected" became a two-stop route.
    ///
    /// Read on the main actor when Optimize is pressed, so the route is computed for
    /// exactly what was on screen — the count below does not need the objects.
    private var selectedRoutableSchools: [School] {
        schools.filter { selectedSchools.contains($0.id) && routableSchoolIDs.contains($0.id) }
    }

    private var selectedCount: Int { selectedSchools.intersection(routableSchoolIDs).count }

    private var isStartAvailable: Bool {
        switch selectedStartingPoint {
        case .currentLocation: return true // requested when optimizing
        case .homeAddress: return hasHomeAddress
        case .workAddress: return hasWorkAddress
        }
    }

    private var canOptimize: Bool { selectedCount >= 2 && isStartAvailable }

    /// The reason the button is inert, so a disabled control teaches the rule.
    private var optimizeCaption: String? {
        if selectedCount < 2 { return "Select at least two schools" }
        if !isStartAvailable { return startWarning }
        return nil
    }

    private var startWarning: String? {
        switch selectedStartingPoint {
        case .currentLocation: return nil
        case .homeAddress: return hasHomeAddress ? nil : "Home address not set in profile"
        case .workAddress: return hasWorkAddress ? nil : "Organization address not available"
        }
    }

    private var endWarning: String? {
        switch selectedEndPoint {
        case .home: return hasHomeAddress ? nil : "Home address not set in profile"
        case .work: return hasWorkAddress ? nil : "Organization address not available"
        }
    }

    private var noEndPointPossible: Bool { !hasHomeAddress && !hasWorkAddress }

    // MARK: - Choice-row labels
    //
    // The approved design labels the start options "Current Location / Home /
    // Work". `StartingPointType.rawValue` spells the last two "Home Address" and
    // "Work Address", so the mapping lives here — the kit takes plain strings and
    // does not know these enums exist.

    private static func label(for type: StartingPointType) -> String {
        switch type {
        case .currentLocation: return "Current Location"
        case .homeAddress: return "Home"
        case .workAddress: return "Work"
        }
    }

    private static func startingPoint(forLabel label: String) -> StartingPointType? {
        StartingPointType.allCases.first { Self.label(for: $0) == label }
    }

    private var startSelection: Binding<String?> {
        Binding(get: { Self.label(for: selectedStartingPoint) },
                set: { newValue in
                    guard let newValue, let type = Self.startingPoint(forLabel: newValue) else { return }
                    selectedStartingPoint = type
                })
    }

    private var endSelection: Binding<String?> {
        Binding(get: { selectedEndPoint.rawValue },
                set: { newValue in
                    guard let newValue, let type = EndPointType(rawValue: newValue) else { return }
                    selectedEndPoint = type
                })
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            AmbientBackdrop()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let optimizeFailure {
                            // RETRY ONLY WHEN IT WILL RUN. `optimizeRoute()`
                            // guard-returns unless `canOptimize`, so if the
                            // selection changed after the failure the old Retry
                            // cleared the card and did nothing at all — the failure
                            // looked dismissed and no route was planned. Without it
                            // the card says what to change instead.
                            RouteFailureCard(message: optimizeFailure,
                                             hint: canOptimize ? nil : "Adjust your selection, then optimize again.",
                                             tint: tint,
                                             retry: canOptimize ? {
                                                 self.optimizeFailure = nil
                                                 optimizeRoute()
                                             } : nil)
                        }
                        RouteSearchCard(text: $searchText)
                        routeSection
                        schoolsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .ambientNoBounceWhenShort()

                RouteOptimizeBar(enabled: canOptimize,
                                 isOptimizing: isOptimizing,
                                 caption: optimizeCaption,
                                 tint: tint,
                                 action: optimizeRoute)
            }
        }
        .navigationTitle("Route Planner")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadSchools()
            checkAddressAvailability()
        }
        .onChange(of: organizationService.organizationCoordinates) { _ in
            checkAddressAvailability()
        }
        .ambientPush(item: $destination) { destination in
            switch destination {
            case .preview(let model):
                RoutePreviewScreen(model: model)
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Start and end

    private var routeSection: some View {
        RouteEndpointsSection(
            status: selectedCount == 1 ? "1 stop" : "\(selectedCount) stops",
            statusTint: selectedCount >= 2 ? tint : nil,
            startOptions: StartingPointType.allCases.map(Self.label(for:)),
            start: startSelection,
            startWarning: startWarning,
            addsEndPoint: $addEndPoint,
            endOptions: EndPointType.allCases.map(\.rawValue),
            end: endSelection,
            endWarning: endWarning,
            endPointDisabled: noEndPointPossible,
            // The live screen's footer, kept verbatim. It names only "home"
            // although a work address also satisfies the end point — a pre-existing
            // copy asymmetry the parity inventory records; rewriting it is not this
            // phase's call.
            endPointNote: noEndPointPossible
                ? "Set your home address in Settings to enable end point"
                : nil,
            tint: tint)
    }

    // MARK: - The school list

    private var schoolsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Schools")
                    .font(.footnote.weight(.semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(selectedCount) selected")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                if !selectedSchools.isEmpty {
                    Button("Clear") {
                        withAnimation(AmbientMotion.snappy) { selectedSchools.removeAll() }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(tint)
                }
            }

            if isLoading && schools.isEmpty {
                loadingRow
            } else if filteredSchools.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: AmbientDensity.compact.stackSpacing) {
                    ForEach(filteredSchools) { school in
                        RouteSchoolRow(model: rowModel(for: school),
                                       isSelected: selectedSchools.contains(school.id),
                                       tint: tint) {
                            toggleSchoolSelection(school)
                        }
                    }
                }
            }
        }
    }

    private func rowModel(for school: School) -> RouteSchoolRowModel {
        let address = school.address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return RouteSchoolRowModel(
            id: school.id,
            name: school.name,
            // The old row simply omitted the line when the address was empty,
            // which left a school with no address looking identical to one whose
            // address had not loaded.
            address: address.isEmpty ? "No address on file" : address,
            isRoutable: routableSchoolIDs.contains(school.id))
    }

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Loading schools…").font(.subheadline).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .ambientCard(density: .compact, fillWidth: true)
    }

    /// The live screen has NO empty state: no schools, or no search match, leaves a
    /// blank section reading "0 selected".
    @ViewBuilder
    private var emptyState: some View {
        if schools.isEmpty {
            AmbientEmptyState(
                title: "No schools yet",
                message: "Routes are built from your organization's schools. An administrator adds them in Settings.",
                systemImage: "building.2")
        } else {
            AmbientEmptyState(title: "No schools match",
                              message: "Search looks at the name and the address.",
                              systemImage: "magnifyingglass")
        }
    }

    // MARK: - Actions

    private func toggleSchoolSelection(_ school: School) {
        withAnimation(AmbientMotion.snappy) {
            if selectedSchools.contains(school.id) {
                selectedSchools.remove(school.id)
            } else {
                selectedSchools.insert(school.id)
            }
        }
        AmbientHaptics.selection()
    }

    private func checkAddressAvailability() {
        hasHomeAddress = RouteOptimizerService.isEndPointAvailable(.home)
        hasWorkAddress = RouteOptimizerService.isEndPointAvailable(.work)

        // Default to an available starting point
        if selectedStartingPoint == .homeAddress && !hasHomeAddress {
            selectedStartingPoint = .currentLocation
        }
        if selectedStartingPoint == .workAddress && !hasWorkAddress {
            selectedStartingPoint = .currentLocation
        }

        // Default to an available end point
        if selectedEndPoint == .home && !hasHomeAddress && hasWorkAddress {
            selectedEndPoint = .work
        }
        if selectedEndPoint == .work && !hasWorkAddress && hasHomeAddress {
            selectedEndPoint = .home
        }
    }

    private func loadSchools() async {
        isLoading = true
        defer { isLoading = false }

        guard let orgID = UserDefaults.standard.string(forKey: "userOrganizationID") else {
            errorMessage = "Organization ID not found"
            return
        }

        do {
            let loaded = try await SchoolService.shared.getSchools(organizationID: orgID)
            schools = loaded
            // The coordinates are parsed HERE, once per load, instead of per body pass.
            routableSchoolIDs = Set(loaded.filter { $0.parsedCoordinates != nil }.map(\.id))
        } catch {
            // A cancellation is the view being dismissed, not a failure worth an alert.
            //
            // TESTED AS A TYPE, not by looking for "cancel" in a sentence. The old test
            // lowercased `localizedDescription` and searched it for a substring — a
            // LOCALIZED, server-authored string, so on a non-English device it matched
            // nothing (a real cancellation raised an alert on a dismissed screen) while
            // any unrelated failure whose message happens to contain the word was
            // swallowed instead of shown.
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                print("School loading was cancelled (view dismissed)")
            } else {
                errorMessage = "Failed to load schools: \(error.localizedDescription)"
            }
        }
    }

    private func optimizeRoute() {
        guard canOptimize else { return }

        isOptimizing = true
        optimizeFailure = nil
        AmbientHaptics.impact(.medium)

        // The schools are read HERE, on the main actor, so the route is computed
        // for exactly what was on screen when the button was pressed.
        let schoolsToOptimize = selectedRoutableSchools
        let startingPoint = selectedStartingPoint
        let wantsEndPoint = addEndPoint
        let endPoint = selectedEndPoint

        Task { @MainActor in
            defer { isOptimizing = false }

            let startCoordinates: CLLocationCoordinate2D
            switch startingPoint {
            case .currentLocation:
                if let location = locationManager.location {
                    startCoordinates = location.coordinate
                } else {
                    // UNCHANGED, deliberately: a fixed 2-second wait for a GPS fix
                    // is a location strategy, and replacing it is not a design
                    // change (parity §3 item 6).
                    locationManager.requestLocation()
                    try? await Task.sleep(nanoseconds: 2_000_000_000)

                    guard let location = locationManager.location else {
                        optimizeFailure = "Unable to get current location. Please enable location services."
                        return
                    }
                    startCoordinates = location.coordinate
                }

            case .homeAddress:
                guard let coords = RouteOptimizerService.getCoordinates(for: .homeAddress, currentLocation: nil) else {
                    optimizeFailure = "Home address not available. Please set it in your profile."
                    return
                }
                startCoordinates = coords

            case .workAddress:
                guard let coords = RouteOptimizerService.getCoordinates(for: .workAddress, currentLocation: nil) else {
                    optimizeFailure = "Work address not available."
                    return
                }
                startCoordinates = coords
            }

            let endCoordinates = wantsEndPoint
                ? RouteOptimizerService.getEndPointCoordinates(for: endPoint)
                : nil
            if wantsEndPoint && endCoordinates == nil {
                optimizeFailure = "\(endPoint.rawValue) address not available, so it can't be the end point."
                return
            }

            do {
                let result = try await RouteOptimizerService.shared.optimizeRoute(
                    schools: schoolsToOptimize,
                    startingFrom: startCoordinates,
                    startingPointType: startingPoint,
                    endLocation: endCoordinates,
                    endPointType: wantsEndPoint ? endPoint : nil)

                // A result with no stops is the same lie in a different shape.
                guard !result.schools.isEmpty else {
                    optimizeFailure = "The route came back with no stops in it."
                    return
                }

                destination = .preview(RoutePreviewModel(
                    result: result,
                    startLabel: Self.label(for: startingPoint),
                    endLabel: wantsEndPoint ? endPoint.rawValue : nil,
                    startingPoint: startingPoint,
                    endCoordinates: endCoordinates))
            } catch {
                optimizeFailure = error.localizedDescription
            }
        }
    }
}

// MARK: - The preview, as a snapshot

/// Everything the preview draws, captured when Optimize was pressed. Holding the
/// timeline as already-built kit entries is what makes the snapshot real: there is
/// nothing left for a realtime organisation update to change under it.
private struct RoutePreviewModel {
    let entries: [RouteTimelineEntry]
    let totalDistanceLabel: String
    let totalDurationLabel: String
    let skippedSchools: [String]
    /// The optimized order, for handing to a map app.
    let schools: [School]
    let startingPoint: StartingPointType
    let endCoordinates: CLLocationCoordinate2D?

    init(result: OptimizedRouteResult,
         startLabel: String,
         endLabel: String?,
         startingPoint: StartingPointType,
         endCoordinates: CLLocationCoordinate2D?) {
        self.totalDistanceLabel = RoutePlannerFormat.distance(miles: result.totalDistanceMiles)
        self.totalDurationLabel = RoutePlannerFormat.duration(minutes: result.totalDurationMinutes)
        self.skippedSchools = result.skippedSchools
        self.schools = result.schools
        self.startingPoint = startingPoint
        self.endCoordinates = endCoordinates

        // `legs[i]` is the leg ARRIVING at row i's successor: leg 0 is start → stop
        // 1, leg n is the last stop → the end point. So each row carries the leg
        // LEAVING it, and the final row carries none.
        func legLabel(_ index: Int) -> String? {
            guard index >= 0 && index < result.legs.count else { return nil }
            let leg = result.legs[index]
            return RoutePlannerFormat.leg(miles: leg.distanceMiles, minutes: leg.durationMinutes)
        }

        var entries: [RouteTimelineEntry] = [
            RouteTimelineEntry(id: "start",
                               marker: .start,
                               title: startLabel,
                               subtitle: "Starting point",
                               legLabel: legLabel(0))
        ]

        for (index, school) in result.schools.enumerated() {
            let address = school.address?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            entries.append(RouteTimelineEntry(
                id: "stop-\(index)-\(school.id)",
                marker: .stop(index + 1),
                title: school.name,
                subtitle: address.isEmpty ? "No address on file" : address,
                legLabel: legLabel(index + 1)))
        }

        if let endLabel {
            entries.append(RouteTimelineEntry(id: "end",
                                              marker: .end,
                                              title: endLabel,
                                              subtitle: "End point"))
        }

        self.entries = entries
    }
}

private struct RoutePreviewScreen: View {
    let model: RoutePreviewModel

    @State private var errorMessage: String?

    private var tint: Color { RoutePlannerStyle.tint }

    var body: some View {
        ZStack {
            AmbientBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    RouteTotalsHero(distanceLabel: model.totalDistanceLabel,
                                    durationLabel: model.totalDurationLabel,
                                    tint: tint)
                    if !model.skippedSchools.isEmpty {
                        RouteSkippedNotice(names: model.skippedSchools)
                    }
                    RouteTimeline(entries: model.entries, tint: tint)
                    RouteMapButtons(tint: tint,
                                    openAppleMaps: openInAppleMaps,
                                    openGoogleMaps: openInGoogleMaps)
                    RoutePreviewFootnote()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .ambientNoBounceWhenShort()
        }
        // A PUSHED screen insets itself: a safe-area inset does not travel out of a
        // navigation container into what that container pushes.
        .tabBarClearance()
        .navigationTitle("Optimized Route")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Route Planner", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func openInAppleMaps() {
        guard let url = RouteOptimizerService.appleMapsURL(
            for: model.schools,
            startingPoint: model.startingPoint,
            endLocation: model.endCoordinates
        ) else {
            errorMessage = "Unable to generate Apple Maps URL"
            return
        }
        UIApplication.shared.open(url)
    }

    /// THE WELL-FORMED UNIVERSAL LINK, UNCONDITIONALLY.
    ///
    /// The installed-app branch used to rewrite the https prefix onto
    /// `comgooglemaps://?` — which produced a doubled `?` and parameters in the
    /// wrong scheme, and `comgooglemaps` IS in `LSApplicationQueriesSchemes`, so
    /// the broken URL won whenever Google Maps was installed. It also carried a
    /// force-unwrapped `URL(string:)!`. Google Maps claims its own universal
    /// links, so opening the https URL lands in the app when it is installed and
    /// in the browser when it is not.
    private func openInGoogleMaps() {
        guard let url = RouteOptimizerService.googleMapsURL(
            for: model.schools,
            startingPoint: model.startingPoint,
            endLocation: model.endCoordinates
        ) else {
            errorMessage = "Unable to generate Google Maps URL"
            return
        }
        UIApplication.shared.open(url)
    }
}

// MARK: - Route Location Manager

private class RouteLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    @Published var location: CLLocation?
    private var authorizationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = manager.authorizationStatus

        // Request authorization if needed
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }

        // Fetch a single location fix if authorized. The route planner only
        // needs the current position once (as a starting point), so we use a
        // one-shot request instead of continuous updates that would drain the
        // battery for as long as this manager is alive.
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func requestLocation() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager error: \(error)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus

        // One-shot fix on authorization (e.g. the user just granted access) —
        // not continuous tracking.
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }
}

#Preview {
    NavigationView {
        RoutePlannerView()
    }
}
