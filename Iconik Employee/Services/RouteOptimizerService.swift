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
enum StartingPointType: String, CaseIterable, Identifiable {
    case currentLocation = "Current Location"
    case homeAddress = "Home Address"
    case workAddress = "Work Address"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .currentLocation: return "location.fill"
        case .homeAddress: return "house.fill"
        case .workAddress: return "building.2.fill"
        }
    }

    var shortName: String {
        switch self {
        case .currentLocation: return "Current"
        case .homeAddress: return "Home"
        case .workAddress: return "Work"
        }
    }
}

/// End point options for route optimization
enum EndPointType: String, CaseIterable, Identifiable {
    case home = "Home"
    case work = "Work"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .work: return "building.2.fill"
        }
    }
}

/// Distance/duration information for a route leg
struct RouteLeg: Codable {
    let distanceMeters: Double
    let durationSeconds: Double

    var distanceMiles: Double {
        distanceMeters * 0.000621371
    }

    var durationMinutes: Double {
        durationSeconds / 60.0
    }

    var formattedDistance: String {
        String(format: "%.1f mi", distanceMiles)
    }

    var formattedDuration: String {
        let minutes = Int(durationMinutes)
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        }
    }
}

/// Result of route optimization including schools and distance data
struct OptimizedRouteResult {
    let schools: [School]
    let totalDistanceMiles: Double
    let totalDurationMinutes: Double
    let legs: [RouteLeg]
    let startingPointType: StartingPointType
    let endPointType: EndPointType?

    var formattedTotalDistance: String {
        String(format: "%.1f mi", totalDistanceMiles)
    }

    var formattedTotalDuration: String {
        let minutes = Int(totalDurationMinutes)
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return "\(hours)h \(remainingMinutes)m"
        }
    }
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

    /// Checks if a starting point type is available (has valid coordinates)
    @MainActor
    static func isStartingPointAvailable(_ type: StartingPointType, currentLocation: CLLocationCoordinate2D?) -> Bool {
        return getCoordinates(for: type, currentLocation: currentLocation) != nil
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
    ///   - startingPointType: Type of starting point for display purposes
    ///   - endLocation: Optional end location coordinates
    ///   - endPointType: Type of end point for display purposes
    /// - Returns: OptimizedRouteResult with schools, distances, and metadata
    func optimizeRoute(
        schools: [School],
        startingFrom: CLLocationCoordinate2D,
        startingPointType: StartingPointType = .currentLocation,
        endLocation: CLLocationCoordinate2D? = nil,
        endPointType: EndPointType? = nil
    ) async throws -> OptimizedRouteResult {
        guard !schools.isEmpty else {
            return OptimizedRouteResult(
                schools: [],
                totalDistanceMiles: 0,
                totalDurationMinutes: 0,
                legs: [],
                startingPointType: startingPointType,
                endPointType: endPointType
            )
        }

        // Filter schools with valid coordinates
        let validSchools = schools.filter { $0.parsedCoordinates != nil }
        guard !validSchools.isEmpty else {
            return OptimizedRouteResult(
                schools: [],
                totalDistanceMiles: 0,
                totalDurationMinutes: 0,
                legs: [],
                startingPointType: startingPointType,
                endPointType: endPointType
            )
        }

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

        guard response.success else {
            let errorMessage = response.error ?? "Unknown error"
            print("RouteOptimizerService: Edge Function error: \(errorMessage)")
            throw RouteOptimizerError.apiError(statusCode: 500)
        }

        // Log any skipped shipments
        if let skipped = response.skippedShipments, !skipped.isEmpty {
            print("⚠️ Google API skipped \(skipped.count) shipment(s):")
            for skip in skipped {
                print("   - Index \(skip.index): \(skip.label ?? "Unknown")")
            }
        } else {
            print("✅ No skipped shipments (or field is nil)")
        }

        guard let optimizedOrder = response.optimizedOrder, !optimizedOrder.isEmpty else {
            print("RouteOptimizerService: No optimized order returned, using original order")
            return OptimizedRouteResult(
                schools: validSchools,
                totalDistanceMiles: 0,
                totalDurationMinutes: 0,
                legs: [],
                startingPointType: startingPointType,
                endPointType: endPointType
            )
        }

        // Debug: Log the schools sent and order received
        print("🗺️ Route Optimization Debug:")
        print("   Starting from: \(startingFrom.latitude), \(startingFrom.longitude)")
        print("   Schools sent (in order):")
        for (index, school) in validSchools.enumerated() {
            let coords = school.parsedCoordinates!
            print("     [\(index)] \(school.name) at \(coords.lat), \(coords.lng)")
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
            startingPointType: startingPointType,
            endPointType: endPointType
        )
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

enum RouteOptimizerError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case apiError(statusCode: Int)
    case noApiKey
    case noProjectID
    case noStartingPoint

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL for route optimization"
        case .invalidResponse:
            return "Invalid response from route optimization API"
        case .apiError(let statusCode):
            return "Route optimization API error (status: \(statusCode))"
        case .noApiKey:
            return "Google API key not configured"
        case .noProjectID:
            return "Google Cloud Project ID not configured"
        case .noStartingPoint:
            return "Starting point address not available"
        }
    }
}
