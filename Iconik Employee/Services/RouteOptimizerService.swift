//
//  RouteOptimizerService.swift
//  Iconik Employee
//
//  Service for optimizing multi-stop routes using Google Route Optimization API
//  Calls a Supabase Edge Function that handles OAuth2 authentication
//

import Foundation
import CoreLocation
import Supabase

// MARK: - Public Types

/// Starting point options for route optimization
///
/// `icon` and `shortName` were deleted with the converted screen: the segmented
/// picker that used `shortName` and the icon-in-a-circle rows that used `icon` are
/// both gone (the timeline draws plain markers), and the approved design's option
/// labels are mapped in `RoutePlannerView` rather than restated here. The
/// `rawValue`s still travel to the Edge Function as the origin's label.
enum StartingPointType: String, CaseIterable, Identifiable {
    case currentLocation = "Current Location"
    case homeAddress = "Home Address"
    case workAddress = "Work Address"

    var id: String { rawValue }
}

/// End point options for route optimization
enum EndPointType: String, CaseIterable, Identifiable {
    case home = "Home"
    case work = "Work"

    var id: String { rawValue }
}

/// Distance/duration information for a route leg
///
/// NO DISPLAY STRINGS HERE. `formattedDistance` / `formattedDuration` were deleted
/// when the screen was converted: `formattedDuration` did `Int(durationMinutes)`,
/// so 59.6 minutes read "59 min", while the approved design's own formatter
/// rounded. Two formatters cannot disagree if there is only one, and it lives in
/// `RoutePlannerKit.RoutePlannerFormat` — which the lab mockup draws with too.
struct RouteLeg: Codable {
    let distanceMeters: Double
    let durationSeconds: Double

    var distanceMiles: Double {
        distanceMeters * 0.000621371
    }

    var durationMinutes: Double {
        durationSeconds / 60.0
    }
}

/// Result of route optimization including schools and distance data
struct OptimizedRouteResult {
    let schools: [School]
    let totalDistanceMiles: Double
    let totalDurationMinutes: Double
    let legs: [RouteLeg]
    /// Schools the router REFUSED to fit into the route, by name.
    ///
    /// `skippedShipments` has always been decoded, counted and printed to the
    /// console, and surfaced nowhere — so a route quietly missing two of your
    /// stops looked exactly like a route with all of them. The preview now lists
    /// these.
    let skippedSchools: [String]
    let endPointType: EndPointType?
}

// MARK: - Service

class RouteOptimizerService {
    static let shared = RouteOptimizerService()

    private var supabase: SupabaseClient { SupabaseManager.shared.client }

    private init() {}

    // MARK: - Coordinate Helpers

