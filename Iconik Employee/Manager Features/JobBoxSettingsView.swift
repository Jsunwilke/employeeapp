//  JobBoxSettingsView.swift
//  Iconik Employee — the tracker's stalled-time thresholds, converted in AMB.11
//
//  THE DESIGN IS `JobBoxLabSettingsSheet` in `DesignLab/Mockups/JobBoxMockup.swift`,
//  approved at the batch-4 sitting (2026-07-30).
//
//  WHAT THE CONVERSION CHANGED:
//    · IT SAYS THESE SETTINGS ARE DEVICE-LOCAL. They live in `UserDefaults` and are
//      never synced, so two managers on two iPads can see different boxes called
//      stalled from identical data, and nothing said so anywhere.
//    · THE SHEET OWNS ITS OWN NAVIGATION. The caller used to wrap it and supply the
//      "Done" button; one sheet, one title bar.
//    · THE "LEFT JOB" DEFAULT IS 12 HOURS, not 192 (approved). 192 is OUTSIDE its
//      own slider's 0.5…48 range: on first open the slider rendered clamped and the
//      first touch silently rewrote a 192-hour threshold to 48 or less, changing
//      which boxes the tracker called stalled with no confirmation. 12 matches the
//      Job Box Alert's own threshold.
//
//  WHAT IS KEPT ON PURPOSE: every drag tick commits (there is no Save and no
//  Cancel, and Reset is the only undo — that is behaviour, not layout), the
//  `UserDefaults` keys, the "all three are 0" first-run detection, and the
//  `.unknown` status's 3-hour threshold with no control.

import SwiftUI

// Model for job box stalled timings
struct JobBoxStalledTimings {
    var packed: Double      // Hours
    var pickedUp: Double    // Hours
    var leftJob: Double     // Hours

    // Default values
    static let defaultTimings = JobBoxStalledTimings(
        packed: 48.0,       // 2 days
        pickedUp: 96.0,     // 4 days
        // 12 HOURS, not 192 (AMB.11, approved). The old default sat outside this
        // value's own slider range, so the control could not represent it and the
        // first drag destroyed it silently.
        leftJob: 12.0
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

        // Use default values if settings haven't been saved yet.
        // KEPT AS IS: "all three are 0" is the first-run test, and a device that
        // has ever saved these keys keeps its own numbers — including a saved
        // 192-hour leftJob, which the slider will clamp for display exactly as it
        // does today. Only the DEFAULT changed.
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
    @Environment(\.dismiss) private var dismiss

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
        NavigationView {
            ZStack {
                AmbientBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        AmbientNoteCard(
                            title: "These settings live on this device",
                            text: "They are stored on this iPad only and are not shared. Two managers on two devices can see different boxes called stalled from identical data.",
                            accent: .orange, density: .compact)

                        AmbientFormSection(title: "Stalled thresholds", status: "3 rules", statusTint: nil) {
                            VStack(alignment: .leading, spacing: 14) {
                                JobBoxThresholdSlider(
                                    title: "Packed",
                                    value: $packedHours, range: 24...240, step: 24,
                                    readout: "\(Int(packedHours / 24)) days",
                                    tint: JobBoxTripStage.packed.meterTint,
                                    caption: "Job boxes in 'Packed' status will be marked as stalled after this time.")
                                    .onChange(of: packedHours) { _ in updateSettings() }

                                JobBoxThresholdSlider(
                                    title: "Picked up",
                                    value: $pickedUpHours, range: 24...240, step: 24,
                                    readout: "\(Int(pickedUpHours / 24)) days",
                                    tint: JobBoxTripStage.pickedUp.meterTint,
                                    caption: "Job boxes in 'Picked Up' status will be marked as stalled after this time.")
                                    .onChange(of: pickedUpHours) { _ in updateSettings() }

                                JobBoxThresholdSlider(
                                    title: "Left job",
                                    value: $leftJobHours, range: 0.5...48, step: 0.5,
                                    readout: String(format: "%.1f hrs", leftJobHours),
                                    tint: JobBoxTripStage.leftJob.meterTint,
                                    caption: "Job boxes in 'Left Job' status will be marked as stalled after this time.")
                                    .onChange(of: leftJobHours) { _ in updateSettings() }
                            }
                        }

                        Button {
                            showingResetConfirmation = true
                        } label: {
                            Text("Reset to default values")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                // ambient-allow: a destructive control, not a container.
                                .background(Capsule().fill(Color.red.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
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
                    .padding(16)
                }
            }
            .navigationTitle("Job Box Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    // Update settings in the manager — on EVERY drag tick, deliberately unchanged.
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

/// One threshold: a title, its readout in the stage's own colour, the slider, and
/// the sentence that says what the number does. From `JobBoxLabSlider`, plus the
/// caption the shipped screen carried under each control.
private struct JobBoxThresholdSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let readout: String
    let tint: Color
    let caption: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.footnote.weight(.semibold))
                Spacer(minLength: 8)
                Text(readout).font(.footnote.weight(.semibold)).foregroundStyle(tint)
            }
            Slider(value: $value, in: range, step: step)
                .tint(tint)
                .accessibilityLabel("\(title) stalled threshold")
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct JobBoxSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        JobBoxSettingsView()
    }
}
