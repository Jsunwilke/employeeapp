//
//  VehicleRatesTests.swift
//  Iconik EmployeeTests
//
//  CAR.2 — pins the personal-vs-company mileage math so it stays in lockstep
//  with the web authority (src/utils/mileage/vehicleRates.js). Pure logic,
//  no Supabase dependency.
//

import Testing
@testable import Iconik_Employee

struct VehicleRatesTests {

    // MARK: - Classification

    @Test func isCompany_onlyForExactCompanyString() {
        #expect(VehicleRates.isCompany("company") == true)
        #expect(VehicleRates.isCompany("personal") == false)
        #expect(VehicleRates.isCompany(nil) == false)
        #expect(VehicleRates.isCompany("") == false)
        #expect(VehicleRates.isCompany("Company") == false) // case-sensitive, like the web
    }

    @Test func label_matchesClassification() {
        #expect(VehicleRates.label("company") == "Company")
        #expect(VehicleRates.label("personal") == "Personal")
        #expect(VehicleRates.label(nil) == "Personal")
    }

    // MARK: - Rate resolution

    @Test func resolveCompanyCarRate_nilFallsBack_zeroRespected() {
        #expect(VehicleRates.resolveCompanyCarRate(nil) == 0.10)
        #expect(VehicleRates.resolveCompanyCarRate(0.25) == 0.25)
        #expect(VehicleRates.resolveCompanyCarRate(0) == 0) // explicit 0 respected
    }

    @Test func resolvePersonalRate_falsyFallsBack() {
        #expect(VehicleRates.resolvePersonalRate(nil) == 0.67)
        #expect(VehicleRates.resolvePersonalRate(0) == 0.67)   // falsy → default, like `|| 0.67`
        #expect(VehicleRates.resolvePersonalRate(0.55) == 0.55)
    }

    // MARK: - Rate for a report

    @Test func rate_picksTheRightBucket() {
        #expect(VehicleRates.rate(forVehicleType: "company", personalRate: 0.55, companyCarRate: 0.10) == 0.10)
        #expect(VehicleRates.rate(forVehicleType: "personal", personalRate: 0.55, companyCarRate: 0.10) == 0.55)
        // Company with a NULL org rate uses the company default, not the personal rate.
        #expect(VehicleRates.rate(forVehicleType: "company", personalRate: 0.55, companyCarRate: nil) == 0.10)
    }

    // MARK: - Split

    @Test func split_bucketsMilesAndCompensation() {
        var s = VehicleRates.Split()
        s.add(miles: 100, vehicleType: "personal", personalRate: 0.50, companyCarRate: 0.10)
        s.add(miles: 40, vehicleType: "company", personalRate: 0.50, companyCarRate: 0.10)
        s.add(miles: 10, vehicleType: nil, personalRate: 0.50, companyCarRate: 0.10) // nil → personal

        #expect(s.personalMiles == 110)
        #expect(s.companyMiles == 40)
        #expect(s.personalCompensation == 55)  // 110 * 0.50
        #expect(s.companyCompensation == 4)     // 40 * 0.10
        #expect(s.totalMiles == 150)
        #expect(s.totalCompensation == 59)
        #expect(s.hasCompany == true)
    }

    @Test func split_allPersonal_hasNoCompany() {
        var s = VehicleRates.Split()
        s.add(miles: 20, vehicleType: "personal", personalRate: 0.67, companyCarRate: nil)
        #expect(s.hasCompany == false)
        #expect(s.companyMiles == 0)
        #expect(s.totalCompensation == 20 * 0.67)
    }

    @Test func split_companyWithNilOrgRate_usesCompanyDefault() {
        var s = VehicleRates.Split()
        s.add(miles: 50, vehicleType: "company", personalRate: 0.67, companyCarRate: nil)
        #expect(s.companyCompensation == 5) // 50 * 0.10
    }
}
