import XCTest
@testable import AppReaper

final class UninstallerTests: XCTestCase {
    final class FakeTrasher: Trashing {
        var trashed: [URL] = []
        var failing: [URL: Error] = [:]
        func trash(_ url: URL) throws {
            if let e = failing[url] { throw e }
            trashed.append(url)
        }
    }

    let lib = URL(fileURLWithPath: "/tmp/fakehome/Library")
    func app(_ id: String = "com.foo.Widget", path: String = "/tmp/Widget.app") -> InstalledApp {
        InstalledApp(id: id, name: "Widget", version: "1", bundleURL: URL(fileURLWithPath: path), teamIdentifier: nil, source: .applications)
    }
    func item(_ rel: String) -> LeftoverItem {
        LeftoverItem(url: lib.appendingPathComponent(rel), category: .caches, reason: "t", size: 1)
    }

    func testTrashesLeftoversThenApp() throws {
        let t = FakeTrasher()
        let u = Uninstaller(trasher: t, libraryURL: lib)
        let plan = try u.makePlan(app: app(), leftovers: [item("Caches/com.foo.Widget")])
        let r = u.execute(plan)
        XCTAssertTrue(r.failures.isEmpty)
        XCTAssertEqual(t.trashed.last?.path, "/tmp/Widget.app")
        XCTAssertEqual(t.trashed.count, 2)
    }

    func testProtectedAppRefused() {
        let u = Uninstaller(trasher: FakeTrasher(), libraryURL: lib)
        let safari = app("com.apple.Safari", path: "/System/Applications/Safari.app")
        XCTAssertThrowsError(try u.makePlan(app: safari, leftovers: []))
        let r = u.execute(UninstallPlan(app: safari, leftovers: [], appSize: 0))
        XCTAssertEqual(r.failures.count, 1)
        XCTAssertTrue(r.trashed.isEmpty)
    }

    func testSelfNotRemovable() {
        XCTAssertThrowsError(try Uninstaller(trasher: FakeTrasher(), libraryURL: lib)
            .makePlan(app: app(InstalledApp.selfBundleID), leftovers: []))
    }

    func testUnsafeLeftoverSkipped() throws {
        let t = FakeTrasher()
        let u = Uninstaller(trasher: t, libraryURL: lib)
        let bad = LeftoverItem(url: URL(fileURLWithPath: "/Users/other/Documents"), category: .other, reason: "x", size: 1)
        let r = u.execute(UninstallPlan(app: app(), leftovers: [bad], appSize: 0))
        XCTAssertEqual(r.failures.count, 1)
        XCTAssertFalse(t.trashed.contains(bad.url))
    }

    func testPermissionFailureFlaggedAsAdmin() throws {
        let t = FakeTrasher()
        t.failing[URL(fileURLWithPath: "/tmp/Widget.app")] = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
        let u = Uninstaller(trasher: t, libraryURL: lib)
        let r = u.execute(try u.makePlan(app: app(), leftovers: []))
        XCTAssertEqual(r.failures.first?.needsAdmin, true)
    }

    func testDryRunTouchesNothing() throws {
        let t = FakeTrasher()
        let u = Uninstaller(trasher: t, libraryURL: lib)
        let lines = u.dryRun(try u.makePlan(app: app(), leftovers: [item("Caches/com.foo.Widget")]))
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(t.trashed.isEmpty)
    }
}
