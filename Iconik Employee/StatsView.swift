import SwiftUI
import Firebase
import FirebaseFirestore
import Charts

struct StatsView: View {
    @StateObject private var viewModel = StatsViewModel()
    @State private var timeRange: TimeRange = .year
    @State private var activeTab: StatTab = .overview
    
    // Environment for color scheme
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header with time range picker
                headerView
                
                // Tab selector
                tabSelector
                
                if viewModel.isLoading {
                    ProgressView("Loading statistics...")
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else if !viewModel.errorMessage.isEmpty {
                    errorView
                } else {
                    // Display the appropriate tab content
                    TabView(selection: $activeTab) {
                        overviewTab
                            .tag(StatTab.overview)
                        
                        mileageTab
                            .tag(StatTab.mileage)
                        
                        locationsTab
                            .tag(StatTab.locations)
                        
                        photographersTab
                            .tag(StatTab.photographers)
                        
                        jobTypeTab
                            .tag(StatTab.jobTypes)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .frame(minHeight: 600)
                }
            }
            .padding()
        }
        .navigationTitle("Statistics")
        .onAppear {
            viewModel.loadData(timeRange: timeRange)
        }
        .onChange(of: timeRange) { newValue in
            viewModel.loadData(timeRange: newValue)
        }
    }
    
    // MARK: - Header View
    
    private var headerView: some View {
        HStack {
            Text("Photography Business Analytics")
                .font(.title2)
                .fontWeight(.bold)
            
            Spacer()
            
            // Time range selector
            Picker("Time Range", selection: $timeRange) {
                Text("Month").tag(TimeRange.month)
                Text("Quarter").tag(TimeRange.quarter)
                Text("Year").tag(TimeRange.year)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
        }
    }
    
    // MARK: - Tab Selector
    
    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(StatTab.allCases, id: \.self) { tab in
                Button(action: {
                    withAnimation {
                        activeTab = tab
                    }
                }) {
                    VStack(spacing: 4) {
                        Text(tab.title)
                            .fontWeight(activeTab == tab ? .semibold : .regular)
                        
                        // Indicator for active tab
                        Rectangle()
                            .fill(activeTab == tab ? Color.blue : Color.clear)
                            .frame(height: 2)
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(PlainButtonStyle())
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.secondarySystemBackground))
        )
    }
    
    // MARK: - Error View
    
    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text("Error Loading Data")
                .font(.headline)
            
            Text(viewModel.errorMessage)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Button("Try Again") {
                viewModel.loadData(timeRange: timeRange)
            }
            .padding()
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 300)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(.systemGray6) : Color.white)
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
    }
    
    // MARK: - Overview Tab
    
    private var overviewTab: some View {
        VStack(spacing: 20) {
            // Summary cards
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                summaryCard(
                    title: "Total Mileage",
                    value: "\(viewModel.totalMileage.formatted()) miles",
                    subvalue: "Avg \(viewModel.avgMileagePerMonth.formatted()) per month",
                    icon: "car.fill",
                    color: .blue
                )
                
                summaryCard(
                    title: "Total Jobs",
                    value: "\(viewModel.totalJobs.formatted())",
                    subvalue: "Across \(viewModel.jobTypeData.count) job types",
                    icon: "briefcase.fill",
                    color: .green
                )
                
                summaryCard(
                    title: "Photographers",
                    value: "\(viewModel.totalPhotographers)",
                    subvalue: "Avg \(viewModel.avgJobsPerPhotographer.formatted()) jobs each",
                    icon: "person.fill",
                    color: .orange
                )
                
                summaryCard(
                    title: "Locations",
                    value: "\(viewModel.totalLocations)",
                    subvalue: "Avg \(viewModel.avgVisitsPerLocation.formatted(.number)) visits each",
                    icon: "mappin.and.ellipse",
                    color: .red
                )
            }
            
            // Monthly revenue chart
            ChartCard(title: "Monthly Revenue") {
                Chart(viewModel.monthlyRevenue) { item in
                    BarMark(
                        x: .value("Month", item.month),
                        y: .value("Revenue", item.revenue)
                    )
                    .foregroundStyle(Color.blue)
                    
                    LineMark(
                        x: .value("Month", item.month),
                        y: .value("Mileage Reimbursement", item.mileageReimbursement)
                    )
                    .foregroundStyle(Color.orange)
                    .lineStyle(StrokeStyle(lineWidth: 3))
                }
                .chartYAxisLabel("Amount ($)")
                .chartLegend(position: .bottom, alignment: .center)
            }
            
            // Job types chart and mileage chart in a grid
            LazyVGrid(columns: [GridItem(.flexible())], spacing: 16) {
                // Job types pie chart
                ChartCard(title: "Job Types Distribution") {
                    Chart(viewModel.jobTypeData) { item in
                        SectorMark(
                            angle: .value("Jobs", item.value),
                            innerRadius: .ratio(0.5),
                            angularInset: 1
                        )
                        .foregroundStyle(by: .value("Type", item.name))
                        .annotation(position: .overlay) {
                            Text("\(Int(item.value))")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                    }
                    .chartLegend(position: .bottom)
                }
                
                // Monthly mileage chart
                ChartCard(title: "Monthly Mileage") {
                    Chart(viewModel.mileageData) { item in
                        LineMark(
                            x: .value("Month", item.month),
                            y: .value("Total", item.total)
                        )
                        .foregroundStyle(Color.purple)
                        
                        AreaMark(
                            x: .value("Month", item.month),
                            y: .value("Total", item.total)
                        )
                        .foregroundStyle(Color.purple.opacity(0.2))
                    }
                    .chartYAxisLabel("Miles")
                }
            }
        }
    }
    
    // MARK: - Mileage Tab
    
    private var mileageTab: some View {
        VStack(spacing: 20) {
            // Mileage by photographer
            ChartCard(title: "Mileage by Photographer") {
                Chart {
                    ForEach(viewModel.photographerData) { photographer in
                        BarMark(
                            x: .value("Photographer", photographer.name),
                            y: .value("Miles", photographer.miles)
                        )
                        .foregroundStyle(Color.blue.gradient)
                    }
                }
                .chartYAxisLabel("Miles")
            }
            
            // Mileage trend
            ChartCard(title: "Mileage Trends") {
                Chart(viewModel.mileageData) { item in
                    ForEach(viewModel.photographerNames, id: \.self) { name in
                        LineMark(
                            x: .value("Month", item.month),
                            y: .value("Miles", item[name] as? Double ?? 0)
                        )
                        .foregroundStyle(by: .value("Photographer", name))
                    }
                }
                .chartYAxisLabel("Miles")
                .chartLegend(position: .bottom)
            }
            
            // Reimbursement 
            ChartCard(title: "Mileage Reimbursement") {
                Chart(viewModel.mileageData) { item in
                    BarMark(
                        x: .value("Month", item.month),
                        y: .value("Reimbursement", item.total * 0.3)
                    )
                    .foregroundStyle(Color.green.gradient)
                }
                .chartYAxisLabel("Amount ($)")
            }
        }
    }
    
    // MARK: - Locations Tab
    
    private var locationsTab: some View {
        VStack(spacing: 20) {
            // Top locations by visits
            ChartCard(title: "Top Locations by Visits") {
                Chart(viewModel.locationData.prefix(5)) { item in
                    BarMark(
                        x: .value("Visits", item.visits),
                        y: .value("Location", item.name)
                    )
                    .foregroundStyle(Color.orange.gradient)
                }
            }
            
            // Locations by mileage
            ChartCard(title: "Locations by Mileage") {
                Chart(viewModel.locationData.prefix(5)) { item in
                    BarMark(
                        x: .value("Mileage", item.mileage),
                        y: .value("Location", item.name)
                    )
                    .foregroundStyle(Color.purple.gradient)
                }
                .chartYAxisLabel("Miles")
            }
            
            // Visits to mileage ratio
            ChartCard(title: "Visit Efficiency (Miles per Visit)") {
                Chart(viewModel.locationData.sorted { 
                    ($0.mileage / Double($0.visits)) > ($1.mileage / Double($1.visits)) 
                }.prefix(5)) { item in
                    BarMark(
                        x: .value("Miles per Visit", item.mileage / Double(item.visits)),
                        y: .value("Location", item.name)
                    )
                    .foregroundStyle(Color.teal.gradient)
                }
                .chartYAxisLabel("Miles per Visit")
            }
        }
    }
    
    // MARK: - Photographers Tab
    
    private var photographersTab: some View {
        VStack(spacing: 20) {
            // Jobs by photographer
            ChartCard(title: "Jobs by Photographer") {
                Chart(viewModel.photographerData) { item in
                    BarMark(
                        x: .value("Photographer", item.name),
                        y: .value("Jobs", item.jobs)
                    )
                    .foregroundStyle(Color.blue.gradient)
                }
            }
            
            // Average job time
            ChartCard(title: "Average Job Time (Hours)") {
                Chart(viewModel.photographerData) { item in
                    BarMark(
                        x: .value("Photographer", item.name),
                        y: .value("Hours", item.avgJobTime)
                    )
                    .foregroundStyle(Color.green.gradient)
                }
                .chartYAxisLabel("Hours")
            }
            
            // Efficiency (Jobs per mile)
            ChartCard(title: "Jobs per 100 Miles") {
                Chart(viewModel.photographerData.map { photographer in
                    (name: photographer.name, ratio: Double(photographer.jobs) / photographer.miles * 100)
                }, id: \.name) { item in
                    BarMark(
                        x: .value("Photographer", item.name),
                        y: .value("Jobs per 100 Miles", item.ratio)
                    )
                    .foregroundStyle(Color.orange.gradient)
                }
            }
        }
    }
    
    // MARK: - Job Type Tab
    
    private var jobTypeTab: some View {
        VStack(spacing: 20) {
            // Pie chart of job types
            ChartCard(title: "Job Type Distribution") {
                Chart(viewModel.jobTypeData) { item in
                    SectorMark(
                        angle: .value("Count", item.value),
                        innerRadius: .ratio(0.5),
                        angularInset: 1
                    )
                    .foregroundStyle(by: .value("Type", item.name))
                }
                .chartLegend(position: .bottom)
            }
            
            // Bar chart of job types
            ChartCard(title: "Job Types by Count") {
                Chart(viewModel.jobTypeData.sorted(by: { $0.value > $1.value })) { item in
                    BarMark(
                        x: .value("Count", item.value),
                        y: .value("Type", item.name)
                    )
                    .foregroundStyle(Color.blue.gradient)
                }
            }
            
            // Weather impact on jobs
            ChartCard(title: "Weather Impact on Jobs") {
                Chart(viewModel.weatherImpactData) { item in
                    BarMark(
                        x: .value("Weather", item.weather),
                        y: .value("Jobs", item.jobs)
                    )
                    .foregroundStyle(Color.blue)
                }
                .chartYScale(domain: 0...350)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            ForEach(viewModel.weatherImpactData) { item in
                                let point = proxy.position(for: .init(x: item.weather, y: item.jobs))
                                if let point {
                                    Text("\(item.onTimeArrival)%")
                                        .font(.caption)
                                        .position(
                                            x: point.x,
                                            y: point.y - 20
                                        )
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Helper Views
    
    private func summaryCard(title: String, value: String, subvalue: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
            
            Text(subvalue)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(height: 100)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(.systemGray6) : Color.white)
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
    }
}

// MARK: - Chart Card View

struct ChartCard<Content: View>: View {
    let title: String
    let content: () -> Content
    
    @Environment(\.colorScheme) var colorScheme
    
    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            
            content()
                .frame(height: 300)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(.systemGray6) : Color.white)
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
    }
}

// MARK: - Enums

enum TimeRange: String, CaseIterable {
    case month = "Month"
    case quarter = "Quarter"
    case year = "Year"
}

enum StatTab: String, CaseIterable {
    case overview = "Overview"
    case mileage = "Mileage"
    case locations = "Locations"
    case photographers = "Photographers"
    case jobTypes = "Job Types"
    
    var title: String {
        return self.rawValue
    }
    
    var icon: String {
        switch self {
        case .overview:
            return "chart.pie.fill"
        case .mileage:
            return "car.fill"
        case .locations:
            return "mappin.and.ellipse"
        case .photographers:
            return "person.2.fill"
        case .jobTypes:
            return "briefcase.fill"
        }
    }
}

// MARK: - Preview Provider

struct StatsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            StatsView()
        }
    }
}