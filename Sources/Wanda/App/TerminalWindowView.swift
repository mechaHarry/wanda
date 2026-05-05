import SwiftUI

struct TerminalWindowView: View {
    @StateObject private var viewModel = TerminalViewModel()

    var body: some View {
        GeometryReader { geometry in
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                resizeTerminal(to: geometry.size)
            }
            .onChange(of: geometry.size) { _, newSize in
                resizeTerminal(to: newSize)
            }
            .task {
                viewModel.startDefaultShell()
                resizeTerminal(to: geometry.size)
            }
            .onDisappear {
                viewModel.stop()
            }
        }
        .frame(minWidth: 720, minHeight: 420)
    }

    private func resizeTerminal(to size: CGSize) {
        let columns = max(1, Int(size.width / 9))
        let rows = max(1, Int(size.height / 18))
        viewModel.resize(columns: columns, rows: rows)
    }
}
