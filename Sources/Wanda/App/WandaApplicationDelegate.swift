import AppKit

@MainActor
protocol ApplicationActivationControlling: AnyObject {
    func setActivationPolicy(_ activationPolicy: NSApplication.ActivationPolicy) -> Bool
    func activate(ignoringOtherApps flag: Bool)
}

extension NSApplication: ApplicationActivationControlling {}

@MainActor
final class WandaApplicationDelegate: NSObject, NSApplicationDelegate {
    private let application: ApplicationActivationControlling
    private let windowSpaceManager: WindowSpaceManaging

    override convenience init() {
        self.init(application: NSApplication.shared, windowSpaceManager: NSApplicationWindowSpaceManager())
    }

    init(
        application: ApplicationActivationControlling,
        windowSpaceManager: WindowSpaceManaging = NSApplicationWindowSpaceManager()
    ) {
        self.application = application
        self.windowSpaceManager = windowSpaceManager
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = application.setActivationPolicy(.regular)
        application.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard flag else {
            return true
        }

        _ = application.setActivationPolicy(.regular)
        application.activate(ignoringOtherApps: true)
        windowSpaceManager.bringVisibleWindowsToActiveSpace()
        return false
    }
}
