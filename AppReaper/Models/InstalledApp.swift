import Foundation

enum AppSource: Hashable {
    case applications
    case userApplications
    case macAppStore
    case homebrewCask(String)
    case setapp

    var label: String {
        switch self {
        case .applications: "Applications"
        case .userApplications: "User Applications"
        case .macAppStore: "App Store"
        case .homebrewCask: "Homebrew"
        case .setapp: "Setapp"
        }
    }
}

struct InstalledApp: Identifiable, Hashable {
    let id: String // CFBundleIdentifier
    let name: String
    let version: String
    let bundleURL: URL
    let teamIdentifier: String?
    var source: AppSource
}

extension InstalledApp {
    static let selfBundleID = "com.amitkatzav.AppReaper"

    private static let protectedPathPrefixes = [
        "/System/",
        "/Library/Apple",
        "/System/Applications",
        "/System/Library/CoreServices",
    ]

    private static let loginCriticalBundleIDs: Set<String> = [
        "com.apple.loginwindow",
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.systemuiserver",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.WindowManager",
    ]

    /// Bundle-ID prefixes Apple reserves, SIP-protected install locations and login-critical items.
    /// Anything matching these is hard-excluded from removal, never just hidden.
    static func isAppleOwned(bundleID: String, bundleURL: URL) -> Bool {
        let path = bundleURL.standardizedFileURL.path
        return bundleID.hasPrefix("com.apple.")
            || loginCriticalBundleIDs.contains(bundleID)
            || protectedPathPrefixes.contains { path.hasPrefix($0) }
    }

    var isRemovable: Bool {
        !Self.isAppleOwned(bundleID: id, bundleURL: bundleURL) && id != Self.selfBundleID
    }
}
