import Foundation
import CoreLocation
import Combine

// Google Places API Service
class GooglePlacesService: ObservableObject {
    static let shared = GooglePlacesService()
    
    private let apiKey = "AIzaSyA3kS7YLt4XqYodsfn8TAo8Y4Hcu3UJnSE"
    private let baseURL = "https://places.googleapis.com/v1/places"
    private let legacyBaseURL = "https://maps.googleapis.com/maps/api/place"
    private let geocodeURL = "https://maps.googleapis.com/maps/api/geocode"
    
    @Published var predictions: [PlacePrediction] = []
    @Published var isLoading = false
    
    private var cancellables = Set<AnyCancellable>()
    private var searchWorkItem: DispatchWorkItem?
    
    struct PlacePrediction: Identifiable {
        let id: String
        let primaryText: String
        let secondaryText: String
        let fullText: String
    }
    
    struct PlaceDetails {
        let formattedAddress: String
        let coordinate: CLLocationCoordinate2D
        let streetNumber: String?
        let route: String?
        let city: String?
        let state: String?
        let postalCode: String?
        let country: String?
    }
    
    private init() {}
    
    // MARK: - Autocomplete
    
    func searchPlaces(query: String, centerCoordinates: String? = nil, sessionToken: String? = nil) {
        // Cancel any existing search
        searchWorkItem?.cancel()
        
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            predictions = []
            return
        }
        
        // Debounce the search
        let workItem = DispatchWorkItem { [weak self] in
            self?.performSearch(query: query, centerCoordinates: centerCoordinates, sessionToken: sessionToken)
        }
        
        searchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }
    
    private func performSearch(query: String, centerCoordinates: String? = nil, sessionToken: String?) {
        isLoading = true
        print("🔍 GooglePlaces: Starting search for query: '\(query)'")
        
        let url = URL(string: "\(baseURL):autocomplete")!
        
        // Parse center coordinates if provided
        var latitude = 39.8283  // Default to US center
        var longitude = -98.5795
        
        if let centerCoordinates = centerCoordinates {
            let parts = centerCoordinates.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            if parts.count == 2,
               let lat = Double(parts[0]),
               let lng = Double(parts[1]) {
                latitude = lat
                longitude = lng
                print("📍 Using organization center: \(latitude), \(longitude)")
            }
        }
        
        // Create request body
        var requestBody: [String: Any] = [
            "input": query,
            "locationBias": [
                "circle": [
                    "center": [
                        "latitude": latitude,
                        "longitude": longitude
                    ],
                    "radius": 50000.0  // Maximum allowed radius (50km)
                ]
            ],
            "includedPrimaryTypes": ["street_address", "street_number", "route", "locality"],
            "languageCode": "en-US"
        ]
        
        if let sessionToken = sessionToken {
            requestBody["sessionToken"] = sessionToken
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue("Iconik.Iconik-Employee", forHTTPHeaderField: "X-iOS-Bundle-Identifier")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            print("❌ GooglePlaces: Failed to create request body: \(error)")
            return
        }
        
        print("🔍 GooglePlaces: Request URL: \(url.absoluteString)")
        
        URLSession.shared.dataTaskPublisher(for: request)
            .tryMap { data, response in
                if let httpResponse = response as? HTTPURLResponse {
                    print("🔍 GooglePlaces: Response status code: \(httpResponse.statusCode)")
                    if httpResponse.statusCode != 200 {
                        if let errorString = String(data: data, encoding: .utf8) {
                            print("❌ GooglePlaces: Error response: \(errorString)")
                        }
                    }
                }
                return data
            }
            .decode(type: AutocompleteNewResponse.self, decoder: JSONDecoder())
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isLoading = false
                    if case .failure(let error) = completion {
                        print("❌ GooglePlaces: Autocomplete error: \(error)")
                        self?.predictions = []
                    }
                },
                receiveValue: { [weak self] response in
                    print("✅ GooglePlaces: Received \(response.suggestions?.count ?? 0) suggestions")
                    
                    self?.predictions = response.suggestions?.compactMap { suggestion in
                        guard let placePrediction = suggestion.placePrediction else { return nil }
                        
                        let fullText = placePrediction.text.text
                        let components = fullText.components(separatedBy: ", ")
                        let primaryText = components.first ?? fullText
                        let secondaryText = components.dropFirst().joined(separator: ", ")
                        
                        let result = PlacePrediction(
                            id: placePrediction.placeId ?? placePrediction.place,
                            primaryText: primaryText,
                            secondaryText: secondaryText,
                            fullText: fullText
                        )
                        print("  📍 \(result.fullText)")
                        return result
                    } ?? []
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Place Details
    
    func getPlaceDetails(placeId: String, sessionToken: String? = nil, completion: @escaping (Result<PlaceDetails, Error>) -> Void) {
        print("🔍 GooglePlaces: Getting details for placeId: \(placeId)")
        
        // Still using legacy API for place details until we implement the new one
        var components = URLComponents(string: "\(legacyBaseURL)/details/json")!
        components.queryItems = [
            URLQueryItem(name: "place_id", value: placeId),
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "fields", value: "formatted_address,geometry,address_components")
        ]
        
        if let sessionToken = sessionToken {
            components.queryItems?.append(URLQueryItem(name: "sessiontoken", value: sessionToken))
        }
        
        guard let url = components.url else {
            completion(.failure(NSError(domain: "GooglePlacesService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Iconik.Iconik-Employee", forHTTPHeaderField: "X-iOS-Bundle-Identifier")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "GooglePlacesService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                }
                return
            }
            
            do {
                let response = try JSONDecoder().decode(PlaceDetailsResponse.self, from: data)
                
                if let result = response.result {
                    let coordinate = CLLocationCoordinate2D(
                        latitude: result.geometry.location.lat,
                        longitude: result.geometry.location.lng
                    )
                    
                    var streetNumber: String?
                    var route: String?
                    var city: String?
                    var state: String?
                    var postalCode: String?
                    var country: String?
                    
                    // Parse address components
                    for component in result.addressComponents {
                        if component.types.contains("street_number") {
                            streetNumber = component.longName
                        } else if component.types.contains("route") {
                            route = component.longName
                        } else if component.types.contains("locality") {
                            city = component.longName
                        } else if component.types.contains("administrative_area_level_1") {
                            state = component.shortName
                        } else if component.types.contains("postal_code") {
                            postalCode = component.longName
                        } else if component.types.contains("country") {
                            country = component.longName
                        }
                    }
                    
                    let placeDetails = PlaceDetails(
                        formattedAddress: result.formattedAddress,
                        coordinate: coordinate,
                        streetNumber: streetNumber,
                        route: route,
                        city: city,
                        state: state,
                        postalCode: postalCode,
                        country: country
                    )
                    
                    print("✅ GooglePlaces: Place details:")
                    print("  📍 Formatted Address: \(result.formattedAddress)")
                    print("  📍 Coordinates: \(coordinate.latitude), \(coordinate.longitude)")
                    print("  📍 City: \(city ?? "N/A"), State: \(state ?? "N/A"), Zip: \(postalCode ?? "N/A")")
                    
                    DispatchQueue.main.async {
                        completion(.success(placeDetails))
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "GooglePlacesService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No place details found"])))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    // MARK: - Geocoding
    
    func geocodeAddress(_ address: String, completion: @escaping (Result<CLLocationCoordinate2D, Error>) -> Void) {
        var components = URLComponents(string: "\(geocodeURL)/json")!
        components.queryItems = [
            URLQueryItem(name: "address", value: address),
            URLQueryItem(name: "key", value: apiKey)
        ]
        
        guard let url = components.url else {
            completion(.failure(NSError(domain: "GooglePlacesService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Iconik.Iconik-Employee", forHTTPHeaderField: "X-iOS-Bundle-Identifier")
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "GooglePlacesService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                }
                return
            }
            
            do {
                let response = try JSONDecoder().decode(GeocodeResponse.self, from: data)
                
                if let result = response.results.first {
                    let coordinate = CLLocationCoordinate2D(
                        latitude: result.geometry.location.lat,
                        longitude: result.geometry.location.lng
                    )
                    
                    DispatchQueue.main.async {
                        completion(.success(coordinate))
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(NSError(domain: "GooglePlacesService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No results found"])))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    // Clear predictions
    func clearPredictions() {
        predictions = []
    }
}

// MARK: - Response Models

// New API Response
private struct AutocompleteNewResponse: Codable {
    let suggestions: [Suggestion]?
    
    struct Suggestion: Codable {
        let placePrediction: PlacePrediction?
        let queryPrediction: QueryPrediction?
    }
    
    struct PlacePrediction: Codable {
        let place: String
        let placeId: String?
        let text: TextInfo
        let structuredFormat: StructuredFormat?
        let types: [String]?
        
        struct TextInfo: Codable {
            let text: String
            let matches: [TextMatch]?
        }
        
        struct TextMatch: Codable {
            let startOffset: Int?
            let endOffset: Int?
        }
        
        struct StructuredFormat: Codable {
            let mainText: TextInfo?
            let secondaryText: TextInfo?
        }
    }
    
    struct QueryPrediction: Codable {
        let text: TextInfo
        
        struct TextInfo: Codable {
            let text: String
            let matches: [TextMatch]?
        }
        
        struct TextMatch: Codable {
            let startOffset: Int?
            let endOffset: Int?
        }
    }
}

// Legacy API Response (keeping for reference)
private struct AutocompleteResponse: Codable {
    let predictions: [Prediction]
    let status: String?
    let errorMessage: String?
    
    enum CodingKeys: String, CodingKey {
        case predictions
        case status
        case errorMessage = "error_message"
    }
    
    struct Prediction: Codable {
        let description: String
        let placeId: String
        let structuredFormatting: StructuredFormatting
        
        enum CodingKeys: String, CodingKey {
            case description
            case placeId = "place_id"
            case structuredFormatting = "structured_formatting"
        }
    }
    
    struct StructuredFormatting: Codable {
        let mainText: String
        let secondaryText: String?
        
        enum CodingKeys: String, CodingKey {
            case mainText = "main_text"
            case secondaryText = "secondary_text"
        }
    }
}

private struct PlaceDetailsResponse: Codable {
    let result: PlaceResult?
    
    struct PlaceResult: Codable {
        let formattedAddress: String
        let geometry: Geometry
        let addressComponents: [AddressComponent]
        
        enum CodingKeys: String, CodingKey {
            case formattedAddress = "formatted_address"
            case geometry
            case addressComponents = "address_components"
        }
    }
    
    struct Geometry: Codable {
        let location: Location
    }
    
    struct Location: Codable {
        let lat: Double
        let lng: Double
    }
    
    struct AddressComponent: Codable {
        let longName: String
        let shortName: String
        let types: [String]
        
        enum CodingKeys: String, CodingKey {
            case longName = "long_name"
            case shortName = "short_name"
            case types
        }
    }
}

private struct GeocodeResponse: Codable {
    let results: [GeocodeResult]
    
    struct GeocodeResult: Codable {
        let geometry: Geometry
    }
    
    struct Geometry: Codable {
        let location: Location
    }
    
    struct Location: Codable {
        let lat: Double
        let lng: Double
    }
}