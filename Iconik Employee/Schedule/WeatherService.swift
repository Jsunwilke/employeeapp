import Foundation
import CoreLocation
import SwiftUI

// Simplified weather data for UI display
struct WeatherData {
    let temperature: Double?      // in Fahrenheit
    let tempMin: Double?
    let tempMax: Double?
    let windSpeed: Double?        // in mph
    let windDirection: Int?       // in degrees
    let condition: String?        // e.g., "Clear", "Clouds", "Rain"
    let description: String?      // e.g., "clear sky", "scattered clouds"
    let iconSystemName: String?   // SF Symbol name
    let timestamp: Date
    let isForecast: Bool          // Indicates if this is forecast data
    
    // Helper to get a color based on condition
    var conditionColor: Color {
        guard let condition = condition?.lowercased() else { return .gray }
        
        switch condition {
        case "clear sky", "sunny", "mostly clear":
            return .yellow
        case "partly cloudy", "mostly cloudy", "cloudy", "overcast", "fog":
            return .gray
        case "rain", "drizzle", "showers":
            return .blue
        case "thunderstorm":
            return .purple
        case "snow", "sleet", "mixed", "ice":
            return .cyan
        default:
            return .gray
        }
    }
    
    // Simple formatted temperature string
    var temperatureString: String {
        guard let temp = temperature else { return "-- °F" }
        return "\(Int(round(temp)))°F"
    }
    
    var tempRangeString: String {
        if let min = tempMin, let max = tempMax {
            return "H:\(Int(round(max)))° L:\(Int(round(min)))°"
        }
        return "H:--° L:--°"
    }
    
    var windString: String {
        guard let speed = windSpeed else { return "-- mph" }
        
        var direction = ""
        if let degrees = windDirection {
            // Convert degrees to cardinal direction
            let directions = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
            let index = Int((Double(degrees) + 22.5) / 45.0) % 8
            direction = " " + directions[index]
        }
        
        return "\(Int(round(speed))) mph\(direction)"
    }
    
    // Create a "Weather Unavailable" state
    static func unavailable(message: String = "Weather data unavailable") -> WeatherData {
        return WeatherData(
            temperature: nil,
            tempMin: nil,
            tempMax: nil,
            windSpeed: nil,
            windDirection: nil,
            condition: nil,
            description: nil,
            iconSystemName: "exclamationmark.icloud",
            timestamp: Date(),
            isForecast: false
        )
    }
}

// Weather service using Open-Meteo API
class WeatherService {
    // Cache weather data with expiration time (30 minutes)
    private var cachedWeather: [String: (data: WeatherData, expiry: Date)] = [:]
    
    // Debug flag - set to true for verbose logging
    private let debug = true
    
    // Public API to get weather data by location name and date
    func getWeatherData(for location: String, date: Date? = nil, completion: @escaping (WeatherData?, String?) -> Void) {
        // Determine if this is a future forecast request
        let targetDate = date ?? Date()
        let isFuture = Calendar.current.isDateInFuture(targetDate)
        let cacheKey = generateCacheKey(location: location, date: targetDate)
        
        debugLog("Request for weather at \(location) on \(targetDate), isFuture: \(isFuture)")
        
        // Check cache first
        if let cached = cachedWeather[cacheKey], cached.expiry > Date() {
            debugLog("Using cached weather data for \(cacheKey)")
            completion(cached.data, nil)
            return
        }
        
        debugLog("Geocoding address: \(location)")
        
        // Convert address to coordinates using geocoding
        let geocoder = CLGeocoder()
        geocoder.geocodeAddressString(location) { [weak self] placemarks, error in
            if let error = error {
                print("Error geocoding address: \(error.localizedDescription)")
                completion(nil, "Could not find location: \(location)")
                return
            }
            
            guard let self = self, let placemark = placemarks?.first, let location = placemark.location else {
                print("No location found for address")
                completion(nil, "Could not find location")
                return
            }
            
            self.debugLog("Successfully geocoded to coordinates: \(location.coordinate.latitude), \(location.coordinate.longitude)")
            
            // Now get weather using coordinates for the specified date
            self.getWeatherData(latitude: location.coordinate.latitude,
                               longitude: location.coordinate.longitude,
                               date: targetDate,
                               completion: completion)
        }
    }
    
