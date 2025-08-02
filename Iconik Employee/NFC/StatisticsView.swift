import SwiftUI
import Charts

struct StatisticsView: View {
    @ObservedObject private var userManager = UserManager.shared
    
    // Callback for navigation to search
    var onNavigateToSearch: ((String, Bool) -> Void)?
    
    @State private var records: [FirestoreRecord] = []
    @State private var jobBoxRecords: [JobBox] = []
    @State private var isLoading = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var selectedTimeFrame: TimeFrame = .all
    @State private var isJobBoxMode = false
    
    // For status distribution
    @State private var statusCounts: [StatusCount] = []
    @State private var totalCards: Int = 0
    
    // For time tracking
    @State private var averageTimes: [StatusTime] = []
    
    // For card lifecycle tracking
    @State private var cardLifecycles: [CardLifecycle] = []
    @State private var averageCycleDuration: Double = 0
    @State private var shortestCycle: Double = 0
    @State private var longestCycle: Double = 0
    @State private var totalCompletedCycles: Int = 0
    
    // For job box specific stats
    @State private var jobBoxStatusCounts: [StatusCount] = []
    @State private var totalJobBoxes: Int = 0
    @State private var jobBoxAverageTimes: [StatusTime] = []
    @State private var averageJobAssignmentTime: Double = 0 // Time from Packed to Picked Up
    @State private var averageJobCompletionTime: Double = 0 // Time from Picked Up to Turned In
    
    // For photographer job box "Left Job" duration metrics
    @State private var photographerLeftJobTimes: [PhotographerLeftJobTime] = []
    
    // For debugging taps
    @State private var lastTapLocation: CGPoint?
    
    // For debugging
    @State private var debugMode = false
    
    enum TimeFrame: String, CaseIterable, Identifiable {
        case day = "Today"
        case week = "This Week"
        case month = "This Month"
        case all = "All Time"
        
        var id: String { self.rawValue }
    }
    
    struct StatusCount: Identifiable {
        let id = UUID()
        let status: String
        let count: Int
        let percentage: Double
        
        var formattedPercentage: String {
            return String(format: "%.1f%%", percentage)
        }
    }
    
    struct StatusTime: Identifiable {
        let id = UUID()
        let status: String
        let averageHours: Double
        
        var formattedTime: String {
            if averageHours < 24 {
                return String(format: "%.1f hours", averageHours)
            } else {
                let days = averageHours / 24
                return String(format: "%.1f days", days)
            }
        }
    }
    
    struct CardLifecycle: Identifiable {
        let id = UUID()
        let cardNumber: String
        let startDate: Date
        let endDate: Date
        let durationDays: Double
    }
    
