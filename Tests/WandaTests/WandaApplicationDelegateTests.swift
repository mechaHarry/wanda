import AppKit
import XCTest
@testable import Wanda

@MainActor
final class WandaApplicationDelegateTests: XCTestCase {
    func testLaunchRequestsForegroundActivation() {
        let application = SpyApplicationActivationController()
        let delegate = WandaApplicationDelegate(application: application)

        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

        XCTAssertEqual(application.requestedPolicies, [.regular])
        XCTAssertEqual(application.activationRequests, [true])
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