    // Public API to get weather data by coordinates and date
    func getWeatherData(latitude: Double, longitude: Double, date: Date? = nil, completion: @escaping (WeatherData?, String?) -> Void) {
        // Determine if this is a future forecast request
        let targetDate = date ?? Date()
        let isFuture = Calendar.current.isDateInFuture(targetDate)
        let cacheKey = generateCacheKey(latitude: latitude, longitude: longitude, date: targetDate)
        
        debugLog("Request for weather at (\(latitude), \(longitude)) on \(targetDate), isFuture: \(isFuture)")
        
        // Check cache first
        if let cached = cachedWeather[cacheKey], cached.expiry > Date() {
            debugLog("Using cached weather data for \(cacheKey)")
            completion(cached.data, nil)
            return
        }
        
        debugLog("Fetching \(isFuture ? "forecast" : "current") weather data for coordinates: \(latitude), \(longitude)")
        
        // Calculate days in future for forecast
        let daysInFuture = calculateDaysFromToday(date: targetDate)
        debugLog("Target date is \(daysInFuture) days from today")
        
        // Call Open-Meteo API
        fetchOpenMeteoData(latitude: latitude, longitude: longitude, daysInFuture: daysInFuture) { [weak self] weatherData, errorMessage in
            guard let self = self else { return }
            
            if let weatherData = weatherData {
                // Cache the result
                let expiryDate = Date().addingTimeInterval(30 * 60) // 30 minutes
                self.cachedWeather[cacheKey] = (weatherData, expiryDate)
                
                self.debugLog("Successfully retrieved weather data: \(weatherData.temperature?.description ?? "nil") °F, \(weatherData.condition ?? "nil")")
                
                // Return the successful result
                completion(weatherData, nil)
            } else {
                self.debugLog("Failed to retrieve weather data: \(errorMessage ?? "Unknown error")")
                // Return error
                completion(nil, errorMessage)
            }
        }
    }
    
    // MARK: - Open-Meteo API Integration
    
    private func fetchOpenMeteoData(latitude: Double, longitude: Double, daysInFuture: Int, completion: @escaping (WeatherData?, String?) -> Void) {
        // Calculate the correct endpoint and parameters based on whether we need future forecast
        let isForecast = daysInFuture > 0
        
        // Set up the URL for current or forecast data
        var urlComponents = [
            "latitude=\(latitude)",
            "longitude=\(longitude)",
            "temperature_unit=fahrenheit",
            "timezone=auto"
        ]
        
        // Add parameters for current or forecast data
        if isForecast && daysInFuture <= 16 { // Open-Meteo supports up to 16 days forecast
            // We need forecast data for a future day
            urlComponents.append("daily=temperature_2m_max,temperature_2m_min,weather_code,wind_speed_10m_max,wind_direction_10m_dominant")
            urlComponents.append("forecast_days=\(daysInFuture + 1)") // +1 to include the target day
            urlComponents.append("wind_speed_unit=mph")
        } else {
            // Use current or today's data
            urlComponents.append("current=temperature_2m,weather_code,wind_speed_10m,wind_direction_10m")
            urlComponents.append("daily=temperature_2m_max,temperature_2m_min,weather_code,wind_speed_10m_max,wind_direction_10m_dominant")
            urlComponents.append("forecast_days=1")
            urlComponents.append("wind_speed_unit=mph")
        }
        
        // Construct the URL
        let urlString = "https://api.open-meteo.com/v1/forecast?\(urlComponents.joined(separator: "&"))"
        
        debugLog("Open-Meteo API URL: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            debugLog("Invalid URL created")
            completion(nil, "Invalid URL for weather service")
            return
        }
        
        let task = URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }
            
            // Check for network error
            if let error = error {
                print("Network error: \(error.localizedDescription)")
                completion(nil, "Network error: Unable to connect to weather service")
                return
            }
            
            // Check HTTP status
            if let httpResponse = response as? HTTPURLResponse {
                self.debugLog("HTTP Status: \(httpResponse.statusCode)")
                
                if httpResponse.statusCode != 200 {
                    completion(nil, "Weather service error (HTTP \(httpResponse.statusCode))")
                    return
                }
            }
            
