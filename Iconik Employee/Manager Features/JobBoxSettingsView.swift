import SwiftUI
import Firebase
import FirebaseFirestore

// Model for job box stalled timings
struct JobBoxStalledTimings {
    var packed: Double      // Hours
    var pickedUp: Double    // Hours
    var leftJob: Double     // Hours
    
    // Default values
    static let defaultTimings = JobBoxStalledTimings(
        packed: 48.0,       // 2 days
        pickedUp: 96.0,     // 4 days
        leftJob: 192.0      // 8 days
    )
}

// Manager for job box settings
class JobBoxSettingsManager: ObservableObject {
    static let shared = JobBoxSettingsManager()
    
    @Published var stalledTimings: JobBoxStalledTimings
    
    // Keys for UserDefaults
    private let packedTimeKey = "jobbox_packed_stalled_hours"
    private let pickedUpTimeKey = "jobbox_pickedup_stalled_hours"
    private let leftJobTimeKey = "jobbox_leftjob_stalled_hours"
    
    init() {
        // Load settings from UserDefaults
        let userDefaults = UserDefaults.standard
        
        let packedTime = userDefaults.double(forKey: packedTimeKey)
        let pickedUpTime = userDefaults.double(forKey: pickedUpTimeKey)
        let leftJobTime = userDefaults.double(forKey: leftJobTimeKey)
        
        // Use default values if settings haven't been saved yet
        if packedTime == 0 && pickedUpTime == 0 && leftJobTime == 0 {
            stalledTimings = JobBoxStalledTimings.defaultTimings
            // Save default values
            saveSettings()
        } else {
            stalledTimings = JobBoxStalledTimings(
                packed: packedTime,
                pickedUp: pickedUpTime,
                leftJob: leftJobTime
            )
        }
    }
    
    // Save settings to UserDefaults
    func saveSettings() {
        let userDefaults = UserDefaults.standard
        userDefaults.set(stalledTimings.packed, forKey: packedTimeKey)
        userDefaults.set(stalledTimings.pickedUp, forKey: pickedUpTimeKey)
        userDefaults.set(stalledTimings.leftJob, forKey: leftJobTimeKey)
    }
    
    // Get stalled threshold for a particular status
    func getStalledThreshold(for status: JobBoxStatus) -> TimeInterval {
        switch status {
        case .packed:
            return stalledTimings.packed * 3600 // Convert hours to seconds
        case .pickedUp:
            return stalledTimings.pickedUp * 3600
        case .leftJob:
            return stalledTimings.leftJob * 3600
        case .turnedIn:
            return .infinity // Never stall for turned in
        case .unknown:
            return 3 * 3600 // Default 3 hours for unknown
        }
    }
    
    // Reset settings to default values
    func resetToDefaults() {
        stalledTimings = JobBoxStalledTimings.defaultTimings
        saveSettings()
    }
}

// Settings view for job box tracking
struct JobBoxSettingsView: View {
    @ObservedObject private var settingsManager = JobBoxSettingsManager.shared
    
    // Temporary values for the sliders
    @State private var packedHours: Double
    @State private var pickedUpHours: Double
    @State private var leftJobHours: Double
    
    // Show confirmation for reset
    @State private var showingResetConfirmation = false
    
    init() {
        // Initialize state variables with current settings
        self._packedHours = State(initialValue: JobBoxSettingsManager.shared.stalledTimings.packed)
        self._pickedUpHours = State(initialValue: JobBoxSettingsManager.shared.stalledTimings.pickedUp)
        self._leftJobHours = State(initialValue: JobBoxSettingsManager.shared.stalledTimings.leftJob)
    }
    
    var body: some View {
        Form {
            Section(header: Text("Stalled Time Thresholds").font(.headline)) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Packed Status")
                        .font(.subheadline)
                    
                    HStack {
                        Slider(value: $packedHours, in: 24...240, step: 24)
                            .onChange(of: packedHours) { _ in
                                updateSettings()
                            }
                        
                        Text("\(Int(packedHours/24)) days")
                            .frame(width: 60)
                    }
                    
                    Text("Job boxes in 'Packed' status will be marked as stalled after this time.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Picked Up Status")
                        .font(.subheadline)
                    
                    HStack {
                        Slider(value: $pickedUpHours, in: 24...240, step: 24)
                            .onChange(of: pickedUpHours) { _ in
                                updateSettings()
                            }
                        
                        Text("\(Int(pickedUpHours/24)) days")
                            .frame(width: 60)
                    }
                    
                    Text("Job boxes in 'Picked Up' status will be marked as stalled after this time.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Left Job Status")
                        .font(.subheadline)
                    
                    HStack {
                        Slider(value: $leftJobHours, in: 0.5...48, step: 0.5)
                            .onChange(of: leftJobHours) { _ in
                                updateSettings()
                            }
                        
                        Text("\(leftJobHours, specifier: "%.1f") hrs")
                            .frame(width: 60)
                    }
                    
                    Text("Job boxes in 'Left Job' status will be marked as stalled after this time.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }
            
            Section {
                Button(action: {
                    showingResetConfirmation = true
                }) {
                    HStack {
                        Spacer()
                        Text("Reset to Default Values")
                            .foregroundColor(.red)
                        Spacer()
                    }
                }
                .alert(isPresented: $showingResetConfirmation) {
                    Alert(
                        title: Text("Reset Settings"),
                        message: Text("Are you sure you want to reset all stalled time thresholds to default values?"),
                        primaryButton: .destructive(Text("Reset")) {
                            resetToDefaults()
                        },
                        secondaryButton: .cancel()
                    )
                }
            }
        }
        .navigationTitle("Job Box Settings")
    }
    
    // Update settings in the manager
    private func updateSettings() {
        settingsManager.stalledTimings = JobBoxStalledTimings(
            packed: packedHours,
            pickedUp: pickedUpHours,
            leftJob: leftJobHours
        )
        settingsManager.saveSettings()
    }
    
    // Reset to default values
    private func resetToDefaults() {
        settingsManager.resetToDefaults()
        
        // Update local state variables
        packedHours = settingsManager.stalledTimings.packed
        pickedUpHours = settingsManager.stalledTimings.pickedUp
        leftJobHours = settingsManager.stalledTimings.leftJob
    }
}

struct JobBoxSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            JobBoxSettingsView()
        }
    }
}
