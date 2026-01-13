import Foundation
import Supabase

/// Manages Captura API credentials from multiple sources
class CapturaAPIKeyManager {
    static let shared = CapturaAPIKeyManager()

    private let supabase = SupabaseManager.shared.client

    // Keys for storing credentials
    private enum Keys {
        static let clientID = "CAPTURA_CLIENT_ID"
        static let clientSecret = "CAPTURA_CLIENT_SECRET"
        static let accountID = "CAPTURA_ACCOUNT_ID"
        static let googleClientID = "CAPTURA_GOOGLE_CLIENT_ID"
    }

    // Cached credentials
    private var cachedCredentials: CapturaCredentials?

    private init() {}

    /// Represents Captura API credentials
    struct CapturaCredentials {
        let clientID: String
        let clientSecret: String
        let accountID: String
        let googleClientID: String

        var isValid: Bool {
            !clientID.isEmpty && !clientSecret.isEmpty && !accountID.isEmpty && !googleClientID.isEmpty
        }
    }

    /// Fetches Captura credentials from available sources
    /// Priority: Info.plist > UserDefaults/Keychain > Environment > Supabase
    func getCredentials(completion: @escaping (Result<CapturaCredentials, Error>) -> Void) {
        // Check cached credentials first
        if let cached = cachedCredentials, cached.isValid {
            completion(.success(cached))
            return
        }

        // Try Info.plist first (from xcconfig)
        if let credentials = getCredentialsFromInfoPlist(), credentials.isValid {
            cachedCredentials = credentials
            completion(.success(credentials))
            return
        }

        // Try UserDefaults/Keychain
        if let credentials = getCredentialsFromUserDefaults(), credentials.isValid {
            cachedCredentials = credentials
            completion(.success(credentials))
            return
        }

        // Try Environment variables
        if let credentials = getCredentialsFromEnvironment(), credentials.isValid {
            cachedCredentials = credentials
            completion(.success(credentials))
            return
        }

        // Try Supabase
        fetchCredentialsFromSupabase { [weak self] credentials in
            if let credentials = credentials, credentials.isValid {
                self?.cachedCredentials = credentials
                completion(.success(credentials))
            } else {
                completion(.failure(CapturaCredentialsError.noCredentialsFound))
            }
        }
    }

    /// Get credentials from Info.plist (configured via xcconfig)
    private func getCredentialsFromInfoPlist() -> CapturaCredentials? {
        guard let clientID = Bundle.main.object(forInfoDictionaryKey: Keys.clientID) as? String,
              let clientSecret = Bundle.main.object(forInfoDictionaryKey: Keys.clientSecret) as? String,
              let accountID = Bundle.main.object(forInfoDictionaryKey: Keys.accountID) as? String,
              let googleClientID = Bundle.main.object(forInfoDictionaryKey: Keys.googleClientID) as? String else {
            return nil
        }

        return CapturaCredentials(
            clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines),
            clientSecret: clientSecret.trimmingCharacters(in: .whitespacesAndNewlines),
            accountID: accountID.trimmingCharacters(in: .whitespacesAndNewlines),
            googleClientID: googleClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Get credentials from UserDefaults (non-secrets) and Keychain (secrets)
    private func getCredentialsFromUserDefaults() -> CapturaCredentials? {
        let defaults = UserDefaults.standard

        // Non-sensitive values from UserDefaults
        guard let clientID = defaults.string(forKey: Keys.clientID),
              let accountID = defaults.string(forKey: Keys.accountID),
              let googleClientID = defaults.string(forKey: Keys.googleClientID) else {
            return nil
        }

        // Sensitive client secret from Keychain
        guard let clientSecret = KeychainService.shared.get(.capturaClientSecret) else {
            return nil
        }

        return CapturaCredentials(
            clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines),
            clientSecret: clientSecret.trimmingCharacters(in: .whitespacesAndNewlines),
            accountID: accountID.trimmingCharacters(in: .whitespacesAndNewlines),
            googleClientID: googleClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Get credentials from environment variables
    private func getCredentialsFromEnvironment() -> CapturaCredentials? {
        let env = ProcessInfo.processInfo.environment

        guard let clientID = env[Keys.clientID],
              let clientSecret = env[Keys.clientSecret],
              let accountID = env[Keys.accountID],
              let googleClientID = env[Keys.googleClientID] else {
            return nil
        }

        return CapturaCredentials(
            clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines),
            clientSecret: clientSecret.trimmingCharacters(in: .whitespacesAndNewlines),
            accountID: accountID.trimmingCharacters(in: .whitespacesAndNewlines),
            googleClientID: googleClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Fetch credentials from Supabase organization settings
    private func fetchCredentialsFromSupabase(completion: @escaping (CapturaCredentials?) -> Void) {
        guard let orgID = UserDefaults.standard.string(forKey: "userOrganizationID"),
              !orgID.isEmpty else {
            completion(nil)
            return
        }

        Task {
            do {
                struct CapturaConfig: Decodable {
                    let client_id: String?
                    let client_secret: String?
                    let account_id: String?
                    let google_client_id: String?

                    // Legacy camelCase support
                    let clientID: String?
                    let clientSecret: String?
                    let accountID: String?
                    let googleClientID: String?
                }

                struct OrgWithCaptura: Decodable {
                    let captura_config: CapturaConfig?
                }

                let result: OrgWithCaptura = try await supabase
                    .from("organizations")
                    .select("captura_config")
                    .eq("id", value: orgID.lowercased())
                    .single()
                    .execute()
                    .value

                if let config = result.captura_config {
                    let clientID = config.client_id ?? config.clientID ?? ""
                    let clientSecret = config.client_secret ?? config.clientSecret ?? ""
                    let accountID = config.account_id ?? config.accountID ?? ""
                    let googleClientID = config.google_client_id ?? config.googleClientID ?? ""

                    let credentials = CapturaCredentials(
                        clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines),
                        clientSecret: clientSecret.trimmingCharacters(in: .whitespacesAndNewlines),
                        accountID: accountID.trimmingCharacters(in: .whitespacesAndNewlines),
                        googleClientID: googleClientID.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    completion(credentials)
                } else {
                    completion(nil)
                }
            } catch {
                completion(nil)
            }
        }
    }

    /// Save credentials to UserDefaults (non-secrets) and Keychain (secrets)
    func saveCredentialsToUserDefaults(_ credentials: CapturaCredentials) {
        let defaults = UserDefaults.standard

        // Non-sensitive values to UserDefaults
        defaults.set(credentials.clientID, forKey: Keys.clientID)
        defaults.set(credentials.accountID, forKey: Keys.accountID)
        defaults.set(credentials.googleClientID, forKey: Keys.googleClientID)

        // Sensitive client secret to Keychain
        _ = KeychainService.shared.save(credentials.clientSecret, for: .capturaClientSecret)

        // Remove any legacy client secret from UserDefaults for security
        defaults.removeObject(forKey: Keys.clientSecret)

        // Update cache
        cachedCredentials = credentials
    }

    /// Clear cached credentials
    func clearCache() {
        cachedCredentials = nil
    }
}

/// Errors related to Captura credentials
enum CapturaCredentialsError: LocalizedError {
    case noCredentialsFound
    case invalidCredentials

    var errorDescription: String? {
        switch self {
        case .noCredentialsFound:
            return "No Captura API credentials found. Please configure them in Settings."
        case .invalidCredentials:
            return "Invalid Captura API credentials. Please check your configuration."
        }
    }
}
