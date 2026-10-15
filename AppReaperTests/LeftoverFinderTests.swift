import XCTest
@testable import AppReaper

final class LeftoverFinderTests: XCTestCase {
    var lib: URL!
    let fm = FileManager.default

    override func setUpWithError() throws {
        lib = fm.temporaryDirectory.appendingPathComponent("lib-\(UUID().uuidString)")
        try fm.createDirectory(at: lib, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? fm.removeItem(at: lib) }

    func make(_ rel: String, dir: Bool = false, bytes: Int = 10) throws {
        let u = lib.appendingPathComponent(rel)
        try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        if dir { try fm.createDirectory(at: u, withIntermediateDirectories: true); try Data(count: bytes).write(to: u.appendingPathComponent("f")) }
        else { try Data(count: bytes).write(to: u) }
    }

    func app(_ id: String = "com.foo.Widget", name: String = "Widget", path: String = "/Applications/Widget.app") -> InstalledApp {
        InstalledApp(id: id, name: name, version: "1", bundleURL: URL(fileURLWithPath: path), teamIdentifier: nil, source: .applications)
    }

    func testMatchesBundleIDAndName() throws {
        try make("Preferences/com.foo.Widget.plist")
        try make("Application Support/Widget", dir: true, bytes: 100)
        try make("Caches/com.foo.Widget", dir: true)
        try make("Containers/com.foo.Widget", dir: true)
        try make("Group Containers/ABCDE12345.com.foo.Widget", dir: true)
        try make("Saved Application State/com.foo.Widget.savedState", dir: true)
        let names = Set(LeftoverFinder(libraryURL: lib).find(for: app()).map { $0.url.lastPathComponent })
        XCTAssertEqual(names, ["com.foo.Widget.plist", "Widget", "com.foo.Widget", "ABCDE12345.com.foo.Widget", "com.foo.Widget.savedState"])
    }

    func testSizesReported() throws {
        try make("Application Support/Widget", dir: true, bytes: 8192)
        let items = LeftoverFinder(libraryURL: lib).find(for: app())
        XCTAssertGreaterThan(items.first?.size ?? 0, 0)
    }

    func testDoesNotMatchSimilarNames() throws {
        try make("Application Support/Widgets", dir: true)
        try make("Application Support/MyWidget", dir: true)
        try make("Preferences/com.foo.WidgetPro.plist")
        try make("Preferences/com.foo.Widgetry.plist")
        try make("Containers/com.other.Widget", dir: true)
        XCTAssertTrue(LeftoverFinder(libraryURL: lib).find(for: app()).isEmpty)
    }

    func testSiblingAppBundleIDNotClaimed() throws {
        try make("Preferences/com.foo.Widget.beta.plist")
        try make("Preferences/com.foo.Widget.helper.plist")
        let items = LeftoverFinder(libraryURL: lib).find(for: app(), otherBundleIDs: ["com.foo.Widget.beta"])
        XCTAssertEqual(items.map { $0.url.lastPathComponent }, ["com.foo.Widget.helper.plist"])
    }

    func testAppleAppsReturnNothing() throws {
        try make("Preferences/com.apple.Safari.plist")
        let safari = app("com.apple.Safari", name: "Safari", path: "/System/Volumes/Preboot/Safari.app")
        XCTAssertTrue(LeftoverFinder(libraryURL: lib).find(for: safari).isEmpty)
    }

    func testGenericOrShortNamesNotNameMatched() throws {
        try make("Application Support/Google", dir: true)
        try make("Application Support/App", dir: true)
        try make("Application Support/Mac", dir: true)
        let g = app("com.google.Chrome", name: "Google")
        let a = app("com.x.App", name: "App")
        let m = app("com.x.Mac", name: "Mac")
        let f = LeftoverFinder(libraryURL: lib)
        XCTAssertTrue(f.find(for: g).isEmpty)
        XCTAssertTrue(f.find(for: a).isEmpty)
        XCTAssertTrue(f.find(for: m).isEmpty)
    }

    func testNameMatchOnlyInAllowedFolders() throws {
        try make("Preferences/Widget", dir: true)
        try make("Containers/Widget", dir: true)
        XCTAssertTrue(LeftoverFinder(libraryURL: lib).find(for: app()).isEmpty)
    }

    func testSafeTargetRejectsLibraryRootAndOutside() {
        XCTAssertFalse(LeftoverFinder.isSafeTarget(lib, libraryURL: lib))
        XCTAssertFalse(LeftoverFinder.isSafeTarget(lib.appendingPathComponent("Caches"), libraryURL: lib))
        XCTAssertFalse(LeftoverFinder.isSafeTarget(URL(fileURLWithPath: "/Applications/Foo.app"), libraryURL: lib))
        XCTAssertFalse(LeftoverFinder.isSafeTarget(lib.appendingPathComponent("Caches/../../etc"), libraryURL: lib))
        XCTAssertFalse(LeftoverFinder.isSafeTarget(lib.appendingPathComponent("Preferences/com.apple.finder.plist"), libraryURL: lib))
        XCTAssertTrue(LeftoverFinder.isSafeTarget(lib.appendingPathComponent("Caches/com.foo.Widget"), libraryURL: lib))
    }

    func testUnusableBundleIDs() {
        XCTAssertFalse(LeftoverFinder.isUsableBundleID("foo"))
        XCTAssertFalse(LeftoverFinder.isUsableBundleID("com.foo"))
        XCTAssertTrue(LeftoverFinder.isUsableBundleID("com.foo.bar"))
    }

    func testConfidenceTiers() throws {
        try make("Preferences/com.foo.Widget.plist")
        try make("Group Containers/ABCDE12345.com.foo.Widget", dir: true)
        try make("Application Support/Widget", dir: true, bytes: 1)
        let items = LeftoverFinder(libraryURL: lib).find(for: app())
        let byName = Dictionary(uniqueKeysWithValues: items.map { ($0.url.lastPathComponent, $0) })
        XCTAssertEqual(byName["com.foo.Widget.plist"]?.confidence, .exact)
        XCTAssertEqual(byName["ABCDE12345.com.foo.Widget"]?.confidence, .probable)
        XCTAssertEqual(byName["Widget"]?.confidence, .possible)
    }

    func testOnlyExactAndProbableSelectedByDefault() {
        XCTAssertTrue(MatchConfidence.exact.isSelectedByDefault)
        XCTAssertTrue(MatchConfidence.probable.isSelectedByDefault)
        XCTAssertFalse(MatchConfidence.possible.isSelectedByDefault)
    }
}
