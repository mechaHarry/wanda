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

    override convenience init() {
        self.init(application: NSApplication.shared)
    }

    init(application: ApplicationActivationControlling) {
        self.application = application
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = application.setActivationPolicy(.regular)
        application.activate(ignoringOtherApps: true)
    }
}
