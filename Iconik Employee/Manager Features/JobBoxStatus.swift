//
//  JobBoxStatus.swift
//  Iconik Employee
//
//  Created by administrator on 5/10/25.
//


import Foundation
import Supabase

// Enum for possible job box status values
enum JobBoxStatus: String {
    case packed = "Packed"
    case pickedUp = "Picked Up"
    case leftJob = "Left Job"
    case turnedIn = "Turned In"
    case unknown = "Unknown"
}

// Model for job box data - Supabase compatible
struct JobBox: Identifiable, Codable {
    let id: String
    let shift_uid: String
    let status: String
    let photographer: String
    let updated_at: Date?

    // New fields from updated schema
    let box_number: String?
    let organization_id: String
    let school: String?
    let school_id: String?
    let user_id: String?

    // Computed properties for backward compatibility
    var shiftUid: String { shift_uid }
    var scannedBy: String { photographer }
    var boxNumber: String { box_number ?? "" }
    var organizationID: String { organization_id }
    var schoolId: String { school_id ?? "" }
    var userId: String { user_id ?? "" }

    var jobBoxStatus: JobBoxStatus {
        JobBoxStatus(rawValue: status) ?? .unknown
    }

    var timestampDate: Date {
        updated_at ?? Date()
    }

    enum CodingKeys: String, CodingKey {
        case id
        case shift_uid
        case status
        case photographer
        case updated_at
        case box_number
        case organization_id
        case school
        case school_id
        case user_id
    }
}

// Service to interact with job box data in Supabase
class JobBoxService {
    // Singleton instance
    static let shared = JobBoxService()

    private var supabase: SupabaseClient { SupabaseManager.shared.client }
    private var activeChannels: [String: RealtimeChannelV2] = [:]

    private init() {}
    
    // Generate a custom shift ID using the same formula as the other app
    static func generateCustomShiftID(schoolName: String, date: Date) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd" // Date only, no time component
        let dateString = dateFormatter.string(from: date)
        
        // DEBUG: Print input parameters
        print("DEBUG-SHIFTUID - Generating shift UID with inputs:")
        print("DEBUG-SHIFTUID - School Name: '\(schoolName)'")
        print("DEBUG-SHIFTUID - Date: \(date)")
        print("DEBUG-SHIFTUID - Formatted Date String: \(dateString)")
        
        // FIXED: Modified normalization to match the other app's format
        // 1. Convert to lowercase
        // 2. Replace spaces with underscores
        // 3. Keep hyphens (do not remove them)
        let normalizedSchool = schoolName.lowercased().replacingOccurrences(of: " ", with: "_")
        print("DEBUG-SHIFTUID - Normalized School Name: '\(normalizedSchool)'")
        
        // FIXED: Create the custom UID with the correct format to match the other app
        // 1. Added underscore after "shift"
        // 2. Added underscore before the date
        let shiftUid = "shift_\(normalizedSchool)_\(dateString)"
        print("DEBUG-SHIFTUID - Generated shift UID: '\(shiftUid)'")
        
