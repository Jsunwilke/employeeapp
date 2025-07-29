import SwiftUI
import FirebaseAuth

struct PTOBalanceView: View {
    @StateObject private var ptoService = PTOService.shared
    @State private var ptoBalance: PTOBalance?
    @State private var ptoSettings: PTOSettings?
    @State private var isLoading = true
    @State private var errorMessage = ""
    @State private var projectedDate = Date().addingTimeInterval(30 * 24 * 60 * 60) // 30 days from now
    @State private var projectedBalance = 0.0
    
    private var userId: String? {
        Auth.auth().currentUser?.uid
    }
    
    private var organizationId: String? {
        UserDefaults.standard.string(forKey: "userOrganizationID")
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if isLoading {
                    ProgressView("Loading PTO information...")
                        .padding(.top, 50)
                } else if !errorMessage.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(errorMessage)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                        Button("Retry") {
                            loadPTOData()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 50)
                } else {
                    // Current Balance Card
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Current Balance", systemImage: "clock.fill")
                            .font(.headline)
                        
                        if let balance = ptoBalance {
                            HStack {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("\(Int(balance.availableBalance))")
                                        .font(.system(size: 36, weight: .bold))
                                    Text("hours available")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            
                            Divider()
                            
                            // Balance breakdown
                            VStack(spacing: 12) {
                                BalanceRow(label: "Total Balance", value: balance.totalBalance)
                                if balance.pendingBalance > 0 {
                                    BalanceRow(label: "Pending Requests", value: -balance.pendingBalance, color: .orange)
                                }
                                BalanceRow(label: "Available to Use", value: balance.availableBalance, color: .green)
                            }
                            
                            if balance.bankingBalance > 0 {
                                Divider()
                                BalanceRow(label: "Banking Balance", value: balance.bankingBalance, color: .blue)
                                    .font(.caption)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // Year-to-Date Summary
                    if let balance = ptoBalance {
                        VStack(alignment: .leading, spacing: 16) {
                            Label("Year-to-Date", systemImage: "calendar")
                                .font(.headline)
                            
                            VStack(spacing: 12) {
                                SummaryRow(label: "Used This Year", value: "\(Int(balance.usedThisYear)) hours")
                                SummaryRow(label: "Total Accrued", value: "\(Int(balance.totalAccrued)) hours")
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    
                    // Accrual Information
                    if let settings = ptoSettings, settings.enabled {
                        VStack(alignment: .leading, spacing: 16) {
                            Label("Accrual Policy", systemImage: "chart.line.uptrend.xyaxis")
                                .font(.headline)
                            
                            VStack(spacing: 12) {
                                SummaryRow(label: "Accrual Rate", value: settings.formattedAccrualRate)
                                SummaryRow(label: "Maximum Balance", value: settings.formattedMaxAccrual)
                                SummaryRow(label: "Rollover Policy", value: settings.formattedRolloverPolicy)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    
                    // Future Balance Calculator
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Balance Projection", systemImage: "calendar.badge.plus")
                            .font(.headline)
                        
                        DatePicker("Calculate balance for:", selection: $projectedDate, in: Date()..., displayedComponents: .date)
                            .onChange(of: projectedDate) { _ in
                                calculateProjectedBalance()
                            }
                        
                        if projectedBalance > 0 {
                            HStack {
                                Text("Projected Balance:")
                                Spacer()
                                Text("\(Int(projectedBalance)) hours")
                                    .fontWeight(.semibold)
                                    .foregroundColor(.blue)
                            }
                            .padding(.top, 8)
                            
                            if let balance = ptoBalance, projectedBalance > balance.availableBalance {
                                Text("You will accrue \(Int(projectedBalance - balance.availableBalance)) more hours by this date")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
            }
            .padding()
        }
        .navigationTitle("PTO Balance")
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            loadPTOData()
        }
    }
    
    // MARK: - Helper Views
    
    struct BalanceRow: View {
        let label: String
        let value: Double
        var color: Color = .primary
        
        var body: some View {
            HStack {
                Text(label)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(value < 0 ? "" : "+")\(Int(abs(value)))")
                    .fontWeight(.medium)
                    .foregroundColor(color)
            }
        }
    }
    
    struct SummaryRow: View {
        let label: String
        let value: String
        
        var body: some View {
            HStack {
                Text(label)
                    .foregroundColor(.secondary)
                Spacer()
                Text(value)
                    .fontWeight(.medium)
            }
        }
    }
    
    // MARK: - Data Loading
    
    private func loadPTOData() {
        guard let userId = userId,
              let orgId = organizationId else {
            errorMessage = "Unable to load user information"
            isLoading = false
            return
        }
        
        isLoading = true
        errorMessage = ""
        
        // Load PTO balance
        ptoService.getPTOBalance(userId: userId, organizationID: orgId) { balance in
            DispatchQueue.main.async {
                self.ptoBalance = balance
                self.calculateProjectedBalance()
                
                // Load settings after balance
                self.ptoService.getPTOSettings(organizationID: orgId) { settings in
                    DispatchQueue.main.async {
                        self.ptoSettings = settings
                        self.isLoading = false
                    }
                }
            }
        }
    }
    
    private func calculateProjectedBalance() {
        guard let balance = ptoBalance,
              let settings = ptoSettings else { return }
        
        projectedBalance = ptoService.calculateProjectedBalance(
            currentBalance: balance,
            settings: settings,
            targetDate: projectedDate
        )
    }
}


struct PTOBalanceView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PTOBalanceView()
        }
    }
}