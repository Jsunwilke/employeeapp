//
//  StatusBadge.swift
//  Iconik Employee
//
//  Equipment Management Feature - Status and Condition Badge Components
//
//  MOSTLY EMPTIED BY AMB.3. Seven of the components that lived here — the status,
//  condition, overdue, permanent, return-date and item-count badges, and
//  KitColorBorder — were deleted with their last call sites in the same commit that
//  converted Equipment. Their replacements are `AmbientBadge` (DesignSystem), and
//  `KitTapeEdge` / `KitDueBadge` (Components/EquipmentAmbientRows.swift).
//
//  WHAT IS LEFT, AND WHY:
//
//    KitColorIndicator     still has one live caller, AdminKitTemplatesView, which
//                          belongs to AMB.12 (the manager-tools tail). Converting it
//                          is that phase's job, so its dependency stays until then.
//
//    DamageSeverityBadge   dead before AMB.3 and untouched by it — neither has ever
//    RequestStatusBadge    had a call site anywhere in the app. They are left alone
//                          deliberately: deleting them is a cleanup this phase was
//                          not asked to make, and quietly widening scope is how a
//                          restyle turns into something nobody reviewed. Recorded
//                          here so the next phase through can decide.
//

import SwiftUI

// MARK: - Damage Severity Badge

/// NOTE: no call sites. See the file header.
struct DamageSeverityBadge: View {
    let severity: DamageSeverity

    var body: some View {
        Text(severity.label)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(severity.color)
            .cornerRadius(12)
    }
}

// MARK: - Request Status Badge

/// NOTE: no call sites. See the file header.
struct RequestStatusBadge: View {
    let status: RequestStatus

    var body: some View {
        Text(status.label)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.color)
            .cornerRadius(12)
    }
}

// MARK: - Kit Color Indicator

/// The kit tape colour as a dot, with the spinning rainbow gradient.
///
/// Kept for AdminKitTemplatesView until AMB.12 converts it. Everything inside the
/// Equipment screens now draws its kit colour with `KitTapeDot` / `KitTapeEdge`,
/// which are the same signal without the endless animation.
struct KitColorIndicator: View {
    let hexColor: String?
    let size: CGFloat
    @State private var animationOffset: CGFloat = 0

    init(hexColor: String?, size: CGFloat = 12) {
        self.hexColor = hexColor
        self.size = size
    }

    private var isRainbow: Bool {
        hexColor?.lowercased() == "rainbow"
    }

    private var rainbowGradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: [
                .red, .orange, .yellow, .green, .blue, .purple, .red
            ]),
            center: .center,
            startAngle: .degrees(animationOffset),
            endAngle: .degrees(animationOffset + 360)
        )
    }

    var body: some View {
        if let hex = hexColor {
            if isRainbow {
                Circle()
                    .fill(rainbowGradient)
                    .frame(width: size, height: size)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .shadow(radius: 2, x: 0, y: 1)
                    .onAppear {
                        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                            animationOffset = 360
                        }
                    }
            } else {
                let color = Color(hex: hex)
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
                    .overlay(
                        Circle()
                            .stroke(Color.white, lineWidth: 2)
                    )
                    .shadow(color: color.opacity(0.3), radius: 2, x: 0, y: 1)
            }
        }
    }
}
