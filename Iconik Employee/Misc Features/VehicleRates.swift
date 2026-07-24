//
//  VehicleRates.swift
//  Iconik Employee
//
//  Single authority for personal-vs-company vehicle mileage math (CAR.2).
//  Mirrors the web app's src/utils/mileage/vehicleRates.js so the two platforms
//  agree on rate selection and split totals.
//
//  A daily job report's vehicle_type is "personal" or "company"; anything else
//  (NULL on pre-CAR rows, unexpected values) counts as personal.
//

import Foundation

enum VehicleRates {
    /// Personal-vehicle fallback (IRS standard). Matches the web DEFAULT_MILEAGE_RATE.
    static let defaultMileageRate: Double = 0.67
    /// Company-car fallback when the org has no rate set. Matches web DEFAULT_COMPANY_CAR_RATE.
    static let defaultCompanyCarRate: Double = 0.10

    static func isCompany(_ vehicleType: String?) -> Bool {
        vehicleType == "company"
    }

    static func label(_ vehicleType: String?) -> String {
        isCompany(vehicleType) ? "Company" : "Personal"
    }

    /// Org company-car rate: NULL/nil → default; an explicit 0 is respected.
    static func resolveCompanyCarRate(_ companyCarRate: Double?) -> Double {
        companyCarRate ?? defaultCompanyCarRate
    }

    /// Photographer personal rate: falsy (unset or 0) → default, matching the
    /// pre-CAR behavior of every consumer (amount_per_mile || 0.67).
    static func resolvePersonalRate(_ amountPerMile: Double?) -> Double {
        guard let rate = amountPerMile, rate != 0 else { return defaultMileageRate }
        return rate
    }

    /// The rate one report pays. personalRate must already be resolved;
    /// companyCarRate may be raw (NULL tolerated).
    static func rate(forVehicleType vehicleType: String?, personalRate: Double, companyCarRate: Double?) -> Double {
        isCompany(vehicleType) ? resolveCompanyCarRate(companyCarRate) : personalRate
    }

    /// Personal/company buckets of miles + compensation.
    struct Split {
        var personalMiles: Double = 0
        var companyMiles: Double = 0
        var personalCompensation: Double = 0
        var companyCompensation: Double = 0

        var totalMiles: Double { personalMiles + companyMiles }
        var totalCompensation: Double { personalCompensation + companyCompensation }
        /// True once any company-vehicle miles exist — surfaces show the split only then.
        var hasCompany: Bool { companyMiles > 0 }

        /// Add one report's miles into the right bucket. personalRate must be resolved;
        /// companyCarRate may be raw (NULL tolerated).
        mutating func add(miles: Double, vehicleType: String?, personalRate: Double, companyCarRate: Double?) {
            if VehicleRates.isCompany(vehicleType) {
                companyMiles += miles
                companyCompensation += miles * VehicleRates.resolveCompanyCarRate(companyCarRate)
            } else {
                personalMiles += miles
                personalCompensation += miles * personalRate
            }
        }
    }
}
