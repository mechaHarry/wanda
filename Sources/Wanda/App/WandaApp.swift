import SwiftUI

@main
struct WandaApp: App {
    var body: some Scene {
        WindowGroup("Wanda") {
            TerminalWindowView()
        }
        .windowResizability(.contentSize)
    }
}
