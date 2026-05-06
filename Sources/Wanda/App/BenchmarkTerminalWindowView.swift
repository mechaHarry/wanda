import SwiftUI

struct BenchmarkTerminalWindowView: View {
    private static let terminalCellSize = CGSize(width: 9, height: 18)
    private static let terminalTheme = TerminalTheme.default

    @StateObject private var viewModel = BenchmarkTerminalViewModel()

    var body: some View {
        GeometryReader { geometry in
            let layout = terminalSurfaceLayout(for: geometry.size)

            TerminalMetalViewRepresentable(
                snapshot: viewModel.snapshot,
                theme: Self.terminalTheme,
                onFramePresented: { timestamp in
                    Task { @MainActor in
                        viewModel.framePresented(at: timestamp)
                    }
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: Self.terminalTheme.background))
            .onAppear {
                resizeTerminal(to: layout)
                viewModel.start()
            }
            .onChange(of: geometry.size) { _, newSize in
                resizeTerminal(to: terminalSurfaceLayout(for: newSize))
            }
        }
        .frame(minWidth: 720, minHeight: 420)
        .background(Color(nsColor: Self.terminalTheme.background))
        .background {
            WindowAccessor { window in
                WandaWindowSpacePolicy.configure(window)
            }
        }
    }

    private func resizeTerminal(to layout: TerminalSurfaceLayout) {
        viewModel.resize(columns: layout.resizeColumns, rows: layout.resizeRows)
    }

    private func terminalSurfaceLayout(for size: CGSize) -> TerminalSurfaceLayout {
        TerminalSurfaceLayout(
            viewSize: size,
            displayedColumns: viewModel.snapshot.columns,
            displayedRows: viewModel.snapshot.rows,
            preferredCellSize: Self.terminalCellSize
        )
    }
}