    /// Parses a coordinate string in "lat,lng" format
    static func parseCoordinateString(_ coords: String) -> CLLocationCoordinate2D? {
        let parts = coords.split(separator: ",")
        guard parts.count == 2,
              let lat = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let lng = Double(parts[1].trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    /// Gets coordinates for a starting point type
    @MainActor
    static func getCoordinates(
        for type: StartingPointType,
        currentLocation: CLLocationCoordinate2D?
    ) -> CLLocationCoordinate2D? {
        switch type {
        case .currentLocation:
            return currentLocation
        case .homeAddress:
            let homeCoords = UserDefaults.standard.string(forKey: "userHomeAddress") ?? ""
            return parseCoordinateString(homeCoords)
        case .workAddress:
            let orgCoords = OrganizationService.shared.organizationCoordinates
            return parseCoordinateString(orgCoords)
        }
    }

    /// Gets coordinates for an end point type
    @MainActor
    static func getEndPointCoordinates(for type: EndPointType) -> CLLocationCoordinate2D? {
        switch type {
        case .home:
            let homeCoords = UserDefaults.standard.string(forKey: "userHomeAddress") ?? ""
            return parseCoordinateString(homeCoords)
        case .work:
            let orgCoords = OrganizationService.shared.organizationCoordinates
            return parseCoordinateString(orgCoords)
        }
    }

    /// Checks if an end point type is available (has valid coordinates)
    @MainActor
    static func isEndPointAvailable(_ type: EndPointType) -> Bool {
        return getEndPointCoordinates(for: type) != nil
    }

    // MARK: - Route Optimization

    /// Optimizes the order of schools to visit using Google Route Optimization API
    /// - Parameters:
    ///   - schools: Array of schools to visit
    ///   - startingFrom: Starting location coordinates
    ///   - startingPointType: Labels the origin in the request sent to the Edge
    ///     Function. It is NO LONGER echoed back on the result: that member was
    ///     set on every path and read by nothing, and the converted screen
    ///     snapshots its own start label when it pushes the preview.
    ///   - endLocation: Optional end location coordinates
    ///   - endPointType: Type of end point, carried through to the result
    /// - Returns: OptimizedRouteResult with schools, distances, skipped schools
    ///   and metadata. THROWS rather than returning a zero-mile result when the
    ///   optimization did not actually happen.
    func optimizeRoute(
        schools: [School],
        startingFrom: CLLocationCoordinate2D,
        startingPointType: StartingPointType = .currentLocation,
        endLocation: CLLocationCoordinate2D? = nil,
        endPointType: EndPointType? = nil
    ) async throws -> OptimizedRouteResult {
        // BOTH EMPTY GUARDS THROW. They used to return a zero-mile "result", which
        // is the same failure-masking shape as the missing-order case below: the
        // caller could not tell it apart from a route that really was zero miles
        // long. The converted screen cannot reach either — it refuses to optimize
        // below two ROUTABLE selections — so this is honesty in a path that is
        // now unreachable rather than a behaviour change the user will see.
        guard !schools.isEmpty else { throw RouteOptimizerError.noRoutableSchools }

        // Filter schools with valid coordinates
        let validSchools = schools.filter { $0.parsedCoordinates != nil }
        guard !validSchools.isEmpty else { throw RouteOptimizerError.noRoutableSchools }

        // Build the request body for the Edge Function
        let origin = OptimizeLocation(
            latitude: startingFrom.latitude,
            longitude: startingFrom.longitude,
            label: startingPointType.rawValue
        )

        let destinations = validSchools.compactMap { school -> OptimizeLocation? in
            guard let coords = school.parsedCoordinates else { return nil }
            return OptimizeLocation(
                latitude: coords.lat,
                longitude: coords.lng,
                label: school.name
            )
        }

        // Build end location if specified
        let endLocationRequest: OptimizeLocation? = endLocation.map { coord in
            OptimizeLocation(
                latitude: coord.latitude,
                longitude: coord.longitude,
                label: endPointType?.rawValue ?? "End Point"
            )
        }

        let requestBody = OptimizeRouteRequest(
            origin: origin,
            destinations: destinations,
            endLocation: endLocationRequest
        )

        // Call the Edge Function
        let response: OptimizeRouteResponse = try await supabase.functions.invoke(
            "optimize-route",
            options: .init(body: requestBody)
        )

        // Debug: Log full response
        print("📥 Edge Function Response:")
        print("   Success: \(response.success)")
        print("   Optimized order: \(response.optimizedOrder?.description ?? "nil")")
        print("   Skipped shipments: \(response.skippedShipments?.description ?? "nil")")

        // THE SERVER'S OWN WORDS REACH THE USER. This used to read `response.error`,
        // print it, and then throw a hardcoded `apiError(statusCode: 500)` — so a
        // configuration problem, a quota refusal and a malformed request all
        // surfaced as the same meaningless status code, and five of the seven error
        // cases were unreachable.
        guard response.success else {
            throw RouteOptimizerError.serverMessage(Self.readableMessage(response.error))
        }

        // The schools the router refused. Resolved to NAMES here rather than being
        // printed and dropped — the label the server echoes back is what we sent,
        // and the index is the position in `validSchools`.
        let skippedSchools: [String] = (response.skippedShipments ?? []).map { skip in
            if skip.index >= 0 && skip.index < validSchools.count {
                return validSchools[skip.index].name
            }
            return skip.label ?? "Unknown school"
        }

        // NO SILENT FALLBACK TO THE ORIGINAL ORDER. This used to return the
        // user's own list with `totalDistanceMiles: 0`, and the view's `> 0` gate
        // then hid the totals — so a failed optimization rendered as a route.
        guard let optimizedOrder = response.optimizedOrder, !optimizedOrder.isEmpty else {
            throw RouteOptimizerError.noOrderReturned(Self.readableMessage(response.error))
        }

        // Debug: Log the schools sent and order received
        print("🗺️ Route Optimization Debug:")
        print("   Starting from: \(startingFrom.latitude), \(startingFrom.longitude)")
        print("   Schools sent (in order):")
        for (index, school) in validSchools.enumerated() {
            // Optional-bound rather than force-unwrapped. The filter above makes
            // this safe today, and a `!` that is only safe because of a line
            // fifty lines away is one edit from a crash in a debug print.
            if let coords = school.parsedCoordinates {
                print("     [\(index)] \(school.name) at \(coords.lat), \(coords.lng)")
            }
        }
        print("   Optimized order received from API: \(optimizedOrder)")
        print("   Total distance: \(response.totalDistanceMeters ?? 0)m")
        print("   Legs: \(response.legs?.count ?? 0)")

        // Reorder schools based on the optimized order
        let reorderedSchools: [School] = optimizedOrder.enumerated().compactMap { (position, index) -> School? in
            guard index >= 0 && index < validSchools.count else {
                print("⚠️ Invalid school index \(index) in optimized order")
                return nil
            }
            print("     Reordered position \(position + 1): \(validSchools[index].name)")
            return validSchools[index]
        }

        // Extract distance data
        let totalDistanceMeters = response.totalDistanceMeters ?? 0
        let totalDurationSeconds = response.totalDurationSeconds ?? 0
        let legs = response.legs ?? []

        return OptimizedRouteResult(
            schools: reorderedSchools,
            totalDistanceMiles: totalDistanceMeters * 0.000621371,
            totalDurationMinutes: totalDurationSeconds / 60.0,
            legs: legs,
            skippedSchools: skippedSchools,
            endPointType: endPointType
        )
    }

    /// The server's message, trimmed — or nil when it said nothing usable, so the
    /// error type can supply its own wording rather than printing "Unknown error"
    /// at the user.
    private static func readableMessage(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    // MARK: - Map App URLs

    /// Generates a URL to open the route in Apple Maps
    /// - Parameters:
    ///   - schools: Schools in the order to visit
    ///   - startingPoint: Type of starting point
    ///   - endLocation: Optional end location coordinates
    /// - Returns: URL for Apple Maps, or nil if invalid
    @MainActor
    static func appleMapsURL(
        for schools: [School],
        startingPoint: StartingPointType = .currentLocation,
        endLocation: CLLocationCoordinate2D? = nil
    ) -> URL? {
        guard !schools.isEmpty else { return nil }

        var urlString = "maps://?"

        // Set starting address
        switch startingPoint {
        case .currentLocation:
            urlString += "saddr=Current+Location"
        case .homeAddress:
            if let coords = getCoordinates(for: .homeAddress, currentLocation: nil) {
                urlString += "saddr=\(coords.latitude),\(coords.longitude)"
            } else {
                urlString += "saddr=Current+Location"
            }
        case .workAddress:
            if let coords = getCoordinates(for: .workAddress, currentLocation: nil) {
                urlString += "saddr=\(coords.latitude),\(coords.longitude)"
            } else {
                urlString += "saddr=Current+Location"
            }
        }

        urlString += "&dirflg=d"

        // Add all schools as waypoints
        for school in schools {
            if let coords = school.parsedCoordinates {
                urlString += "&daddr=\(coords.lat),\(coords.lng)"
            }
        }

        // Add end location if specified
        if let end = endLocation {
            urlString += "&daddr=\(end.latitude),\(end.longitude)"
        }

        return URL(string: urlString)
    }

    /// Generates a URL to open the route in Google Maps
    /// - Parameters:
    ///   - schools: Schools in the order to visit
    ///   - startingPoint: Type of starting point
    ///   - endLocation: Optional end location coordinates
    /// - Returns: URL for Google Maps, or nil if invalid
    @MainActor
    static func googleMapsURL(
        for schools: [School],
        startingPoint: StartingPointType = .currentLocation,
        endLocation: CLLocationCoordinate2D? = nil
    ) -> URL? {
        guard !schools.isEmpty else { return nil }

        // Google Maps URL format:
        // https://www.google.com/maps/dir/?api=1&origin=LAT,LNG&destination=LAT,LNG&waypoints=LAT1,LNG1|LAT2,LNG2&travelmode=driving

        var urlString = "https://www.google.com/maps/dir/?api=1&travelmode=driving"

        // Set origin
        switch startingPoint {
        case .currentLocation:
            urlString += "&origin=Current+Location"
        case .homeAddress:
            if let coords = getCoordinates(for: .homeAddress, currentLocation: nil) {
                urlString += "&origin=\(coords.latitude),\(coords.longitude)"
            } else {
                urlString += "&origin=Current+Location"
            }
        case .workAddress:
            if let coords = getCoordinates(for: .workAddress, currentLocation: nil) {
                urlString += "&origin=\(coords.latitude),\(coords.longitude)"
            } else {
                urlString += "&origin=Current+Location"
            }
        }

        // Determine destination (end location or last school)
        if let end = endLocation {
            urlString += "&destination=\(end.latitude),\(end.longitude)"

            // All schools are waypoints
            let waypoints = schools.compactMap { school -> String? in
                guard let coords = school.parsedCoordinates else { return nil }
                return "\(coords.lat),\(coords.lng)"
            }

            if !waypoints.isEmpty {
                urlString += "&waypoints=\(waypoints.joined(separator: "|"))"
            }
        } else {
            // Last school is the destination
            if let lastSchool = schools.last, let coords = lastSchool.parsedCoordinates {
                urlString += "&destination=\(coords.lat),\(coords.lng)"
            }

            // All other schools are waypoints
            if schools.count > 1 {
                let waypoints = schools.dropLast().compactMap { school -> String? in
                    guard let coords = school.parsedCoordinates else { return nil }
                    return "\(coords.lat),\(coords.lng)"
                }

                if !waypoints.isEmpty {
                    urlString += "&waypoints=\(waypoints.joined(separator: "|"))"
                }
            }
        }

        return URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString)
    }
}

// MARK: - Private Request/Response Models

private struct OptimizeLocation: Codable {
    let latitude: Double
    let longitude: Double
    let label: String?
}

private struct OptimizeRouteRequest: Codable {
    let origin: OptimizeLocation
    let destinations: [OptimizeLocation]
    let endLocation: OptimizeLocation?
}

private struct SkippedShipment: Codable {
    let index: Int
    let label: String?
}

private struct OptimizeRouteResponse: Codable {
    let success: Bool
    let optimizedOrder: [Int]?
    let totalDistanceMeters: Double?
    let totalDurationSeconds: Double?
    let legs: [RouteLeg]?
    let error: String?
    let skippedShipments: [SkippedShipment]?
}

// MARK: - Errors

/// THREE CASES, ALL OF THEM REACHABLE.
///
/// There were seven, five of them unreachable — `invalidURL`, `invalidResponse`,
/// `noApiKey`, `noProjectID` and `noStartingPoint` were never thrown from anywhere
/// (the API keys live in the Edge Function, not the app), and the one that WAS
/// thrown, `apiError(statusCode: 500)`, was a hardcoded number standing in front
/// of the message the server had actually sent. Deleted rather than left as a menu
/// of errors the app cannot produce.
enum RouteOptimizerError: Error, LocalizedError {
    /// The Edge Function reported failure. Carries the server's own text when it
    /// sent any.
    case serverMessage(String?)
    /// The call succeeded but came back with no order — the case that used to be
    /// disguised as a zero-mile route.
    case noOrderReturned(String?)
    /// Nothing was sent that could be routed. Unreachable from the converted
    /// screen, which refuses to optimize below two routable schools.
    case noRoutableSchools

    var errorDescription: String? {
        switch self {
        case .serverMessage(let message):
            return message ?? "The route service reported an error but did not say what it was."
        case .noOrderReturned(let message):
            return message ?? "The route service did not return an order for these schools."
        case .noRoutableSchools:
            return "None of the selected schools have a map pin, so there is nothing to route."
        }
    }
}
