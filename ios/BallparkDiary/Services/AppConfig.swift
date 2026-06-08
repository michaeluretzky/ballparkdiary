import Foundation

/// App-wide configuration. The Google OAuth iOS client id is read from the
/// app's Info.plist (`GIDClientID`). When it's absent — e.g. in the cloud
/// preview simulator before a client id has been configured — the app falls
/// back to a clearly-labelled demo scan so the experience is still explorable.
enum AppConfig {
    /// The Google OAuth *iOS* client id, e.g. `1234-abc.apps.googleusercontent.com`.
    /// Configured via `INFOPLIST_KEY_GIDClientID` in the Xcode project.
    static var googleClientID: String? {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
            !value.isEmpty,
            value.hasSuffix("apps.googleusercontent.com")
        else { return nil }
        return value
    }

    /// Whether real Gmail scanning is available on this build.
    static var gmailScanningEnabled: Bool { googleClientID != nil }
}
