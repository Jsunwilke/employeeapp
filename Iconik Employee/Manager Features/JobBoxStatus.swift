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

        // Normalize school name: lowercase and replace spaces with underscores
        let normalizedSchool = schoolName.lowercased().replacingOccurrences(of: " ", with: "_")

        // Create the custom UID
        let shiftUid = "shift_\(normalizedSchool)_\(dateString)"

        return shiftUid
    }
    
    // Listen for job box updates for a specific shift
    func listenForJobBoxes(forShift event: ICSEvent, organizationID: String, completion: @escaping ([JobBox]) -> Void) -> ListenerRegistrationWrapper {
        // Use the event ID (which is the session ID) as the shiftUid
        let shiftUid = event.id

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

                await MainActor.run {
                    completion(jobBoxes)
                }
            } catch {
                print("Error fetching job boxes: \(error.localizedDescription)")
                await MainActor.run {
                    completion([])
                }
            }
        }

        // Set up realtime subscription using realtimeV2
        let channelKey = "jobbox_\(shiftUid)_\(organizationID)"
        let channel = supabase.realtimeV2.channel(channelKey)

        let changeStream = channel.postgresChange(
            AnyAction.self,
            schema: "public",
            table: "job_boxes",
            filter: "shift_uid=eq.\(shiftUid)"
        )

        Task {
            for await _ in changeStream {
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
                    print("Error re-fetching job boxes: \(error.localizedDescription)")
                }
            }
        }

        Task {
            await channel.subscribe()
        }

        activeChannels[channelKey] = channel

        return ListenerRegistrationWrapper {
            Task {
                await channel.unsubscribe()
                self.activeChannels.removeValue(forKey: channelKey)
            }
        }
    }
    
    // Process a job box notification payload
    func processJobBoxNotification(userInfo: [AnyHashable: Any]) -> (status: JobBoxStatus, scannedBy: String)? {
        guard let statusString = userInfo["status"] as? String,
              let scannedBy = userInfo["photographer"] as? String else {
            return nil
        }

        let status = JobBoxStatus(rawValue: statusString) ?? .unknown
        return (status: status, scannedBy: scannedBy)
    }
    
    // NOTE (PSH.1, 2026-07-27): registerDeviceToken was deleted here. It wrote the raw APNs
    // device token into a `users.fcm_token` column that DOES NOT EXIST on the live database
    // (verified — only the orphaned `fcm_token_updated_at` remains), so it errored into a
    // swallowed print on every single launch. It was also not job-box-specific in any way:
    // it duplicated PushNotificationManager's own token write. Token storage now lives in
    // exactly one place, PushNotificationManager.saveAPNsTokenToSupabase.

    // Query all job boxes (for debugging purposes)
    func debugQueryAllJobBoxes(completion: @escaping ([JobBox]) -> Void) {
        Task {
            do {
                let jobBoxes: [JobBox] = try await supabase
                    .from("job_boxes")
                    .select()
                    .limit(20)
                    .execute()
                    .value

                await MainActor.run {
                    completion(jobBoxes)
                }
            } catch {
                await MainActor.run {
                    completion([])
                }
            }
        }
    }

    // Query job boxes using partial matching (for debugging purposes)
    func debugQueryJobBoxesByPartialShiftID(partialID: String, completion: @escaping ([JobBox]) -> Void) {
        Task {
            do {
                let jobBoxes: [JobBox] = try await supabase
                    .from("job_boxes")
                    .select()
                    .like("shift_uid", pattern: "\(partialID)%")
                    .limit(20)
                    .execute()
                    .value

                await MainActor.run {
                    completion(jobBoxes)
                }
            } catch {
                await MainActor.run {
                    completion([])
                }
            }
        }
    }
}
