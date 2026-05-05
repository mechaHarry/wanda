import SwiftUI

@main
struct WandaApp: App {
    @NSApplicationDelegateAdaptor(WandaApplicationDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Wanda") {
            TerminalWindowView()
        }
        .windowResizability(.contentSize)
    }
}
