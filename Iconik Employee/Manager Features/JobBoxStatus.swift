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
    /// The scan moment, from the live table's `timestamp` column.
    ///
    /// This used to be `updated_at` — a column that DOES NOT EXIST on job_boxes. Because
    /// it decoded as an optional it never errored; it was just nil on every row, and
    /// `timestampDate` substituted "now" for every scan — so sorting for "the latest
    /// scan" compared rows whose keys were all the moment of comparison, and the shift
    /// detail's progression bar showed an effectively RANDOM one of the shift's scans.
    /// The PSH.1 defect class (code that looks right reading a column that isn't there),
    /// found live 2026-07-29 after the operator reported the progression not moving.
    let timestamp: Date?

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

    /// distantPast, not Date(): an undated row must LOSE to every dated row when picking
    /// the latest scan — substituting "now" is what made the winner random.
    var timestampDate: Date {
        timestamp ?? .distantPast
    }

    enum CodingKeys: String, CodingKey {
        case id
        case shift_uid
        case status
        case photographer
        case timestamp
        case box_number
        case organization_id
        case school
        case school_id
        case user_id
    }
}

// Decodable lives in an extension so the memberwise initializer survives (the manager
// tracker constructs JobBox by hand).
extension JobBox {
    // Shared, not per-row (review round): ISO8601DateFormatter is documented-expensive
    // to create, and the manager tracker decodes 1000+ rows per load — the string-parse
    // fallback was constructing one (sometimes two) formatters per row.
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// The `timestamp` column is timestamptz and arrives as an ISO8601 string that may
    /// or may not carry fractional seconds (both exist live). A decode that only handles
    /// one form throws, and a thrown decode empties the WHOLE fetch — the failure would
    /// present as "no job boxes", the empty-state class this project keeps paying for.
    /// Same tolerant pattern as Session.created_at.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        // Tolerant of NULLs by necessity, not style: live 2026-07-29, 316 of 1055 rows
        // have NULL shift_uid and 334 NULL photographer. One strict field would throw on
        // the first such row and empty the manager tracker's org-wide fetch.
        shift_uid = try c.decodeIfPresent(String.self, forKey: .shift_uid) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "Unknown"
        photographer = try c.decodeIfPresent(String.self, forKey: .photographer) ?? ""
        box_number = try c.decodeIfPresent(String.self, forKey: .box_number)
        organization_id = try c.decodeIfPresent(String.self, forKey: .organization_id) ?? ""
        school = try c.decodeIfPresent(String.self, forKey: .school)
        school_id = try c.decodeIfPresent(String.self, forKey: .school_id)
        user_id = try c.decodeIfPresent(String.self, forKey: .user_id)

        if let date = try? c.decode(Date.self, forKey: .timestamp) {
            timestamp = date
        } else if let string = try? c.decode(String.self, forKey: .timestamp) {
            timestamp = Self.isoFractional.date(from: string) ?? Self.isoPlain.date(from: string)
        } else {
            timestamp = nil
        }
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
    // device token into a `users.fcm_token` column that DOES NOT EXIST on the live database,
    // so it errored into a swallowed print on every single launch. It was also not
    // job-box-specific in any way: it duplicated PushNotificationManager's own token write.
    // (PSH.2, 2026-07-29: the orphaned fcm_token_updated_at companion column was dropped
    // too.) Token storage now lives in exactly one place —
    // PushNotificationManager.saveAPNsTokenToSupabase, writing user_devices.

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
