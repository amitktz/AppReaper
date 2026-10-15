import Foundation
import Security

/// Scans application folders and builds `InstalledApp` values.
struct AppDiscoveryService {
    var directories: [URL]
    var homebrewCaskroomDirs: [URL]
    var fileManager: FileManager = .default

    static func defaultDirectories() -> [URL] {
        [URL(fileURLWithPath: "/Applications"),
         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
    }

    init(directories: [URL] = AppDiscoveryService.defaultDirectories(),
         homebrewCaskroomDirs: [URL] = [URL(fileURLWithPath: "/opt/homebrew/Caskroom"),
                                        URL(fileURLWithPath: "/usr/local/Caskroom")]) {
        self.directories = directories
        self.homebrewCaskroomDirs = homebrewCaskroomDirs
    }

    func discover() -> [InstalledApp] {
        let casks = installedCasks()
        var seen = Set<String>()
        var result: [InstalledApp] = []
        for dir in directories {
            for url in appBundles(in: dir) {
                guard let app = makeApp(at: url, root: dir, casks: casks), seen.insert(app.id).inserted else { continue }
                result.append(app)
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Finds .app bundles one level deep, plus one level into plain subfolders (e.g. /Applications/Utilities, Setapp).
    func appBundles(in dir: URL) -> [URL] {
        guard let items = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        var out: [URL] = []
        for item in items {
            if item.pathExtension == "app" { out.append(item) }
            else if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                    let sub = try? fileManager.contentsOfDirectory(at: item, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                out += sub.filter { $0.pathExtension == "app" }
            }
        }
        return out
    }

    func makeApp(at url: URL, root: URL, casks: Set<String> = []) -> InstalledApp? {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
        let info = bundle.infoDictionary ?? [:]
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent
        let version = (info["CFBundleShortVersionString"] as? String) ?? (info["CFBundleVersion"] as? String) ?? ""
        let baseSource: AppSource = root.lastPathComponent == "Applications" && root.deletingLastPathComponent().path != "/" ? .userApplications : .applications
        let source = detectSource(url: url, name: url.deletingPathExtension().lastPathComponent, base: baseSource, casks: casks)
        return InstalledApp(id: id, name: name, version: version, bundleURL: url,
                            teamIdentifier: Self.teamIdentifier(of: url), source: source)
    }

    func detectSource(url: URL, name: String, base: AppSource, casks: Set<String>) -> AppSource {
        if fileManager.fileExists(atPath: url.appendingPathComponent("Contents/_MASReceipt/receipt").path) { return .macAppStore }
        if url.path.contains("/Setapp/") { return .setapp }
        if let cask = Self.matchCask(appName: name, casks: casks) { return .homebrewCask(cask) }
        return base
    }

    /// Names of installed casks (directory names in Caskroom).
    func installedCasks() -> Set<String> {
        var out = Set<String>()
        for dir in homebrewCaskroomDirs {
            for u in (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [] {
                out.insert(u.lastPathComponent)
            }
        }
        return out
    }

    /// Cask tokens are lowercase, hyphenated app names ("Visual Studio Code" -> "visual-studio-code").
    static func matchCask(appName: String, casks: Set<String>) -> String? {
        let token = appName.lowercased().replacingOccurrences(of: " ", with: "-")
        return casks.contains(token) ? token : nil
    }

    static func teamIdentifier(of url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var infoRef: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &infoRef) == errSecSuccess,
              let info = infoRef as? [String: Any] else { return nil }
        return info[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
