import AppKit

protocol Trashing {
    func trash(_ url: URL) throws
}

struct FileManagerTrasher: Trashing {
    func trash(_ url: URL) throws {
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
    }
}

struct UninstallPlan {
    let app: InstalledApp
    let leftovers: [LeftoverItem]
    var appSize: Int64
    var totalSize: Int64 { appSize + leftovers.reduce(0) { $0 + $1.size } }
    var allURLs: [URL] { [app.bundleURL] + leftovers.map(\.url) }
}

struct UninstallFailure {
    let url: URL
    let message: String
    let needsAdmin: Bool
}

struct UninstallResult {
    var trashed: [URL] = []
    var failures: [UninstallFailure] = []
}

enum UninstallError: Error, LocalizedError {
    case notRemovable(String)
    var errorDescription: String? {
        switch self { case .notRemovable(let n): "\(n) is a protected app and cannot be removed." }
    }
}

struct Uninstaller {
    var trasher: Trashing = FileManagerTrasher()
    var libraryURL: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")

    func makePlan(app: InstalledApp, leftovers: [LeftoverItem]) throws -> UninstallPlan {
        guard app.isRemovable else { throw UninstallError.notRemovable(app.name) }
        return UninstallPlan(app: app, leftovers: leftovers, appSize: LeftoverFinder.size(of: app.bundleURL))
    }

    /// Human-readable dry run; touches nothing.
    func dryRun(_ plan: UninstallPlan) -> [String] {
        plan.allURLs.map { $0.path }
    }

    func runningInstances(of app: InstalledApp) -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: app.id)
    }

    /// Asks the app to quit and waits briefly. Returns true if no instance remains.
    func quit(_ app: InstalledApp, timeout: TimeInterval = 5) async -> Bool {
        let apps = runningInstances(of: app)
        apps.forEach { $0.terminate() }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if apps.allSatisfy(\.isTerminated) { return true }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return apps.allSatisfy(\.isTerminated)
    }

    /// Moves everything to Trash. Never deletes permanently. Re-validates every path.
    func execute(_ plan: UninstallPlan) -> UninstallResult {
        var result = UninstallResult()
        guard plan.app.isRemovable else {
            result.failures.append(UninstallFailure(url: plan.app.bundleURL, message: UninstallError.notRemovable(plan.app.name).localizedDescription, needsAdmin: false))
            return result
        }
        // Leftovers first, app last, so a failure on the app does not orphan data silently.
        for item in plan.leftovers {
            guard LeftoverFinder.isSafeTarget(item.url, libraryURL: libraryURL) else {
                result.failures.append(UninstallFailure(url: item.url, message: "Path failed safety check; skipped.", needsAdmin: false))
                continue
            }
            attempt(item.url, into: &result)
        }
        attempt(plan.app.bundleURL, into: &result)
        return result
    }

    private func attempt(_ url: URL, into result: inout UninstallResult) {
        do {
            try trasher.trash(url)
            result.trashed.append(url)
        } catch {
            result.failures.append(UninstallFailure(url: url, message: error.localizedDescription, needsAdmin: Self.isPermissionError(error)))
        }
    }

    static func isPermissionError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && [NSFileWriteNoPermissionError, NSFileReadNoPermissionError].contains(ns.code) { return true }
        if ns.domain == NSPOSIXErrorDomain && [Int(EPERM), Int(EACCES)].contains(ns.code) { return true }
        if let under = ns.userInfo[NSUnderlyingErrorKey] as? NSError, under !== ns { return isPermissionError(under) }
        return false
    }
}

enum ByteFormat {
    static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
