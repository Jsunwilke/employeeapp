import SwiftUI
import Firebase
import FirebaseFirestore

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
                    // Show the selected tab content
                    switch activeTab {
                    case .overview:
                        overviewTab
                    case .mileage:
                        mileageTab
                    case .locations:
                        locationsTab
                    case .photographers:
                        photographersTab
                    case .jobTypes:
                        jobTypeTab
                    }
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
                    subvalue: "Avg \(String(format: "%.1f", viewModel.avgVisitsPerLocation)) visits each",
                    icon: "mappin.and.ellipse",
                    color: .red
                )
            }
            
            // Additional summary info as replacement for revenue chart
            ChartCard(title: "Mileage Summary") {
                HStack(spacing: 24) {
                    VStack(alignment: .center, spacing: 8) {
                        Text("\(viewModel.totalMileage.formatted())")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                        
                        Text("Total Miles")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    
                    VStack(alignment: .center, spacing: 8) {
                        Text("\(viewModel.totalJobs.formatted())")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                        
                        Text("Total Jobs")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    
                    VStack(alignment: .center, spacing: 8) {
                        Text(String(format: "%.1f", viewModel.avgVisitsPerLocation))
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.orange)
                        
                        Text("Avg Locations")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 20)
            }
            
            // Job types pie chart representation
            ChartCard(title: "Job Types Distribution") {
                // Simple visual representation of job distribution
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(viewModel.jobTypeData.sorted(by: { $0.value > $1.value })) { jobType in
                        let percentage = jobType.value / Double(viewModel.totalJobs) * 100
                        
                        HStack {
                            Circle()
                                .fill(getColorForIndex(viewModel.jobTypeData.firstIndex(where: { $0.id == jobType.id }) ?? 0))
                                .frame(width: 12, height: 12)
                            
                            Text(jobType.name)
                                .font(.caption)
                                .lineLimit(1)
                            
                            Spacer()
                            
                            Text("\(Int(percentage))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
            }
            
            // Monthly mileage chart
            ChartCard(title: "Monthly Mileage") {
                VStack {
                    // Get the maximum mileage for scaling
                    let maxMileage = viewModel.mileageData.map { $0.total }.max() ?? 1.0
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .bottom, spacing: 15) {
                            ForEach(viewModel.mileageData) { item in
                                VStack {
                                    // Total mileage bar
                                    Rectangle()
                                        .fill(Color.purple)
                                        .frame(width: 24, height: getScaledHeight(for: item.total, maxValue: maxMileage, maxHeight: 150))
                                    
                                    // Mileage value under the bar (not overlapping)
                                    Text("\(Int(item.total))")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                        .padding(.top, 4)
                                    
                                    // Month label
                                    Text(item.month)
                                        .font(.caption)
                                        .padding(.top, 2)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    // Legend
                    HStack {
                        Circle()
                            .fill(Color.purple)
                            .frame(width: 10, height: 10)
                        
                        Text("Total Mileage")
                            .font(.caption)
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                }
            }
        }
    }
    
    // MARK: - Mileage Tab
    
    private var mileageTab: some View {
        VStack(spacing: 20) {
            // Mileage by photographer
            ChartCard(title: "Mileage by Photographer") {
                VStack {
                    // Calculate the maximum mileage for proper scaling
                    let maxMileage = viewModel.photographerData.map { $0.miles }.max() ?? 1.0
                    
                    ForEach(viewModel.photographerData.sorted(by: { $0.miles > $1.miles })) { photographer in
                        HStack {
                            Text(photographer.name)
                                .font(.subheadline)
                                .frame(width: 60, alignment: .leading)
                            
                            // Mileage bar
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    // Background bar
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: geometry.size.width, height: 20)
                                    
                                    // Filled bar - using proper scaling
                                    Rectangle()
                                        .fill(Color.blue)
                                        .frame(width: getScaledWidth(for: photographer.miles, maxValue: maxMileage, maxWidth: geometry.size.width), height: 20)
                                    
                                    // Value text
                                    Text("\(Int(photographer.miles)) miles")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .padding(.leading, 6)
                                }
                            }
                            .frame(height: 20)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal)
            }
            
            // Mileage trends
            ChartCard(title: "Mileage Trends") {
                VStack {
                    // Legend
                    HStack {
                        ForEach(viewModel.photographerNames, id: \.self) { name in
                            HStack {
                                Circle()
                                    .fill(getColorForPhotographer(name))
                                    .frame(width: 10, height: 10)
                                
                                Text(name)
                                    .font(.caption)
                            }
                            .padding(.trailing, 8)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 10)
                    
                    // Find the maximum mileage value for proper scaling
                    let maxMileage = viewModel.mileageData.flatMap { data in
                        viewModel.photographerNames.compactMap { name in
                            data[name] as? Double
                        }
                    }.max() ?? 600.0
                    
                    // Simplified line chart
                    GeometryReader { geometry in
                        ZStack {
                            // Background grid
                            VStack(spacing: 0) {
                                ForEach(0..<5) { i in
                                    Divider()
                                        .background(Color.gray.opacity(0.2))
                                        .frame(height: 1)
                                        .offset(y: CGFloat(i) * geometry.size.height / 4)
                                }
                            }
                            
                            // Data lines
                            ForEach(viewModel.photographerNames, id: \.self) { name in
                                Path { path in
                                    let points = viewModel.mileageData.enumerated().map { (index, item) -> CGPoint in
                                        let x = CGFloat(index) * (geometry.size.width / CGFloat(max(viewModel.mileageData.count - 1, 1)))
                                        let mileage = item[name] as? Double ?? 0
                                        // Proper scaling with maxMileage
                                        let y = geometry.size.height - (mileage / maxMileage) * geometry.size.height
                                        return CGPoint(x: x, y: y)
                                    }
                                    
                                    // Start the path at the first point
                                    if let firstPoint = points.first {
                                        path.move(to: firstPoint)
                                    }
                                    
                                    // Draw lines to subsequent points
                                    for point in points.dropFirst() {
                                        path.addLine(to: point)
                                    }
                                }
                                .stroke(getColorForPhotographer(name), lineWidth: 2)
                            }
                            
                            // Month labels at bottom
                            HStack(spacing: 0) {
                                ForEach(viewModel.mileageData.indices, id: \.self) { index in
                                    Text(viewModel.mileageData[index].month)
                                        .font(.system(size: 8))
                                        .frame(width: geometry.size.width / CGFloat(max(viewModel.mileageData.count, 1)))
                                }
                            }
                            .offset(y: geometry.size.height / 2 + 5)
                        }
                    }
                    .frame(height: 200)
                    .padding(.horizontal)
                }
            }
            
            // Reimbursement
            ChartCard(title: "Mileage Reimbursement") {
                VStack {
                    // Get maximum reimbursement value for scaling
                    let maxReimbursement = viewModel.mileageData.map { $0.total * 0.3 }.max() ?? 1.0
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .bottom, spacing: 15) {
                            ForEach(viewModel.mileageData) { item in
                                VStack {
                                    // Reimbursement bar
                                    ZStack(alignment: .bottom) {
                                        Rectangle()
                                            .fill(Color.green)
                                            .frame(width: 24, height: getScaledHeight(for: item.total * 0.3, maxValue: maxReimbursement, maxHeight: 150))
                                        
                                        Text("$\(Int(item.total * 0.3))")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                    }
                                    
                                    // Month label
                                    Text(item.month)
                                        .font(.caption)
                                        .padding(.top, 5)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
    }
    
    // MARK: - Locations Tab
    
    private var locationsTab: some View {
        VStack(spacing: 20) {
            // Top locations by visits
            ChartCard(title: "Top Locations by Visits") {
                VStack {
                    // Get max visits for scaling
                    let maxVisits = viewModel.locationData.map { $0.visits }.max() ?? 1
                    
                    ForEach(viewModel.locationData.sorted(by: { $0.visits > $1.visits }).prefix(5)) { location in
                        HStack {
                            Text(location.name)
                                .font(.subheadline)
                                .lineLimit(1)
                                .frame(width: 120, alignment: .leading)
                            
                            Spacer()
                            
                            // Visits bar
                            ZStack(alignment: .leading) {
                                // Background bar
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 150, height: 20)
                                
                                // Filled bar
                                Rectangle()
                                    .fill(Color.orange)
                                    .frame(width: getScaledWidth(for: Double(location.visits), maxValue: Double(maxVisits), maxWidth: 150), height: 20)
                                
                                // Value text
                                Text("\(location.visits) visits")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(.leading, 6)
                            }
                            .frame(width: 150, height: 20)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal)
            }
            
            // Locations by mileage
            ChartCard(title: "Locations by Mileage") {
                VStack {
                    // Get max mileage for scaling
                    let maxMileage = viewModel.locationData.map { $0.mileage }.max() ?? 1.0
                    
                    ForEach(viewModel.locationData.sorted(by: { $0.mileage > $1.mileage }).prefix(5)) { location in
                        HStack {
                            Text(location.name)
                                .font(.subheadline)
                                .lineLimit(1)
                                .frame(width: 120, alignment: .leading)
                            
                            Spacer()
                            
                            // Mileage bar
                            ZStack(alignment: .leading) {
                                // Background bar
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 150, height: 20)
                                
                                // Filled bar - using proper scaling
                                Rectangle()
                                    .fill(Color.purple)
                                    .frame(width: getScaledWidth(for: location.mileage, maxValue: maxMileage, maxWidth: 150), height: 20)
                                
                                // Value text
                                Text("\(Int(location.mileage)) miles")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(.leading, 6)
                            }
                            .frame(width: 150, height: 20)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal)
            }
            
            // Visits to mileage ratio
            ChartCard(title: "Visit Efficiency (Miles per Visit)") {
                VStack {
                    // Calculate a reasonable maximum for miles per visit
                    let milesPerVisitValues = viewModel.locationData.map {
                        location in location.visits > 0 ? location.mileage / Double(location.visits) : 0
                    }
                    let maxMilesPerVisit = milesPerVisitValues.max() ?? 50.0
                    
                    ForEach(viewModel.locationData.sorted {
                        ($0.visits > 0 ? $0.mileage / Double($0.visits) : 0) >
                        ($1.visits > 0 ? $1.mileage / Double($1.visits) : 0)
                    }.prefix(5)) { location in
                        let milesPerVisit = location.visits > 0 ? location.mileage / Double(location.visits) : 0
                        
                        HStack {
                            Text(location.name)
                                .font(.subheadline)
                                .lineLimit(1)
                                .frame(width: 120, alignment: .leading)
                            
                            Spacer()
                            
                            // Efficiency bar
                            ZStack(alignment: .leading) {
                                // Background bar
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 150, height: 20)
                                
                                // Filled bar - proper scaling
                                Rectangle()
                                    .fill(Color.teal)
                                    .frame(width: getScaledWidth(for: milesPerVisit, maxValue: maxMilesPerVisit, maxWidth: 150), height: 20)
                                
                                // Value text
                                Text("\(Int(milesPerVisit)) miles/visit")
                                    .font(.caption)
                                    .foregroundColor(.white)
                                    .padding(.leading, 6)
                            }
                            .frame(width: 150, height: 20)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Photographers Tab
    
    private var photographersTab: some View {
        VStack(spacing: 20) {
            // Jobs by photographer
            ChartCard(title: "Jobs by Photographer") {
                VStack {
                    // Get max jobs for scaling
                    let maxJobs = viewModel.photographerData.map { Double($0.jobs) }.max() ?? 1.0
                    
                    ForEach(viewModel.photographerData.sorted(by: { $0.jobs > $1.jobs })) { photographer in
                        HStack {
                            Text(photographer.name)
                                .font(.subheadline)
                                .frame(width: 60, alignment: .leading)
                            
                            // Jobs bar
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    // Background bar
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: geometry.size.width, height: 20)
                                    
                                    // Filled bar - proper scaling
                                    Rectangle()
                                        .fill(Color.blue)
                                        .frame(width: getScaledWidth(for: Double(photographer.jobs), maxValue: maxJobs, maxWidth: geometry.size.width), height: 20)
                                    
                                    // Value text
                                    Text("\(photographer.jobs) jobs")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .padding(.leading, 6)
                                }
                            }
                            .frame(height: 20)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal)
            }
            
            // Average job time
            ChartCard(title: "Average Job Time (Hours)") {
                VStack {
                    // Get max avg job time for scaling
                    let maxJobTime = viewModel.photographerData.map { $0.avgJobTime }.max() ?? 1.0
                    
                    ForEach(viewModel.photographerData.sorted(by: { $0.avgJobTime > $1.avgJobTime })) { photographer in
                        HStack {
                            Text(photographer.name)
                                .font(.subheadline)
                                .frame(width: 60, alignment: .leading)
                            
                            // Avg job time bar
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    // Background bar
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: geometry.size.width, height: 20)
                                    
                                    // Filled bar - proper scaling
                                    Rectangle()
                                        .fill(Color.green)
                                        .frame(width: getScaledWidth(for: photographer.avgJobTime, maxValue: maxJobTime, maxWidth: geometry.size.width), height: 20)
                                    
                                    // Value text
                                    Text("\(photographer.avgJobTime, specifier: "%.1f") hours")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .padding(.leading, 6)
                                }
                            }
                            .frame(height: 20)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal)
            }
            
            // Efficiency (Jobs per mile)
            ChartCard(title: "Jobs per 100 Miles") {
                VStack {
                    // Calculate the jobs per 100 miles values and find the maximum
                    let jobsPer100MilesValues = viewModel.photographerData.map { photographer in
                        photographer.miles > 0 ? Double(photographer.jobs) / photographer.miles * 100 : 0
                    }
                    let maxJobsPer100Miles = jobsPer100MilesValues.max() ?? 1.0
                    
                    ForEach(viewModel.photographerData.sorted(by: {
                        ($0.miles > 0 ? Double($0.jobs) / $0.miles : 0) > ($1.miles > 0 ? Double($1.jobs) / $1.miles : 0)
                    })) { photographer in
                        let jobsPer100Miles = photographer.miles > 0 ? Double(photographer.jobs) / photographer.miles * 100 : 0
                        
                        HStack {
                            Text(photographer.name)
                                .font(.subheadline)
                                .frame(width: 60, alignment: .leading)
                            
                            // Efficiency bar
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    // Background bar
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(width: geometry.size.width, height: 20)
                                    
                                    // Filled bar - proper scaling
                                    Rectangle()
                                        .fill(Color.orange)
                                        .frame(width: getScaledWidth(for: jobsPer100Miles, maxValue: maxJobsPer100Miles, maxWidth: geometry.size.width), height: 20)
                                    
                                    // Value text
                                    Text("\(jobsPer100Miles, specifier: "%.1f") jobs/100mi")
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .padding(.leading, 6)
                                }
                            }
                            .frame(height: 20)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    // MARK: - Job Type Tab
    
    private var jobTypeTab: some View {
        VStack(spacing: 20) {
            // Job type distribution visual
            ChartCard(title: "Job Type Distribution") {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(viewModel.jobTypeData.sorted(by: { $0.value > $1.value })) { jobType in
                            let percentage = jobType.value / Double(viewModel.totalJobs) * 100
                            
                            HStack {
                                // Color indicator
                                Circle()
                                    .fill(getColorForIndex(viewModel.jobTypeData.firstIndex(where: { $0.id == jobType.id }) ?? 0))
                                    .frame(width: 16, height: 16)
                                
                                // Job type name
                                Text(jobType.name)
                                    .font(.subheadline)
                                
                                Spacer()
                                
                                // Job count and percentage
                                VStack(alignment: .trailing) {
                                    Text("\(Int(jobType.value)) jobs")
                                        .font(.subheadline)
                                    
                                    Text("\(Int(percentage))%")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                            
                            // Bar representation
                            GeometryReader { geometry in
                                Rectangle()
                                    .fill(getColorForIndex(viewModel.jobTypeData.firstIndex(where: { $0.id == jobType.id }) ?? 0))
                                    .frame(width: percentage / 100 * geometry.size.width, height: 8)
                                    .cornerRadius(4)
                            }
                            .frame(height: 8)
                        }
                    }
                    .padding()
                }
                .frame(height: 300)
            }
            
            // Weather impact
            ChartCard(title: "Weather Impact on Jobs") {
                VStack {
                    ForEach(viewModel.weatherImpactData.sorted(by: { $0.jobs > $1.jobs })) { weatherItem in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                // Weather type and job count
                                HStack {
                                    Image(systemName: weatherIconForType(weatherItem.weather))
                                        .foregroundColor(colorForWeather(weatherItem.weather))
                                    
                                    Text(weatherItem.weather)
                                        .font(.subheadline)
                                }
                                
                                Spacer()
                                
                                Text("\(weatherItem.jobs) jobs")
                                    .font(.subheadline)
                            }
                            
                            // On-time arrival percentage
                            HStack {
                                Text("On-time arrival:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                GeometryReader { geometry in
                                    ZStack(alignment: .leading) {
                                        // Background bar
                                        Rectangle()
                                            .fill(Color.gray.opacity(0.2))
                                            .frame(width: geometry.size.width, height: 16)
                                            .cornerRadius(8)
                                        
                                        // Filled bar
                                        Rectangle()
                                            .fill(colorForWeather(weatherItem.weather))
                                            .frame(width: CGFloat(weatherItem.onTimeArrival) / 100 * geometry.size.width, height: 16)
                                            .cornerRadius(8)
                                        
                                        // Percentage text
                                        Text("\(weatherItem.onTimeArrival)%")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                            .padding(.leading, 6)
                                    }
                                }
                                .frame(height: 16)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                    }
                }
                .padding()
            }
        }
    }
    
    // MARK: - Helper Functions
    
    // Improved scaling function for bar heights
    private func getScaledHeight(for value: Double, maxValue: Double, maxHeight: CGFloat) -> CGFloat {
        // Ensure we don't divide by zero
        guard maxValue > 0 else { return 0 }
        
        // Calculate the ratio but cap it at 1.0 to prevent oversized bars
        let ratio = min(value / maxValue, 1.0)
        
        // Calculate height with a minimum visible height for small values
        let minVisibleHeight: CGFloat = 5
        let scaledHeight = CGFloat(ratio) * (maxHeight - minVisibleHeight) + minVisibleHeight
        
        return scaledHeight
    }
    
    // Improved scaling function for bar widths
    private func getScaledWidth(for value: Double, maxValue: Double, maxWidth: CGFloat) -> CGFloat {
        // Ensure we don't divide by zero
        guard maxValue > 0 else { return 0 }
        
        // Calculate the ratio but cap it at 1.0 to prevent oversized bars
        let ratio = min(value / maxValue, 1.0)
        
        // Calculate width with a minimum visible width for small values
        let minVisibleWidth: CGFloat = 5
        let scaledWidth = CGFloat(ratio) * (maxWidth - minVisibleWidth) + minVisibleWidth
        
        return scaledWidth
    }
    
    private func getColorForIndex(_ index: Int) -> Color {
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .yellow, .red]
        return colors[index % colors.count]
    }
    
    private func getColorForPhotographer(_ name: String) -> Color {
        switch name {
        case "John": return .blue
        case "Sarah": return .green
        case "Mike": return .orange
        default: return .gray
        }
    }
    
    private func colorForWeather(_ weather: String) -> Color {
        switch weather {
        case "Clear": return .yellow
        case "Cloudy": return .gray
        case "Rain": return .blue
        case "Snow": return .cyan
        case "Fog": return .purple
        default: return .gray
        }
    }
    
    private func weatherIconForType(_ weather: String) -> String {
        switch weather {
        case "Clear": return "sun.max.fill"
        case "Cloudy": return "cloud.fill"
        case "Rain": return "cloud.rain.fill"
        case "Snow": return "cloud.snow.fill"
        case "Fog": return "cloud.fog.fill"
        default: return "questionmark.circle"
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
