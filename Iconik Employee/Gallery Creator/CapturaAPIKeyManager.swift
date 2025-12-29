import Foundation
import Supabase

/// Manages Captura API credentials from multiple sources
class CapturaAPIKeyManager {
    static let shared = CapturaAPIKeyManager()

    private let debugMode = true
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
    /// Priority: Info.plist > UserDefaults > Environment > Supabase
    func getCredentials(completion: @escaping (Result<CapturaCredentials, Error>) -> Void) {
        // Check cached credentials first
        if let cached = cachedCredentials, cached.isValid {
            if debugMode {
                print("📦 CapturaAPIKeyManager: Using cached credentials")
            }
            completion(.success(cached))
            return
        }

        // Try Info.plist first (from xcconfig)
        if let credentials = getCredentialsFromInfoPlist(), credentials.isValid {
            if debugMode {
                print("📦 CapturaAPIKeyManager: Found credentials in Info.plist")
            }
            cachedCredentials = credentials
            completion(.success(credentials))
            return
        }

        // Try UserDefaults
        if let credentials = getCredentialsFromUserDefaults(), credentials.isValid {
            if debugMode {
                print("📦 CapturaAPIKeyManager: Found credentials in UserDefaults")
            }
            cachedCredentials = credentials
            completion(.success(credentials))
            return
        }

        // Try Environment variables
        if let credentials = getCredentialsFromEnvironment(), credentials.isValid {
            if debugMode {
                print("📦 CapturaAPIKeyManager: Found credentials in Environment")
            }
            cachedCredentials = credentials
            completion(.success(credentials))
            return
        }

        // Try Supabase
        fetchCredentialsFromSupabase { [weak self] credentials in
            if let credentials = credentials, credentials.isValid {
                if self?.debugMode == true {
                    print("📦 CapturaAPIKeyManager: Found credentials in Supabase")
                }
                self?.cachedCredentials = credentials
                completion(.success(credentials))
            } else {
                if self?.debugMode == true {
                    print("📦 CapturaAPIKeyManager: No valid credentials found")
                }
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

    /// Get credentials from UserDefaults
    private func getCredentialsFromUserDefaults() -> CapturaCredentials? {
        let defaults = UserDefaults.standard

        guard let clientID = defaults.string(forKey: Keys.clientID),
              let clientSecret = defaults.string(forKey: Keys.clientSecret),
              let accountID = defaults.string(forKey: Keys.accountID),
              let googleClientID = defaults.string(forKey: Keys.googleClientID) else {
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
            if debugMode {
                print("📦 CapturaAPIKeyManager: No organization ID found")
            }
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
                    if self.debugMode {
                        print("📦 CapturaAPIKeyManager: No Captura config found in organization settings")
                    }
                    completion(nil)
                }
            } catch {
                if self.debugMode {
                    print("📦 CapturaAPIKeyManager: Supabase error: \(error.localizedDescription)")
                }
                completion(nil)
            }
        }
    }

    /// Save credentials to UserDefaults
    func saveCredentialsToUserDefaults(_ credentials: CapturaCredentials) {
        let defaults = UserDefaults.standard
        defaults.set(credentials.clientID, forKey: Keys.clientID)
        defaults.set(credentials.clientSecret, forKey: Keys.clientSecret)
        defaults.set(credentials.accountID, forKey: Keys.accountID)
        defaults.set(credentials.googleClientID, forKey: Keys.googleClientID)

        // Update cache
        cachedCredentials = credentials

        if debugMode {
            print("📦 CapturaAPIKeyManager: Saved credentials to UserDefaults")
        }
    }

    /// Clear cached credentials
    func clearCache() {
        cachedCredentials = nil
        if debugMode {
            print("📦 CapturaAPIKeyManager: Cleared credential cache")
        }
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