        return shiftUid
    }
    
    // Listen for job box updates for a specific shift
    func listenForJobBoxes(forShift event: ICSEvent, organizationID: String, completion: @escaping ([JobBox]) -> Void) -> ListenerRegistrationWrapper {
        print("DEBUG-JOBBOX-LISTEN - ===== LISTENER SETUP START =====")
        print("DEBUG-JOBBOX-LISTEN - Event ID (Session ID): '\(event.id)'")
        print("DEBUG-JOBBOX-LISTEN - School Name: '\(event.schoolName)'")
        print("DEBUG-JOBBOX-LISTEN - Organization ID: '\(organizationID)'")

        // Use the event ID (which is the session ID) as the shiftUid
        let shiftUid = event.id
        print("DEBUG-JOBBOX-LISTEN - Using shiftUid: '\(shiftUid)'")

        // Initial fetch from Supabase
        Task {
            do {
                let jobBoxes: [JobBox] = try await supabase
                    .from("job_boxes")
                    .select()
                    .eq("shift_uid", value: shiftUid)
                    .eq("organization_id", value: organizationID)
                    .execute()
                    .value

                print("DEBUG-JOBBOX-LISTEN - Found \(jobBoxes.count) job box documents")

                await MainActor.run {
                    completion(jobBoxes)
                }
            } catch {
                print("ERROR-JOBBOX-LISTEN - Error fetching job boxes: \(error.localizedDescription)")
                await MainActor.run {
                    completion([])
                }
            }
        }

        // Set up realtime subscription
        let channelKey = "jobbox_\(shiftUid)_\(organizationID)"
        let channel = supabase.channel(channelKey)

        let changeStream = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "job_boxes",
            filter: "shift_uid=eq.\(shiftUid)"
        )

        Task {
            for await change in changeStream {
                print("DEBUG-JOBBOX-LISTEN - Realtime change detected")
                // Re-fetch all job boxes on any change
                do {
                    let jobBoxes: [JobBox] = try await supabase
                        .from("job_boxes")
                        .select()
                        .eq("shift_uid", value: shiftUid)
                        .eq("organization_id", value: organizationID)
                        .execute()
                        .value

                    await MainActor.run {
                        completion(jobBoxes)
                    }
                } catch {
                    print("ERROR-JOBBOX-LISTEN - Error re-fetching job boxes: \(error.localizedDescription)")
                }
            }
        }

        Task {
            await channel.subscribe()
            print("DEBUG-JOBBOX-LISTEN - Subscribed to realtime channel: \(channelKey)")
        }

        activeChannels[channelKey] = channel
        print("DEBUG-JOBBOX-LISTEN - ===== LISTENER SETUP END =====")

        return ListenerRegistrationWrapper {
            Task {
                await channel.unsubscribe()
                self.activeChannels.removeValue(forKey: channelKey)
            }
        }
    }
    
    // Process a job box notification payload
    func processJobBoxNotification(userInfo: [AnyHashable: Any]) -> (status: JobBoxStatus, scannedBy: String)? {
        print("DEBUG-JOBBOX-NOTIFY - Processing notification payload: \(userInfo)")
        
        guard let statusString = userInfo["status"] as? String,
              let scannedBy = userInfo["photographer"] as? String else {  // FIXED: Use photographer field instead of scannedBy
            print("ERROR-JOBBOX-NOTIFY - Missing required fields in notification payload")
            return nil
        }
        
        print("DEBUG-JOBBOX-NOTIFY - Extracted status: '\(statusString)', scannedBy: '\(scannedBy)'")
        
        // Check if shiftUid is present in the notification
        if let notificationShiftUid = userInfo["shiftUid"] as? String {
            print("DEBUG-JOBBOX-NOTIFY - Notification contains shiftUid: '\(notificationShiftUid)'")
        } else {
            print("DEBUG-JOBBOX-NOTIFY - Warning: Notification does not contain shiftUid")
        }
        
        let status = JobBoxStatus(rawValue: statusString) ?? .unknown
        print("DEBUG-JOBBOX-NOTIFY - Final processed status: \(status.rawValue)")
        
        return (status: status, scannedBy: scannedBy)
    }
    
    // Register device token for push notifications
    func registerDeviceToken(_ deviceToken: Data) {
        guard let userId = UserManager.shared.getCurrentUserIDUnified() else {
            print("ERROR-JOBBOX-TOKEN - Cannot register device token: No user is signed in")
            return
        }

        // Convert token to string format
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("DEBUG-JOBBOX-TOKEN - Registering device token for user \(userId): \(tokenString)")

        // Store the token in Supabase
        Task {
            do {
                try await supabase
                    .from("users")
                    .update(["fcm_token": tokenString])
                    .eq("id", value: userId.lowercased())
                    .execute()

                print("DEBUG-JOBBOX-TOKEN - Successfully registered device token for job box notifications")
            } catch {
                print("ERROR-JOBBOX-TOKEN - Error registering device token: \(error.localizedDescription)")
            }
        }
    }
    
    // DEBUG: Query all job boxes to check for any matching records
    func debugQueryAllJobBoxes(completion: @escaping ([JobBox]) -> Void) {
        print("DEBUG-JOBBOX-QUERY - Querying all job boxes in the collection")

        Task {
            do {
                let jobBoxes: [JobBox] = try await supabase
                    .from("job_boxes")
                    .select()
                    .limit(20)
                    .execute()
                    .value

                print("DEBUG-JOBBOX-QUERY - Found \(jobBoxes.count) job box documents in the collection")

                // Print the shiftUid of each document for debugging
                jobBoxes.forEach { jobBox in
                    print("DEBUG-JOBBOX-QUERY - Document ID: \(jobBox.id), shiftUid: '\(jobBox.shiftUid)'")
                }

                await MainActor.run {
                    completion(jobBoxes)
                }
            } catch {
                print("ERROR-JOBBOX-QUERY - Error querying job boxes: \(error.localizedDescription)")
                await MainActor.run {
                    completion([])
                }
            }
        }
    }

    // DEBUG: Query job boxes using partial matching
    func debugQueryJobBoxesByPartialShiftID(partialID: String, completion: @escaping ([JobBox]) -> Void) {
        print("DEBUG-JOBBOX-PARTIAL - Querying job boxes with partial shiftUid: '\(partialID)'")

        Task {
            do {
                let jobBoxes: [JobBox] = try await supabase
                    .from("job_boxes")
                    .select()
                    .like("shift_uid", pattern: "\(partialID)%")
                    .limit(20)
                    .execute()
                    .value

                print("DEBUG-JOBBOX-PARTIAL - Found \(jobBoxes.count) job box documents with partial ID: '\(partialID)'")

                jobBoxes.forEach { jobBox in
                    print("DEBUG-JOBBOX-PARTIAL - Document ID: \(jobBox.id), shiftUid: '\(jobBox.shiftUid)'")
                }

                await MainActor.run {
                    completion(jobBoxes)
                }
            } catch {
                print("ERROR-JOBBOX-PARTIAL - Error querying job boxes: \(error.localizedDescription)")
                await MainActor.run {
                    completion([])
                }
            }
        }
    }
}
