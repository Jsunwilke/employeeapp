import Foundation
import Supabase

/// Arguments for the flag_user / unflag_user database functions (FLG.2).
private struct FlagUserArgs: Encodable {
    let p_user_id: String
    let p_note: String
}

private struct UnflagUserArgs: Encodable {
    let p_user_id: String
}

@MainActor
class TeamService: ObservableObject {
    static let shared = TeamService()
    private let supabase = SupabaseManager.shared.client

    @Published var teamMembers: [TeamMember] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private init() {}

    // MARK: - Decoder Error Helper
    private func describeDecodingError(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return error.localizedDescription
        }
        switch decodingError {
        case .keyNotFound(let key, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Missing field '\(key.stringValue)' at: \(path.isEmpty ? "root" : path)"
        case .typeMismatch(let type, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Type mismatch for \(type) at: \(path.isEmpty ? "root" : path) - \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Null value for \(type) at: \(path.isEmpty ? "root" : path)"
        case .dataCorrupted(let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "Corrupted data at: \(path.isEmpty ? "root" : path) - \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }
    
    /// The columns TeamMember decodes, MINUS flag_note and flagged_by.
    ///
    /// FLG.1: these selects used to be a bare .select(), i.e. SELECT *. That was harmless
    /// only because flag_note and flagged_by did not exist -- TeamMember has always declared
    /// them, so the moment this phase created the columns, every one of these queries began
    /// shipping a manager's written criticism of an employee to every other employee's
    /// device. getTeamMembers alone is called with NO permission check from TasksViewModel,
    /// TaskDetailView, DailyReportView, CreateSessionView and EditSessionView, and its result
    /// lands in the @Published teamMembers array on this shared singleton.
    ///
    /// BE HONEST ABOUT WHAT THIS IS AND IS NOT. An earlier version of this comment called the
    /// column list "the only control". It is not a security boundary. RLS filters rows, not
    /// columns, and there is no column-level REVOKE on users -- so any signed-in employee can
    /// still request flag_note straight from PostgREST with their own token
    /// (GET /rest/v1/users?select=id,flag_note). What the explicit list does is stop the app
    /// from ROUTINELY shipping the note to every device and parking it in shared observable
    /// state, which is worth doing on its own. Actually restricting access needs either a
    /// column-level grant or the note moved to a manager-gated table, and that is recorded as
    /// a follow-on rather than pretended to be done here.
    ///
    /// is_flagged is kept -- it is a boolean with no content, and callers filter on it. Only
    /// the note and its author are withheld.
    private static let memberColumns = """
        id, organization_id, email, first_name, last_name, photo_url, \
        is_active, role, display_name, created_at, updated_at, is_flagged
        """

    /// The full set, including the note and who wrote it. For the manager-facing
    /// flagged-users list ONLY.
    private static let memberColumnsWithFlagDetail = memberColumns + ", flag_note, flagged_by"

    // MARK: - Get Team Members for Organization
    func getTeamMembers(organizationID: String) async throws -> [TeamMember] {
        do {
            // Query users from Supabase (Codable handles snake_case automatically)
            let members: [TeamMember] = try await supabase
                .from("users")
                .select(Self.memberColumns)
                .eq("organization_id", value: organizationID)
                .execute()
                .value

            // Sort by active status first, then by name
            return members.sorted { lhs, rhs in
                if lhs.is_active != rhs.is_active {
                    return lhs.is_active
                }
                return lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
            }
        } catch {
            print("❌ TeamService decode error: \(describeDecodingError(error))")
            throw error
        }
    }
    
    // MARK: - Load Team Members with Loading State
    @MainActor
    func loadTeamMembers(organizationID: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            teamMembers = try await getTeamMembers(organizationID: organizationID)
        } catch {
            errorMessage = error.localizedDescription
            print("Error loading team members: \(error)")
        }
        
        isLoading = false
    }
    
    // MARK: - Get Team Member by ID
    func getTeamMember(userId: String) async throws -> TeamMember? {
        // Query single user from Supabase by ID
        let members: [TeamMember] = try await supabase
            .from("users")
            .select(Self.memberColumns)
            .eq("id", value: userId)
            .limit(1)
            .execute()
            .value

        return members.first
    }
    
    // MARK: - Get Photographers Only
    func getPhotographers(organizationID: String) async throws -> [TeamMember] {
        let allMembers = try await getTeamMembers(organizationID: organizationID)

        // In many organizations, all team members can be assigned as photographers
        // You can filter by role if needed
        return allMembers.filter { $0.isActive }
    }

    // MARK: - Get Flagged Users
    /// The ONE caller that legitimately needs the note and its author: UnflagUserView, which
    /// is manager-gated and shows the note so a manager can decide whether to clear it.
    func getFlaggedUsers(organizationID: String) async throws -> [TeamMember] {
        let members: [TeamMember] = try await supabase
            .from("users")
            .select(Self.memberColumnsWithFlagDetail)
            .eq("organization_id", value: organizationID)
            .eq("is_flagged", value: true)
            .execute()
            .value

        return members.sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
    }

    // MARK: - Flag User (Admin Only)
    /// NOTE (FLG.1, 2026-07-27): flag_note and flagged_by did not exist on public.users
    /// until this fix added them, so this UPDATE failed as a unit -- PostgREST rejects the
    /// whole statement on the unknown column names, meaning is_flagged was not set either.
    /// Flagging a user had never once worked, on any build, for anyone. The column names
    /// were kept rather than renamed: the users table is shared, and the web app has no
    /// user-flagging feature at all (checked 2026-07-27 -- every "flag" in its src is an
    /// unrelated boolean), so there was no other vocabulary to match.
    /// See 20260727_flg1_user_flag_columns.sql.
    ///
    /// FLG.2: goes through the flag_user database function, NOT a direct table write.
    ///
    /// The direct .update() this replaces could only ever work for an org ADMIN. RLS policy
    /// users_update_org is (id = auth.uid()::text OR is_admin_of_org(organization_id)), so a
    /// manager -- who holds the in-app users-edit permission this screen gates on -- matched
    /// zero rows, and a PostgREST UPDATE matching zero rows returns 200. The operator asked
    /// for managers to be able to flag (2026-07-28).
    ///
    /// The alternative was widening users_update_org to include users-edit, which was
    /// rejected: that policy governs the WHOLE ROW, so it would also have let every manager
    /// rewrite any colleague's email, home address and apns_token. The function grants
    /// exactly this one capability and checks permission, organization and self internally --
    /// see 20260728_flg2_flag_user_rpc.sql.
    ///
    /// No zero-row check is needed here any more: the function raises on every failure
    /// (including a row count other than 1), so anything short of success arrives as a thrown
    /// error carrying a sentence the manager can read.
    ///
    /// `flaggedBy` is no longer passed -- the function records auth.uid() itself, which is the
    /// only value that cannot be spoofed by the caller.
    func flagUser(userId: String, note: String) async throws {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            try await supabase
                .rpc("flag_user", params: FlagUserArgs(p_user_id: userId, p_note: note))
                .execute()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    // MARK: - Unflag User (admin or users-edit)
    /// FLG.2: same reasoning as flagUser -- through the database function, which raises rather
    /// than silently clearing nothing.
    func unflagUser(userId: String) async throws {
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        do {
            try await supabase
                .rpc("unflag_user", params: UnflagUserArgs(p_user_id: userId))
                .execute()
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
}