//
//  RoutePlannerView.swift
//  Iconik Employee
//
//  View for planning optimized routes between multiple schools
//  Uses Google Routes API to find the most efficient driving order
//

import SwiftUI
import CoreLocation

struct RoutePlannerView: View {
    @StateObject private var locationManager = RouteLocationManager()
    @ObservedObject private var organizationService = OrganizationService.shared
    @State private var schools: [School] = []
    @State private var selectedSchools: Set<String> = []
    @State private var isLoading = false
    @State private var isOptimizing = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var showingRoutePreview = false

    // Starting point selection
    @State private var selectedStartingPoint: StartingPointType = .currentLocation

    // End point selection
    @State private var addEndPoint: Bool = false
    @State private var selectedEndPoint: EndPointType = .home

    // Route result with distances
    @State private var routeResult: OptimizedRouteResult?

    // Address availability
    @State private var hasHomeAddress: Bool = false
    @State private var hasWorkAddress: Bool = false

    private var filteredSchools: [School] {
        if searchText.isEmpty {
            return schools
        }
        return schools.filter { school in
            school.name.localizedCaseInsensitiveContains(searchText) ||
            (school.address?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var selectedSchoolsList: [School] {
        schools.filter { selectedSchools.contains($0.id) }
    }

    private var canOptimize: Bool {
        guard selectedSchools.count >= 2 else { return false }

        // Check if selected starting point is available
        switch selectedStartingPoint {
        case .currentLocation:
            return true // Will request location when optimizing
        case .homeAddress:
            return hasHomeAddress
        case .workAddress:
            return hasWorkAddress
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if showingRoutePreview {
                routePreviewView
            } else {
                schoolSelectionView
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
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - School Selection View

    private var schoolSelectionView: some View {
        VStack(spacing: 0) {
            // Manual search bar above the list
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                TextField("Search schools...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(8)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal)
            .padding(.vertical, 8)

            List {
                // Starting Point Section
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Start From")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Picker("Starting Point", selection: $selectedStartingPoint) {
                            ForEach(StartingPointType.allCases) { type in
                                Text(type.shortName)
                                    .tag(type)
                            }
                        }
                        .pickerStyle(.segmented)

                        // Warning for unavailable addresses
                        if selectedStartingPoint == .homeAddress && !hasHomeAddress {
                            Label("Home address not set in profile", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        if selectedStartingPoint == .workAddress && !hasWorkAddress {
                            Label("Organization address not available", systemImage: "exclamationmark.triangle")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // End Point Section
                Section {
                    Toggle(isOn: $addEndPoint) {
                        HStack {
                            Image(systemName: "flag.checkered")
                            Text("Add End Point")
                        }
                    }
                    .disabled(!hasHomeAddress && !hasWorkAddress)

                    if addEndPoint {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("End At")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Picker("End Point", selection: $selectedEndPoint) {
                                ForEach(EndPointType.allCases) { type in
                                    Text(type.rawValue)
                                        .tag(type)
                                }
                            }
                            .pickerStyle(.segmented)

                            // Warning for unavailable end point
                            if selectedEndPoint == .home && !hasHomeAddress {
                                Label("Home address not set in profile", systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            if selectedEndPoint == .work && !hasWorkAddress {
                                Label("Organization address not available", systemImage: "exclamationmark.triangle")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } footer: {
                    if !hasHomeAddress && !hasWorkAddress {
                        Text("Set your home address in Settings to enable end point")
                    }
                }

                // Schools Section
                Section {
                    ForEach(filteredSchools) { school in
                        SchoolRowView(
                            school: school,
                            isSelected: selectedSchools.contains(school.id),
                            onToggle: {
                                toggleSchoolSelection(school)
                            }
                        )
                    }
                } header: {
                    HStack {
                        Text("Schools")
                        Spacer()
                        Text("\(selectedSchools.count) selected")
                            .foregroundColor(.secondary)
                        if !selectedSchools.isEmpty {
                            Button("Clear") {
                                selectedSchools.removeAll()
                            }
                            .font(.caption)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)

            // Bottom action bar
            if selectedSchools.count >= 2 {
                optimizeButton
            }
        }
        .overlay {
            if isLoading {
                ProgressView("Loading schools...")
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                    .shadow(radius: 4)
            }
        }
    }

    private var optimizeButton: some View {
        VStack(spacing: 0) {
            Divider()

            Button(action: optimizeRoute) {
                HStack {
                    if isOptimizing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.triangle.swap")
                    }
                    Text(isOptimizing ? "Optimizing..." : "Optimize Route")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canOptimize ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(isOptimizing || !canOptimize)
            .padding()
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Route Preview View

    private var routePreviewView: some View {
        VStack(spacing: 0) {
            // Header with total distance
            routePreviewHeader

            // Route list with distances
            routeListWithDistances

            // Open in Maps buttons
            mapButtons
        }
    }

    private var routePreviewHeader: some View {
        VStack(spacing: 8) {
            // Navigation header
            HStack {
                Button(action: { showingRoutePreview = false }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Edit")
                    }
                }

                Spacer()

                Text("Optimized Route")
                    .font(.headline)

                Spacer()

                // Invisible spacer for centering
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Edit")
                }
                .opacity(0)
            }

            // Total distance display
            if let result = routeResult, result.totalDistanceMiles > 0 {
                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Image(systemName: "car.fill")
                            .foregroundColor(.blue)
                        Text(result.formattedTotalDistance)
                            .fontWeight(.semibold)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "clock.fill")
                            .foregroundColor(.blue)
                        Text(result.formattedTotalDuration)
                            .fontWeight(.semibold)
                    }
                }
                .font(.subheadline)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }

    private var routeListWithDistances: some View {
        List {
            // Starting point section
            Section {
                startingPointRow
            }

            // Stops section with distances
            Section("Stops") {
                ForEach(Array((routeResult?.schools ?? []).enumerated()), id: \.element.id) { index, school in
                    VStack(alignment: .leading, spacing: 0) {
                        // Leg distance from previous stop
                        if let result = routeResult,
                           index < result.legs.count,
                           result.legs[index].distanceMeters > 0 {
                            HStack {
                                Image(systemName: "arrow.down")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(result.legs[index].formattedDistance)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("•")
                                    .foregroundColor(.secondary)
                                Text(result.legs[index].formattedDuration)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.leading, 40)
                            .padding(.bottom, 4)
                        }

                        // School row
                        schoolStopRow(index: index, school: school)
                    }
                }
            }

            // End point section (if enabled)
            if addEndPoint, let result = routeResult, result.endPointType != nil {
                Section {
                    endPointRow
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var startingPointRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.green)
                    .frame(width: 28, height: 28)
                Image(systemName: selectedStartingPoint.icon)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(selectedStartingPoint.rawValue)
                    .font(.headline)
                Text("Starting point")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func schoolStopRow(index: Int, school: School) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 28, height: 28)
                Text("\(index + 1)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(school.name)
                    .font(.headline)
                if let address = school.address, !address.isEmpty {
                    Text(address)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var endPointRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Distance to end point
            if let result = routeResult,
               let lastLeg = result.legs.last,
               result.endPointType != nil,
               lastLeg.distanceMeters > 0 {
                HStack {
                    Image(systemName: "arrow.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(lastLeg.formattedDistance)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("•")
                        .foregroundColor(.secondary)
                    Text(lastLeg.formattedDuration)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.leading, 40)
                .padding(.bottom, 4)
            }

            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 28, height: 28)
                    Image(systemName: selectedEndPoint.icon)
                        .font(.system(size: 14))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedEndPoint.rawValue)
                        .font(.headline)
                    Text("End point")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var mapButtons: some View {
        VStack(spacing: 0) {
            Divider()

            VStack(spacing: 12) {
                // Apple Maps
                Button(action: openInAppleMaps) {
                    HStack {
                        Image(systemName: "map.fill")
                        Text("Open in Apple Maps")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }

                // Google Maps
                Button(action: openInGoogleMaps) {
                    HStack {
                        Image(systemName: "globe")
                        Text("Open in Google Maps")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
                    .cornerRadius(10)
                }
            }
            .padding()
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Actions

    private func toggleSchoolSelection(_ school: School) {
        if selectedSchools.contains(school.id) {
            selectedSchools.remove(school.id)
        } else {
            selectedSchools.insert(school.id)
        }
    }

    private func checkAddressAvailability() {
        hasHomeAddress = RouteOptimizerService.isEndPointAvailable(.home)
        hasWorkAddress = RouteOptimizerService.isEndPointAvailable(.work)

        // Default to available starting point
        if selectedStartingPoint == .homeAddress && !hasHomeAddress {
            selectedStartingPoint = .currentLocation
        }
        if selectedStartingPoint == .workAddress && !hasWorkAddress {
            selectedStartingPoint = .currentLocation
        }

        // Default to available end point
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

        do {
            guard let orgID = UserDefaults.standard.string(forKey: "userOrganizationID") else {
                errorMessage = "Organization ID not found"
                return
            }

            schools = try await SchoolService.shared.getSchools(organizationID: orgID)
        } catch {
            // Check if error is cancellation-related
            let errorDesc = error.localizedDescription.lowercased()
            if errorDesc.contains("cancel") || (error as NSError).code == NSURLErrorCancelled {
                // Task was cancelled - ignore this error
                print("School loading was cancelled (view dismissed)")
            } else {
                errorMessage = "Failed to load schools: \(error.localizedDescription)"
            }
        }
    }

    private func optimizeRoute() {
        guard selectedSchools.count >= 2 else { return }

        isOptimizing = true

        Task {
            defer {
                Task { @MainActor in
                    isOptimizing = false
                }
            }

            do {
                // Get starting coordinates based on selection
                let startCoordinates: CLLocationCoordinate2D

                switch selectedStartingPoint {
                case .currentLocation:
                    // Get current location
                    if let location = locationManager.location {
                        startCoordinates = location.coordinate
                    } else {
                        // Request location if not available
                        locationManager.requestLocation()
                        try await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 seconds

                        guard let location = locationManager.location else {
                            await MainActor.run {
                                errorMessage = "Unable to get current location. Please enable location services."
                            }
                            return
                        }
                        startCoordinates = location.coordinate
                    }

                case .homeAddress:
                    guard let coords = RouteOptimizerService.getCoordinates(for: .homeAddress, currentLocation: nil) else {
                        await MainActor.run {
                            errorMessage = "Home address not available. Please set it in your profile."
                        }
                        return
                    }
                    startCoordinates = coords

                case .workAddress:
                    guard let coords = RouteOptimizerService.getCoordinates(for: .workAddress, currentLocation: nil) else {
                        await MainActor.run {
                            errorMessage = "Work address not available."
                        }
                        return
                    }
                    startCoordinates = coords
                }

                // Get end coordinates if enabled
                let endCoordinates: CLLocationCoordinate2D?
                let endType: EndPointType?

                if addEndPoint {
                    endCoordinates = RouteOptimizerService.getEndPointCoordinates(for: selectedEndPoint)
                    endType = selectedEndPoint
                } else {
                    endCoordinates = nil
                    endType = nil
                }

                await performOptimization(
                    from: startCoordinates,
                    endLocation: endCoordinates,
                    endPointType: endType
                )
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to optimize route: \(error.localizedDescription)"
                }
            }
        }
    }

    private func performOptimization(
        from location: CLLocationCoordinate2D,
        endLocation: CLLocationCoordinate2D?,
        endPointType: EndPointType?
    ) async {
        do {
            let schoolsToOptimize = selectedSchoolsList
            let result = try await RouteOptimizerService.shared.optimizeRoute(
                schools: schoolsToOptimize,
                startingFrom: location,
                startingPointType: selectedStartingPoint,
                endLocation: endLocation,
                endPointType: endPointType
            )

            await MainActor.run {
                routeResult = result
                showingRoutePreview = true
            }
        } catch {
            await MainActor.run {
                errorMessage = "Failed to optimize route: \(error.localizedDescription)"
            }
        }
    }

    private func openInAppleMaps() {
        guard let result = routeResult else { return }

        let endCoords = addEndPoint ? RouteOptimizerService.getEndPointCoordinates(for: selectedEndPoint) : nil

        guard let url = RouteOptimizerService.appleMapsURL(
            for: result.schools,
            startingPoint: selectedStartingPoint,
            endLocation: endCoords
        ) else {
            errorMessage = "Unable to generate Apple Maps URL"
            return
        }

        UIApplication.shared.open(url)
    }

    private func openInGoogleMaps() {
        guard let result = routeResult else { return }

        let endCoords = addEndPoint ? RouteOptimizerService.getEndPointCoordinates(for: selectedEndPoint) : nil

        guard let url = RouteOptimizerService.googleMapsURL(
            for: result.schools,
            startingPoint: selectedStartingPoint,
            endLocation: endCoords
        ) else {
            errorMessage = "Unable to generate Google Maps URL"
            return
        }

        // Check if Google Maps is installed
        if UIApplication.shared.canOpenURL(URL(string: "comgooglemaps://")!) {
            // Convert web URL to app URL
            if let appURL = URL(string: url.absoluteString.replacingOccurrences(of: "https://www.google.com/maps/dir/", with: "comgooglemaps://?")) {
                UIApplication.shared.open(appURL)
                return
            }
        }

        // Fall back to web URL
        UIApplication.shared.open(url)
    }
}

// MARK: - School Row View

private struct SchoolRowView: View {
    let school: School
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                // Checkbox
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isSelected ? .blue : .gray)

                // School info
                VStack(alignment: .leading, spacing: 2) {
                    Text(school.name)
                        .font(.body)
                        .foregroundColor(.primary)

                    if let address = school.address, !address.isEmpty {
                        Text(address)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Coordinate indicator
                if school.parsedCoordinates != nil {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                } else {
                    Image(systemName: "mappin.slash")
                        .foregroundColor(.orange)
                        .font(.caption)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Route Location Manager

private class RouteLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        authorizationStatus = manager.authorizationStatus

        // Request authorization if needed
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }

        // Start updating location if authorized
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
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

        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }
}

#Preview {
    NavigationStack {
        RoutePlannerView()
    }
}
