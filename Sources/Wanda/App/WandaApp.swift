import SwiftUI

@main
struct WandaApp: App {
    @NSApplicationDelegateAdaptor(WandaApplicationDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Wanda") {
            TerminalWindowView()
        }
        .windowResizability(.contentSize)
        .commands {
            WandaCommands()
        }

        Window("Metal Stress Benchmark", id: WandaWindowID.metalStressBenchmark) {
            BenchmarkTerminalWindowView()
        }
        .windowResizability(.contentSize)
    }
}
