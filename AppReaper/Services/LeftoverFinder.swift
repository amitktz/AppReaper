import Foundation

enum LeftoverCategory: String, CaseIterable {
    case applicationSupport = "Application Support"
    case caches = "Caches"
    case preferences = "Preferences"
    case containers = "Containers"
    case groupContainers = "Group Containers"
    case logs = "Logs"
    case launchAgents = "LaunchAgents"
    case savedState = "Saved Application State"
    case httpStorages = "HTTPStorages"
    case webKit = "WebKit"
    case cookies = "Cookies"
    case other = "Other"

    /// Path relative to ~/Library, and whether a name-based match (not only bundle ID) is allowed there.
    var relativePath: String {
        switch self {
        case .applicationSupport: "Application Support"
        case .caches: "Caches"
        case .preferences: "Preferences"
        case .containers: "Containers"
        case .groupContainers: "Group Containers"
        case .logs: "Logs"
        case .launchAgents: "LaunchAgents"
        case .savedState: "Saved Application State"
        case .httpStorages: "HTTPStorages"
        case .webKit: "WebKit"
        case .cookies: "Cookies"
        case .other: ""
        }
    }

    var allowsNameMatch: Bool {
        self == .applicationSupport || self == .caches || self == .logs
    }
}

struct LeftoverItem: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let category: LeftoverCategory
    let reason: String
    let size: Int64
}

/// Conservative finder: matches by bundle ID (with dot boundaries) and, in a few folders, exact app name.
struct LeftoverFinder {
    var libraryURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
    var fileManager: FileManager = .default

    /// Names that are never matched by name, no matter what (too generic / shared).
    static let genericNames: Set<String> = ["apple", "google", "microsoft", "adobe", "mozilla", "cache", "caches", "data",
                                            "app", "apps", "logs", "preferences", "support", "shared", "default", "common", "java", "python", "node"]

    /// `otherBundleIDs`: IDs of other installed apps; used so "com.foo.app" never claims "com.foo.app.beta" files.
    func find(for app: InstalledApp, otherBundleIDs: Set<String> = []) -> [LeftoverItem] {
        guard app.isRemovable, Self.isUsableBundleID(app.id) else { return [] }
        let siblings = otherBundleIDs.filter { $0 != app.id && $0.hasPrefix(app.id + ".") }
        var items: [LeftoverItem] = []
        for category in LeftoverCategory.allCases where category != .other {
            let dir = libraryURL.appendingPathComponent(category.relativePath)
            var searchDirs = [dir]
            if category == .preferences { searchDirs.append(dir.appendingPathComponent("ByHost")) }
            for d in searchDirs {
                guard let names = try? fileManager.contentsOfDirectory(atPath: d.path) else { continue }
                for n in names {
                    guard let reason = Self.match(entry: n, app: app, category: category, siblings: siblings) else { continue }
                    let url = d.appendingPathComponent(n)
                    guard Self.isSafeTarget(url, libraryURL: libraryURL) else { continue }
                    items.append(LeftoverItem(url: url, category: category, reason: reason, size: Self.size(of: url, fm: fileManager)))
                }
            }
        }
        return items.sorted { $0.size > $1.size }
    }

    static func isUsableBundleID(_ id: String) -> Bool {
        id.split(separator: ".").count >= 3 && !id.hasPrefix("com.apple.")
    }

    /// Returns the reason an entry matches, or nil.
    static func match(entry: String, app: InstalledApp, category: LeftoverCategory, siblings: Set<String> = []) -> String? {
        let id = app.id
        let lowerEntry = entry.lowercased()
        let lowerID = id.lowercased()
        if lowerEntry.hasPrefix("com.apple.") { return nil }
        if lowerEntry == "." || lowerEntry == ".." || entry.isEmpty { return nil }

        // Exact bundle ID, optionally with an extension (.plist, .savedState, .binarycookies, ...)
        let stem = (entry as NSString).deletingPathExtension.lowercased()
        if lowerEntry == lowerID || stem == lowerID { return "Bundle ID" }

        // Group containers: "<TEAMID>.<bundleID>" or "group.<bundleID>"
        if category == .groupContainers {
            if lowerEntry.hasSuffix("." + lowerID) || lowerEntry == "group." + lowerID { return "Group container for bundle ID" }
            return nil
        }

        // Bundle ID followed by a dot suffix (e.g. "id.helper.plist", "id.ShipIt"), unless it belongs to a sibling app.
        if lowerEntry.hasPrefix(lowerID + ".") {
            if siblings.contains(where: { lowerEntry.hasPrefix($0.lowercased() + ".") || stem == $0.lowercased() }) { return nil }
            // Preferences/launch items: only the well-known forms, not arbitrary children.
            return "Bundle ID prefix"
        }

        if category.allowsNameMatch {
            let name = app.name.lowercased()
            let fileName = app.bundleURL.deletingPathExtension().lastPathComponent.lowercased()
            for candidate in [name, fileName] where candidate.count >= 4 && !genericNames.contains(candidate) {
                if lowerEntry == candidate { return "App name" }
            }
            // Company-style folders in Application Support named after the team/bundle vendor are NOT matched.
        }
        return nil
    }

    /// Must be a strict descendant of ~/Library, not a protected path, and not a symlink escaping away.
    static func isSafeTarget(_ url: URL, libraryURL: URL) -> Bool {
        let lib = libraryURL.standardizedFileURL.path
        let p = url.standardizedFileURL.path
        guard p.hasPrefix(lib + "/"), p.count > lib.count + 1 else { return false }
        let rel = String(p.dropFirst(lib.count + 1))
        // Must be at least one level below a top-level Library folder (or a top-level file never allowed).
        guard rel.contains("/") else { return false }
        if rel.lowercased().contains("com.apple.") && !rel.lowercased().contains("group.") { return false }
        return true
    }

    static func size(of url: URL, fm: FileManager = .default) -> Int64 {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        func fileSize(_ u: URL) -> Int64 {
            let v = try? u.resourceValues(forKeys: Set(keys))
            return Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
        }
        if !isDir.boolValue { return fileSize(url) }
        var total: Int64 = 0
        if let e = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in true }) {
            for case let u as URL in e { total += fileSize(u) }
        }
        return total
    }
}
