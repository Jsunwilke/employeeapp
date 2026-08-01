//  CoordinateString.swift
//  Iconik Employee — the "lat,lng" string, parsed and validated in one place
//
//  CONSOLIDATED IN AMB.12. This check existed VERBATIM in three files —
//  `AddressAutocompleteField`, `CreateAccountView` and `EmployeeInfoView` — each
//  with its own copy of the same eight lines. Three copies of a validator is
//  three chances for one of them to drift into accepting something the others
//  reject, on a value that decides whether a map is drawn and where a pin lands.
//
//  The app stores coordinates as a single "lat,lng" TEXT value rather than two
//  numeric columns, so the parse is the validation.

import CoreLocation
import Foundation

enum CoordinateString {
    /// True when the string is a well-formed, in-range "lat,lng" pair.
    ///
    /// `isFinite` is checked because `Double("nan")` and `Double("inf")` both
    /// parse successfully and then fail the range comparisons silently — a NaN
    /// compares false against every bound, so without the check the result
    /// depends on the order the comparisons happen to be written in.
    static func isValid(_ value: String) -> Bool {
        coordinate(from: value) != nil
    }

    /// The parsed pair, or nil. Returns the coordinate rather than a Bool so a
    /// caller does not have to validate and then parse again.
    static func coordinate(from value: String) -> CLLocationCoordinate2D? {
        let parts = value.split(separator: ",").map {
            String($0).trimmingCharacters(in: .whitespaces)
        }
        guard parts.count == 2,
              let lat = Double(parts[0]),
              let lng = Double(parts[1]),
              lat.isFinite, lng.isFinite,
              (-90...90).contains(lat),
              (-180...180).contains(lng) else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    /// The storage spelling, so a coordinate is written the same way everywhere.
    static func string(from coordinate: CLLocationCoordinate2D) -> String {
        "\(coordinate.latitude),\(coordinate.longitude)"
    }
}
