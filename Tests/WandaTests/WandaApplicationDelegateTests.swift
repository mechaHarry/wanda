import AppKit
import XCTest
@testable import Wanda

@MainActor
final class WandaApplicationDelegateTests: XCTestCase {
    func testVersionConstantMatchesRepoVersionFile() throws {
        let versionURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("VERSION")
        let repoVersion = try String(contentsOf: versionURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        XCTAssertEqual(WandaVersion.semanticVersion, repoVersion)
        XCTAssertTrue(WandaVersion.semanticVersion.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil)
    }

    func testAboutPanelOptionsStateCurrentSemver() {
        let options = WandaAboutPanel.options(version: WandaVersion.aboutApplicationVersion)

        XCTAssertEqual(options[.applicationName] as? String, "Wanda")
        XCTAssertEqual(options[.applicationVersion] as? String, WandaVersion.semanticVersion)
        XCTAssertEqual(options[.version] as? String, WandaVersion.buildVersion)
    }

    func testCommandLabelsExposeBenchmarkNearAbout() {
        XCTAssertEqual(WandaCommandLabel.aboutWanda, "About Wanda")
        XCTAssertEqual(WandaCommandLabel.runMetalStressBenchmark, "Run Metal Stress Benchmark")
        XCTAssertEqual(WandaWindowID.metalStressBenchmark, "metal-stress-benchmark")
    }

    func testLaunchRequestsForegroundActivation() {
        let application = SpyApplicationActivationController()
        let windowSpaceManager = SpyWindowSpaceManager()
        let delegate = WandaApplicationDelegate(application: application, windowSpaceManager: windowSpaceManager)

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        XCTAssertEqual(application.requestedPolicies, [.regular])
        XCTAssertEqual(application.activationRequests, [true])
        XCTAssertEqual(windowSpaceManager.bringRequests, 0)
    }

    func testReopenWithVisibleWindowsMovesWindowsToActiveSpaceWithoutDefaultReopen() {
        let application = SpyApplicationActivationController()
        let windowSpaceManager = SpyWindowSpaceManager()
        let delegate = WandaApplicationDelegate(application: application, windowSpaceManager: windowSpaceManager)

        let shouldHandleDefaultReopen = delegate.applicationShouldHandleReopen(
            NSApplication.shared,
            hasVisibleWindows: true
        )

        XCTAssertFalse(shouldHandleDefaultReopen)
        XCTAssertEqual(application.requestedPolicies, [.regular])
        XCTAssertEqual(application.activationRequests, [true])
        XCTAssertEqual(windowSpaceManager.bringRequests, 1)
    }

    func testReopenWithoutVisibleWindowsLetsSwiftUICreateAWindow() {
        let application = SpyApplicationActivationController()
        let windowSpaceManager = SpyWindowSpaceManager()
        let delegate = WandaApplicationDelegate(application: application, windowSpaceManager: windowSpaceManager)

        let shouldHandleDefaultReopen = delegate.applicationShouldHandleReopen(
            NSApplication.shared,
            hasVisibleWindows: false
        )

        XCTAssertTrue(shouldHandleDefaultReopen)
        XCTAssertEqual(application.requestedPolicies, [])
        XCTAssertEqual(application.activationRequests, [])
        XCTAssertEqual(windowSpaceManager.bringRequests, 0)
    }
}

@MainActor
private final class SpyApplicationActivationController: ApplicationActivationControlling {
    var requestedPolicies: [NSApplication.ActivationPolicy] = []
    var activationRequests: [Bool] = []

    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool {
        requestedPolicies.append(activationPolicy)
        return true
    }

    func activate(ignoringOtherApps flag: Bool) {
        activationRequests.append(flag)
    }
}

@MainActor
private final class SpyWindowSpaceManager: WindowSpaceManaging {
    var bringRequests = 0

    func bringVisibleWindowsToActiveSpace() {
        bringRequests += 1
    }
}