            // Check data
            guard let data = data else {
                self.debugLog("No data received from API")
                completion(nil, "No data received from weather service")
                return
            }
            
            // Log raw response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                self.debugLog("API Response: \(responseString)")
            }
            
            do {
                // Parse JSON
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    // Check for API error response
                    if let error = json["error"] as? Bool, error == true,
                       let reason = json["reason"] as? String {
                        self.debugLog("API returned error: \(reason)")
                        completion(nil, "Weather API error: \(reason)")
                        return
                    }
                    
                    // Extract weather data
                    let weatherData = self.parseOpenMeteoData(json: json, daysInFuture: daysInFuture)
                    completion(weatherData, nil)
                } else {
                    self.debugLog("Failed to parse response as JSON dictionary")
                    completion(nil, "Invalid response format")
                }
            } catch {
                self.debugLog("JSON parsing error: \(error.localizedDescription)")
                completion(nil, "Error processing weather data")
            }
        }
        
        task.resume()
    }
    
    // Parse Open-Meteo JSON response
    private func parseOpenMeteoData(json: [String: Any], daysInFuture: Int) -> WeatherData? {
        debugLog("Parsing Open-Meteo data for day \(daysInFuture) in future")
        
        let isForecast = daysInFuture > 0
        var temperature: Double?
        var tempMin: Double?
        var tempMax: Double?
        var windSpeed: Double?
        var windDirection: Int?
        var weatherCode: Int?
        
        if isForecast && daysInFuture <= 16 {
            // Extract from daily forecast for future dates
            if let daily = json["daily"] as? [String: Any] {
                debugLog("Daily data: \(daily)")
                
                // Get forecast for the specific future day
                if let minTemps = daily["temperature_2m_min"] as? [Double], daysInFuture < minTemps.count {
                    tempMin = minTemps[daysInFuture]
                    debugLog("Min temperature for day \(daysInFuture): \(minTemps[daysInFuture])°F")
                }
                
                if let maxTemps = daily["temperature_2m_max"] as? [Double], daysInFuture < maxTemps.count {
                    tempMax = maxTemps[daysInFuture]
                    debugLog("Max temperature for day \(daysInFuture): \(maxTemps[daysInFuture])°F")
                    
                    // Use max temp as the main temperature for future days
                    temperature = maxTemps[daysInFuture]
                }
                
                if let codes = daily["weather_code"] as? [Int], daysInFuture < codes.count {
                    weatherCode = codes[daysInFuture]
                    debugLog("Weather code for day \(daysInFuture): \(codes[daysInFuture])")
                }
                
                // Extract wind data for future days
                if let winds = daily["wind_speed_10m_max"] as? [Double], daysInFuture < winds.count {
                    windSpeed = winds[daysInFuture]
                    debugLog("Wind speed for day \(daysInFuture): \(winds[daysInFuture]) mph")
                }
                
                if let directions = daily["wind_direction_10m_dominant"] as? [Int], daysInFuture < directions.count {
                    windDirection = directions[daysInFuture]
                    debugLog("Wind direction for day \(daysInFuture): \(directions[daysInFuture])°")
                }
            } else {
                debugLog("Missing 'daily' in response for forecast")
            }
        } else {
            // Extract current conditions for today
            if let current = json["current"] as? [String: Any] {
                debugLog("Current data: \(current)")
                
                if let temp = current["temperature_2m"] as? Double {
                    temperature = temp
                    debugLog("Current temperature: \(temp)°F")
                }
                
                if let code = current["weather_code"] as? Int {
                    weatherCode = code
                    debugLog("Current weather code: \(code)")
                }
                
                // Extract current wind data
                if let ws = current["wind_speed_10m"] as? Double {
                    windSpeed = ws
                    debugLog("Current wind speed: \(ws) mph")
                }
                
                if let wd = current["wind_direction_10m"] as? Int {
                    windDirection = wd
                    debugLog("Current wind direction: \(wd)°")
                }
            } else {
                debugLog("Missing 'current' in response")
            }
            
            // Extract min/max from daily for today
            if let daily = json["daily"] as? [String: Any] {
                if let minTemps = daily["temperature_2m_min"] as? [Double], !minTemps.isEmpty {
                    tempMin = minTemps[0]
                    debugLog("Today's min temperature: \(minTemps[0])°F")
                }
                
                if let maxTemps = daily["temperature_2m_max"] as? [Double], !maxTemps.isEmpty {
                    tempMax = maxTemps[0]
                    debugLog("Today's max temperature: \(maxTemps[0])°F")
                }
                
                // If we couldn't get current weather code, fall back to daily
                if weatherCode == nil, let codes = daily["weather_code"] as? [Int], !codes.isEmpty {
                    weatherCode = codes[0]
                    debugLog("Using daily weather code: \(codes[0])")
                }
                
                // If we couldn't get current wind data, fall back to daily
                if windSpeed == nil, let winds = daily["wind_speed_10m_max"] as? [Double], !winds.isEmpty {
                    windSpeed = winds[0]
                    debugLog("Using daily wind speed: \(winds[0]) mph")
                }
                
                if windDirection == nil, let directions = daily["wind_direction_10m_dominant"] as? [Int], !directions.isEmpty {
                    windDirection = directions[0]
                    debugLog("Using daily wind direction: \(directions[0])°")
                }
            }
        }
        
        // Map weather code to condition text and icon
        let (condition, description, iconName) = mapWeatherCode(weatherCode)
        debugLog("Mapped weather code \(weatherCode?.description ?? "nil") to condition: \(condition ?? "nil"), icon: \(iconName ?? "nil")")
        
        return WeatherData(
            temperature: temperature,
            tempMin: tempMin,
            tempMax: tempMax,
            windSpeed: windSpeed,
            windDirection: windDirection,
            condition: condition,
            description: description,
            iconSystemName: iconName,
            timestamp: Date(),
            isForecast: isForecast
        )
    }
    
    // Map WMO weather codes to user-friendly text and SF Symbols
    // Based on Open-Meteo weather code documentation
    private func mapWeatherCode(_ code: Int?) -> (String?, String?, String?) {
        guard let code = code else {
            return (nil, nil, "exclamationmark.icloud")
        }
        
        switch code {
        case 0:
            return ("Clear sky", "Clear sky", "sun.max.fill")
        case 1:
            return ("Mostly clear", "Mainly clear", "sun.max.fill")
        case 2:
            return ("Partly cloudy", "Partly cloudy", "cloud.sun.fill")
        case 3:
            return ("Cloudy", "Overcast", "cloud.fill")
        case 45, 48:
            return ("Fog", "Fog or depositing rime fog", "cloud.fog.fill")
        case 51:
            return ("Drizzle", "Light drizzle", "cloud.drizzle.fill")
        case 53:
            return ("Drizzle", "Moderate drizzle", "cloud.drizzle.fill")
        case 55:
            return ("Drizzle", "Dense drizzle", "cloud.drizzle.fill")
        case 56, 57:
            return ("Freezing Drizzle", "Freezing drizzle", "cloud.sleet.fill")
        case 61:
            return ("Rain", "Slight rain", "cloud.rain.fill")
        case 63:
            return ("Rain", "Moderate rain", "cloud.rain.fill")
        case 65:
            return ("Rain", "Heavy rain", "cloud.heavyrain.fill")
        case 66, 67:
            return ("Freezing Rain", "Freezing rain", "cloud.sleet.fill")
        case 71:
            return ("Snow", "Slight snow fall", "cloud.snow.fill")
        case 73:
            return ("Snow", "Moderate snow fall", "cloud.snow.fill")
        case 75:
            return ("Snow", "Heavy snow fall", "cloud.snow.fill")
        case 77:
            return ("Snow grains", "Snow grains", "cloud.snow.fill")
        case 80:
            return ("Rain showers", "Slight rain showers", "cloud.sun.rain.fill")
        case 81:
            return ("Rain showers", "Moderate rain showers", "cloud.sun.rain.fill")
        case 82:
            return ("Rain showers", "Violent rain showers", "cloud.heavyrain.fill")
        case 85, 86:
            return ("Snow showers", "Snow showers", "cloud.snow.fill")
        case 95:
            return ("Thunderstorm", "Thunderstorm", "cloud.bolt.fill")
        case 96, 99:
            return ("Thunderstorm", "Thunderstorm with hail", "cloud.bolt.rain.fill")
        default:
            return ("Unknown", "Unknown weather condition", "exclamationmark.icloud")
        }
    }
    
    // MARK: - Helper Methods
    
    // Generate cache key based on location and date
    private func generateCacheKey(location: String, date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)
        return "\(location.lowercased())-\(dateString)"
    }
    
    // Generate cache key based on coordinates and date
    private func generateCacheKey(latitude: Double, longitude: Double, date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: date)
        return "\(latitude),\(longitude)-\(dateString)"
    }
    
    // Calculate days from today to a target date
    private func calculateDaysFromToday(date: Date) -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let targetDate = calendar.startOfDay(for: date)
        
        if let days = calendar.dateComponents([.day], from: today, to: targetDate).day {
            return max(0, days) // Ensure non-negative
        }
        return 0
    }
    
    // Helper to print debug messages
    private func debugLog(_ message: String) {
        if debug {
            print("WeatherService Debug: \(message)")
        }
    }
}

