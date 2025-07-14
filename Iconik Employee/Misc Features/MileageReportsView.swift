import SwiftUI
import Firebase
import FirebaseFirestore

struct MileageReportsView: View {
    @StateObject var viewModel: MileageReportsViewModel
    @State private var selectedPeriodStart: Date
    
    // Assume the user's home address is stored in AppStorage.
    @AppStorage("userHomeAddress") private var userHomeAddress: String = ""
    
    // Create an array of available pay periods (current + previous five).
    private var availablePeriods: [Date] {
        var periods: [Date] = []
        let calendar = Calendar.current
        let periodLength = 14
        var currentStart = viewModel.currentPeriodStart
        
        for _ in 0..<6 {
            periods.append(currentStart)
            if let nextStart = calendar.date(byAdding: .day, value: -periodLength, to: currentStart) {
                currentStart = nextStart
            }
        }
        return periods
    }
    
    // Formatter for period card display.
    private var cardFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }
    
    // Formatter for full period range display.
    private var fullRangeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }
    
    // Formatter for current month's full name.
    private var monthName: String {
        let formatter = DateFormatter()
        let monthIndex = Calendar.current.component(.month, from: Date()) - 1
        return formatter.monthSymbols[monthIndex]
    }
    
    init(userName: String) {
        let vm = MileageReportsViewModel(userName: userName)
        _viewModel = StateObject(wrappedValue: vm)
        _selectedPeriodStart = State(initialValue: vm.currentPeriodStart)
    }
    
    var body: some View {
        VStack(spacing: 12) {
                
                // Carousel-style period picker.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(availablePeriods, id: \.self) { period in
                            Button(action: {
                                selectedPeriodStart = period
                                viewModel.loadRecords(forPayPeriodStart: period)
                            }) {
                                VStack {
                                    Text(cardFormatter.string(from: period))
                                        .font(.headline)
                                        .foregroundColor(selectedPeriodStart == period ? .white : .primary)
                                    Text("to")
                                        .font(.caption)
                                        .foregroundColor(selectedPeriodStart == period ? .white : .secondary)
                                    if let periodEnd = Calendar.current.date(byAdding: .day, value: 13, to: period) {
                                        Text(cardFormatter.string(from: periodEnd))
                                            .font(.headline)
                                            .foregroundColor(selectedPeriodStart == period ? .white : .primary)
                                    }
                                }
                                .padding(8)
                                .background(selectedPeriodStart == period ? Color.blue : Color.gray.opacity(0.2))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Display full selected period dates.
                if let periodEnd = Calendar.current.date(byAdding: .day, value: 13, to: selectedPeriodStart) {
                    Text("Selected Period: \(fullRangeFormatter.string(from: selectedPeriodStart)) - \(fullRangeFormatter.string(from: periodEnd))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                // Summary info - Enhanced with more compact card-based UI
                VStack(spacing: 12) {
                    // Current period and monthly in a row
                    HStack(spacing: 10) {
                        // Current Period card
                        SummaryCardView(
                            title: "Current Period",
                            miles: viewModel.currentPeriodMileage,
                            reimbursement: viewModel.currentPeriodMileage * 0.3,
                            iconName: "calendar",
                            color: .blue
                        )
                        
                        // Monthly card
                        SummaryCardView(
                            title: "Miles in \(monthName)",
                            miles: viewModel.monthMileage,
                            reimbursement: viewModel.monthMileage * 0.3,
                            iconName: "clock",
                            color: .green
                        )
                    }
                    
                    // Yearly card (full width)
                    SummaryCardView(
                        title: "Miles this Year",
                        miles: viewModel.yearMileage,
                        reimbursement: viewModel.yearMileage * 0.3,
                        iconName: "calendar.badge.clock",
                        color: .orange,
                        isWide: true
                    )
                }
                .padding(.horizontal)
                
                // List of mileage records with updated navigation link to MileageDetailView
                List {
                    ForEach(viewModel.records.sorted(by: { $0.date > $1.date })) { record in
                        NavigationLink(destination: MileageDetailView(record: record)) {
                            HStack(alignment: .center) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(formatDate(record.date))
                                        .font(.headline)
                                    
                                    Text(record.schoolName)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(record.totalMileage, specifier: "%.1f") miles")
                                        .font(.system(.body, design: .rounded))
                                        .fontWeight(.medium)
                                    
                                    Text("$\(record.totalMileage * 0.3, specifier: "%.2f")")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .listStyle(InsetGroupedListStyle())
            }
        .navigationBarTitle("Mileage Reports", displayMode: .inline)
        .onAppear {
            viewModel.loadRecords(forPayPeriodStart: selectedPeriodStart)
            viewModel.loadYearAndMonthMileage()
        }
    }
    
    // Format date as "Month Day, Year"
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: date)
    }
}

// Separate view for summary cards to ensure proper formatting
struct SummaryCardView: View {
    let title: String
    let miles: Double
    let reimbursement: Double
    let iconName: String
    let color: Color
    var isWide: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .font(.headline)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                Spacer()
            }
            
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatMiles(miles))
                        .font(.title3)
                        .fontWeight(.bold)
                    
                    Text("miles")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatCurrency(reimbursement))
                        .font(.headline)
                    
                    Text("reimbursement")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .frame(height: 85)
        .frame(maxWidth: isWide ? .infinity : nil)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
    
    // Helper functions for proper formatting
    private func formatMiles(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 1
        formatter.minimumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? "0.0"
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }
}
