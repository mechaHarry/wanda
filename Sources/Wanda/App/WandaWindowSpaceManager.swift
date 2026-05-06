import AppKit

@MainActor
enum WandaWindowSpacePolicy {
    static func configure(_ window: NSWindow) {
        window.collectionBehavior.insert(.moveToActiveSpace)
    }
}

@MainActor
protocol WindowSpaceManaging: AnyObject {
    func bringVisibleWindowsToActiveSpace()
}

@MainActor
final class NSApplicationWindowSpaceManager: WindowSpaceManaging {
    private weak var application: NSApplication?

    init(application: NSApplication = .shared) {
        self.application = application
    }

    func bringVisibleWindowsToActiveSpace() {
        guard let application else {
            return
        }

        for window in application.windows where window.isVisible {
            WandaWindowSpacePolicy.configure(window)
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        }
    }
}