// Extension to Calendar for date comparison
extension Calendar {
    func isDateInFuture(_ date: Date) -> Bool {
        let startOfToday = self.startOfDay(for: Date())
        let startOfTarget = self.startOfDay(for: date)
        return startOfTarget > startOfToday
    }
}

// A reusable weather display component
struct WeatherBar: View {
    let weather: WeatherData?
    let errorMessage: String?
    let isCompact: Bool
    
    // Convenience initializer with just weather data
    init(weather: WeatherData?, isCompact: Bool = false) {
        self.weather = weather
        self.errorMessage = nil
        self.isCompact = isCompact
    }
    
    // Main initializer with weather data and error message
    init(weather: WeatherData?, errorMessage: String?, isCompact: Bool = false) {
        self.weather = weather
        self.errorMessage = errorMessage
        self.isCompact = isCompact
    }
    
    var body: some View {
        if isCompact {
            // Compact version for small spaces
            HStack(spacing: 4) {
                if let weather = weather, weather.condition != nil {
                    Image(systemName: weather.iconSystemName ?? "exclamationmark.icloud")
                        .foregroundColor(weather.conditionColor)
                    Text(weather.temperatureString)
                        .fontWeight(.medium)
                } else {
                    Image(systemName: "exclamationmark.icloud")
                        .foregroundColor(.gray)
                    Text("--°F")
                        .fontWeight(.medium)
                }
            }
            .font(.caption)
        } else {
            // Full version
            VStack(spacing: 8) {
                HStack(spacing: 16) {
                    if let weather = weather, weather.condition != nil {
                        HStack(spacing: 8) {
                            Image(systemName: weather.iconSystemName ?? "exclamationmark.icloud")
                                .font(.title2)
                                .foregroundColor(weather.condition != nil ? weather.conditionColor : .gray)
                            
                            VStack(alignment: .leading) {
                                Text(weather.temperatureString)
                                    .font(.title3)
                                    .fontWeight(.bold)
                                Text(weather.condition ?? "Weather Unavailable")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text(weather.tempRangeString)
                                .font(.caption)
                            Text(weather.isForecast ? "Forecast" : "Current")
                                .font(.caption)
                                .foregroundColor(weather.isForecast ? .blue : .green)
                        }
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.icloud")
                                .font(.title2)
                                .foregroundColor(.gray)
                            
                            VStack(alignment: .leading) {
                                Text("--°F")
                                    .font(.title3)
                                    .fontWeight(.bold)
                                Text("Weather Unavailable")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text("H:--° L:--°")
                                .font(.caption)
                            Text("No Data")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                // Add Wind information row
                if let weather = weather, weather.windSpeed != nil {
                    HStack {
                        Image(systemName: "wind")
                            .foregroundColor(.cyan)
                            .frame(width: 20)
                        
                        Text("Wind:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Text(weather.windString)
                            .font(.subheadline)
                    }
                    .padding(.top, 4)
                }
                
                // Show error message if present
                if let errorMessage = errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .cornerRadius(10)
        }
    }
}
