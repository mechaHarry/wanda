import SwiftUI

struct TerminalWindowView: View {
    @StateObject private var viewModel = TerminalViewModel()

    var body: some View {
        ZStack(alignment: .topLeading) {
            TerminalMetalViewRepresentable(
                snapshot: viewModel.snapshot,
                onFramePresented: viewModel.framePresented(at:)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TerminalInputView { keyEvent in
                viewModel.handleKey(keyEvent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())

            if let statusMessage = viewModel.statusMessage {
                Text(statusMessage)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    .padding(12)
            }
        }
        .frame(minWidth: 720, minHeight: 420)
        .task {
            viewModel.startDefaultShell()
        }
        .onDisappear {
            viewModel.stop()
        }
    }
}
