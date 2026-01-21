//
//  HeatMapUtils.swift
//  Iconik Employee
//
//  Heat map utilities for schedule staffing visualization
//

import SwiftUI

// MARK: - Staffing Totals Model

/// Represents the total staffing needs for a day
struct DayStaffingTotals {
    let photographers: Int
    let posers: Int
    let helpers: Int

    var total: Int { photographers + posers + helpers }
    var isEmpty: Bool { total == 0 }

    var breakdownText: String {
        "Photographers: \(photographers), Posers: \(posers), Helpers: \(helpers)"
    }
}

// MARK: - Heat Map Color Logic

/// Returns the heat map color based on total staffing needed
/// - Parameter total: Total staff needed for the day
/// - Returns: Color representing the workload intensity
/// Color thresholds match the web app implementation
func getHeatMapColor(total: Int) -> Color {
    if total == 0 { return .clear }
    if total <= 3 { return Color(hex: "#22c55e") }  // Green - Light load
    if total <= 6 { return Color(hex: "#eab308") }  // Yellow - Medium load
    if total <= 9 { return Color(hex: "#f97316") }  // Orange - High load
    return Color(hex: "#ef4444")                     // Red - Critical load
}

// Note: Color(hex:) extension is defined in Extensions/Color+Hex.swift

// MARK: - Staffing Popover View

/// Popover view showing detailed staffing breakdown
struct StaffingPopoverView: View {
    let staffing: DayStaffingTotals
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Staffing Breakdown")
                .font(.headline)

            HStack {
                Image(systemName: "camera.fill")
                    .foregroundColor(.blue)
                    .frame(width: 20)
                Text("\(staffing.photographers) Photographer\(staffing.photographers == 1 ? "" : "s")")
            }

            HStack {
                Image(systemName: "person.fill")
                    .foregroundColor(.green)
                    .frame(width: 20)
                Text("\(staffing.posers) Poser\(staffing.posers == 1 ? "" : "s")")
            }

            HStack {
                Image(systemName: "hands.sparkles.fill")
                    .foregroundColor(.orange)
                    .frame(width: 20)
                Text("\(staffing.helpers) Helper\(staffing.helpers == 1 ? "" : "s")")
            }

            Divider()

            HStack {
                Text("Total:")
                    .fontWeight(.bold)
                Spacer()
                Text("\(staffing.total)")
                    .fontWeight(.bold)
            }
        }
        .padding()
        .frame(minWidth: 180)
    }
}

// MARK: - Preview

struct StaffingPopoverView_Previews: PreviewProvider {
    static var previews: some View {
        StaffingPopoverView(
            staffing: DayStaffingTotals(photographers: 3, posers: 2, helpers: 1),
            date: Date()
        )
    }
}
