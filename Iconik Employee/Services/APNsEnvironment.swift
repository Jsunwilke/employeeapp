import Foundation

/// Which of Apple's two push services minted this build's device token.
///
/// Apple runs two entirely separate push services — sandbox and production — and a device
/// token issued by one is rejected by the other with `BadDeviceToken`. Which one a build
/// talks to is fixed at signing time by the `aps-environment` entitlement, NOT by the Swift
/// build configuration: a Release build signed with a development profile is still sandbox.
/// So `#if DEBUG` is the wrong test and would be wrong for exactly the builds that matter.
///
/// PSH.1 (2026-07-27) exists because the server assumed every token was a production one.
/// The server had `APNS_PRODUCTION = true` while the app shipped `aps-environment =
/// development`, so every push was rejected. Apple's own answer, captured from the
/// `session-notification` function log during the investigation:
///
///     error: "BadDeviceToken", statusCode: 400
///
/// The fix is not a flag — one global flag cannot serve a development install and a
/// TestFlight install at the same time. Each token is stored with the environment that
/// minted it, and the sender picks the endpoint per token.
enum APNsEnvironment: String {
    case sandbox
    case production

    /// Resolved from the provisioning profile embedded in the running app bundle.
    ///
    /// How this is determined, and the two facts it rests on:
    ///  1. Development, ad-hoc and enterprise builds embed `embedded.mobileprovision`, whose
    ///     `Entitlements` dictionary carries `aps-environment` (`development` or `production`).
    ///  2. App Store builds do NOT embed that file — the App Store strips it — so its absence
    ///     means an App Store build, which is always production.
    ///
    /// The simulator has no profile and cannot receive remote pushes at all; it is reported
    /// as sandbox so it can never be mistaken for a production device.
    static var current: APNsEnvironment {
        #if targetEnvironment(simulator)
        return .sandbox
        #else
        guard let apsValue = embeddedProfileAPSEnvironment() else {
            // No embedded profile => App Store build.
            return .production
        }
        // Apple writes "development" for sandbox; anything else ("production") is production.
        return apsValue == "development" ? .sandbox : .production
        #endif
    }

    /// Reads `Entitlements.aps-environment` out of the embedded provisioning profile.
    ///
    /// The file is a CMS (PKCS#7) envelope with an XML property list inside it. Rather than
    /// pull in a crypto dependency to unwrap the envelope, the plist is sliced out by its
    /// document markers, which is the conventional approach for this one value.
    ///
    /// ISO Latin-1 is used deliberately: the envelope contains arbitrary binary bytes around
    /// the plist, and Latin-1 is the only encoding that maps every possible byte to a
    /// character without failing, so the decode cannot return nil on the binary padding.
    private static func embeddedProfileAPSEnvironment() -> String? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let envelope = String(data: data, encoding: .isoLatin1),
              let start = envelope.range(of: "<?xml"),
              let end = envelope.range(of: "</plist>")
        else {
            return nil
        }

        let plistText = String(envelope[start.lowerBound..<end.upperBound])

        guard let plistData = plistText.data(using: .isoLatin1),
              let root = try? PropertyListSerialization.propertyList(
                  from: plistData, options: [], format: nil
              ) as? [String: Any],
              let entitlements = root["Entitlements"] as? [String: Any],
              let aps = entitlements["aps-environment"] as? String
        else {
            return nil
        }

        return aps
    }
}
