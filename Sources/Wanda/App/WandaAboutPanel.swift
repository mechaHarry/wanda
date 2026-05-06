import AppKit

enum WandaAboutPanel {
    @MainActor
    static func show(version: String = WandaVersion.aboutApplicationVersion) {
        let application = NSApplication.shared
        application.orderFrontStandardAboutPanel(options: options(version: version))
        application.activate(ignoringOtherApps: true)
    }

    static func options(version: String) -> [NSApplication.AboutPanelOptionKey: Any] {
        [
            .applicationName: "Wanda",
            .applicationVersion: version,
            .version: WandaVersion.buildVersion
        ]
    }
}