    // Status colors using unified color scheme
    func statusColor(_ status: String) -> Color {
        StatusColors.color(for: status, isJobBox: isJobBoxMode)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Toggle between SD Cards and Job Boxes
                Picker("View Mode", selection: $isJobBoxMode) {
                    Text("SD Cards").tag(false)
                    Text("Job Boxes").tag(true)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                .onChange(of: isJobBoxMode) { _ in
                    // Recalculate stats when changing modes
                    calculateStats()
                }
                
                // Time frame selector
                HStack {
                    Text("Time Frame:")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Picker("Time Frame", selection: $selectedTimeFrame) {
                        ForEach(TimeFrame.allCases) { timeFrame in
                            Text(timeFrame.rawValue).tag(timeFrame)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: selectedTimeFrame) { _ in
                        calculateStats()
                    }
                }
                .padding(.horizontal)
                
                // Card/Box status distribution
                VStack(alignment: .leading, spacing: 8) {
                    Text(isJobBoxMode ? "Job Box Status Distribution" : "Card Status Distribution")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .padding(.horizontal)
                    
                    if (isJobBoxMode ? jobBoxStatusCounts.isEmpty : statusCounts.isEmpty) {
                        Text("No data available")
                            .foregroundColor(.gray)
                            .padding()
                            .frame(maxWidth: .infinity)
                    } else {
                        // Pie Chart
                        ZStack {
                            // Background Card
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.secondarySystemBackground))
                                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                            
                            VStack {
                                Text("Total \(isJobBoxMode ? "Job Boxes" : "Cards"): \(isJobBoxMode ? totalJobBoxes : totalCards)")
                                    .font(.headline)
                                    .padding(.top, 8)
                                
                                pieChartView
                                
                                // Legend
                                VStack(alignment: .leading) {
                                    ForEach(isJobBoxMode ? jobBoxStatusCounts : statusCounts) { item in
                                        Button(action: {
                                            navigateToSearchView(with: item.status)
                                        }) {
                                            HStack {
                                                RoundedRectangle(cornerRadius: 4)
                                                    .fill(statusColor(item.status))
                                                    .frame(width: 20, height: 20)
                                                
                                                Text(item.status)
                                                    .font(.subheadline)
                                                    .foregroundColor(.primary)
                                                
                                                Spacer()
                                                
                                                Text("\(item.count) (\(item.formattedPercentage))")
                                                    .font(.subheadline)
                                                    .foregroundColor(.primary)
                                            }
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.horizontal)
                                .padding(.bottom)
                            }
                            .padding(8)
                        }
                        .padding(.horizontal)
                    }
                }
                
                // Average Time in Status
                VStack(alignment: .leading, spacing: 8) {
                    Text("Average Time in Status")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .padding(.horizontal)
                    
                    timeInStatusView
                }
                
                if !isJobBoxMode {
                    // Card Lifecycle (SD Cards only)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Card Lifecycle")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.horizontal)
                        
                        cardLifecycleView
                    }
                } else {
                    // Job Box Process Time
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Job Box Process Time")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.horizontal)
                        
                        jobBoxProcessTimeView
                    }
                }
                
                // Photographer Performance
                VStack(alignment: .leading, spacing: 8) {
                    Text("Photographer Performance")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .padding(.horizontal)
                    
                    photographerPerformanceView
                }
                
                // Photographer Job Box "Left Job" Times
                if isJobBoxMode {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Job Box 'Left Job' Duration by Photographer")
                            .font(.headline)
                            .foregroundColor(.primary)
                            .padding(.horizontal)
                        
                        PhotographerJobBoxMetrics(photographerLeftJobTimes: photographerLeftJobTimes)
                    }
                }
            }
            .padding(.vertical)
        }
        .navigationTitle("Statistics")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
        .onAppear {
            print("DEBUG: StatisticsView appeared")
            loadData()
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Error"),
                  message: Text(alertMessage),
                  dismissButton: .default(Text("OK")))
        }
    }
    
    // Breaking up the complex view into smaller components to help the compiler
    var pieChartView: some View {
        Group {
            if #available(iOS 16.0, *) {
                pieChartIOS16
            } else {
                pieChartFallback
            }
        }
    }
    
    @available(iOS 16.0, *)
    var pieChartIOS16: some View {
        GeometryReader { geometry in
            let data = isJobBoxMode ? jobBoxStatusCounts : statusCounts
            let total = data.reduce(0) { $0 + $1.count }
            
            if total == 0 {
                Text("No data available")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack {
                    // Draw pie slices
                    let slices = createPieChartSlices(from: data, total: total)
                    ForEach(slices, id: \.status) { slice in
                        PieSlice(
                            startAngle: slice.startAngle,
                            endAngle: slice.endAngle,
                            innerRadiusRatio: 0
                        )
                        .fill(statusColor(slice.status))
                    }
                    
                    // Add labels around the pie
                    ForEach(slices, id: \.status) { slice in
                        let midAngle = (slice.startAngle + slice.endAngle) / 2
                        let labelRadius = min(geometry.size.width, geometry.size.height) * 0.35
                        let x = cos(midAngle.radians) * labelRadius
                        let y = sin(midAngle.radians) * labelRadius
                        
                        Text("\(slice.percentage)%")
                            .font(.caption)
                            .foregroundColor(.white)
                            .position(
                                x: geometry.size.width / 2 + CGFloat(x),
                                y: geometry.size.height / 2 + CGFloat(y)
                            )
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(height: 200)
    }
    
    var pieChartFallback: some View {
        VStack(spacing: 8) {
            ForEach(isJobBoxMode ? jobBoxStatusCounts : statusCounts) { item in
                HStack {
                    Text(item.status)
                        .font(.subheadline)
                        .frame(width: 80, alignment: .leading)
                    
                    Button(action: {
                        navigateToSearchView(with: item.status)
                    }) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(statusColor(item.status))
                            .frame(width: CGFloat(item.count) / CGFloat(isJobBoxMode ? totalJobBoxes : totalCards) * 200, height: 20)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Text("\(item.count) (\(item.formattedPercentage))")
                        .font(.subheadline)
                }
            }
        }
        .frame(height: 250)
        .padding()
    }
    
    var timeInStatusView: some View {
        Group {
            if (isJobBoxMode ? jobBoxAverageTimes.isEmpty : averageTimes.isEmpty) {
                Text("No data available")
                    .foregroundColor(.gray)
                    .padding()
                    .frame(maxWidth: .infinity)
            } else {
                // Bar Chart
                ZStack {
                    // Background Card
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                    
                    VStack {
                        if #available(iOS 16.0, *) {
                            Chart(isJobBoxMode ? jobBoxAverageTimes : averageTimes) { statusTime in
                                BarMark(
                                    x: .value("Status", statusTime.status),
                                    y: .value("Hours", statusTime.averageHours)
                                )
                                .foregroundStyle(statusColor(statusTime.status))
                                .annotation(position: .top) {
                                    Text(statusTime.formattedTime)
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                }
                            }
                            .chartYAxis {
                                AxisMarks(position: .leading)
                            }
                            .frame(height: 250)
                        } else {
                            // Simple bar representation
                            Text("Chart requires iOS 16+")
                                .foregroundColor(.gray)
                            
                            let maxHours = (isJobBoxMode ? jobBoxAverageTimes : averageTimes).map { $0.averageHours }.max() ?? 1
                            
                            VStack(spacing: 8) {
                                ForEach(isJobBoxMode ? jobBoxAverageTimes : averageTimes) { item in
                                    HStack {
                                        Text(item.status)
                                            .font(.subheadline)
                                            .frame(width: 80, alignment: .leading)
                                        
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(statusColor(item.status))
                                            .frame(width: CGFloat(item.averageHours) / CGFloat(maxHours) * 200, height: 20)
                                        
                                        Text(item.formattedTime)
                                            .font(.subheadline)
                                    }
                                }
                            }
                            .frame(height: 250)
                            .padding()
                        }
                        
                        // Table View
                        VStack(alignment: .leading) {
                            ForEach(isJobBoxMode ? jobBoxAverageTimes : averageTimes) { item in
                                HStack {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(statusColor(item.status))
                                        .frame(width: 20, height: 20)
                                    
                                    Text(item.status)
                                        .font(.subheadline)
                                    
                                    Spacer()
                                    
                                    Text(item.formattedTime)
                                        .font(.subheadline)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                    .padding(8)
                }
                .padding(.horizontal)
            }
        }
    }
    
    var cardLifecycleView: some View {
        ZStack {
            // Background Card
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Card Lifecycle (Job Box → Cleared)")
                    .font(.headline)
                    .padding(.top, 12)
                
                if totalCompletedCycles > 0 {
                    HStack(spacing: 20) {
                        VStack(alignment: .center) {
                            Text("Average")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text(String(format: "%.1f days", averageCycleDuration))
                                .font(.title3)
                                .bold()
                        }
                        .frame(maxWidth: .infinity)
                        
                        VStack(alignment: .center) {
                            Text("Shortest")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text(String(format: "%.1f days", shortestCycle))
                                .font(.title3)
                                .bold()
                        }
                        .frame(maxWidth: .infinity)
                        
                        VStack(alignment: .center) {
                            Text("Longest")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Text(String(format: "%.1f days", longestCycle))
                                .font(.title3)
                                .bold()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal)
                    
                    if #available(iOS 16.0, *) {
                        // Limit to the 10 most recent completed cycles for the chart
                        let displayLifecycles = Array(cardLifecycles.prefix(10))
                        
                        Chart(displayLifecycles) { lifecycle in
                            BarMark(
                                x: .value("Card", lifecycle.cardNumber),
                                y: .value("Days", lifecycle.durationDays)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [Color.blue, Color.purple],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading)
                        }
                        .chartXAxis {
                            AxisMarks { _ in
                                AxisValueLabel()
                                    .font(.caption)
                            }
                        }
                        .frame(height: 200)
                        .padding(.horizontal)
                    } else {
                        // Limit to 10 most recent cycles
                        let displayLifecycles = Array(cardLifecycles.prefix(10))
                        let maxDuration = displayLifecycles.max(by: { $0.durationDays < $1.durationDays })?.durationDays ?? 1
                        
                        VStack(spacing: 10) {
                            ForEach(displayLifecycles) { lifecycle in
                                HStack {
                                    Text(lifecycle.cardNumber)
                                        .font(.caption)
                                        .frame(width: 60, alignment: .leading)
                                    
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.blue, Color.purple],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: CGFloat(lifecycle.durationDays) / CGFloat(maxDuration) * 200, height: 20)
                                    
                                    Text(String(format: "%.1f days", lifecycle.durationDays))
                                        .font(.caption)
                                }
                            }
                        }
                        .frame(height: 200)
                        .padding(.horizontal)
                    }
                    
                    HStack {
                        Text("Total completed cycles:")
                            .font(.callout)
                        Text("\(totalCompletedCycles)")
                            .font(.callout)
                            .bold()
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                } else {
                    VStack {
                        Text("No complete card cycles found")
                            .foregroundColor(.gray)
                            .padding()
                        Text("Complete cycles go from Job Box to Cleared status")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                }
            }
            .padding(16)
        }
        .frame(height: 320)
    }
    
    // Job Box process time view
    var jobBoxProcessTimeView: some View {
        ZStack {
            // Background Card
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Job Box Processing Timeline")
                    .font(.headline)
                    .padding(.top, 12)
                
                HStack(spacing: 20) {
                    VStack(alignment: .center) {
                        Text("Assignment Time")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(String(format: "%.1f hours", averageJobAssignmentTime))
                            .font(.title3)
                            .bold()
                        Text("Packed → Picked Up")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    
                    VStack(alignment: .center) {
                        Text("Completion Time")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(String(format: "%.1f hours", averageJobCompletionTime))
                            .font(.title3)
                            .bold()
                        Text("Picked Up → Turned In")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal)
                
                if #available(iOS 16.0, *) {
                    jobBoxProcessChartIOS16
                } else {
                    jobBoxProcessChartFallback
                }
            }
            .padding(16)
        }
        .frame(height: 300)
    }
    
    @available(iOS 16.0, *)
    var jobBoxProcessChartIOS16: some View {
        // Simple horizontal bar chart showing the process stages
        Chart {
            BarMark(
                x: .value("Hours", averageJobAssignmentTime),
                y: .value("Stage", "Assignment")
            )
            .foregroundStyle(Color.blue)
            
            BarMark(
                x: .value("Hours", averageJobCompletionTime),
                y: .value("Stage", "Completion")
            )
            .foregroundStyle(Color.green)
        }
        .chartXAxis {
            AxisMarks(position: .bottom) {
                AxisGridLine()
                AxisTick()
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) {
                AxisValueLabel()
            }
        }
        .frame(height: 150)
    }
    
    var jobBoxProcessChartFallback: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Assignment")
                    .font(.caption)
                    .frame(width: 80, alignment: .leading)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.blue)
                    .frame(width: CGFloat(min(averageJobAssignmentTime, 100)) * 2, height: 30)
                
                Text(String(format: "%.1f hours", averageJobAssignmentTime))
                    .font(.caption)
            }
            
            HStack {
                Text("Completion")
                    .font(.caption)
                    .frame(width: 80, alignment: .leading)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.green)
                    .frame(width: CGFloat(min(averageJobCompletionTime, 100)) * 2, height: 30)
                
                Text(String(format: "%.1f hours", averageJobCompletionTime))
                    .font(.caption)
            }
        }
        .frame(height: 150)
        .padding(.horizontal)
    }
    
    // Photographer performance view
    var photographerPerformanceView: some View {
        ZStack {
            // Background Card
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Photographer Activity")
                    .font(.headline)
                    .padding(.top, 12)
                
                if #available(iOS 16.0, *) {
                    let photographerData = getPhotographerData()
                    
                    Chart(photographerData) { data in
                        BarMark(
                            x: .value("Photographer", data.name),
                            y: .value(isJobBoxMode ? "Job Boxes" : "Cards", data.count)
                        )
                        .foregroundStyle(Color.blue.gradient)
                        .annotation(position: .top) {
                            Text("\(data.count)")
                                .font(.caption)
                                .foregroundColor(.primary)
                        }
                    }
                    .chartXAxis {
                        AxisMarks { value in
                            AxisValueLabel {
                                if let name = value.as(String.self) {
                                    Text(name)
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .frame(height: 220)
                } else {
                    let data = getPhotographerData()
                    let maxCount = data.map { $0.count }.max() ?? 1
                    
                    VStack(spacing: 10) {
                        ForEach(data) { item in
                            HStack {
                                Text(item.name)
                                    .font(.caption)
                                    .frame(width: 80, alignment: .leading)
                                    .lineLimit(1)
                                
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.blue)
                                    .frame(width: CGFloat(item.count) / CGFloat(maxCount) * 200, height: 20)
                                
                                Text("\(item.count)")
                                    .font(.caption)
                            }
                        }
                    }
                    .frame(height: 220)
                }
                
                Spacer()
            }
            .padding(16)
        }
        .frame(height: 300)
    }
    
    // MARK: - Helper Methods
    
    // Helper for finding tapped status
    func findTappedStatus(at point: CGPoint, in size: CGSize) -> StatusCount? {
        // Get the center of the chart
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        
        // Calculate distance from center to tapped point
        let dx = point.x - center.x
        let dy = point.y - center.y
        let distanceFromCenter = sqrt(dx*dx + dy*dy)
        
        // Chart radius
        let radius = min(size.width, size.height) / 2.0
        
        // Inner radius of the donut (we use innerRadius: .ratio(0.5) in our chart)
        let innerRadius = radius * 0.5
        
        // Check if tap is outside chart bounds or in the inner donut hole
        if distanceFromCenter > radius || distanceFromCenter < innerRadius {
            return nil
        }
        
        // Calculate angle in radians using inverted y-coordinate
        // atan2 returns angle in range -π to π, where 0 is at positive x-axis (3 o'clock)
        var angle = atan2(-dy, dx)  // Note the negation of dy here
        
        // Convert to 0...2π range
        if angle < 0 {
            angle += 2 * .pi
        }
        
        // Convert to degrees (0-360)
        let angleDegrees = angle * 180 / .pi
        
        // In SwiftUI Charts, 0 degrees is at 12 o'clock and moves clockwise
        // So we need to adjust our angle (90 degrees counter-clockwise)
        var adjustedAngleDegrees = 90 - angleDegrees
        if adjustedAngleDegrees < 0 {
            adjustedAngleDegrees += 360
        }
        
        // Normalize to 0-360 range
        adjustedAngleDegrees = adjustedAngleDegrees.truncatingRemainder(dividingBy: 360)
        
        // Calculate sector angles
        let statusData = isJobBoxMode ? jobBoxStatusCounts : statusCounts
        let totalValue = statusData.reduce(0) { $0 + $1.count }
        
        // Now we determine which sector contains our angle
        var startAngle: Double = 0
        for statusCount in statusData {
            // Calculate what percentage of the pie this sector represents
            let percentage = Double(statusCount.count) / Double(totalValue)
            
            // Convert to degrees (360 degrees in a full circle)
            let sweepAngle = percentage * 360
            
            // End angle of this sector
            let endAngle = startAngle + sweepAngle
            
            // Check if our tap angle falls within this sector
            if startAngle <= adjustedAngleDegrees && adjustedAngleDegrees < endAngle {
                print("DEBUG: Tap at point: \(point)")
                print("DEBUG: Angle in degrees: \(adjustedAngleDegrees)")
                print("DEBUG: Selected sector: \(statusCount.status) (Start: \(startAngle)°, End: \(endAngle)°)")
                return statusCount
            }
            
            // Move to next sector
            startAngle = endAngle
        }
        
        // If we get here, we didn't find a match (shouldn't happen unless data is empty)
        print("DEBUG: No sector found for angle: \(adjustedAngleDegrees)°")
        return nil
    }
    
    func navigateToSearchView(with status: String) {
        if let navigate = onNavigateToSearch {
            navigate(status, isJobBoxMode)
        }
    }
    
    // Data structure for photographer chart
    struct PhotographerData: Identifiable {
        let id = UUID()
        let name: String
        let count: Int
    }
    
    // Generate photographer data for chart
    func getPhotographerData() -> [PhotographerData] {
        let photographerGroups: [String: [Any]]
        
        if isJobBoxMode {
            photographerGroups = Dictionary(grouping: jobBoxRecords, by: { $0.scannedBy })
                .mapValues { $0 as [Any] }
        } else {
            photographerGroups = Dictionary(grouping: records, by: { $0.photographer })
                .mapValues { $0 as [Any] }
        }
        
        return photographerGroups.compactMap { name, records in
            guard !name.isEmpty else { return nil }
            let uniqueCount: Int
            
            if isJobBoxMode {
                let jobBoxes = records.compactMap { $0 as? JobBox }
                uniqueCount = Set(jobBoxes.map { $0.boxNumber }).count
            } else {
                let sdCards = records.compactMap { $0 as? FirestoreRecord }
                uniqueCount = Set(sdCards.map { $0.cardNumber }).count
            }
            
            return PhotographerData(name: name, count: uniqueCount)
        }
        .sorted { $0.count > $1.count }
        .prefix(5) // Just show top 5 photographers
        .map { $0 } // Convert to array
    }
    
    func calculateCardLifecycles(_ records: [FirestoreRecord]) {
        // Group all records by card number
        let cardGroups = Dictionary(grouping: records, by: { $0.cardNumber })
        
        var lifecycles: [CardLifecycle] = []
        
        for (cardNumber, cardRecords) in cardGroups {
            // Sort records by timestamp (oldest first)
            let sortedRecords = cardRecords.sorted(by: { $0.timestamp < $1.timestamp })
            
            // Find all job box entries (cycle starts)
            let jobBoxEntries = sortedRecords.filter { $0.status.lowercased() == "job box" }
            
            // For each job box entry, find the next "cleared" status
            for jobBoxEntry in jobBoxEntries {
                // Find records that occurred after this job box entry
                let subsequentRecords = sortedRecords.filter { $0.timestamp > jobBoxEntry.timestamp }
                
                // Find the next "cleared" status
                if let clearedEntry = subsequentRecords.first(where: { $0.status.lowercased() == "cleared" }) {
                    // Calculate duration in days
                    let durationSeconds = clearedEntry.timestamp.timeIntervalSince(jobBoxEntry.timestamp)
                    let durationDays = durationSeconds / (24 * 3600) // Convert seconds to days
                    
                    // Only include realistic cycles (more than 0 days, less than 90 days)
                    if durationDays > 0 && durationDays < 90 {
                        let lifecycle = CardLifecycle(
                            cardNumber: cardNumber,
                            startDate: jobBoxEntry.timestamp,
                            endDate: clearedEntry.timestamp,
                            durationDays: durationDays
                        )
                        lifecycles.append(lifecycle)
                    }
                }
            }
        }
        
        // Calculate statistics
        if !lifecycles.isEmpty {
            let totalDays = lifecycles.reduce(0) { $0 + $1.durationDays }
            averageCycleDuration = totalDays / Double(lifecycles.count)
            shortestCycle = lifecycles.min(by: { $0.durationDays < $1.durationDays })?.durationDays ?? 0
            longestCycle = lifecycles.max(by: { $0.durationDays < $1.durationDays })?.durationDays ?? 0
            totalCompletedCycles = lifecycles.count
        } else {
            averageCycleDuration = 0
            shortestCycle = 0
            longestCycle = 0
            totalCompletedCycles = 0
        }
        
        cardLifecycles = lifecycles.sorted(by: { $0.endDate > $1.endDate })
    }
    
    func calculateJobBoxTimelines(_ records: [JobBox]) {
        // Group by box number
        let boxGroups = Dictionary(grouping: records, by: { $0.boxNumber })
        
        var assignmentTimes: [Double] = []
        var completionTimes: [Double] = []
        
        for (_, boxRecords) in boxGroups {
            // Sort records by timestamp (oldest first)
            let sortedRecords = boxRecords.sorted(by: { $0.timestamp < $1.timestamp })
            
            // Find transition times between statuses
            for i in 0..<sortedRecords.count-1 {
                let currentRecord = sortedRecords[i]
                let nextRecord = sortedRecords[i+1]
                
                // Packed → Picked Up (Assignment time)
                if currentRecord.status == .packed && nextRecord.status == .pickedUp {
                    let durationHours = nextRecord.timestamp.timeIntervalSince(currentRecord.timestamp) / 3600.0
                    if durationHours > 0 && durationHours < 168 { // Less than a week to avoid outliers
                        assignmentTimes.append(durationHours)
                    }
                }
                
                // Picked Up → Turned In (Completion time)
                if currentRecord.status == .pickedUp && nextRecord.status == .turnedIn {
                    let durationHours = nextRecord.timestamp.timeIntervalSince(currentRecord.timestamp) / 3600.0
                    if durationHours > 0 && durationHours < 168 { // Less than a week to avoid outliers
                        completionTimes.append(durationHours)
                    }
                }
            }
        }
        
        // Calculate averages
        if !assignmentTimes.isEmpty {
            averageJobAssignmentTime = assignmentTimes.reduce(0, +) / Double(assignmentTimes.count)
        } else {
            averageJobAssignmentTime = 0
        }
        
        if !completionTimes.isEmpty {
            averageJobCompletionTime = completionTimes.reduce(0, +) / Double(completionTimes.count)
        } else {
            averageJobCompletionTime = 0
        }
    }
    
    // Calculate photographer left job times with improved debugging
    func calculatePhotographerLeftJobTimes(_ records: [JobBox]) {
        print("DEBUG: Starting calculatePhotographerLeftJobTimes with \(records.count) records")
        
        // Group by photographer (scannedBy field)
        let photographerGroups = Dictionary(grouping: records, by: { $0.scannedBy })
        print("DEBUG: Found \(photographerGroups.count) photographers")
        
        var leftJobMetrics: [PhotographerLeftJobTime] = []
        let currentTime = Date()
        
        for (photographerName, boxRecords) in photographerGroups {
            // Skip if no photographer name (shouldn't happen but just in case)
            if photographerName.isEmpty {
                print("DEBUG: Skipping empty photographer name")
                continue
            }
            
            print("DEBUG: Processing photographer '\(photographerName)' with \(boxRecords.count) box records")
            
            // Sort records by box number and timestamp to group by individual box
            let sortedByBox = Dictionary(grouping: boxRecords, by: { $0.boxNumber })
            print("DEBUG: Photographer has \(sortedByBox.count) unique job boxes")
            
            var totalLeftJobHours: Double = 0
            var leftJobTransitionsCount: Int = 0
            var currentLeftJobBoxes: Int = 0
            
            for (boxNumber, boxRecords) in sortedByBox {
                let sortedRecords = boxRecords.sorted(by: { $0.timestamp < $1.timestamp })
                print("DEBUG: Box #\(boxNumber) has \(sortedRecords.count) status records")
                
                // Track periods in "Left Job" status
                var inLeftJob = false
                var leftJobStartTime: Date?
                
                for (index, record) in sortedRecords.enumerated() {
                    if record.status == .leftJob {
                        if !inLeftJob {
                            // Entering "Left Job" status
                            inLeftJob = true
                            leftJobStartTime = record.timestamp
                            print("DEBUG: Box #\(boxNumber) entered 'Left Job' at \(record.timestamp)")
                        }
                        
                        // If this is the last record for this box and it's still in "Left Job"
                        if index == sortedRecords.count - 1 && inLeftJob {
                            currentLeftJobBoxes += 1
                            print("DEBUG: Box #\(boxNumber) is currently in 'Left Job'")
                            
                            // Add the time from the start to now for current boxes still in "Left Job"
                            if let startTime = leftJobStartTime {
                                let hoursInLeftJob = currentTime.timeIntervalSince(startTime) / 3600.0
                                print("DEBUG: Box #\(boxNumber) has been in 'Left Job' for \(hoursInLeftJob) hours")
                                
                                // Always count current boxes, regardless of duration
                                totalLeftJobHours += hoursInLeftJob
                                leftJobTransitionsCount += 1
                            }
                        }
                    } else if inLeftJob {
                        // Transitioning out of "Left Job" status
                        inLeftJob = false
                        print("DEBUG: Box #\(boxNumber) exited 'Left Job' to '\(record.status)' at \(record.timestamp)")
                        
                        if let startTime = leftJobStartTime {
                            let hoursInLeftJob = record.timestamp.timeIntervalSince(startTime) / 3600.0
                            print("DEBUG: Box #\(boxNumber) was in 'Left Job' for \(hoursInLeftJob) hours")
                            
                            // Only count if it was in "Left Job" for at least 1 hour
                            if hoursInLeftJob >= 1 {
                                totalLeftJobHours += hoursInLeftJob
                                leftJobTransitionsCount += 1
                            }
                        }
                        
                        // Reset the start time
                        leftJobStartTime = nil
                    }
                }
            }
            
            // Calculate the average hours in "Left Job" status
            let averageHours: Double
            if leftJobTransitionsCount > 0 {
                averageHours = totalLeftJobHours / Double(leftJobTransitionsCount)
            } else {
                // If we have current boxes but no completed transitions, use the total hours
                averageHours = totalLeftJobHours
            }
            
            print("DEBUG: Photographer '\(photographerName)' stats: " +
                  "currentBoxes=\(currentLeftJobBoxes), " +
                  "transitions=\(leftJobTransitionsCount), " +
                  "totalHours=\(totalLeftJobHours), " +
                  "avgHours=\(averageHours)")
            
            // Create metric object - include all photographers with any data
            let metric = PhotographerLeftJobTime(
                photographerName: photographerName,
                averageHours: averageHours,
                totalHours: totalLeftJobHours,
                transitionCount: leftJobTransitionsCount,
                currentBoxes: currentLeftJobBoxes
            )
            
            // Include photographers with any data about job boxes in "Left Job" status
            if leftJobTransitionsCount > 0 || currentLeftJobBoxes > 0 ||
               (debugMode && sortedByBox.contains { box, records in
                   records.contains { $0.status == .leftJob }
               }) {
                leftJobMetrics.append(metric)
                print("DEBUG: Added photographer '\(photographerName)' to metrics")
            }
        }
        
        // Sort by average time, longest first
        self.photographerLeftJobTimes = leftJobMetrics.sorted(by: { $0.averageHours > $1.averageHours })
        print("DEBUG: Final photographer metrics count: \(self.photographerLeftJobTimes.count)")
    }
    
    func calculateStats() {
        // Filter records by timeframe
        let filteredRecords = filterRecordsByTimeFrame(records)
        let filteredJobBoxRecords = filterJobBoxRecordsByTimeFrame(jobBoxRecords)
        
        if isJobBoxMode {
            // Calculate job box stats
            calculateJobBoxStatusDistribution(filteredJobBoxRecords)
            calculateJobBoxAverageTimeInStatus(filteredJobBoxRecords)
            calculateJobBoxTimelines(filteredJobBoxRecords)
            calculatePhotographerLeftJobTimes(filteredJobBoxRecords)
        } else {
            // Calculate SD card stats
            calculateStatusDistribution(filteredRecords)
            calculateAverageTimeInStatus(filteredRecords)
            calculateCardLifecycles(filteredRecords)
        }
    }
    
    func loadData() {
        let orgID = userManager.currentUserOrganizationID
        guard !orgID.isEmpty else {
            alertMessage = "User organization not found"
            showAlert = true
            return
        }
        
        isLoading = true
        
        // Load SD card records
        FirestoreManager.shared.fetchRecords(field: "all", value: "", organizationID: orgID) { result in
            switch result {
            case .success(let fetchedRecords):
                print("DEBUG: Loaded \(fetchedRecords.count) SD card records")
                self.records = fetchedRecords
                
                // Now load job box records
                FirestoreManager.shared.fetchJobBoxRecords(field: "all", value: "", organizationID: orgID) { jobBoxResult in
                    self.isLoading = false
                    
                    switch jobBoxResult {
                    case .success(let fetchedJobBoxRecords):
                        print("DEBUG: Loaded \(fetchedJobBoxRecords.count) job box records")
                        self.jobBoxRecords = fetchedJobBoxRecords
                        
                        // Calculate stats once both data sets are loaded
                        self.calculateStats()
                        
                    case .failure(let error):
                        self.alertMessage = "Error loading job box data: \(error.localizedDescription)"
                        self.showAlert = true
                        print("DEBUG: Failed to load job box records: \(error.localizedDescription)")
                        
                        // Still calculate SD card stats
                        self.calculateStats()
                    }
                }
                
            case .failure(let error):
                self.isLoading = false
                self.alertMessage = "Error loading data: \(error.localizedDescription)"
                self.showAlert = true
                print("DEBUG: Failed to load SD card records: \(error.localizedDescription)")
            }
        }
    }
    
    func filterRecordsByTimeFrame(_ records: [FirestoreRecord]) -> [FirestoreRecord] {
        let calendar = Calendar.current
        let now = Date()
        
        switch selectedTimeFrame {
        case .day:
            let startOfDay = calendar.startOfDay(for: now)
            return records.filter { calendar.isDate($0.timestamp, inSameDayAs: startOfDay) }
            
        case .week:
            let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            return records.filter { $0.timestamp >= startOfWeek }
            
        case .month:
            let components = calendar.dateComponents([.year, .month], from: now)
            let startOfMonth = calendar.date(from: components)!
            return records.filter { $0.timestamp >= startOfMonth }
            
        case .all:
            return records
        }
    }
    
    func filterJobBoxRecordsByTimeFrame(_ records: [JobBox]) -> [JobBox] {
        let calendar = Calendar.current
        let now = Date()
        
        switch selectedTimeFrame {
        case .day:
            let startOfDay = calendar.startOfDay(for: now)
            return records.filter { calendar.isDate($0.timestamp, inSameDayAs: startOfDay) }
            
        case .week:
            let startOfWeek = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            return records.filter { $0.timestamp >= startOfWeek }
            
        case .month:
            let components = calendar.dateComponents([.year, .month], from: now)
            let startOfMonth = calendar.date(from: components)!
            return records.filter { $0.timestamp >= startOfMonth }
            
        case .all:
            return records
        }
    }
    
    func calculateStatusDistribution(_ records: [FirestoreRecord]) {
        // Group records by card number
        let cardGroups = Dictionary(grouping: records, by: { $0.cardNumber })
        
        // Get the latest status for each card
        var latestRecords: [FirestoreRecord] = []
        for (_, cardRecords) in cardGroups {
            if let latestRecord = cardRecords.sorted(by: { $0.timestamp > $1.timestamp }).first {
                latestRecords.append(latestRecord)
            }
        }
        
        // Count by status
        let statusGroups = Dictionary(grouping: latestRecords, by: { $0.status.lowercased() })
        let counts = statusGroups.mapValues { $0.count }
        
        totalCards = latestRecords.count
        
        // Create the status counts array
        statusCounts = counts.map { status, count in
            let percentage = totalCards > 0 ? (Double(count) / Double(totalCards) * 100.0) : 0
            return StatusCount(status: status.capitalized, count: count, percentage: percentage)
        }.sorted { $0.count > $1.count }
    }
    
    func calculateJobBoxStatusDistribution(_ records: [JobBox]) {
        // Group records by box number
        let boxGroups = Dictionary(grouping: records, by: { $0.boxNumber })
        
        // Get the latest status for each box
        var latestRecords: [JobBox] = []
        for (_, boxRecords) in boxGroups {
            if let latestRecord = boxRecords.sorted(by: { $0.timestamp > $1.timestamp }).first {
                latestRecords.append(latestRecord)
            }
        }
        
        // Count by status
        let statusGroups = Dictionary(grouping: latestRecords, by: { $0.status.rawValue.lowercased() })
        let counts = statusGroups.mapValues { $0.count }
        
        totalJobBoxes = latestRecords.count
        
        // Create the status counts array
        jobBoxStatusCounts = counts.map { status, count in
            let percentage = totalJobBoxes > 0 ? (Double(count) / Double(totalJobBoxes) * 100.0) : 0
            return StatusCount(status: status.capitalized, count: count, percentage: percentage)
        }.sorted { $0.count > $1.count }
    }
    
    func calculateAverageTimeInStatus(_ records: [FirestoreRecord]) {
        // Group records by card number
        let cardGroups = Dictionary(grouping: records, by: { $0.cardNumber })
        
        // Track time spent in each status
        var statusDurations: [String: [TimeInterval]] = [:]
        
        for (_, cardRecords) in cardGroups {
            // Sort by timestamp (oldest first)
            let sortedRecords = cardRecords.sorted(by: { $0.timestamp < $1.timestamp })
            
            // Process transitions
            for i in 0..<sortedRecords.count-1 {
                let currentRecord = sortedRecords[i]
                let nextRecord = sortedRecords[i+1]
                
                let duration = nextRecord.timestamp.timeIntervalSince(currentRecord.timestamp)
                let status = currentRecord.status.lowercased()
                
                if duration > 0 {
                    if statusDurations[status] == nil {
                        statusDurations[status] = []
                    }
                    statusDurations[status]?.append(duration)
                }
            }
            
            // For the last record, calculate time from then to now (if it's recent enough)
            if let lastRecord = sortedRecords.last {
                let now = Date()
                let duration = now.timeIntervalSince(lastRecord.timestamp)
                let status = lastRecord.status.lowercased()
                
                // Only include if it's less than 30 days to avoid skewing data
                if duration > 0 && duration < (30 * 24 * 60 * 60) {
                    if statusDurations[status] == nil {
                        statusDurations[status] = []
                    }
                    statusDurations[status]?.append(duration)
                }
            }
        }
        
        // Calculate averages
        averageTimes = statusDurations.compactMap { status, durations in
            guard !durations.isEmpty else { return nil }
            let totalSeconds = durations.reduce(0, +)
            let averageSeconds = totalSeconds / Double(durations.count)
            let averageHours = averageSeconds / 3600.0 // Convert to hours
            
            return StatusTime(status: status.capitalized, averageHours: averageHours)
        }.sorted { $0.averageHours > $1.averageHours }
    }
    
    func calculateJobBoxAverageTimeInStatus(_ records: [JobBox]) {
        // Group records by box number
        let boxGroups = Dictionary(grouping: records, by: { $0.boxNumber })
        
        // Track time spent in each status
        var statusDurations: [String: [TimeInterval]] = [:]
        
        for (_, boxRecords) in boxGroups {
            // Sort by timestamp (oldest first)
            let sortedRecords = boxRecords.sorted(by: { $0.timestamp < $1.timestamp })
            
            // Process transitions
            for i in 0..<sortedRecords.count-1 {
                let currentRecord = sortedRecords[i]
                let nextRecord = sortedRecords[i+1]
                
                let duration = nextRecord.timestamp.timeIntervalSince(currentRecord.timestamp)
                let status = currentRecord.status.rawValue.lowercased()
                
                if duration > 0 {
                    if statusDurations[status] == nil {
                        statusDurations[status] = []
                    }
                    statusDurations[status]?.append(duration)
                }
            }
            
            // For the last record, calculate time from then to now (if it's recent enough)
            if let lastRecord = sortedRecords.last {
                let now = Date()
                let duration = now.timeIntervalSince(lastRecord.timestamp)
                let status = lastRecord.status.rawValue.lowercased()
                
                // Only include if it's less than 30 days to avoid skewing data
                if duration > 0 && duration < (30 * 24 * 60 * 60) {
                    if statusDurations[status] == nil {
                        statusDurations[status] = []
                    }
                    statusDurations[status]?.append(duration)
                }
            }
        }
        
        // Calculate averages
        jobBoxAverageTimes = statusDurations.compactMap { status, durations in
            guard !durations.isEmpty else { return nil }
            let totalSeconds = durations.reduce(0, +)
            let averageSeconds = totalSeconds / Double(durations.count)
            let averageHours = averageSeconds / 3600.0 // Convert to hours
            
            return StatusTime(status: status.capitalized, averageHours: averageHours)
        }.sorted { $0.averageHours > $1.averageHours }
    }
}

// MARK: - Supporting Structs

struct PhotographerLeftJobTime: Identifiable {
    let id = UUID()
    let photographerName: String
    let averageHours: Double
    let totalHours: Double
    let transitionCount: Int
    let currentBoxes: Int
    
    var formattedAverageTime: String {
        if averageHours < 24 {
            return String(format: "%.1f hours", averageHours)
        } else {
            let days = averageHours / 24
            return String(format: "%.1f days", days)
        }
    }
}

// MARK: - PhotographerJobBoxMetrics View

struct PhotographerJobBoxMetrics: View {
    let photographerLeftJobTimes: [PhotographerLeftJobTime]
    
    var body: some View {
        ZStack {
            // Background Card
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.secondarySystemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 12) {
                if photographerLeftJobTimes.isEmpty {
                    Text("No 'Left Job' data available")
                        .foregroundColor(.gray)
                        .padding()
                        .frame(maxWidth: .infinity)
                } else {
                    ForEach(photographerLeftJobTimes) { metric in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(metric.photographerName)
                                    .font(.headline)
                                
                                Spacer()
                                
                                if metric.currentBoxes > 0 {
                                    Label("\(metric.currentBoxes)", systemImage: "exclamationmark.triangle.fill")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                            
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Average Time")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Text(metric.formattedAverageTime)
                                        .font(.subheadline)
                                        .bold()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                
                                VStack(alignment: .leading) {
                                    Text("Total Transitions")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                    Text("\(metric.transitionCount)")
                                        .font(.subheadline)
                                        .bold()
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                
                                if metric.currentBoxes > 0 {
                                    VStack(alignment: .leading) {
                                        Text("Currently Left")
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                        Text("\(metric.currentBoxes)")
                                            .font(.subheadline)
                                            .bold()
                                            .foregroundColor(.orange)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            
                            Divider()
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.vertical)
        }
    }
}

// Extension to get the mid-point of a CGRect
extension CGRect {
    var midPoint: CGPoint {
        return CGPoint(x: midX, y: midY)
    }
}

// MARK: - Pie Chart Helpers

extension StatisticsView {
    // Calculate start angle for a pie slice
    func startAngle(for index: Int) -> Angle {
        let data = isJobBoxMode ? jobBoxStatusCounts : statusCounts
        let total = data.reduce(0) { $0 + $1.count }
        var cumulativeCount = 0
        
        for i in 0..<index {
            cumulativeCount += data[i].count
        }
        
        let startPercentage = Double(cumulativeCount) / Double(total)
        return .degrees(startPercentage * 360 - 90) // -90 to start at top
    }
    
    // Calculate end angle for a pie slice
    func endAngle(for index: Int) -> Angle {
        let data = isJobBoxMode ? jobBoxStatusCounts : statusCounts
        let total = data.reduce(0) { $0 + $1.count }
        var cumulativeCount = 0
        
        for i in 0...index {
            cumulativeCount += data[i].count
        }
        
        let endPercentage = Double(cumulativeCount) / Double(total)
        return .degrees(endPercentage * 360 - 90) // -90 to start at top
    }
    
    // Calculate label position for pie slice
    func labelPosition(for index: Int, in size: CGSize) -> CGPoint {
        let data = isJobBoxMode ? jobBoxStatusCounts : statusCounts
        let startAngle = self.startAngle(for: index)
        let endAngle = self.endAngle(for: index)
        let midAngle = (startAngle.degrees + endAngle.degrees) / 2
        let radius = min(size.width, size.height) / 2 * 0.75 // Position at 75% of radius
        
        let x = size.width / 2 + radius * cos(midAngle * .pi / 180)
        let y = size.height / 2 + radius * sin(midAngle * .pi / 180)
        
        return CGPoint(x: x, y: y)
    }
    
    // MARK: - Pie Chart Helper Methods
    
    func createPieChartSlices(from data: [StatusCount], total: Int) -> [PieChartSlice] {
        var slices: [PieChartSlice] = []
        var currentAngle = Angle(degrees: -90) // Start at top
        
        for item in data {
            let percentage = Int((Double(item.count) / Double(total)) * 100)
            let sweepAngle = Angle(degrees: (Double(item.count) / Double(total)) * 360)
            let endAngle = currentAngle + sweepAngle
            
            slices.append(PieChartSlice(
                status: item.status,
                startAngle: currentAngle,
                endAngle: endAngle,
                percentage: percentage
            ))
            
            currentAngle = endAngle
        }
        
        return slices
    }
}

// MARK: - Pie Chart Helpers

struct PieChartSlice {
    let status: String
    let startAngle: Angle
    let endAngle: Angle
    let percentage: Int
}

// MARK: - Pie Slice Shape

struct PieSlice: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let innerRadiusRatio: CGFloat
    
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let innerRadius = radius * innerRadiusRatio
        
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        path.addArc(center: center, radius: innerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: true)
        path.closeSubpath()
        
        return path
    }
}