import AppKit
import SwiftUI

struct TerminalWindowView: View {
    private static let terminalCellSize = CGSize(width: 9, height: 18)
    private static let terminalTheme = TerminalTheme.default

    @StateObject private var viewModel = TerminalViewModel()
    @StateObject private var windowGeometry = TerminalWindowGeometryController()

    var body: some View {
        GeometryReader { geometry in
            let surfaceLayout = terminalSurfaceLayout(for: geometry.size)

            ZStack(alignment: .topLeading) {
                TerminalMetalViewRepresentable(
                    snapshot: viewModel.snapshot,
                    theme: Self.terminalTheme,
                    onFramePresented: viewModel.framePresented(at:)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                TerminalSelectionOverlayRepresentable(
                    selection: viewModel.selection,
                    snapshot: viewModel.snapshot
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                TerminalInputView(
                    layout: surfaceLayout.inputLayout,
                    onKey: { keyEvent in
                        viewModel.handleKey(keyEvent)
                    },
                    onSelectionBegan: { point in
                        viewModel.beginSelection(at: point)
                    },
                    onSelectionChanged: { point in
                        viewModel.updateSelection(to: point)
                    },
                    onTokenSelection: { point in
                        viewModel.selectToken(at: point)
                    },
                    onCopy: {
                        _ = TerminalSelectionClipboard.copy(viewModel.selectedText())
                    }
                )
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
            .background(Color(nsColor: Self.terminalTheme.background))
            .onAppear {
                resizeTerminal(to: surfaceLayout)
            }
            .onChange(of: geometry.size) { _, newSize in
                resizeTerminal(to: terminalSurfaceLayout(for: newSize))
            }
            .task {
                viewModel.startDefaultShell()
                resizeTerminal(to: surfaceLayout)
            }
            .onDisappear {
                windowGeometry.saveCurrentWindowFrame()
                viewModel.stop()
            }
        }
        .frame(minWidth: 720, minHeight: 420)
        .background(Color(nsColor: Self.terminalTheme.background))
        .background {
            WindowAccessor { window in
                windowGeometry.observe(window: window)
            }
        }
    }

    private func resizeTerminal(to layout: TerminalSurfaceLayout) {
        viewModel.resize(columns: layout.resizeColumns, rows: layout.resizeRows)
    }

    private func terminalSurfaceLayout(for size: CGSize) -> TerminalSurfaceLayout {
        TerminalSurfaceLayout(
            viewSize: size,
            displayedColumns: viewModel.snapshot?.columns,
            displayedRows: viewModel.snapshot?.rows,
            preferredCellSize: Self.terminalCellSize
        )
    }
}

@MainActor
final class TerminalWindowGeometryController: ObservableObject {
    private let geometryStore: GeometryStore
    private weak var window: NSWindow?
    private var restoredWindowID: ObjectIdentifier?

    init(geometryStore: GeometryStore = GeometryStore()) {
        self.geometryStore = geometryStore
    }

    func observe(window: NSWindow) {
        self.window = window
        WandaWindowSpacePolicy.configure(window)

        guard let frame = frameToApply(
            to: ObjectIdentifier(window),
            currentFrame: window.frame,
            visibleFrame: Self.visibleFrame(for: window)
        ) else {
            return
        }

        window.setFrame(frame, display: true)
    }

    func saveCurrentWindowFrame() {
        guard let frame = window?.frame else {
            return
        }

        save(frame: frame)
    }

    func frameToApply(to windowID: ObjectIdentifier, currentFrame: CGRect, visibleFrame: CGRect) -> CGRect? {
        guard restoredWindowID != windowID else {
            return nil
        }

        restoredWindowID = windowID
        let frame = geometryStore.load(validatingAgainst: visibleFrame)
        guard frame != currentFrame else {
            return nil
        }

        return frame
    }

    func save(frame: CGRect) {
        geometryStore.save(frame: frame)
    }

    private static func visibleFrame(for window: NSWindow) -> CGRect {
        window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
    }
}
