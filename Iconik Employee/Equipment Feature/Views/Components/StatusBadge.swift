//
//  StatusBadge.swift
//  Iconik Employee
//
//  Equipment Management Feature - Status and Condition Badge Components
//

import SwiftUI

// MARK: - Equipment Status Badge

struct EquipmentStatusBadge: View {
    let status: EquipmentStatus

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

// MARK: - Equipment Condition Badge

struct EquipmentConditionBadge: View {
    let condition: EquipmentCondition

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(condition.color)
                .frame(width: 8, height: 8)
            Text(condition.label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Damage Severity Badge

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

// MARK: - Overdue Badge

struct OverdueBadge: View {
    let daysOverdue: Int?

    var body: some View {
        if let days = daysOverdue, days > 0 {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                Text("\(days)d overdue")
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.red)
            .cornerRadius(12)
        }
    }
}

// MARK: - Permanent Badge

struct PermanentBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "infinity")
                .font(.caption2)
            Text("Permanent")
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(hex: "#6366f1")) // Indigo
        .cornerRadius(12)
    }
}

// MARK: - Return Date Badge

struct ReturnDateBadge: View {
    let date: Date?

    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter
    }

    var body: some View {
        if let date = date {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.caption2)
                Text("Due: \(dateFormatter.string(from: date))")
                    .font(.caption2)
            }
            .foregroundColor(.secondary)
        } else {
            PermanentBadge()
        }
    }
}

// MARK: - Kit Color Indicator

struct KitColorIndicator: View {
    let hexColor: String?
    let size: CGFloat
    @State private var animationOffset: CGFloat = 0

    init(color: Color?, size: CGFloat = 12) {
        // Convert Color to hex if possible, otherwise nil
        self.hexColor = nil
        self.size = size
    }

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

// MARK: - Kit Color Border (for equipment cards)

struct KitColorBorder: View {
    let hexColor: String?
    let width: CGFloat
    @State private var animationOffset: CGFloat = 0

    init(color: Color?, width: CGFloat = 4) {
        self.hexColor = nil
        self.width = width
    }

    init(hexColor: String?, width: CGFloat = 4) {
        self.hexColor = hexColor
        self.width = width
    }

    private var isRainbow: Bool {
        hexColor?.lowercased() == "rainbow"
    }

    private var rainbowGradient: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [
                .red, .orange, .yellow, .green, .blue, .purple, .red
            ]),
            startPoint: UnitPoint(x: 0.5, y: animationOffset),
            endPoint: UnitPoint(x: 0.5, y: animationOffset + 1)
        )
    }

    var body: some View {
        if let hex = hexColor {
            if isRainbow {
                Rectangle()
                    .fill(rainbowGradient)
                    .frame(width: width)
                    .onAppear {
                        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
                            animationOffset = 1
                        }
                    }
            } else {
                Rectangle()
                    .fill(Color(hex: hex))
                    .frame(width: width)
            }
        } else {
            EmptyView()
        }
    }
}

// MARK: - Item Count Badge

struct ItemCountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count) item\(count == 1 ? "" : "s")")
            .font(.caption)
            .foregroundColor(.secondary)
    }
}

// MARK: - Preview

struct StatusBadge_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Status badges
            VStack(alignment: .leading, spacing: 8) {
                Text("Equipment Status").font(.headline)
                HStack {
                    EquipmentStatusBadge(status: .available)
                    EquipmentStatusBadge(status: .checkedOut)
                    EquipmentStatusBadge(status: .needsRepair)
                    EquipmentStatusBadge(status: .retired)
                }
            }

            // Condition badges
            VStack(alignment: .leading, spacing: 8) {
                Text("Condition").font(.headline)
                HStack {
                    EquipmentConditionBadge(condition: .excellent)
                    EquipmentConditionBadge(condition: .good)
                    EquipmentConditionBadge(condition: .fair)
                    EquipmentConditionBadge(condition: .poor)
                }
            }

            // Severity badges
            VStack(alignment: .leading, spacing: 8) {
                Text("Damage Severity").font(.headline)
                HStack {
                    DamageSeverityBadge(severity: .minor)
                    DamageSeverityBadge(severity: .moderate)
                    DamageSeverityBadge(severity: .severe)
                }
            }

            // Other badges
            VStack(alignment: .leading, spacing: 8) {
                Text("Other Badges").font(.headline)
                HStack {
                    OverdueBadge(daysOverdue: 3)
                    PermanentBadge()
                    ItemCountBadge(count: 5)
                }
            }

            // Kit color indicators
            VStack(alignment: .leading, spacing: 8) {
                Text("Kit Colors").font(.headline)
                HStack(spacing: 12) {
                    KitColorIndicator(hexColor: "#ef4444")
                    KitColorIndicator(hexColor: "#f97316")
                    KitColorIndicator(hexColor: "#eab308")
                    KitColorIndicator(hexColor: "#22c55e")
                    KitColorIndicator(hexColor: "#3b82f6")
                    KitColorIndicator(hexColor: "#a855f7")
                }
            }
        }
        .padding()
    }
}
