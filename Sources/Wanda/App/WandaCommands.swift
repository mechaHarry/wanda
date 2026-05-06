import SwiftUI

enum WandaWindowID {
    static let metalStressBenchmark = "metal-stress-benchmark"
}

enum WandaCommandLabel {
    static let aboutWanda = "About Wanda"
    static let runMetalStressBenchmark = "Run Metal Stress Benchmark"
}

struct WandaCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button(WandaCommandLabel.aboutWanda) {
                WandaAboutPanel.show()
            }

            Button(WandaCommandLabel.runMetalStressBenchmark) {
                openWindow(id: WandaWindowID.metalStressBenchmark)
            }
        }
    }
}
