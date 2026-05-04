import SwiftUI

struct TerminalWindowView: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("Wanda")
                .font(.system(.title2, design: .monospaced))
            Text("Terminal core is not connected yet.")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 720, minHeight: 420)
        .padding(24)
    }
}
