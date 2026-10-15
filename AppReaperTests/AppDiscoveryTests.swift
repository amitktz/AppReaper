import XCTest
@testable import AppReaper

final class AppDiscoveryTests: XCTestCase {
    func testCaskMatching() {
        XCTAssertEqual(AppDiscoveryService.matchCask(appName: "Visual Studio Code", casks: ["visual-studio-code"]), "visual-studio-code")
        XCTAssertNil(AppDiscoveryService.matchCask(appName: "Foo", casks: ["bar"]))
    }

    func testDiscoversFakeApp() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("apps-\(UUID().uuidString)")
        let app = root.appendingPathComponent("Fake.app/Contents")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("_MASReceipt"), withIntermediateDirectories: true)
        try Data().write(to: app.appendingPathComponent("_MASReceipt/receipt"))
        let plist: [String: Any] = ["CFBundleIdentifier": "com.test.Fake", "CFBundleName": "Fake", "CFBundleShortVersionString": "2.0", "CFBundlePackageType": "APPL"]
        try (plist as NSDictionary).write(to: app.appendingPathComponent("Info.plist"))
        defer { try? FileManager.default.removeItem(at: root) }
        let found = AppDiscoveryService(directories: [root], homebrewCaskroomDirs: []).discover()
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].id, "com.test.Fake")
        XCTAssertEqual(found[0].version, "2.0")
        XCTAssertEqual(found[0].source, .macAppStore)
    }
}
